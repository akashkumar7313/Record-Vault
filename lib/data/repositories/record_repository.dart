import '../../core/constants/app_constants.dart';
import '../../core/utils/safe_logger.dart';
import '../database/app_database.dart';
import '../models/personal_record.dart';
import '../models/sync_status.dart';

/// Domain-facing persistence API. UI and sync layers depend on this class
/// rather than talking to [AppDatabase] directly, keeping storage concerns
/// isolated (single responsibility / dependency inversion).
///
/// Records are keyed by their 12-digit [PersonalRecord.aadhaarNumber].
class RecordRepository {
  RecordRepository(this._db);

  final AppDatabase _db;

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  Future<List<PersonalRecord>> getAll({bool includeDeleted = false}) async {
    final records = await _db.getRecords(includeDeleted: includeDeleted);
    SafeLogger.trace(
      'LOCAL',
      'read.all',
      detail: 'count=${records.length} includeDeleted=$includeDeleted',
    );
    return records;
  }

  Future<List<PersonalRecord>> search(
    String query, {
    bool includeDeleted = false,
  }) async {
    final records = await _db.searchRecords(
      query,
      includeDeleted: includeDeleted,
    );
    SafeLogger.trace('LOCAL', 'read.search', detail: 'hits=${records.length}');
    return records;
  }

  Future<List<PersonalRecord>> getRecent({
    int limit = AppConstants.recentRecordsLimit,
  }) => _db.getRecords(limit: limit);

  Future<PersonalRecord?> getByAadhaar(String aadhaarNumber) async {
    final record = await _db.getRecord(aadhaarNumber);
    SafeLogger.trace('LOCAL', 'read.one', id: aadhaarNumber);
    return record;
  }

  Future<int> count() => _db.countRecords();

  Future<Map<SyncStatus, int>> statusCounts() => _db.syncStatusCounts();

  Future<List<PersonalRecord>> getPending() async {
    final records = await _db.getPendingRecords();
    SafeLogger.trace(
      'LOCAL',
      'read.pending',
      detail: 'count=${records.length}',
    );
    return records;
  }

  // ---------------------------------------------------------------------------
  // Local writes
  // ---------------------------------------------------------------------------

  /// Inserts a brand new record and marks it pending sync.
  Future<PersonalRecord> create(PersonalRecord record) async {
    final stored = record.copyWith(syncStatus: SyncStatus.pending);
    await _db.upsertRecord(stored);
    SafeLogger.trace('LOCAL', 'create', id: record.aadhaarNumber);
    return stored;
  }

  /// Updates an existing record, bumping [PersonalRecord.updatedAt].
  Future<PersonalRecord> update(PersonalRecord record) async {
    final stored = record.copyWith(
      updatedAt: DateTime.now().toUtc(),
      syncStatus: SyncStatus.pending,
    );
    await _db.upsertRecord(stored);
    SafeLogger.trace('LOCAL', 'update', id: record.aadhaarNumber);
    return stored;
  }

  /// Soft-deletes a record by writing a tombstone. The row is only removed
  /// once the server confirms deletion (see [hardDelete]).
  Future<void> markDeleted(String aadhaarNumber) async {
    final existing = await _db.getRecord(aadhaarNumber);
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
    SafeLogger.trace('LOCAL', 'delete.soft', id: aadhaarNumber);
  }

  Future<void> hardDelete(String aadhaarNumber) async {
    await _db.deleteRecordPermanently(aadhaarNumber);
    SafeLogger.trace('LOCAL', 'delete.hard', id: aadhaarNumber);
  }

  /// Stores a locally-cached copy of a record's remote photo without touching
  /// sync metadata (used to backfill photos for already-synced records).
  Future<void> attachPhoto(String aadhaarNumber, String path) async {
    final current = await _db.getRecord(aadhaarNumber);
    if (current == null) return;
    await _db.upsertRecord(current.copyWith(photoPath: path));
    SafeLogger.trace('LOCAL', 'photo.attach', id: aadhaarNumber);
  }

  // ---------------------------------------------------------------------------
  // Sync-state transitions
  // ---------------------------------------------------------------------------

  /// Marks a record synced, but only if the local copy still matches
  /// [expectedUpdatedAt]. This prevents a sync round-trip from overwriting a
  /// newer edit made while the request was in flight.
  Future<bool> markSynced(
    String aadhaarNumber, {
    DateTime? syncedAt,
    DateTime? remoteUpdatedAt,
    DateTime? expectedUpdatedAt,
    String? photoFileId,
  }) async {
    final current = await _db.getRecord(aadhaarNumber);
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
        photoFileId: photoFileId,
      ),
    );
    SafeLogger.trace(
      'LOCAL',
      'mark.synced',
      id: aadhaarNumber,
      detail: 'photoFileId=${photoFileId == null ? '-' : 'yes'}',
    );
    return true;
  }

  Future<void> markFailed(String aadhaarNumber) async {
    final current = await _db.getRecord(aadhaarNumber);
    if (current == null) return;
    if (current.syncStatus == SyncStatus.conflict) return;
    await _db.upsertRecord(current.copyWith(syncStatus: SyncStatus.failed));
    SafeLogger.trace('LOCAL', 'mark.failed', id: aadhaarNumber);
  }

  Future<void> markConflict(
    String aadhaarNumber, {
    DateTime? remoteUpdatedAt,
  }) async {
    final current = await _db.getRecord(aadhaarNumber);
    if (current == null) return;
    await _db.upsertRecord(
      current.copyWith(
        syncStatus: SyncStatus.conflict,
        remoteUpdatedAt: remoteUpdatedAt ?? current.remoteUpdatedAt,
      ),
    );
    SafeLogger.trace('LOCAL', 'mark.conflict', id: aadhaarNumber);
  }

  /// User chose to keep their local version of a conflicting record.
  Future<void> resolveKeepLocal(String aadhaarNumber) async {
    final current = await _db.getRecord(aadhaarNumber);
    if (current == null) return;
    await _db.upsertRecord(current.copyWith(syncStatus: SyncStatus.pending));
    SafeLogger.trace('LOCAL', 'resolve.keepLocal', id: aadhaarNumber);
  }

  /// Overwrites the local copy with the authoritative server version.
  Future<void> resolveUseRemote(PersonalRecord remote) async {
    final existing = await _db.getRecord(remote.aadhaarNumber);
    await _db.upsertRecord(
      remote.copyWith(
        photoPath: remote.photoPath ?? existing?.photoPath,
        photoFileId: remote.photoFileId ?? existing?.photoFileId,
        syncStatus: SyncStatus.synced,
        lastSyncedAt: DateTime.now().toUtc(),
        remoteUpdatedAt: remote.updatedAt,
      ),
    );
    SafeLogger.trace('LOCAL', 'resolve.useRemote', id: remote.aadhaarNumber);
  }

  /// Stores a record pulled from the server as already-synced, keeping the
  /// local photo file if the remote copy has none.
  Future<void> upsertFromRemote(PersonalRecord remote) async {
    final existing = await _db.getRecord(remote.aadhaarNumber);
    await _db.upsertRecord(
      remote.copyWith(
        photoPath: remote.photoPath ?? existing?.photoPath,
        photoFileId: remote.photoFileId ?? existing?.photoFileId,
        syncStatus: SyncStatus.synced,
        lastSyncedAt: DateTime.now().toUtc(),
        remoteUpdatedAt: remote.updatedAt,
      ),
    );
    SafeLogger.trace('LOCAL', 'upsert.fromRemote', id: remote.aadhaarNumber);
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
