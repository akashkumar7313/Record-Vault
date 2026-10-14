import 'package:flutter_test/flutter_test.dart';
import 'package:record_vault/data/database/app_database.dart';
import 'package:record_vault/data/models/gender.dart';
import 'package:record_vault/data/models/personal_record.dart';
import 'package:record_vault/data/models/sync_status.dart';
import 'package:record_vault/data/repositories/record_repository.dart';

import '../helpers/test_database.dart';

PersonalRecord sample({
  String aadhaar = '123456789012',
  String name = 'Asha Verma',
  String mobile = '9876543210',
}) {
  final now = DateTime.utc(2024, 1, 1);
  return PersonalRecord(
    aadhaarNumber: aadhaar,
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
    await repository.markSynced(record.aadhaarNumber);

    final synced = (await repository.getByAadhaar(record.aadhaarNumber))!;
    expect(synced.syncStatus, SyncStatus.synced);

    await repository.update(synced.copyWith(fullName: 'Asha V. Verma'));
    final updated = (await repository.getByAadhaar(record.aadhaarNumber))!;
    expect(updated.fullName, 'Asha V. Verma');
    expect(updated.syncStatus, SyncStatus.pending);
    expect(updated.updatedAt.isAfter(synced.updatedAt), isTrue);
  });

  test(
    'creating a duplicate Aadhaar replaces rather than duplicates',
    () async {
      await repository.create(sample(name: 'First'));
      await repository.create(sample(name: 'Second'));
      expect(await repository.count(), 1);
      expect(
        (await repository.getByAadhaar('123456789012'))!.fullName,
        'Second',
      );
    },
  );

  test('soft delete hides record but keeps tombstone', () async {
    await repository.create(sample());
    await repository.markDeleted('123456789012');

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
    await repository.hardDelete('123456789012');
    expect(await repository.getAll(includeDeleted: true), isEmpty);
  });

  test('search matches name, mobile and Aadhaar', () async {
    await repository.create(sample());
    await repository.create(
      sample(aadhaar: '999988887777', name: 'John Doe', mobile: '1112223333'),
    );

    expect(await repository.search('asha'), hasLength(1));
    expect(await repository.search('9876'), hasLength(1));
    expect(await repository.search('9999'), hasLength(1));
    expect(await repository.search('zzz'), isEmpty);
  });

  test('syncStatusCounts groups correctly', () async {
    await repository.create(sample(aadhaar: '111111111111'));
    await repository.create(sample(aadhaar: '222222222222'));
    await repository.markSynced('111111111111');

    final counts = await repository.statusCounts();
    expect(counts[SyncStatus.synced], 1);
    expect(counts[SyncStatus.pending], 1);
  });

  test('markSynced refuses to overwrite a newer local edit', () async {
    final record = await repository.create(sample());
    final staleVersion = record.updatedAt;
    await repository.update(record.copyWith(fullName: 'Changed meanwhile'));

    final didMark = await repository.markSynced(
      record.aadhaarNumber,
      expectedUpdatedAt: staleVersion,
    );
    expect(didMark, isFalse);
    final current = (await repository.getByAadhaar(record.aadhaarNumber))!;
    expect(current.syncStatus, SyncStatus.pending);
    expect(current.fullName, 'Changed meanwhile');
  });

  test('markSynced stores the returned photo file id', () async {
    final record = await repository.create(sample());
    await repository.markSynced(
      record.aadhaarNumber,
      photoFileId: 'drive-photo-1',
    );
    final synced = (await repository.getByAadhaar('123456789012'))!;
    expect(synced.photoFileId, 'drive-photo-1');
  });

  test('conflict resolution transitions status', () async {
    await repository.create(sample());
    await repository.markConflict('123456789012');
    expect(
      (await repository.getByAadhaar('123456789012'))!.syncStatus,
      SyncStatus.conflict,
    );

    // Conflicts are excluded from the push queue until resolved.
    expect(await repository.getPending(), isEmpty);

    await repository.resolveKeepLocal('123456789012');
    expect(await repository.getPending(), hasLength(1));
  });

  test('last sync timestamp meta round-trips', () async {
    final stamp = DateTime.utc(2025, 3, 4, 5, 6, 7);
    await repository.setLastSyncAt(stamp);
    final loaded = await repository.getLastSyncAt();
    expect(loaded!.toUtc(), stamp);
  });
}
