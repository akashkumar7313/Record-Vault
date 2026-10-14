/// Local sync state for a record.
///
/// [pending]   - created/edited locally, not yet confirmed by the server.
/// [synced]    - server explicitly confirmed the last local change.
/// [failed]    - last sync attempt errored; the record is kept locally.
/// [conflict]  - remote and local both changed; user review required.
enum SyncStatus {
  pending('pending'),
  synced('synced'),
  failed('failed'),
  conflict('conflict');

  const SyncStatus(this.storageValue);

  final String storageValue;

  static SyncStatus fromStorage(String? value) {
    final normalised = (value ?? '').trim().toLowerCase();
    for (final status in SyncStatus.values) {
      if (status.storageValue == normalised) return status;
    }
    return SyncStatus.pending;
  }

  /// Whether this record still needs to be pushed to the server.
  bool get needsUpload => this != SyncStatus.synced;

  bool get isSynced => this == SyncStatus.synced;
}
