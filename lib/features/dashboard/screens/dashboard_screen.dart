import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/shell/home_shell.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/record_avatar.dart';
import '../../../data/models/personal_record.dart';
import '../../../data/models/sync_status.dart';
import '../../../data/providers/data_providers.dart';
import '../../records/providers/records_providers.dart';
import '../../records/widgets/record_search_field.dart';
import '../../settings/providers/settings_providers.dart';

/// Dashboard: greeting, sync summary, search, recent records and shortcuts.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statsAsync = ref.watch(recordStatsProvider);
    final recentAsync = ref.watch(recentRecordsProvider);
    final syncAsync = ref.watch(syncControllerProvider);
    final online = ref.watch(connectivityProvider).value;

    final stats = statsAsync.value ?? RecordStats.empty;
    final syncState = syncAsync.value ?? const SyncState();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        titleSpacing: AppSpacing.lg,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _greeting(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              Formatters.date(DateTime.now()),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sync now',
            icon: const Icon(Icons.sync),
            onPressed: syncState.isSyncing
                ? null
                : () => ref.read(syncControllerProvider.notifier).syncNow(),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(recordsProvider.notifier).refresh();
          await ref.read(syncControllerProvider.notifier).refresh();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            120,
          ),
          children: [
            if (online == false) const _OfflineNotice(),
            _VaultSummaryCard(
              syncState: syncState,
              stats: stats,
              onSync: () => ref.read(syncControllerProvider.notifier).syncNow(),
              onOpenDetails: () =>
                  ref.read(navigationTabProvider.notifier).select(1),
            ),
            const SizedBox(height: AppSpacing.xl),
            const _SectionTitle(
              title: 'Find a record',
              subtitle: 'Search by name, mobile number or Aadhaar number',
            ),
            const SizedBox(height: AppSpacing.md),
            RecordSearchField(
              onSubmitted: (_) =>
                  ref.read(navigationTabProvider.notifier).select(1),
            ),
            const _SearchResultsHint(),
            const SizedBox(height: AppSpacing.xl),
            _SectionTitle(
              title: 'Recent records',
              trailing: TextButton(
                onPressed: () =>
                    ref.read(navigationTabProvider.notifier).select(1),
                child: const Text('See all'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _RecentRecords(recordsAsync: recentAsync),
            const SizedBox(height: AppSpacing.xl),
            const _SectionTitle(title: 'Quick actions'),
            const SizedBox(height: AppSpacing.md),
            _QuickActions(
              onAdd: () =>
                  Navigator.of(context).pushNamed(AppRoutes.recordForm),
              onBrowse: () =>
                  ref.read(navigationTabProvider.notifier).select(1),
              onSettings: () =>
                  ref.read(navigationTabProvider.notifier).select(2),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'dashboard_add_record',
        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.recordForm),
        icon: const Icon(Icons.add),
        label: const Text('Add record'),
      ),
    );
  }
}

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String _maskAadhaar(String value) {
  final digits = value.replaceAll(RegExp('[^0-9]'), '');
  if (digits.isEmpty) return 'No Aadhaar';
  if (digits.length <= 4) return '••••';
  return '•••• ${digits.substring(digits.length - 4)}';
}

class _VaultSummaryCard extends StatelessWidget {
  const _VaultSummaryCard({
    required this.syncState,
    required this.stats,
    required this.onSync,
    required this.onOpenDetails,
  });

  final SyncState syncState;
  final RecordStats stats;
  final VoidCallback onSync;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final syncing = syncState.isSyncing;

