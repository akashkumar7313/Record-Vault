import 'package:record_vault/data/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Creates an isolated in-memory database for tests.
Future<AppDatabase> createTestDatabase() async {
  sqfliteFfiInit();
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
  // Force creation of the schema.
  await database.database;
  return database;
}
