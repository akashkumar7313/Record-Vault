import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../errors/app_exception.dart';

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
    final detail = error is AppException
        ? ' (${error.type.name}): ${error.message}'
        : '';
    developer.log(
      '[$context] failed with $type$detail',
      name: _name,
      error: null,
      stackTrace: kDebugMode ? stackTrace : null,
      level: 1000,
    );
  }

  /// Masks an identifier (for example an Aadhaar number) so only its last four
  /// characters stay visible. Never returns the full value.
  static String mask(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return '<none>';
    if (text.length <= 4) return '••••';
    return '••••${text.substring(text.length - 4)}';
  }

  /// Logs a single data-flow step between the local store and the server.
  ///
  /// [phase] is one of `LOCAL`, `SERVER` or `SYNC`. [detail] must never contain
  /// personal values — use [mask] for identifiers.
  static void trace(String phase, String action, {String? id, String? detail}) {
    if (!kDebugMode) return;
    final parts = <String>['[$phase]', action];
    if (id != null) parts.add('id=${mask(id)}');
    if (detail != null && detail.isNotEmpty) parts.add(detail);
    developer.log(parts.join(' '), name: _name);
  }
}
