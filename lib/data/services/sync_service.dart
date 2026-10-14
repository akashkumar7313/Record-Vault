import '../../core/errors/app_exception.dart';
import '../../core/utils/safe_logger.dart';
import '../models/personal_record.dart';
import '../models/sync_status.dart';
import '../repositories/record_repository.dart';
import 'google_sheets_service.dart';
import 'photo_storage_service.dart';

/// Immutable summary of a sync run, surfaced to the UI.
class SyncReport {
  const SyncReport({
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.failed = 0,
    this.serverReachable = false,
    required this.message,
  });

  final int pushed;
  final int pulled;
  final int conflicts;
  final int failed;
  final bool serverReachable;
  final String message;

  bool get hasIssues => conflicts > 0 || failed > 0;

  static const SyncReport offline = SyncReport(
    message: 'You are offline. Changes are saved locally and will sync later.',
  );
}

/// Coordinates the offline-first sync between the local SQLite store and the
/// remote Google Sheets endpoint.
///
/// Guarantees:
///  * Local records are never deleted until the server confirms the delete.
///  * A record is marked `synced` only after explicit server confirmation.
///  * Conflicting changes are flagged (`conflict`) and never auto-overwritten.
///  * A failed push leaves the local record intact for a later retry.
class SyncService {
  SyncService(this._repository, this._sheets, {PhotoStorageService? photos})
    // ignore: prefer_initializing_formals
    : _photos = photos;

  final RecordRepository _repository;
  final GoogleSheetsService _sheets;
  final PhotoStorageService? _photos;

  Future<SyncReport> syncAll() async {
    final startedAt = DateTime.now().toUtc();
    SafeLogger.trace('SYNC', 'run.start');
    final pushResult = await _pushLocalChanges();
    if (pushResult.offline) {
      SafeLogger.trace(
        'SYNC',
        'run.offline',
        detail: 'pushed=${pushResult.pushed} failed=${pushResult.failed}',
      );
      return SyncReport(
        failed: pushResult.failed,
        serverReachable: false,
        message: 'No connection. Changes are queued and will sync later.',
      );
    }

    final pullResult = await _pullRemoteChanges(
      startedAt: startedAt,
      pushed: pushResult.pushed,
      pushFailed: pushResult.failed,
    );
    SafeLogger.trace(
      'SYNC',
      'run.done',
      detail:
          'pushed=${pullResult.pushed} pulled=${pullResult.pulled} '
          'conflicts=${pullResult.conflicts} failed=${pullResult.failed} '
          'reachable=${pullResult.serverReachable}',
    );
    return pullResult;
  }

  // ---------------------------------------------------------------------------
  // Push
  // ---------------------------------------------------------------------------

  Future<_PushResult> _pushLocalChanges() async {
    final pending = await _repository.getPending();
    var pushed = 0;
    var failed = 0;

    for (final record in pending) {
      try {
        if (record.isDeleted) {
          SafeLogger.trace('SYNC', 'push.delete', id: record.aadhaarNumber);
          final result = await _sheets.deleteRecord(record.aadhaarNumber);
          if (result.confirmed) {
            await _repository.hardDelete(record.aadhaarNumber);
            pushed++;
            SafeLogger.trace(
              'SYNC',
              'push.delete.ok',
              id: record.aadhaarNumber,
            );
          } else {
            await _repository.markFailed(record.aadhaarNumber);
            failed++;
            SafeLogger.trace(
              'SYNC',
              'push.delete.failed',
              id: record.aadhaarNumber,
              detail: result.message,
            );
          }
          continue;
        }

        // Upload the local photo (if any) so the server can store it in Drive.
        final photoBase64 = await _photos?.readAsBase64(record.photoPath);

        // Only use `update` for records the server already knows about, to
        // avoid duplicate appends on servers where `add` is not idempotent.
        final isUpdate = record.lastSyncedAt != null;
        SafeLogger.trace(
          'SYNC',
          'push.start',
          id: record.aadhaarNumber,
          detail:
              'action=${isUpdate ? 'update' : 'add'} '
              'photo=${photoBase64 == null ? '-' : 'yes'}',
        );
        final result = isUpdate
            ? await _sheets.updateRecord(record, photoBase64: photoBase64)
            : await _sheets.addRecord(record, photoBase64: photoBase64);

        if (result.confirmed) {
          await _repository.markSynced(
            record.aadhaarNumber,
            expectedUpdatedAt: record.updatedAt,
            photoFileId: result.photoFileId,
          );
          pushed++;
          SafeLogger.trace('SYNC', 'push.ok', id: record.aadhaarNumber);
        } else {
          await _repository.markFailed(record.aadhaarNumber);
          failed++;
          SafeLogger.trace(
            'SYNC',
            'push.failed',
            id: record.aadhaarNumber,
            detail: result.message,
          );
        }
      } on AppException catch (e) {
        await _repository.markFailed(record.aadhaarNumber);
        failed++;
        if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
          SafeLogger.info('Push aborted: transport failure');
          return _PushResult(pushed: pushed, failed: failed, offline: true);
        }
        SafeLogger.error('sync_push', e, e.stackTrace);
      } catch (e, s) {
        await _repository.markFailed(record.aadhaarNumber);
        failed++;
        SafeLogger.error('sync_push', e, s);
      }
    }

