/// Central configuration for remote endpoints.
///
/// SECURITY NOTE
/// -------------
/// The default Google Apps Script URL is a *publicly reachable* endpoint and
/// MUST NOT be treated as authentication. Anyone with the URL can read/write
/// whatever the script exposes. Use dummy data until an authenticated,
/// server-side access-controlled API is deployed.
///
/// The URL can be overridden at build time without editing source:
///   flutter run --dart-define=RECORD_VAULT_SHEETS_URL=https://...
class ApiConfig {
  ApiConfig._();

  static const String sheetsWebAppUrl = String.fromEnvironment(
    'RECORD_VAULT_SHEETS_URL',
    defaultValue: 'https://script.google.com/macros/s/AKfycbzWyYnVkin2CpohbOf8YkOu4Yyl6Sw15iykoiSDmi3VvBQgfvJttszBs5Iw_hD5HAnu/exec',
  );

  /// Whether the default endpoint has been replaced with a custom one.
  static bool get hasCustomEndpoint =>
      const String.fromEnvironment('RECORD_VAULT_SHEETS_URL').isNotEmpty;

  static Uri get sheetsEndpoint => Uri.parse(sheetsWebAppUrl);
}
