import '../../core/errors/app_exception.dart';
import '../../core/utils/safe_logger.dart';
import '../models/personal_record.dart';
import '../models/sync_status.dart';
import '../repositories/record_repository.dart';
import 'google_sheets_service.dart';

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
  SyncService(this._repository, this._sheets);

  final RecordRepository _repository;
  final GoogleSheetsService _sheets;

  Future<SyncReport> syncAll() async {
    final startedAt = DateTime.now().toUtc();
    final pushResult = await _pushLocalChanges();
    if (pushResult.offline) {
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
          final result = await _sheets.deleteRecord(record.id);
          if (result.confirmed) {
            await _repository.hardDelete(record.id);
            pushed++;
          } else {
            await _repository.markFailed(record.id);
            failed++;
          }
          continue;
        }

        // Only use `update` for records the server already knows about, to
        // avoid duplicate appends on servers where `add` is not idempotent.
        final result = record.lastSyncedAt != null
            ? await _sheets.updateRecord(record)
            : await _sheets.addRecord(record);

        if (result.confirmed) {
          await _repository.markSynced(
            record.id,
            expectedUpdatedAt: record.updatedAt,
          );
          pushed++;
        } else {
          await _repository.markFailed(record.id);
          failed++;
        }
      } on AppException catch (e) {
        await _repository.markFailed(record.id);
        failed++;
        if (e.type == AppErrorType.network || e.type == AppErrorType.timeout) {
          SafeLogger.info('Push aborted: transport failure');
          return _PushResult(pushed: pushed, failed: failed, offline: true);
        }
        SafeLogger.error('sync_push', e, e.stackTrace);
      } catch (e, s) {
        await _repository.markFailed(record.id);
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
    final localById = <String, PersonalRecord>{for (final r in local) r.id: r};
    final remoteById = <String, PersonalRecord>{
      for (final r in remote) r.id: r,
    };

    var pulled = 0;
    var conflicts = 0;

    for (final remoteRecord in remote) {
      final localRecord = localById[remoteRecord.id];
      if (localRecord == null) {
        // Brand new record that only exists remotely.
        await _repository.upsertFromRemote(remoteRecord);
        pulled++;
        continue;
      }

      if (localRecord.syncStatus == SyncStatus.synced &&
          !localRecord.isDeleted) {
        if (remoteRecord.updatedAt.isAfter(localRecord.updatedAt)) {
          await _repository.upsertFromRemote(remoteRecord);
          pulled++;
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
          localRecord.id,
          remoteUpdatedAt: remoteRecord.updatedAt,
        );
        conflicts++;
      }
      // Otherwise the local change simply wins on the next push.
    }

    // Local synced records absent from the server: possible remote deletion.
    // Records that were (re)synced earlier in this run are excluded, since a
    // follow-up GET may not reflect them yet.
    for (final localRecord in local) {
      if (localRecord.syncStatus != SyncStatus.synced) continue;
      if (localRecord.isDeleted) continue;
      if (remoteById.containsKey(localRecord.id)) continue;
      final syncedThisRun =
          localRecord.lastSyncedAt != null &&
          !localRecord.lastSyncedAt!.isBefore(startedAt);
      if (syncedThisRun) continue;
      await _repository.markConflict(localRecord.id);
      conflicts++;
    }

    await _repository.setLastSyncAt(DateTime.now());

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
  Future<PersonalRecord?> fetchRemote(String id) async {
    final remote = await _sheets.fetchRecords();
    for (final record in remote) {
      if (record.id == id) return record;
    }
    return null;
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
