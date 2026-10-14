import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/personal_record.dart';
import '../models/sync_status.dart';

/// Table and column names used by the local store.
class DbSchema {
  DbSchema._();

  static const String recordsTable = 'records';
  static const String metaTable = 'app_meta';
}

/// Low-level SQLite access for RecordVault.
///
/// [databaseFactory] and [databasePath] are injectable so the same class can be
/// unit-tested against an in-memory database via `sqflite_common_ffi`.
class AppDatabase {
  AppDatabase({DatabaseFactory? factory, String? databasePath})
    : _factory = factory ?? databaseFactory,
      _overridePath = databasePath;

  final DatabaseFactory _factory;
  final String? _overridePath;
  Database? _db;

  Future<Database> get database async {
    return _db ??= await _open();
  }

  Future<Database> _open() async {
    final path =
        _overridePath ?? p.join(await _defaultDir(), 'record_vault.db');
    return _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<String> _defaultDir() async {
    // Imported lazily to avoid pulling plugin code into pure unit tests.
    return getDatabasesPath();
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ${DbSchema.recordsTable} (
        aadhaar_number TEXT PRIMARY KEY,
        full_name TEXT NOT NULL,
        father_name TEXT NOT NULL DEFAULT '',
        mother_name TEXT NOT NULL DEFAULT '',
        mobile_number TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        date_of_birth TEXT NOT NULL,
        gender TEXT NOT NULL,
        photo_path TEXT,
        photo_file_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        last_synced_at TEXT,
        remote_updated_at TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_records_full_name ON ${DbSchema.recordsTable}(full_name)',
    );
    await db.execute(
      'CREATE INDEX idx_records_mobile ON ${DbSchema.recordsTable}(mobile_number)',
    );
    await db.execute(
      'CREATE INDEX idx_records_updated ON ${DbSchema.recordsTable}(updated_at)',
    );
    await db.execute(
      'CREATE INDEX idx_records_sync ON ${DbSchema.recordsTable}(sync_status)',
    );

    await db.execute('''
      CREATE TABLE ${DbSchema.metaTable} (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1 keyed records by a random `id` with no Aadhaar column, which cannot
      // be mapped onto the new Aadhaar primary key. The records table is rebuilt
      // (local cache only — the source of truth is the device + Sheets).
      await db.execute('DROP TABLE IF EXISTS ${DbSchema.recordsTable}');
      await db.execute('''
        CREATE TABLE ${DbSchema.recordsTable} (
          aadhaar_number TEXT PRIMARY KEY,
          full_name TEXT NOT NULL,
          father_name TEXT NOT NULL DEFAULT '',
          mother_name TEXT NOT NULL DEFAULT '',
          mobile_number TEXT NOT NULL DEFAULT '',
          email TEXT NOT NULL DEFAULT '',
          address TEXT NOT NULL DEFAULT '',
          date_of_birth TEXT NOT NULL,
          gender TEXT NOT NULL,
          photo_path TEXT,
          photo_file_id TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          sync_status TEXT NOT NULL DEFAULT 'pending',
          last_synced_at TEXT,
          remote_updated_at TEXT,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          deleted_at TEXT
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_records_full_name ON ${DbSchema.recordsTable}(full_name)',
      );
      await db.execute(
        'CREATE INDEX idx_records_mobile ON ${DbSchema.recordsTable}(mobile_number)',
      );
      await db.execute(
        'CREATE INDEX idx_records_updated ON ${DbSchema.recordsTable}(updated_at)',
      );
      await db.execute(
        'CREATE INDEX idx_records_sync ON ${DbSchema.recordsTable}(sync_status)',
      );
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ---------------------------------------------------------------------------
  // Records
  // ---------------------------------------------------------------------------

  Future<void> upsertRecord(PersonalRecord record) async {
    final db = await database;
    await db.insert(
      DbSchema.recordsTable,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<PersonalRecord?> getRecord(String aadhaarNumber) async {
    final db = await database;
    final rows = await db.query(
      DbSchema.recordsTable,
      where: 'aadhaar_number = ?',
      whereArgs: [aadhaarNumber],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PersonalRecord.fromMap(rows.first);
  }

  Future<List<PersonalRecord>> getRecords({
    bool includeDeleted = false,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    final rows = await db.query(
      DbSchema.recordsTable,
      where: includeDeleted ? null : 'is_deleted = 0',
      orderBy: 'updated_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(PersonalRecord.fromMap).toList(growable: false);
  }

  Future<List<PersonalRecord>> searchRecords(
    String query, {
    bool includeDeleted = false,
    int? limit,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return getRecords(includeDeleted: includeDeleted, limit: limit);
    }
    final db = await database;
    final like = '%${trimmed.toLowerCase()}%';
    final conditions = <String>[
      "(LOWER(full_name) LIKE ? OR LOWER(mobile_number) LIKE ? "
          "OR LOWER(aadhaar_number) LIKE ?)",
    ];
    if (!includeDeleted) conditions.add('is_deleted = 0');

    final rows = await db.query(
      DbSchema.recordsTable,
      where: conditions.join(' AND '),
      whereArgs: [like, like, like],
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return rows.map(PersonalRecord.fromMap).toList(growable: false);
  }

  Future<int> countRecords({bool includeDeleted = false}) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${DbSchema.recordsTable}'
      '${includeDeleted ? '' : ' WHERE is_deleted = 0'}',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Map<SyncStatus, int>> syncStatusCounts() async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT sync_status, COUNT(*) AS c FROM ${DbSchema.recordsTable} '
      'GROUP BY sync_status',
    );
    final counts = <SyncStatus, int>{};
    for (final row in rows) {
      final status = SyncStatus.fromStorage(row['sync_status'] as String?);
      counts[status] = (row['c'] as int?) ?? 0;
    }
    return counts;
  }

  /// Records that still need to be pushed to the server (dirty or tombstoned).
  ///
  /// Records in [SyncStatus.conflict] are deliberately excluded: they require
  /// an explicit user decision and must never be auto-overwritten.
  Future<List<PersonalRecord>> getPendingRecords() async {
    final db = await database;
    final rows = await db.query(
      DbSchema.recordsTable,
      where: "(sync_status IN (?, ?)) OR (is_deleted = 1 AND sync_status != ?)",
      whereArgs: [
        SyncStatus.pending.storageValue,
        SyncStatus.failed.storageValue,
        SyncStatus.conflict.storageValue,
      ],
      orderBy: 'updated_at ASC',
    );
    return rows.map(PersonalRecord.fromMap).toList(growable: false);
  }

  Future<void> deleteRecordPermanently(String aadhaarNumber) async {
    final db = await database;
    await db.delete(
      DbSchema.recordsTable,
      where: 'aadhaar_number = ?',
      whereArgs: [aadhaarNumber],
    );
  }

  Future<void> deleteAllRecords() async {
    final db = await database;
    await db.delete(DbSchema.recordsTable);
  }

  // ---------------------------------------------------------------------------
  // Meta key/value
  // ---------------------------------------------------------------------------

  Future<String?> getMeta(String key) async {
    final db = await database;
    final rows = await db.query(
      DbSchema.metaTable,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String? value) async {
    final db = await database;
    await db.insert(DbSchema.metaTable, {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
