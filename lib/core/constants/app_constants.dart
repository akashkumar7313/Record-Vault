/// Application-wide constant values.
///
/// Nothing here is secret. The Google Apps Script endpoint is configured in
/// [ApiConfig] and is intentionally treated as untrusted/unauthenticated.
class AppConstants {
  AppConstants._();

  static const String appName = 'RecordVault';
  static const String databaseName = 'record_vault.db';
  static const int databaseVersion = 1;

  /// Network timeout applied to every Google Sheets request.
  static const Duration requestTimeout = Duration(seconds: 20);

  /// Number of attempts for idempotent (read) operations.
  static const int readRetryAttempts = 3;

  /// Number of attempts for writes. Writes are safe to retry because the
  /// server performs id-based upserts, so a retry cannot create a duplicate.
  static const int writeRetryAttempts = 2;

  static const Duration retryBackoff = Duration(milliseconds: 600);

  /// Maximum accepted profile photo size.
  static const int maxPhotoSizeBytes = 6 * 1024 * 1024;

  /// Sub-directory (inside the app documents directory) that holds copies of
  /// selected profile photos.
  static const String photoDirectory = 'record_photos';

  static const int recentRecordsLimit = 5;

  /// Meta keys persisted in the local `app_meta` table.
  static const String metaKeyLastSyncAt = 'last_sync_at';
  static const String metaKeyThemeMode = 'theme_mode';

  /// ISO-8601 date format used for the date-of-birth display.
  static const String dateFormat = 'dd MMM yyyy';
  static const String dateTimeFormat = 'dd MMM yyyy, hh:mm a';
}