    await _repository.setLastSyncAt(DateTime.now());
    return _PushResult(pushed: pushed, failed: failed, offline: false);
  }

  // ---------------------------------------------------------------------------
  // Pull + reconcile
  // ---------------------------------------------------------------------------

  Future<SyncReport> _pullRemoteChanges({
    required DateTime startedAt,
    required int pushed,
    required int pushFailed,
  }) async {
    List<PersonalRecord> remote;
    try {
      remote = await _sheets.fetchRecords();
    } on AppException catch (e) {
      SafeLogger.error('sync_pull', e, e.stackTrace);
      final offline =
          e.type == AppErrorType.network || e.type == AppErrorType.timeout;
      return SyncReport(
        pushed: pushed,
        failed: pushFailed,
        serverReachable: !offline,
        message: offline
            ? 'Pushed local changes, but could not fetch remote updates.'
            : 'Could not fetch remote records: ${e.userMessage}',
      );
    }

    final local = await _repository.getAll(includeDeleted: true);
    final localByAadhaar = <String, PersonalRecord>{
      for (final r in local) r.aadhaarNumber: r,
    };
    final remoteByAadhaar = <String, PersonalRecord>{
      for (final r in remote) r.aadhaarNumber: r,
    };

    SafeLogger.trace(
      'SYNC',
      'pull.compare',
      detail: 'remote=${remote.length} local=${local.length}',
    );

    var pulled = 0;
    var conflicts = 0;

    for (final remoteRecord in remote) {
      final localRecord = localByAadhaar[remoteRecord.aadhaarNumber];
      if (localRecord == null) {
        // Brand new record that only exists remotely.
        await _repository.upsertFromRemote(
          await _withDownloadedPhoto(remoteRecord, null),
        );
        pulled++;
        SafeLogger.trace('SYNC', 'pull.new', id: remoteRecord.aadhaarNumber);
        continue;
      }

      if (localRecord.syncStatus == SyncStatus.synced &&
          !localRecord.isDeleted) {
        if (remoteRecord.updatedAt.isAfter(localRecord.updatedAt)) {
          await _repository.upsertFromRemote(
            await _withDownloadedPhoto(remoteRecord, localRecord),
          );
          pulled++;
          SafeLogger.trace(
            'SYNC',
            'pull.updated',
            id: remoteRecord.aadhaarNumber,
          );
        } else if (!localRecord.hasPhoto && localRecord.hasRemotePhoto) {
          // Backfill a locally-cached photo for an unchanged, already-synced
          // record (e.g. after a reinstall wiped local files).
          final path = await _photos?.download(
            remoteRecord.photoUrl ?? '',
            localRecord.aadhaarNumber,
          );
          if (path != null) {
            await _repository.attachPhoto(localRecord.aadhaarNumber, path);
            SafeLogger.trace(
              'SYNC',
              'pull.photo.backfill',
              id: localRecord.aadhaarNumber,
            );
          }
        }
        continue;
      }

      // Local has unsynced changes. If the server also moved, flag conflict.
      final remoteChanged = remoteRecord.updatedAt.isAfter(
        localRecord.remoteUpdatedAt ?? localRecord.createdAt,
      );
      if (remoteChanged &&
          remoteRecord.updatedAt.isAfter(localRecord.updatedAt)) {
        await _repository.markConflict(
          localRecord.aadhaarNumber,
          remoteUpdatedAt: remoteRecord.updatedAt,
        );
        conflicts++;
        SafeLogger.trace(
          'SYNC',
          'pull.conflict',
          id: localRecord.aadhaarNumber,
        );
      }
      // Otherwise the local change simply wins on the next push.
    }

    // Local synced records absent from the server: possible remote deletion.
    // Records that were (re)synced earlier in this run are excluded, since a
    // follow-up GET may not reflect them yet.
    for (final localRecord in local) {
      if (localRecord.syncStatus != SyncStatus.synced) continue;
      if (localRecord.isDeleted) continue;
      if (remoteByAadhaar.containsKey(localRecord.aadhaarNumber)) continue;
      final syncedThisRun =
          localRecord.lastSyncedAt != null &&
          !localRecord.lastSyncedAt!.isBefore(startedAt);
      if (syncedThisRun) continue;
      await _repository.markConflict(localRecord.aadhaarNumber);
      conflicts++;
      SafeLogger.trace(
        'SYNC',
        'pull.missingRemote',
        id: localRecord.aadhaarNumber,
      );
    }

    await _repository.setLastSyncAt(DateTime.now());

    SafeLogger.trace(
      'SYNC',
      'pull.done',
      detail: 'pulled=$pulled conflicts=$conflicts pushFailed=$pushFailed',
    );

    return SyncReport(
      pushed: pushed,
      pulled: pulled,
      conflicts: conflicts,
      failed: pushFailed,
      serverReachable: true,
      message: _buildMessage(
        pushed: pushed,
        pulled: pulled,
        conflicts: conflicts,
        failed: pushFailed,
      ),
    );
  }

  /// Fetches a single record from the server for conflict resolution.
  Future<PersonalRecord?> fetchRemote(String aadhaarNumber) async {
    final remote = await _sheets.fetchRecords();
    for (final record in remote) {
      if (record.aadhaarNumber == aadhaarNumber) return record;
    }
    return null;
  }

  /// Ensures a pulled record has a usable local photo: reuses the existing local
  /// file when present, otherwise downloads the Drive photo once.
  Future<PersonalRecord> _withDownloadedPhoto(
    PersonalRecord remote,
    PersonalRecord? local,
  ) async {
    if (local?.hasPhoto ?? false) return remote;
    if (!remote.hasRemotePhoto) return remote;
    final url = remote.photoUrl;
    if (url == null) return remote;
    final path = await _photos?.download(url, remote.aadhaarNumber);
    if (path == null) return remote;
    SafeLogger.trace('SYNC', 'pull.photo.cached', id: remote.aadhaarNumber);
    return remote.copyWith(photoPath: path);
  }

  String _buildMessage({
    required int pushed,
    required int pulled,
    required int conflicts,
    required int failed,
  }) {
    if (pushed == 0 && pulled == 0 && conflicts == 0 && failed == 0) {
      return 'Everything is up to date.';
    }
    final parts = <String>[];
    if (pushed > 0) {
      parts.add('$pushed uploaded');
    }
    if (pulled > 0) {
      parts.add('$pulled downloaded');
    }
    if (conflicts > 0) {
      parts.add('$conflicts conflict${conflicts == 1 ? '' : 's'}');
    }
    if (failed > 0) {
      parts.add('$failed failed');
    }
    return parts.join(', ');
  }
}

class _PushResult {
  const _PushResult({
    required this.pushed,
    required this.failed,
    required this.offline,
  });

  final int pushed;
  final int failed;
  final bool offline;
}
