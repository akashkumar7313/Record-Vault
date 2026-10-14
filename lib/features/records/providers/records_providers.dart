import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/personal_record.dart';
import '../../../data/models/sync_status.dart';
import '../../../data/providers/data_providers.dart';

/// Aggregate counts used by the dashboard and settings screens.
class RecordStats {
  const RecordStats({required this.total, required this.byStatus});

  final int total;
  final Map<SyncStatus, int> byStatus;

  int count(SyncStatus status) => byStatus[status] ?? 0;

  int get synced => count(SyncStatus.synced);
  int get conflicts => count(SyncStatus.conflict);
  int get failed => count(SyncStatus.failed);
  int get pending => count(SyncStatus.pending) + failed;
  bool get allSynced => total > 0 && pending == 0 && conflicts == 0;

  static const RecordStats empty = RecordStats(
    total: 0,
    byStatus: <SyncStatus, int>{},
  );
}

/// Current search query shared between dashboard and the records list.
final searchQueryProvider = NotifierProvider<SearchQueryController, String>(
  SearchQueryController.new,
);

class SearchQueryController extends Notifier<String> {
  @override
  String build() => '';

  void update(String value) => state = value;

  void clear() => state = '';
}

/// The main records list, filtered by [searchQueryProvider].
final recordsProvider =
    AsyncNotifierProvider<RecordsController, List<PersonalRecord>>(
      RecordsController.new,
    );

class RecordsController extends AsyncNotifier<List<PersonalRecord>> {
  @override
  Future<List<PersonalRecord>> build() async {
    final repository = ref.watch(recordRepositoryProvider);
    final query = ref.watch(searchQueryProvider).trim();
    return query.isEmpty ? repository.getAll() : repository.search(query);
  }

  Future<List<PersonalRecord>> _load() {
    final repository = ref.read(recordRepositoryProvider);
    final query = ref.read(searchQueryProvider).trim();
    return query.isEmpty ? repository.getAll() : repository.search(query);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  /// Creates or updates a record locally (always pending sync afterwards).
  Future<PersonalRecord> save(
    PersonalRecord record, {
    required bool isNew,
  }) async {
    final repository = ref.read(recordRepositoryProvider);
    final saved = isNew
        ? await repository.create(record)
        : await repository.update(record);
    ref.invalidateSelf();
    await future;
    return saved;
  }

  Future<void> softDelete(String id) async {
    await ref.read(recordRepositoryProvider).markDeleted(id);
    ref.invalidateSelf();
    await future;
  }

  Future<void> resolveKeepLocal(String id) async {
    await ref.read(recordRepositoryProvider).resolveKeepLocal(id);
    ref.invalidateSelf();
    await future;
  }

  Future<void> resolveUseRemote(PersonalRecord remote) async {
    await ref.read(recordRepositoryProvider).resolveUseRemote(remote);
    ref.invalidateSelf();
    await future;
  }
}

/// A single record loaded straight from SQLite (unaffected by search filters).
final recordByIdProvider = FutureProvider.family<PersonalRecord?, String>((
  ref,
  id,
) async {
  ref.watch(recordsProvider);
  return ref.watch(recordRepositoryProvider).getById(id);
});

/// Dashboard aggregate stats; recomputed whenever the record list changes.
final recordStatsProvider = FutureProvider<RecordStats>((ref) async {
  ref.watch(recordsProvider);
  final repository = ref.watch(recordRepositoryProvider);
  final results = await Future.wait([
    repository.count(),
    repository.statusCounts(),
  ]);
  return RecordStats(
    total: results[0] as int,
    byStatus: results[1] as Map<SyncStatus, int>,
  );
});

/// Most recently updated records for the dashboard.
final recentRecordsProvider = FutureProvider<List<PersonalRecord>>((ref) async {
  ref.watch(recordsProvider);
  return ref.watch(recordRepositoryProvider).getRecent();
});
