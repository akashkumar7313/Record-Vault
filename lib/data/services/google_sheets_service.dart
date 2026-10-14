import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/safe_logger.dart';
import '../models/personal_record.dart';

/// Outcome of a single write operation against the Sheets endpoint.
///
/// [confirmed] is true only when the server response explicitly acknowledges
/// success. A bare HTTP 200 with an ambiguous body is treated as *unconfirmed*
/// so the app never claims a sync it cannot verify.
class SyncOperationResult {
  const SyncOperationResult({
    required this.confirmed,
    required this.message,
    this.unsupported = false,
    this.photoFileId,
  });

  const SyncOperationResult.unconfirmed(this.message)
    : confirmed = false,
      unsupported = false,
      photoFileId = null;

  const SyncOperationResult.unsupported(this.message)
    : confirmed = false,
      unsupported = true,
      photoFileId = null;

  final bool confirmed;
  final String message;

  /// True when the server responded but does not implement the action.
  final bool unsupported;

  /// Google Drive file id returned by the server after a photo upload.
  final String? photoFileId;

  static const SyncOperationResult ok = SyncOperationResult(
    confirmed: true,
    message: 'Confirmed by server',
  );
}

/// Thin, testable client for the deployed Google Apps Script Web App.
///
/// Contract implemented (matching the existing deployment):
///   GET  : list records
///   POST : { "action": "add", "record": { ... } }
///
/// Extended actions (`update`, `delete`) are sent using the same envelope and
/// are reported as [SyncOperationResult.unsupported] when the server does not
/// implement them. See `tool/apps_script/Code.gs` for the reference server.
class GoogleSheetsService {
  GoogleSheetsService({
    required this.endpoint,
    http.Client? client,
    Duration? timeout,
    int? readRetries,
    int? writeRetries,
  }) : _client = client ?? http.Client(),
       _timeout = timeout ?? AppConstants.requestTimeout,
       _readRetries = readRetries ?? AppConstants.readRetryAttempts,
       _writeRetries = writeRetries ?? AppConstants.writeRetryAttempts;

