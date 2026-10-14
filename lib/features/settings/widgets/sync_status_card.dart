import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../providers/settings_providers.dart';
import '../../records/providers/records_providers.dart';

/// Displays the current sync state, connectivity, and a manual sync action.
/// Used on both the dashboard and the settings screen.
class SyncStatusCard extends StatelessWidget {
  const SyncStatusCard({
    super.key,
    required this.syncState,
    required this.stats,
    required this.onSync,
    this.onOpenDetails,
  });

  final SyncState syncState;
  final RecordStats stats;
  final VoidCallback onSync;

  /// Optional callback when the user taps the conflict warning.
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final syncing = syncState.isSyncing;

    final Color accent;
    final IconData icon;
    if (syncing) {
      accent = scheme.primary;
      icon = Icons.sync;
    } else if (syncState.phase == SyncPhase.error) {
      accent = scheme.error;
      icon = Icons.sync_problem;
    } else if (stats.pending > 0 || stats.conflicts > 0) {
      accent = const Color(0xFFB26A00);
      icon = Icons.cloud_upload_outlined;
    } else {
      accent = const Color(0xFF2E7D32);
      icon = Icons.cloud_done_outlined;
    }

    final subtitle = _subtitle(theme);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: syncing
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: accent,
                          ),
                        )
                      : Icon(icon, color: accent),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _headline,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: syncing ? null : onSync,
                  icon: const Icon(Icons.sync, size: 18),
                  label: Text(syncing ? 'Syncing' : 'Sync'),
                ),
              ],
            ),
            _statusStrip(theme),
          ],
        ),
      ),
    );
  }

  String get _headline {
    if (syncState.isSyncing) return 'Syncing with Google Sheets…';
    if (stats.total == 0) return 'No records yet';
    if (stats.conflicts > 0) return 'Conflicts need attention';
    if (stats.pending > 0) {
      return '${stats.pending} change${stats.pending == 1 ? '' : 's'} waiting to sync';
    }
    return 'All changes synced';
  }

  String _subtitle(ThemeData theme) {
    if (syncState.lastSyncAt != null) {
      return 'Last synced ${Formatters.dateTime(syncState.lastSyncAt!)}';
    }
    return 'Records are stored on this device. Sync when you are online.';
  }

  Widget _statusStrip(ThemeData theme) {
    final items = <(IconData, String)>[
      (Icons.people_outline, '${stats.total} total'),
      (Icons.cloud_done_outlined, '${stats.synced} synced'),
      (Icons.cloud_upload_outlined, '${stats.pending} pending'),
      (
        Icons.sync_problem_outlined,
        '${stats.conflicts} conflict${stats.conflicts == 1 ? '' : 's'}',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: [
          for (final (icon, label) in items)
            _ChipItem(icon: icon, label: label),
        ],
      ),
    );
  }
}

class _ChipItem extends StatelessWidget {
  const _ChipItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
