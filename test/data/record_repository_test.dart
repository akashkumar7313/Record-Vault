import 'package:flutter_test/flutter_test.dart';
import 'package:record_vault/data/database/app_database.dart';
import 'package:record_vault/data/models/gender.dart';
import 'package:record_vault/data/models/personal_record.dart';
import 'package:record_vault/data/models/sync_status.dart';
import 'package:record_vault/data/repositories/record_repository.dart';

import '../helpers/test_database.dart';

PersonalRecord sample({
  String id = 'id-1',
  String name = 'Asha Verma',
  String mobile = '9876543210',
}) {
  final now = DateTime.utc(2024, 1, 1);
  return PersonalRecord(
    id: id,
    fullName: name,
    mobileNumber: mobile,
    email: 'asha@example.com',
    address: '12 Main Street',
    dateOfBirth: DateTime.utc(1990, 5, 20),
    gender: Gender.female,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late RecordRepository repository;
  late AppDatabase database;

  setUp(() async {
    database = await createTestDatabase();
    repository = RecordRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('create sets pending status and persists', () async {
    await repository.create(sample());
    final all = await repository.getAll();
    expect(all, hasLength(1));
    expect(all.first.syncStatus, SyncStatus.pending);
    expect(await repository.count(), 1);
  });

  test('update bumps updatedAt and resets to pending', () async {
    final record = await repository.create(sample());
    await repository.markSynced(record.id);

    final synced = (await repository.getById(record.id))!;
    expect(synced.syncStatus, SyncStatus.synced);

    await repository.update(synced.copyWith(fullName: 'Asha V. Verma'));
    final updated = (await repository.getById(record.id))!;
    expect(updated.fullName, 'Asha V. Verma');
    expect(updated.syncStatus, SyncStatus.pending);
    expect(updated.updatedAt.isAfter(synced.updatedAt), isTrue);
  });

  test('soft delete hides record but keeps tombstone', () async {
    await repository.create(sample());
    await repository.markDeleted('id-1');

    expect(await repository.count(), 0);
    expect(await repository.getAll(), isEmpty);
    final withDeleted = await repository.getAll(includeDeleted: true);
    expect(withDeleted, hasLength(1));
    expect(withDeleted.first.isDeleted, isTrue);

    final pending = await repository.getPending();
    expect(pending, hasLength(1));
  });

  test('hard delete removes the row', () async {
    await repository.create(sample());
    await repository.hardDelete('id-1');
    expect(await repository.getAll(includeDeleted: true), isEmpty);
  });

  test('search matches name, mobile and id (case-insensitive)', () async {
    await repository.create(sample());
    await repository.create(
      sample(id: 'id-2', name: 'John Doe', mobile: '1112223333'),
    );

    expect(await repository.search('asha'), hasLength(1));
    expect(await repository.search('9876'), hasLength(1));
    expect(await repository.search('ID-2'), hasLength(1));
    expect(await repository.search('zzz'), isEmpty);
  });

  test('syncStatusCounts groups correctly', () async {
    await repository.create(sample(id: 'a'));
    await repository.create(sample(id: 'b'));
    await repository.markSynced('a');

    final counts = await repository.statusCounts();
    expect(counts[SyncStatus.synced], 1);
    expect(counts[SyncStatus.pending], 1);
  });

  test('markSynced refuses to overwrite a newer local edit', () async {
    final record = await repository.create(sample());
    final staleVersion = record.updatedAt;
    await repository.update(record.copyWith(fullName: 'Changed meanwhile'));

    final didMark = await repository.markSynced(
      record.id,
      expectedUpdatedAt: staleVersion,
    );
    expect(didMark, isFalse);
    final current = (await repository.getById(record.id))!;
    expect(current.syncStatus, SyncStatus.pending);
    expect(current.fullName, 'Changed meanwhile');
  });

  test('conflict resolution transitions status', () async {
    await repository.create(sample());
    await repository.markConflict('id-1');
    expect((await repository.getById('id-1'))!.syncStatus, SyncStatus.conflict);

    // Conflicts are excluded from the push queue until resolved.
    expect(await repository.getPending(), isEmpty);

    await repository.resolveKeepLocal('id-1');
    expect(await repository.getPending(), hasLength(1));
  });

  test('last sync timestamp meta round-trips', () async {
    final stamp = DateTime.utc(2025, 3, 4, 5, 6, 7);
    await repository.setLastSyncAt(stamp);
    final loaded = await repository.getLastSyncAt();
    expect(loaded!.toUtc(), stamp);
  });
}
