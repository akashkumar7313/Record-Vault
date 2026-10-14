import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/data_providers.dart';
import '../../../data/services/sync_service.dart';
import '../../records/providers/records_providers.dart';

enum SyncPhase { idle, syncing, success, error }

/// Lightweight, UI-facing sync snapshot.
class SyncState {
  const SyncState({
    this.phase = SyncPhase.idle,
    this.message,
    this.lastSyncAt,
    this.serverReachable,
  });

  final SyncPhase phase;
  final String? message;
  final DateTime? lastSyncAt;
  final bool? serverReachable;

  bool get isSyncing => phase == SyncPhase.syncing;

  SyncState copyWith({
    SyncPhase? phase,
    String? message,
    bool clearMessage = false,
    DateTime? lastSyncAt,
    bool? serverReachable,
  }) {
    return SyncState(
      phase: phase ?? this.phase,
      message: clearMessage ? null : (message ?? this.message),
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      serverReachable: serverReachable ?? this.serverReachable,
    );
  }
}

/// Drives manual and connectivity-triggered synchronisation.
final syncControllerProvider = AsyncNotifierProvider<SyncController, SyncState>(
  SyncController.new,
);

class SyncController extends AsyncNotifier<SyncState> {
  bool _running = false;

  @override
  Future<SyncState> build() async {
    // Auto-sync when connectivity first appears or returns.
    ref.listen<AsyncValue<bool>>(connectivityProvider, (previous, next) {
      final wasOffline = previous?.value == false;
      final nowOnline = next.value == true;
      if (nowOnline && (previous == null || wasOffline)) {
        unawaited(syncNow(auto: true));
      }
    });

    final repository = ref.watch(recordRepositoryProvider);
    final lastSyncAt = await repository.getLastSyncAt();
    return SyncState(lastSyncAt: lastSyncAt);
  }

  Future<SyncReport?> syncNow({bool auto = false}) async {
    if (_running) return null;
    _running = true;

    final current = state.value ?? const SyncState();
    state = AsyncData(
      current.copyWith(
        phase: SyncPhase.syncing,
        message: 'Syncing with Google Sheets…',
      ),
    );

    try {
      final report = await ref.read(syncServiceProvider).syncAll();
      final lastSyncAt = await ref
          .read(recordRepositoryProvider)
          .getLastSyncAt();

      state = AsyncData(
        SyncState(
          phase: report.hasIssues ? SyncPhase.error : SyncPhase.success,
          message: report.message,
          lastSyncAt: lastSyncAt ?? current.lastSyncAt,
          serverReachable: report.serverReachable,
        ),
      );
      ref.invalidate(recordsProvider);
      ref.invalidate(recordStatsProvider);
      return report;
    } catch (e) {
      state = AsyncData(
        current.copyWith(
          phase: SyncPhase.error,
          message: 'Sync failed. Your local data is safe.',
        ),
      );
      return null;
    } finally {
      _running = false;
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

/// Probes the configured endpoint for reachability (used by Settings).
final connectionStatusProvider = FutureProvider<bool>((ref) async {
  return ref.watch(googleSheetsServiceProvider).checkConnection();
});
