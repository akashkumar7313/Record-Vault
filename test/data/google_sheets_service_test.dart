import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:record_vault/core/errors/app_exception.dart';
import 'package:record_vault/data/models/gender.dart';
import 'package:record_vault/data/models/personal_record.dart';
import 'package:record_vault/data/models/sync_status.dart';
import 'package:record_vault/data/services/google_sheets_service.dart';

final _endpoint = Uri.parse('https://example.com/exec');

GoogleSheetsService serviceWith(MockClient client) => GoogleSheetsService(
  endpoint: _endpoint,
  client: client,
  readRetries: 1,
  writeRetries: 1,
);

PersonalRecord sample() => PersonalRecord(
  aadhaarNumber: '123456789012',
  fullName: 'Asha Verma',
  mobileNumber: '9876543210',
  email: 'asha@example.com',
  address: '12 Main Street',
  dateOfBirth: DateTime.utc(1990, 5, 20),
  gender: Gender.female,
  createdAt: DateTime.utc(2024, 1, 1),
  updatedAt: DateTime.utc(2024, 1, 1),
);

void main() {
  group('fetchRecords', () {
    test('parses an object with a records list', () async {
      final service = serviceWith(
        MockClient(
          (_) async => http.Response(
            '{"records":[{"aadhaarNumber":"123456789012",'
            '"fullName":"Asha Verma"}]}',
            200,
          ),
        ),
      );
      final records = await service.fetchRecords();
      expect(records, hasLength(1));
      expect(records.first.fullName, 'Asha Verma');
      expect(records.first.aadhaarNumber, '123456789012');
      expect(records.first.syncStatus, SyncStatus.synced);
    });

    test('parses a bare JSON array', () async {
      final service = serviceWith(
        MockClient(
          (_) async => http.Response(
            '[{"aadhaarNumber":"111111111111"},{"aadhaarNumber":"222222222222"}]',
            200,
          ),
        ),
      );
      expect(await service.fetchRecords(), hasLength(2));
    });

    test('throws malformed on invalid JSON', () async {
      final service = serviceWith(
        MockClient((_) async => http.Response('not json', 200)),
      );
      expect(
        () => service.fetchRecords(),
        throwsA(
          isA<AppException>().having(
            (e) => e.type,
            'type',
            AppErrorType.malformedResponse,
          ),
        ),
      );
    });

    test('throws server error on an HTML login page', () async {
      final service = serviceWith(
        MockClient((_) async => http.Response('<html>Sign in</html>', 200)),
      );
      expect(
        () => service.fetchRecords(),
        throwsA(
          isA<AppException>().having(
            (e) => e.type,
            'type',
            AppErrorType.server,
          ),
        ),
      );
    });

    test('throws timeout when the request times out', () async {
      final service = serviceWith(
        MockClient((_) async => throw TimeoutException('slow')),
      );
      expect(
        () => service.fetchRecords(),
        throwsA(
          isA<AppException>().having(
            (e) => e.type,
            'type',
            AppErrorType.timeout,
          ),
        ),
      );
    });

    test('throws network on socket failure', () async {
      final service = serviceWith(
        MockClient((_) async => throw const SocketException('no route')),
      );
      expect(
        () => service.fetchRecords(),
        throwsA(
          isA<AppException>().having(
            (e) => e.type,
            'type',
            AppErrorType.network,
          ),
        ),
      );
    });

    test('throws server on 5xx', () async {
      final service = serviceWith(
        MockClient((_) async => http.Response('boom', 500)),
      );
      expect(
        () => service.fetchRecords(),
        throwsA(
          isA<AppException>().having(
            (e) => e.type,
            'type',
            AppErrorType.server,
          ),
        ),
      );
    });

    test('surfaces a server error envelope', () async {
      final service = serviceWith(
        MockClient(
          (_) async => http.Response('{"error":"sheet missing"}', 200),
        ),
      );
      expect(() => service.fetchRecords(), throwsA(isA<AppException>()));
    });
  });

  group('addRecord', () {
    test('is confirmed on an explicit success status', () async {
      final service = serviceWith(
        MockClient((_) async => http.Response('{"status":"success"}', 200)),
      );
      final result = await service.addRecord(sample());
      expect(result.confirmed, isTrue);
    });

    test('is confirmed when the Aadhaar is echoed', () async {
      final service = serviceWith(
        MockClient(
          (_) async => http.Response('{"aadhaarNumber":"123456789012"}', 200),
        ),
      );
      expect((await service.addRecord(sample())).confirmed, isTrue);
    });

    test('returns the Drive photo file id from the response', () async {
      final service = serviceWith(
        MockClient(
          (_) async =>
              http.Response('{"success":true,"photoFileId":"drive-9"}', 200),
        ),
      );
      final result = await service.addRecord(sample(), photoBase64: 'AAAA');
      expect(result.confirmed, isTrue);
      expect(result.photoFileId, 'drive-9');
    });

    test('follows the Apps Script 302 redirect to the echo URL', () async {
      final client = MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(
            '',
            302,
            headers: {
              'location':
                  'https://script.googleusercontent.com/macros/echo?x=1',
            },
          );
        }
        return http.Response(
          '{"success":true,"aadhaarNumber":"123456789012"}',
          200,
        );
      });

      final result = await serviceWith(client).addRecord(sample());
      expect(result.confirmed, isTrue);
    });

    test('is NOT confirmed on an ambiguous body', () async {
      final service = serviceWith(
        MockClient((_) async => http.Response('{}', 200)),
      );
      expect((await service.addRecord(sample())).confirmed, isFalse);
    });

    test('reports unsupported for an unknown action', () async {
      final service = serviceWith(
        MockClient(
          (_) async => http.Response('{"error":"Unknown action: update"}', 200),
        ),
      );
      final result = await service.updateRecord(sample());
      expect(result.confirmed, isFalse);
      expect(result.unsupported, isTrue);
    });

    test('does not confirm when the server reports an error', () async {
      final service = serviceWith(
        MockClient(
          (_) async => http.Response('{"error":"quota exceeded"}', 200),
        ),
      );
      expect((await service.addRecord(sample())).confirmed, isFalse);
    });
  });

  group('checkConnection', () {
    test('returns true for a parseable response', () async {
      final service = serviceWith(
        MockClient((_) async => http.Response('{"records":[]}', 200)),
      );
      expect(await service.checkConnection(), isTrue);
    });

    test('returns false when the request fails', () async {
      final service = serviceWith(
        MockClient((_) async => throw const SocketException('nope')),
      );
      expect(await service.checkConnection(), isFalse);
    });
  });
}
