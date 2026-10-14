import 'package:connectivity_plus/connectivity_plus.dart';

/// Wraps `connectivity_plus` and exposes a simple online/offline signal.
///
/// This reports radio/interface state only. It is used to *trigger* sync
/// attempts, not to guarantee that a request will succeed.
class ConnectivityService {
  ConnectivityService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<bool> get onStatusChange =>
      _connectivity.onConnectivityChanged.map(isOnlineResults).distinct();

  Future<bool> isOnline() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return isOnlineResults(results);
    } catch (_) {
      // If connectivity cannot be determined, assume online and let the
      // request itself fail gracefully.
      return true;
    }
  }

  static bool isOnlineResults(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }
}
