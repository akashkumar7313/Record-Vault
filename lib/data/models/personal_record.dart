import 'dart:convert';

import 'gender.dart';
import 'sync_status.dart';

/// The core domain entity for RecordVault.
///
/// Immutable and null-safe. Instances are safe to pass between the UI,
/// repository and sync layers. Personal values must never be logged.
class PersonalRecord {
  const PersonalRecord({
    required this.id,
    required this.fullName,
    this.fatherName = '',
    this.motherName = '',
    this.mobileNumber = '',
    this.email = '',
    this.address = '',
    required this.dateOfBirth,
    this.gender = Gender.other,
    this.photoPath,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.pending,
    this.lastSyncedAt,
    this.remoteUpdatedAt,
    this.isDeleted = false,
    this.deletedAt,
  });

  /// UUID v4 identifier. Also used as the idempotency key with the server.
  final String id;
  final String fullName;
  final String fatherName;
  final String motherName;
  final String mobileNumber;
  final String email;
  final String address;
  final DateTime dateOfBirth;
  final Gender gender;

  /// Absolute path to the locally stored copy of the profile photo.
  final String? photoPath;

  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  /// Last time the server confirmed this record.
  final DateTime? lastSyncedAt;

  /// `updatedAt` reported by the server, used for conflict detection.
  final DateTime? remoteUpdatedAt;

  /// Soft-delete tombstone. Kept until the server confirms deletion.
  final bool isDeleted;
  final DateTime? deletedAt;

  bool get hasPhoto => photoPath != null && photoPath!.isNotEmpty;

  bool get isDirty => syncStatus != SyncStatus.synced;

  PersonalRecord copyWith({
    String? id,
    String? fullName,
    String? fatherName,
    String? motherName,
    String? mobileNumber,
    String? email,
    String? address,
    DateTime? dateOfBirth,
    Gender? gender,
    String? photoPath,
    bool clearPhoto = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
    DateTime? remoteUpdatedAt,
    bool? isDeleted,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return PersonalRecord(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      fatherName: fatherName ?? this.fatherName,
      motherName: motherName ?? this.motherName,
      mobileNumber: mobileNumber ?? this.mobileNumber,
      email: email ?? this.email,
      address: address ?? this.address,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      lastSyncedAt: clearLastSyncedAt
          ? null
          : (lastSyncedAt ?? this.lastSyncedAt),
      remoteUpdatedAt: remoteUpdatedAt ?? this.remoteUpdatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }

  // ---------------------------------------------------------------------------
  // Local persistence (sqflite)
  // ---------------------------------------------------------------------------

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'full_name': fullName,
      'father_name': fatherName,
      'mother_name': motherName,
      'mobile_number': mobileNumber,
      'email': email,
      'address': address,
      'date_of_birth': dateOfBirth.toUtc().toIso8601String(),
      'gender': gender.storageValue,
      'photo_path': photoPath,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'sync_status': syncStatus.storageValue,
      'last_synced_at': lastSyncedAt?.toUtc().toIso8601String(),
      'remote_updated_at': remoteUpdatedAt?.toUtc().toIso8601String(),
      'is_deleted': isDeleted ? 1 : 0,
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    };
  }

  factory PersonalRecord.fromMap(Map<String, Object?> map) {
    return PersonalRecord(
      id: (map['id'] as String?) ?? '',
      fullName: (map['full_name'] as String?) ?? '',
      fatherName: (map['father_name'] as String?) ?? '',
      motherName: (map['mother_name'] as String?) ?? '',
      mobileNumber: (map['mobile_number'] as String?) ?? '',
      email: (map['email'] as String?) ?? '',
      address: (map['address'] as String?) ?? '',
      dateOfBirth: _parseDate(map['date_of_birth']) ?? DateTime(1900),
      gender: Gender.fromStorage(map['gender'] as String?),
      photoPath: map['photo_path'] as String?,
      createdAt: _parseDate(map['created_at']) ?? DateTime.now().toUtc(),
      updatedAt: _parseDate(map['updated_at']) ?? DateTime.now().toUtc(),
      syncStatus: SyncStatus.fromStorage(map['sync_status'] as String?),
      lastSyncedAt: _parseDate(map['last_synced_at']),
      remoteUpdatedAt: _parseDate(map['remote_updated_at']),
      isDeleted: (map['is_deleted'] as int? ?? 0) == 1,
      deletedAt: _parseDate(map['deleted_at']),
    );
  }

