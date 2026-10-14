import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/shell/home_shell.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/record_avatar.dart';
import '../../../data/models/personal_record.dart';
import '../../../data/providers/data_providers.dart';
import '../../records/providers/records_providers.dart';
import '../../records/widgets/record_search_field.dart';
import '../../settings/providers/settings_providers.dart';
import '../../settings/widgets/sync_status_card.dart';

/// Dashboard: totals, search, recent records and sync status.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(recordStatsProvider);
    final recentAsync = ref.watch(recentRecordsProvider);
    final syncAsync = ref.watch(syncControllerProvider);
    final online = ref.watch(connectivityProvider).value;

    final stats = statsAsync.value ?? RecordStats.empty;
    final syncState = syncAsync.value ?? const SyncState();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sync now',
            icon: const Icon(Icons.sync),
            onPressed: syncState.isSyncing
                ? null
                : () => ref.read(syncControllerProvider.notifier).syncNow(),
          ),
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
            SyncStatusCard(
              syncState: syncState,
              stats: stats,
              onSync: () => ref.read(syncControllerProvider.notifier).syncNow(),
              onOpenDetails: () =>
                  ref.read(navigationTabProvider.notifier).select(1),
            ),
            const SizedBox(height: AppSpacing.xl),
            _SectionTitle(
              title: 'Find a record',
              subtitle: 'Search by name, mobile number or record ID',
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
            _OverviewCard(stats: stats),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.recordForm),
        icon: const Icon(Icons.add),
        label: const Text('Add record'),
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
          return EmptyState(
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
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () =>
          Navigator.of(context)
              .pushNamed(AppRoutes.recordDetails, arguments: record.id),
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
                      record.mobileNumber.isEmpty
                          ? record.email
                          : record.mobileNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
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

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.stats});

  final RecordStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${stats.total}',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Text(
                    'Total records',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${stats.synced}',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Synced to cloud',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${stats.pending}',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Pending sync',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
          label: Text('Open search results in Records'),
        ),
      ),
    );
  }
}
