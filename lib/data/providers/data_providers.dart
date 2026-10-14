import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/record_repository.dart';
import '../../data/services/api_config.dart';
import '../../data/services/connectivity_service.dart';
import '../../data/services/excel_export_service.dart';
import '../../data/services/google_sheets_service.dart';
import '../../data/services/photo_storage_service.dart';
import '../../data/services/sync_service.dart';

/// Single shared SQLite database instance.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final recordRepositoryProvider = Provider<RecordRepository>((ref) {
  return RecordRepository(ref.watch(appDatabaseProvider));
});

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final googleSheetsServiceProvider = Provider<GoogleSheetsService>((ref) {
  final service = GoogleSheetsService(
    endpoint: ApiConfig.sheetsEndpoint,
    client: ref.watch(httpClientProvider),
    timeout: AppConstants.requestTimeout,
  );
  return service;
});

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService();
});

/// Emits the current connectivity as a boolean (true = online).
final connectivityProvider = StreamProvider<bool>((ref) {
  return ref.watch(connectivityServiceProvider).onStatusChange;
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    ref.watch(recordRepositoryProvider),
    ref.watch(googleSheetsServiceProvider),
    photos: ref.watch(photoStorageServiceProvider),
  );
});

final excelExportServiceProvider = Provider<ExcelExportService>((ref) {
  return const ExcelExportService();
});

final photoStorageServiceProvider = Provider<PhotoStorageService>((ref) {
  return PhotoStorageService();
});