  final Uri endpoint;
  final http.Client _client;
  final Duration _timeout;
  final int _readRetries;
  final int _writeRetries;

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json; charset=utf-8',
    'Accept': 'application/json',
  };

  void dispose() => _client.close();

  /// Fetches all records from the server.
  ///
  /// Reads are idempotent and may be safely retried.
  Future<List<PersonalRecord>> fetchRecords() async {
    final decoded = await _sendJson(method: 'GET', attempts: _readRetries);
    final list = _extractRecordList(decoded);
    final records = <PersonalRecord>[];
    for (final item in list) {
      if (item is Map) {
        final record = PersonalRecord.fromRemoteJson(
          item.map((k, v) => MapEntry(k.toString(), v)),
        );
        if (record.aadhaarNumber.isNotEmpty) records.add(record);
      }
    }
    SafeLogger.trace(
      'SERVER',
      'read.records',
      detail: 'count=${records.length} of ${list.length}',
    );
    return records;
  }

  /// Lightweight reachability probe used by the Settings screen.
  ///
  /// Returns true when the endpoint responds with a parseable JSON body.
  Future<bool> checkConnection() async {
    try {
      await _sendJson(method: 'GET', attempts: 1);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Adds (or upserts) a record, matched on its Aadhaar number. Safe to retry:
  /// the server matches on [PersonalRecord.aadhaarNumber], so a retried request
  /// updates the existing row instead of appending a duplicate.
  Future<SyncOperationResult> addRecord(
    PersonalRecord record, {
    String? photoBase64,
  }) {
    return _mutate('add', record, photoBase64: photoBase64);
  }

  /// Updates an existing record by Aadhaar number.
  Future<SyncOperationResult> updateRecord(
    PersonalRecord record, {
    String? photoBase64,
  }) {
    return _mutate('update', record, photoBase64: photoBase64);
  }

  /// Deletes a record by Aadhaar number.
  Future<SyncOperationResult> deleteRecord(String aadhaarNumber) async {
    final decoded = await _sendJson(
      method: 'POST',
      attempts: _writeRetries,
      body: jsonEncode({
        'action': 'delete',
        'record': {'aadhaarNumber': aadhaarNumber},
      }),
    );
    final result = _interpretWrite(decoded, expectedAadhaar: aadhaarNumber);
    _logWrite('delete', aadhaarNumber, result);
    return result;
  }

  Future<SyncOperationResult> _mutate(
    String action,
    PersonalRecord record, {
    String? photoBase64,
  }) async {
    final decoded = await _sendJson(
      method: 'POST',
      attempts: _writeRetries,
      body: jsonEncode({
        'action': action,
        'record': record.toRemoteJson(photoBase64: photoBase64),
      }),
    );
    final result = _interpretWrite(
      decoded,
      expectedAadhaar: record.aadhaarNumber,
    );
    _logWrite(action, record.aadhaarNumber, result);
    return result;
  }

  void _logWrite(String action, String aadhaarNumber, SyncOperationResult r) {
    final outcome = r.confirmed
        ? 'confirmed'
        : (r.unsupported ? 'unsupported' : 'unconfirmed');
    SafeLogger.trace(
      'SERVER',
      'write.$action',
      id: aadhaarNumber,
      detail: 'photoFileId=${r.photoFileId == null ? '-' : 'yes'} $outcome',
    );
  }

  // ---------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------

  Future<dynamic> _sendJson({
    required String method,
    int attempts = 1,
    String? body,
  }) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        return await _sendOnce(method: method, body: body);
      } on AppException catch (e) {
        lastError = e;
        lastStack = e.stackTrace;
        final retryable =
            e.type == AppErrorType.timeout ||
            e.type == AppErrorType.network ||
            e.type == AppErrorType.server;
        if (!retryable || attempt == attempts) rethrow;
        SafeLogger.info('Sheets request retry $attempt/$attempts');
        await Future<void>.delayed(AppConstants.retryBackoff * attempt);
      }
    }
    throw AppException.from(lastError!, lastStack);
  }

  Future<dynamic> _sendOnce({required String method, String? body}) async {
    http.Response response;
    try {
      if (method == 'GET') {
        response = await _client
            .get(endpoint, headers: _jsonHeaders)
            .timeout(_timeout);
      } else {
        response = await _post(body: body ?? '').timeout(_timeout);
      }
    } on TimeoutException catch (e, s) {
      SafeLogger.error('SERVER $method', e, s);
      throw AppException(
        AppErrorType.timeout,
        'The server took too long to respond.',
        cause: e,
        stackTrace: s,
      );
    } catch (e, s) {
      SafeLogger.error('SERVER $method', e, s);
      throw AppException.from(e, s);
    }

    SafeLogger.trace(
      'SERVER',
      method,
      detail: 'host=${endpoint.host} status=${response.statusCode}',
    );

    if (response.statusCode >= 500) {
      throw AppException(
        AppErrorType.server,
        'The server is temporarily unavailable (${response.statusCode}).',
      );
    }
    if (response.statusCode >= 400) {
      throw AppException(
        AppErrorType.server,
        'The server rejected the request (${response.statusCode}).',
      );
    }

    final raw = response.body.trim();
    if (raw.isEmpty) {
      throw const AppException(
        AppErrorType.malformedResponse,
        'The server returned an empty response.',
      );
    }
    if (raw.startsWith('<')) {
      // Apps Script returns an HTML page when the deployment is not accessible
      // anonymously or when the script threw before writing JSON.
      throw const AppException(
        AppErrorType.server,
        'The server did not return data. The web app may not be shared for '
        'public access, or access is restricted.',
      );
    }

    try {
      return jsonDecode(raw);
    } on FormatException catch (e, s) {
      throw AppException(
        AppErrorType.malformedResponse,
        'Received an unexpected response format from the server.',
        cause: e,
        stackTrace: s,
      );
    }
  }

  /// Sends a POST and manually follows the Apps Script redirect.
  ///
  /// Apps Script replies to a POST with a `302` pointing at a
  /// `script.googleusercontent.com` "echo" URL that must be fetched with GET.
  /// Dart's HTTP client does not reliably follow that method-changing redirect,
  /// so we do it ourselves. The same client is reused so the session cookie set
  /// by the redirect is carried across.
  Future<http.Response> _post({required String body}) async {
    final request = http.Request('POST', endpoint)
      ..headers.addAll(_jsonHeaders)
      ..body = body
      ..followRedirects = false;

    final streamed = await _client.send(request);
    var response = await http.Response.fromStream(streamed);

    var hops = 0;
    while (response.statusCode >= 300 &&
        response.statusCode < 400 &&
        hops < 5) {
      final location = response.headers['location'];
      if (location == null || location.isEmpty) break;
      final target = endpoint.resolve(location);
      response = await _client.get(target, headers: _jsonHeaders);
      hops++;
    }

    if (hops > 0) {
      SafeLogger.trace(
        'SERVER',
        'redirect',
        detail: 'followed=$hops final=${response.statusCode}',
      );
    }
    return response;
  }

  // ---------------------------------------------------------------------------
  // Parsing helpers
  // ---------------------------------------------------------------------------

  List<dynamic> _extractRecordList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      final map = decoded.map((k, v) => MapEntry(k.toString(), v));
      // A server-side error envelope.
      final error = map['error'];
      if (error != null &&
          error.toString().trim().isNotEmpty &&
          error.toString().toLowerCase() != 'false' &&
          error.toString().toLowerCase() != 'null') {
        throw AppException(
          AppErrorType.server,
          'Server error: ${error.toString()}',
        );
      }
      for (final key in const ['records', 'data', 'rows', 'items', 'values']) {
        final value = map[key];
        if (value is List) return value;
      }
      if (map.containsKey('aadhaarNumber') || map.containsKey('id')) {
        return [map];
      }
    }
    throw const AppException(
      AppErrorType.malformedResponse,
      'The server response did not contain a records list.',
    );
  }

  SyncOperationResult _interpretWrite(
    dynamic decoded, {
    required String expectedAadhaar,
  }) {
    if (decoded is List) {
      if (decoded.isEmpty) {
        return const SyncOperationResult.unconfirmed(
          'Server returned no confirmation for this change.',
        );
      }
      return SyncOperationResult.ok;
    }
    if (decoded is Map) {
      final map = decoded.map((k, v) => MapEntry(k.toString(), v));

      final photoFileId =
          map['photoFileId']?.toString().trim().isNotEmpty == true
          ? map['photoFileId'].toString().trim()
          : null;

      final error = map['error'];
      if (error != null) {
        final normalized = error.toString().trim().toLowerCase();
        if (normalized.isNotEmpty &&
            normalized != 'false' &&
            normalized != 'null' &&
            normalized != 'none') {
          final unsupported =
              normalized.contains('unknown action') ||
              normalized.contains('unsupported') ||
              normalized.contains('not implemented');
          if (unsupported) {
            return SyncOperationResult.unsupported(
              'The server does not support this action yet.',
            );
          }
          return SyncOperationResult(
            confirmed: false,
            message: 'Server reported an error: ${error.toString()}',
          );
        }
      }

      final success = map['success'];
      final statusValue = map['status']?.toString().trim().toLowerCase();
      final statusOk =
          statusValue == 'success' ||
          statusValue == 'ok' ||
          statusValue == 'added' ||
          statusValue == 'updated' ||
          statusValue == 'deleted' ||
          statusValue == 'upserted';
      final messageValue = map['message']?.toString().trim().toLowerCase();
      final unsupportedMessage =
          messageValue != null &&
          (messageValue.contains('unsupported') ||
              messageValue.contains('unknown action') ||
              messageValue.contains('not implemented'));

      if (success is bool) {
        if (success) {
          return SyncOperationResult(
            confirmed: true,
            message: 'Confirmed by server',
            photoFileId: photoFileId,
          );
        }
        if (unsupportedMessage) {
          return SyncOperationResult.unsupported(
            'The server does not support this action yet.',
          );
        }
        return SyncOperationResult(
          confirmed: false,
          message: messageValue != null && messageValue.isNotEmpty
              ? 'Server did not confirm the change: ${map['message']}'
              : 'Server did not confirm the change.',
        );
      }

      if (statusOk) {
        return SyncOperationResult(
          confirmed: true,
          message: 'Confirmed by server',
          photoFileId: photoFileId,
        );
      }

      for (final key in const ['result', 'state', 'message']) {
        final value = map[key]?.toString().trim().toLowerCase();
        if (value == null || value.isEmpty) continue;
        if (value.contains('success') ||
            value == 'ok' ||
            value == 'added' ||
            value == 'updated' ||
            value == 'deleted' ||
            value == 'upserted') {
          return SyncOperationResult(
            confirmed: true,
            message: 'Confirmed by server',
            photoFileId: photoFileId,
          );
        }
        if (value.contains('unknown action') ||
            value.contains('unsupported') ||
            value.contains('not implemented')) {
          return SyncOperationResult.unsupported(
            'The server does not support this action yet.',
          );
        }
        if (value.contains('error') || value.contains('fail')) {
          return const SyncOperationResult(
            confirmed: false,
            message: 'Server did not confirm the change.',
          );
        }
      }

      // Echo of the affected record counts as confirmation.
      final echoedAadhaar =
          map['aadhaarNumber'] ??
          map['id'] ??
          (map['record'] is Map
              ? (map['record'] as Map)['aadhaarNumber'] ??
                    (map['record'] as Map)['id']
              : null);
      if (echoedAadhaar != null &&
          echoedAadhaar.toString() == expectedAadhaar) {
        return SyncOperationResult(
          confirmed: true,
          message: 'Confirmed by server',
          photoFileId: photoFileId,
        );
      }
    }
    return const SyncOperationResult.unconfirmed(
      'Server did not confirm the change.',
    );
  }
}
