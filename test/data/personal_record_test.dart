import 'package:flutter_test/flutter_test.dart';
import 'package:record_vault/data/models/gender.dart';
import 'package:record_vault/data/models/personal_record.dart';
import 'package:record_vault/data/models/sync_status.dart';

PersonalRecord buildRecord({
  String aadhaarNumber = '123456789012',
  DateTime? updatedAt,
  DateTime? createdAt,
}) {
  final now = DateTime.utc(2024, 1, 1);
  return PersonalRecord(
    aadhaarNumber: aadhaarNumber,
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

      expect(restored.aadhaarNumber, record.aadhaarNumber);
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

    test('photo file id round-trips and exposes a Drive url', () {
      final record = buildRecord().copyWith(photoFileId: 'drive-abc');
      final restored = PersonalRecord.fromMap(record.toMap());
      expect(restored.photoFileId, 'drive-abc');
      expect(restored.hasRemotePhoto, isTrue);
      expect(restored.photoUrl, contains('drive-abc'));
    });
  });

  group('Remote JSON', () {
    test('toRemoteJson omits local-only fields and uses Aadhaar', () {
      final json = buildRecord().toRemoteJson();
      expect(json.containsKey('syncStatus'), isFalse);
      expect(json.containsKey('photoPath'), isFalse);
      expect(json.containsKey('isDeleted'), isFalse);
      expect(json.containsKey('id'), isFalse);
      expect(json['aadhaarNumber'], '123456789012');
      expect(json['gender'], 'female');
    });

    test('toRemoteJson includes photoBase64 only when provided', () {
      expect(buildRecord().toRemoteJson().containsKey('photoBase64'), isFalse);
      final json = buildRecord().toRemoteJson(photoBase64: 'BASE64');
      expect(json['photoBase64'], 'BASE64');
    });

    test('fromRemoteJson accepts camelCase keys', () {
      final record = PersonalRecord.fromRemoteJson({
        'aadhaarNumber': '111122223333',
        'fullName': 'John Doe',
        'mobileNumber': '1234567890',
        'email': 'john@example.com',
        'dateOfBirth': '1991-02-03T00:00:00.000Z',
        'gender': 'male',
        'photoFileId': 'drive-1',
        'createdAt': '2023-01-01T00:00:00.000Z',
        'updatedAt': '2024-01-01T00:00:00.000Z',
      });

      expect(record.aadhaarNumber, '111122223333');
      expect(record.fullName, 'John Doe');
      expect(record.gender, Gender.male);
      expect(record.photoFileId, 'drive-1');
      expect(record.syncStatus, SyncStatus.synced);
      expect(record.dateOfBirth.year, 1991);
    });

    test('fromRemoteJson accepts snake_case and tolerant dates', () {
      final record = PersonalRecord.fromRemoteJson({
        'aadhaar_number': '444455556666',
        'full_name': 'Jane Doe',
        'date_of_birth': '20/05/1990',
      });
      expect(record.aadhaarNumber, '444455556666');
      expect(record.fullName, 'Jane Doe');
      expect(record.dateOfBirth, DateTime.utc(1990, 5, 20));
    });

    test('fromRemoteJson tolerates missing optional fields', () {
      final record = PersonalRecord.fromRemoteJson({'aadhaarNumber': 'only'});
      expect(record.aadhaarNumber, 'only');
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