    final Color accent;
    if (syncing) {
      accent = scheme.primary;
    } else if (syncState.phase == SyncPhase.error || stats.conflicts > 0) {
      accent = scheme.error;
    } else if (stats.pending > 0) {
      accent = const Color(0xFFB26A00);
    } else {
      accent = const Color(0xFF2E7D32);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SyncRing(
                  synced: stats.synced,
                  total: stats.total,
                  syncing: syncing,
                  color: accent,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _headline,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _SummaryChip(
                  icon: Icons.people_outline,
                  label: '${stats.total} total',
                ),
                _SummaryChip(
                  icon: Icons.cloud_done_outlined,
                  label: '${stats.synced} synced',
                  color: const Color(0xFF2E7D32),
                ),
                _SummaryChip(
                  icon: Icons.cloud_upload_outlined,
                  label: '${stats.pending} pending',
                  color: const Color(0xFFB26A00),
                ),
                if (stats.conflicts > 0)
                  _SummaryChip(
                    icon: Icons.sync_problem_outlined,
                    label:
                        '${stats.conflicts} conflict'
                        '${stats.conflicts == 1 ? '' : 's'}',
                    color: scheme.error,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (stats.conflicts > 0) ...[
              OutlinedButton.icon(
                onPressed: onOpenDetails,
                icon: Icon(Icons.rule, color: scheme.error, size: 18),
                label: Text(
                  'Review conflicts',
                  style: TextStyle(color: scheme.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: syncing ? null : onSync,
                icon: const Icon(Icons.sync, size: 18),
                label: Text(syncing ? 'Syncing…' : 'Sync now'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _headline {
    if (syncState.isSyncing) return 'Syncing with Google Sheets…';
    if (stats.total == 0) return 'Welcome to your vault';
    if (stats.conflicts > 0) return 'Conflicts need attention';
    if (stats.pending > 0) {
      return '${stats.pending} change${stats.pending == 1 ? '' : 's'} waiting to sync';
    }
    return 'Everything is up to date';
  }

  String get _subtitle {
    if (syncState.lastSyncAt != null) {
      return 'Last synced ${Formatters.dateTime(syncState.lastSyncAt!)}';
    }
    if (stats.total == 0) {
      return 'Store records securely on this device.';
    }
    return 'Records are stored on this device. Sync when online.';
  }
}

class _SyncRing extends StatelessWidget {
  const _SyncRing({
    required this.synced,
    required this.total,
    required this.syncing,
    required this.color,
  });

  final int synced;
  final int total;
  final bool syncing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = total == 0 ? 0.0 : (synced / total).clamp(0.0, 1.0);

    return SizedBox(
      width: 68,
      height: 68,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 68,
            height: 68,
            child: CircularProgressIndicator(
              value: syncing ? null : value,
              strokeWidth: 6,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
          Text(
            total == 0 ? '—' : '$synced/$total',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: tint),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: tint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onAdd,
    required this.onBrowse,
    required this.onSettings,
  });

  final VoidCallback onAdd;
  final VoidCallback onBrowse;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            _QuickAction(
              icon: Icons.person_add_alt_1,
              label: 'Add record',
              onTap: onAdd,
            ),
            _QuickAction(
              icon: Icons.folder_copy_outlined,
              label: 'Browse',
              onTap: onBrowse,
            ),
            _QuickAction(
              icon: Icons.tune,
              label: 'Settings',
              onTap: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer, size: 22),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        // ignore: use_null_aware_elements
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off,
            size: 18,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Offline — records are saved locally and will sync when you reconnect.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentRecords extends StatelessWidget {
  const _RecentRecords({required this.recordsAsync});

  final AsyncValue<List<PersonalRecord>> recordsAsync;

  @override
  Widget build(BuildContext context) {
    return recordsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: Text(
            'Could not load recent records.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ),
      data: (records) {
        if (records.isEmpty) {
          return const EmptyState(
            icon: Icons.person_add_alt,
            title: 'Welcome to RecordVault',
            message:
                'Store personal records securely on your device and sync '
                'them whenever you choose.',
          );
        }
        return Column(
          children: [
            for (final record in records)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _RecentRecordTile(record: record),
              ),
          ],
        );
      },
    );
  }
}

class _RecentRecordTile extends StatelessWidget {
  const _RecentRecordTile({required this.record});

  final PersonalRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contact = record.mobileNumber.isNotEmpty
        ? record.mobileNumber
        : (record.email.isNotEmpty ? record.email : 'No contact details');

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () => Navigator.of(context)
          .pushNamed(AppRoutes.recordDetails, arguments: record.aadhaarNumber),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          child: Row(
            children: [
              RecordAvatar(
                name: record.fullName,
                photoPath: record.photoPath,
                photoUrl: record.photoUrl,
                radius: 22,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.fullName.isEmpty
                          ? 'Unnamed record'
                          : record.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      contact,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _maskAadhaar(record.aadhaarNumber),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SyncStatusDot(status: record.syncStatus),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small colour-coded status indicator for dense list rows.
class SyncStatusDot extends StatelessWidget {
  const SyncStatusDot({super.key, required this.status});

  final SyncStatus status;

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.statusColor(status, Theme.of(context).colorScheme);
    return Tooltip(
      message: switch (status) {
        SyncStatus.synced => 'Synced',
        SyncStatus.pending => 'Pending',
        SyncStatus.failed => 'Failed',
        SyncStatus.conflict => 'Conflict',
      },
      child: Icon(AppTheme.statusIcon(status), size: 18, color: color),
    );
  }
}

class _SearchResultsHint extends ConsumerWidget {
  const _SearchResultsHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider).trim();
    if (query.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: TextButton.icon(
          onPressed: () => ref.read(navigationTabProvider.notifier).select(1),
          icon: const Icon(Icons.arrow_forward, size: 16),
          label: const Text('Open search results in Records'),
        ),
      ),
    );
  }
}
