import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/info_tile.dart';
import '../../../core/widgets/record_avatar.dart';
import '../../../core/widgets/sync_status_chip.dart';
import '../../../data/models/personal_record.dart';
import '../../../data/models/sync_status.dart';
import '../../../data/providers/data_providers.dart';
import '../../settings/providers/settings_providers.dart';
import '../providers/records_providers.dart';

/// Full read-only view of a single record with edit/delete/resolve actions.
class RecordDetailsScreen extends ConsumerWidget {
  const RecordDetailsScreen({super.key, required this.aadhaarNumber});

  final String aadhaarNumber;

  Future<void> _edit(BuildContext context, PersonalRecord record) async {
    await Navigator.of(context).pushNamed(
      AppRoutes.recordForm,
      arguments: RecordFormArgs(record: record),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final record = await ref
        .read(recordRepositoryProvider)
        .getByAadhaar(aadhaarNumber);
    if (record == null || !context.mounted) return;

    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete record?',
      message:
          'This will permanently remove "${record.fullName}" locally and '
          'queue the deletion for the next sync.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    await ref.read(recordsProvider.notifier).softDelete(aadhaarNumber);

    // Push the deletion to the sheet right away so it doesn't linger remotely.
    // If we are offline the tombstone stays queued and retries later.
    final report = await ref
        .read(syncControllerProvider.notifier)
        .syncNow(auto: true);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            report != null && report.serverReachable
                ? 'Record deleted.'
                : 'Record deleted. It will sync when you are online.',
          ),
        ),
      );
    Navigator.of(context).pop();
  }

  Future<void> _keepLocal(BuildContext context, WidgetRef ref) async {
    await ref.read(recordsProvider.notifier).resolveKeepLocal(aadhaarNumber);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your version will be pushed on the next sync.'),
      ),
    );
  }

  Future<void> _useServerVersion(
    BuildContext context,
    WidgetRef ref,
    PersonalRecord local,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final remote = await ref
          .read(syncServiceProvider)
          .fetchRemote(aadhaarNumber);
      if (remote == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('The server no longer has this record.'),
          ),
        );
        return;
      }
      await ref.read(recordsProvider.notifier).resolveUseRemote(remote);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Record updated from the server.')),
        );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(AppException.from(e).userMessage)),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordAsync = ref.watch(recordByAadhaarProvider(aadhaarNumber));

    return Scaffold(
      appBar: AppBar(title: const Text('Record details')),
      body: recordAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ErrorView.fromError(error),
        data: (record) {
          if (record == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'Record not found',
            );
          }
          return buildDetails(context, ref, record);
        },
      ),
    );
  }

  Widget buildDetails(
    BuildContext context,
    WidgetRef ref,
    PersonalRecord record,
  ) {
    final theme = Theme.of(context);
    final isConflict = record.syncStatus == SyncStatus.conflict;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        if (isConflict)
          _ConflictBanner(
            onKeepLocal: () => _keepLocal(context, ref),
            onUseServer: () => _useServerVersion(context, ref, record),
          ),
        if (isConflict) const SizedBox(height: AppSpacing.md),
        _HeaderCard(record: record),
        const SizedBox(height: AppSpacing.xl),
        _SectionCard(
          title: 'Contact',
          children: [
            InfoTile(
              label: 'Mobile number',
              value: record.mobileNumber,
              icon: Icons.phone_outlined,
              copyable: true,
            ),
            const Divider(),
            InfoTile(
              label: 'Email',
              value: record.email,
              icon: Icons.mail_outline,
              copyable: true,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _SectionCard(
          title: 'Personal',
          children: [
            InfoTile(
              label: "Father's name",
              value: record.fatherName,
              icon: Icons.man_outlined,
            ),
            const Divider(),
            InfoTile(
              label: "Mother's name",
              value: record.motherName,
              icon: Icons.woman_outlined,
            ),
            const Divider(),
            InfoTile(
              label: 'Full address',
              value: record.address,
              icon: Icons.location_on_outlined,
              copyable: true,
            ),
            const Divider(),
            InfoTile(
              label: 'Date of birth',
              value: Formatters.date(record.dateOfBirth),
              icon: Icons.cake_outlined,
            ),
            const Divider(),
            InfoTile(
              label: 'Gender',
              value: record.gender.label,
              icon: Icons.wc_outlined,
            ),
            const Divider(),
            InfoTile(
              label: 'Aadhaar number',
              value: record.aadhaarNumber,
              icon: Icons.tag,
              copyable: true,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _SectionCard(
          title: 'Timestamps',
          children: [
            InfoTile(
              label: 'Created',
              value: Formatters.dateTime(record.createdAt),
              icon: Icons.add_circle_outline,
            ),
            const Divider(),
            InfoTile(
              label: 'Last updated',
              value: Formatters.dateTime(record.updatedAt),
              icon: Icons.update,
            ),
            if (record.lastSyncedAt != null) ...[
              const Divider(),
              InfoTile(
                label: 'Last synced',
                value: Formatters.dateTime(record.lastSyncedAt!),
                icon: Icons.cloud_done_outlined,
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _edit(context, record),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                onPressed: () => _delete(context, ref),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
              ),
            ),
          ],
        ),
        if (!isConflict) ...[
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Text(
              'Synced: ${record.syncStatus.name}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.record});

  final PersonalRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            RecordAvatar(
              name: record.fullName,
              photoPath: record.photoPath,
              photoUrl: record.photoUrl,
              radius: 44,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              record.fullName.isEmpty ? 'Unnamed record' : record.fullName,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (record.mobileNumber.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                record.mobileNumber,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
                SyncStatusChip(status: record.syncStatus),
                _MetaPill(
                  icon: Icons.cake_outlined,
                  label:
                      '${Formatters.age(record.dateOfBirth)} old · ${Formatters.date(record.dateOfBirth)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

class _ConflictBanner extends StatelessWidget {
  const _ConflictBanner({required this.onKeepLocal, required this.onUseServer});

  final VoidCallback onKeepLocal;
  final VoidCallback onUseServer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: const Color(0xFF7B1FA2).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: const Color(0xFF7B1FA2).withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sync_problem, color: Color(0xFF7B1FA2)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'This record was also changed on the server. Choose which '
                  'version to keep to avoid overwriting data.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: onUseServer,
                  child: const Text('Use server version'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  onPressed: onKeepLocal,
                  child: const Text('Keep mine'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
