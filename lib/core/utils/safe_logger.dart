import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Logging helper that deliberately never logs personal record values.
///
/// Only error categories, operation names and non-identifying diagnostics are
/// emitted. Values passed to [record] are dropped in release builds entirely.
class SafeLogger {
  SafeLogger._();

  static const String _name = 'RecordVault';

  /// Logs a diagnostic message. The [message] must never contain PII.
  static void info(String message) {
    if (kDebugMode) {
      developer.log(message, name: _name);
    }
  }

  /// Logs an error with its type only. Stack traces are attached in debug mode;
  /// [context] should describe the operation, not the data.
  static void error(String context, Object error, [StackTrace? stackTrace]) {
    final type = error.runtimeType;
    developer.log(
      '[$context] failed with $type',
      name: _name,
      error: null,
      stackTrace: kDebugMode ? stackTrace : null,
      level: 1000,
    );
  }
}
