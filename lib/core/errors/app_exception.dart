/// Categories of failures the app can surface to the user.
///
/// The [AppException.message] is always safe to show and never contains
/// personal record values.
enum AppErrorType {
  validation,
  network,
  timeout,
  server,
  malformedResponse,
  notFound,
  storage,
  export,
  conflict,
  unsupported,
  unknown,
}

/// A typed, user-safe exception used across the data and domain layers.
class AppException implements Exception {
  const AppException(this.type, this.message, {this.cause, this.stackTrace});

  final AppErrorType type;

  /// Technical, non-PII message safe for display.
  final String message;

  /// Original error object. Never rendered to the user.
  final Object? cause;

  final StackTrace? stackTrace;

  /// A short, human friendly message for SnackBars and error views.
  String get userMessage => message;

  /// Builds an [AppException] from an arbitrary error, classifying common
  /// network failures into user-friendly messages.
  factory AppException.from(Object error, [StackTrace? stackTrace]) {
    if (error is AppException) {
      return error;
    }
    final text = error.toString().toLowerCase();
    if (text.contains('socketexception') ||
        text.contains('clientexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable') ||
        text.contains('connection refused') ||
        text.contains('connection closed') ||
        text.contains('connection error')) {
      return AppException(
        AppErrorType.network,
        'No internet connection. Your data is saved locally and will sync later.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (text.contains('timeout') || text.contains('timed out')) {
      return AppException(
        AppErrorType.timeout,
        'The server took too long to respond. Please try again.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is FormatException) {
      return AppException(
        AppErrorType.malformedResponse,
        'Received an unexpected response from the server.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
    return AppException(
      AppErrorType.unknown,
      'Something went wrong. Please try again.',
      cause: error,
      stackTrace: stackTrace,
    );
  }

  @override
  String toString() => 'AppException(${type.name}): $message';
}
