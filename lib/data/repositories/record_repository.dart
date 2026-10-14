import '../../core/constants/app_constants.dart';
import '../database/app_database.dart';
import '../models/personal_record.dart';
import '../models/sync_status.dart';

/// Domain-facing persistence API. UI and sync layers depend on this class
/// rather than talking to [AppDatabase] directly, keeping storage concerns
/// isolated (single responsibility / dependency inversion).
class RecordRepository {
  RecordRepository(this._db);

  final AppDatabase _db;

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  Future<List<PersonalRecord>> getAll({bool includeDeleted = false}) =>
      _db.getRecords(includeDeleted: includeDeleted);

  Future<List<PersonalRecord>> search(
    String query, {
    bool includeDeleted = false,
  }) => _db.searchRecords(query, includeDeleted: includeDeleted);

  Future<List<PersonalRecord>> getRecent({
    int limit = AppConstants.recentRecordsLimit,
  }) => _db.getRecords(limit: limit);

  Future<PersonalRecord?> getById(String id) => _db.getRecord(id);

  Future<int> count() => _db.countRecords();

  Future<Map<SyncStatus, int>> statusCounts() => _db.syncStatusCounts();

  Future<List<PersonalRecord>> getPending() => _db.getPendingRecords();

  // ---------------------------------------------------------------------------
  // Local writes
  // ---------------------------------------------------------------------------

  /// Inserts a brand new record and marks it pending sync.
  Future<PersonalRecord> create(PersonalRecord record) async {
    final stored = record.copyWith(syncStatus: SyncStatus.pending);
    await _db.upsertRecord(stored);
    return stored;
  }

  /// Updates an existing record, bumping [PersonalRecord.updatedAt].
  Future<PersonalRecord> update(PersonalRecord record) async {
    final stored = record.copyWith(
      updatedAt: DateTime.now().toUtc(),
      syncStatus: SyncStatus.pending,
    );
    await _db.upsertRecord(stored);
    return stored;
  }

  /// Soft-deletes a record by writing a tombstone. The row is only removed
  /// once the server confirms deletion (see [hardDelete]).
  Future<void> markDeleted(String id) async {
    final existing = await _db.getRecord(id);
    if (existing == null) return;
    final now = DateTime.now().toUtc();
    await _db.upsertRecord(
      existing.copyWith(
        isDeleted: true,
        deletedAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.pending,
      ),
    );
  }

  Future<void> hardDelete(String id) => _db.deleteRecordPermanently(id);

  // ---------------------------------------------------------------------------
  // Sync-state transitions
  // ---------------------------------------------------------------------------

  /// Marks [id] synced, but only if the local copy still matches
  /// [expectedUpdatedAt]. This prevents a sync round-trip from overwriting a
  /// newer edit made while the request was in flight.
  Future<bool> markSynced(
    String id, {
    DateTime? syncedAt,
    DateTime? remoteUpdatedAt,
    DateTime? expectedUpdatedAt,
  }) async {
    final current = await _db.getRecord(id);
    if (current == null) return false;
    if (expectedUpdatedAt != null &&
        current.updatedAt.toUtc() != expectedUpdatedAt.toUtc()) {
      return false;
    }
    final now = (syncedAt ?? DateTime.now()).toUtc();
    await _db.upsertRecord(
      current.copyWith(
        syncStatus: SyncStatus.synced,
        lastSyncedAt: now,
        remoteUpdatedAt: remoteUpdatedAt ?? current.updatedAt,
      ),
    );
    return true;
  }

  Future<void> markFailed(String id) async {
    final current = await _db.getRecord(id);
    if (current == null) return;
    if (current.syncStatus == SyncStatus.conflict) return;
    await _db.upsertRecord(current.copyWith(syncStatus: SyncStatus.failed));
  }

  Future<void> markConflict(String id, {DateTime? remoteUpdatedAt}) async {
    final current = await _db.getRecord(id);
    if (current == null) return;
    await _db.upsertRecord(
      current.copyWith(
        syncStatus: SyncStatus.conflict,
        remoteUpdatedAt: remoteUpdatedAt ?? current.remoteUpdatedAt,
      ),
    );
  }

  /// User chose to keep their local version of a conflicting record.
  Future<void> resolveKeepLocal(String id) async {
    final current = await _db.getRecord(id);
    if (current == null) return;
    await _db.upsertRecord(current.copyWith(syncStatus: SyncStatus.pending));
  }

  /// Overwrites the local copy with the authoritative server version.
  Future<void> resolveUseRemote(PersonalRecord remote) async {
    await _db.upsertRecord(
      remote.copyWith(
        syncStatus: SyncStatus.synced,
        lastSyncedAt: DateTime.now().toUtc(),
        remoteUpdatedAt: remote.updatedAt,
      ),
    );
  }

  /// Stores a record pulled from the server as already-synced.
  Future<void> upsertFromRemote(PersonalRecord remote) async {
    await _db.upsertRecord(
      remote.copyWith(
        syncStatus: SyncStatus.synced,
        lastSyncedAt: DateTime.now().toUtc(),
        remoteUpdatedAt: remote.updatedAt,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Meta
  // ---------------------------------------------------------------------------

  Future<DateTime?> getLastSyncAt() async {
    final raw = await _db.getMeta(AppConstants.metaKeyLastSyncAt);
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  Future<void> setLastSyncAt(DateTime value) => _db.setMeta(
    AppConstants.metaKeyLastSyncAt,
    value.toUtc().toIso8601String(),
  );

  Future<void> setMeta(String key, String? value) => _db.setMeta(key, value);

  Future<String?> getMeta(String key) => _db.getMeta(key);
}
