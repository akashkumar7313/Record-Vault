import 'package:flutter/foundation.dart';

import '../utils/safe_logger.dart';

/// Installs global Flutter/Dart error handlers.
///
/// Errors are logged in a PII-free form and swallowed so a single failure can
/// never crash the whole app. User-facing messaging happens at the call site
/// through [AppException].
class AppErrorHandler {
  AppErrorHandler._();

  static void install() {
    FlutterError.onError = (FlutterErrorDetails details) {
      SafeLogger.error('flutter_error', details.exception, details.stack);
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      SafeLogger.error('platform_error', error, stack);
      return true;
    };
  }
}
