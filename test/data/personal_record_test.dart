import 'package:flutter_test/flutter_test.dart';
import 'package:record_vault/data/models/gender.dart';
import 'package:record_vault/data/models/personal_record.dart';
import 'package:record_vault/data/models/sync_status.dart';

PersonalRecord buildRecord({
  String id = 'id-1',
  DateTime? updatedAt,
  DateTime? createdAt,
}) {
  final now = DateTime.utc(2024, 1, 1);
  return PersonalRecord(
    id: id,
    fullName: 'Asha Verma',
    fatherName: 'Ramesh Verma',
    motherName: 'Sunita Verma',
    mobileNumber: '9876543210',
    email: 'asha@example.com',
    address: '12 Main Street',
    dateOfBirth: DateTime.utc(1990, 5, 20),
    gender: Gender.female,
    createdAt: createdAt ?? now,
    updatedAt: updatedAt ?? now,
  );
}

void main() {
  group('PersonalRecord map round-trip', () {
    test('toMap/fromMap preserves values', () {
      final record = buildRecord();
      final restored = PersonalRecord.fromMap(record.toMap());

      expect(restored.id, record.id);
      expect(restored.fullName, record.fullName);
      expect(restored.gender, Gender.female);
      expect(restored.dateOfBirth, record.dateOfBirth);
      expect(restored.syncStatus, record.syncStatus);
    });

    test('tombstone fields round-trip', () {
      final record = buildRecord().copyWith(
        isDeleted: true,
        deletedAt: DateTime.utc(2025, 1, 1),
        syncStatus: SyncStatus.pending,
      );
      final restored = PersonalRecord.fromMap(record.toMap());
      expect(restored.isDeleted, isTrue);
      expect(restored.deletedAt, isNotNull);
    });
  });

  group('Remote JSON', () {
    test('toRemoteJson omits local-only fields', () {
      final json = buildRecord().toRemoteJson();
      expect(json.containsKey('syncStatus'), isFalse);
      expect(json.containsKey('photoPath'), isFalse);
      expect(json.containsKey('isDeleted'), isFalse);
      expect(json['id'], 'id-1');
      expect(json['gender'], 'female');
    });

    test('fromRemoteJson accepts camelCase keys', () {
      final record = PersonalRecord.fromRemoteJson({
        'id': 'abc',
        'fullName': 'John Doe',
        'mobileNumber': '1234567890',
        'email': 'john@example.com',
        'dateOfBirth': '1991-02-03T00:00:00.000Z',
        'gender': 'male',
        'createdAt': '2023-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
      });

      expect(record.fullName, 'John Doe');
      expect(record.gender, Gender.male);
      expect(record.syncStatus, SyncStatus.synced);
      expect(record.dateOfBirth.year, 1991);
    });

    test('fromRemoteJson accepts snake_case and tolerant dates', () {
      final record = PersonalRecord.fromRemoteJson({
        'id': 'abc',
        'full_name': 'Jane Doe',
        'date_of_birth': '20/05/1990',
      });
      expect(record.fullName, 'Jane Doe');
      expect(record.dateOfBirth, DateTime.utc(1990, 5, 20));
    });

    test('fromRemoteJson tolerates missing optional fields', () {
      final record = PersonalRecord.fromRemoteJson({'id': 'only-id'});
      expect(record.id, 'only-id');
      expect(record.fatherName, '');
      expect(record.syncStatus, SyncStatus.synced);
    });
  });

  group('Enums', () {
    test('Gender.fromStorage falls back to other', () {
      expect(Gender.fromStorage('female'), Gender.female);
      expect(Gender.fromStorage('unknown'), Gender.other);
    });

    test('SyncStatus.needsUpload', () {
      expect(SyncStatus.pending.needsUpload, isTrue);
      expect(SyncStatus.failed.needsUpload, isTrue);
      expect(SyncStatus.synced.needsUpload, isFalse);
    });
  });

  test('copyWith clearPhoto removes the photo path', () {
    final record = buildRecord().copyWith(photoPath: '/tmp/a.jpg');
    expect(record.hasPhoto, isTrue);
    expect(record.copyWith(clearPhoto: true).photoPath, isNull);
  });
}