  // ---------------------------------------------------------------------------
  // Remote payload (Google Sheets JSON)
  // ---------------------------------------------------------------------------

  /// Payload sent to the Apps Script endpoint. Deliberately excludes local-only
  /// fields such as [syncStatus], [photoPath] and tombstones.
  Map<String, Object?> toRemoteJson() {
    return <String, Object?>{
      'id': id,
      'fullName': fullName,
      'fatherName': fatherName,
      'motherName': motherName,
      'mobileNumber': mobileNumber,
      'email': email,
      'address': address,
      'dateOfBirth': dateOfBirth.toUtc().toIso8601String(),
      'gender': gender.storageValue,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  /// Lenient parser for server rows. Accepts camelCase or snake_case keys and
  /// tolerates missing optional fields.
  factory PersonalRecord.fromRemoteJson(Map<String, Object?> json) {
    final created =
        _parseDate(_pick(json, const ['createdAt', 'created_at', 'created'])) ??
        DateTime.now().toUtc();
    final updated =
        _parseDate(_pick(json, const ['updatedAt', 'updated_at', 'updated'])) ??
        created;
    return PersonalRecord(
      id: (_pickString(json, const ['id', 'recordId', 'record_id'])) ?? '',
      fullName:
          _pickString(json, const ['fullName', 'full_name', 'name']) ?? '',
      fatherName: _pickString(json, const ['fatherName', 'father_name']) ?? '',
      motherName: _pickString(json, const ['motherName', 'mother_name']) ?? '',
      mobileNumber:
          _pickString(json, const [
            'mobileNumber',
            'mobile_number',
            'mobile',
          ]) ??
          '',
      email: _pickString(json, const ['email']) ?? '',
      address: _pickString(json, const ['address']) ?? '',
      dateOfBirth:
          _parseDate(
            _pick(json, const ['dateOfBirth', 'date_of_birth', 'dob']),
          ) ??
          DateTime(1900),
      gender: Gender.fromStorage(_pickString(json, const ['gender'])),
      createdAt: created,
      updatedAt: updated,
      syncStatus: SyncStatus.synced,
      remoteUpdatedAt: updated,
    );
  }

  static Object? _pick(Map<String, Object?> json, List<String> keys) {
    for (final key in keys) {
      if (json.containsKey(key) && json[key] != null) {
        return json[key];
      }
    }
    return null;
  }

  static String? _pickString(Map<String, Object?> json, List<String> keys) {
    final value = _pick(json, keys);
    if (value == null) return null;
    return value.toString();
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    final text = value.toString().trim();
    if (text.isEmpty) return null;

    // Try ISO-8601 first.
    final iso = DateTime.tryParse(text);
    if (iso != null) return iso.toUtc();

    // Try epoch millis encoded as a string.
    final asInt = int.tryParse(text);
    if (asInt != null) {
      return DateTime.fromMillisecondsSinceEpoch(asInt, isUtc: true);
    }

    // Try dd/MM/yyyy (common in Sheets default formatting).
    final parts = text.split(RegExp(r'[/-]'));
    if (parts.length == 3) {
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime.utc(year, month, day);
      }
    }
    return null;
  }

  Map<String, Object?> toRemoteJsonString() => toRemoteJson();

  @override
  String toString() =>
      'PersonalRecord(id: $id, syncStatus: ${syncStatus.name}, '
      'updatedAt: ${updatedAt.toIso8601String()})';
}

/// Convenience helpers for encoding lists of records.
extension PersonalRecordJson on PersonalRecord {
  String encode() => jsonEncode(toRemoteJson());
}
