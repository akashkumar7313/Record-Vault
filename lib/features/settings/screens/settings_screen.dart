import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/theme_providers.dart';
import '../../../core/errors/app_exception.dart';
import '../../../data/providers/data_providers.dart';
import '../../../data/services/api_config.dart';
import '../../export/providers/export_providers.dart';
import '../../records/providers/records_providers.dart';
import '../providers/settings_providers.dart';
import '../widgets/sync_status_card.dart';

/// App preferences, sync controls, export and privacy information.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _export(
    BuildContext context,
    WidgetRef ref, {
    required bool share,
    Rect? origin,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(recordRepositoryProvider);
    final records = await repository.getAll();
    if (records.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('There are no records to export yet.')),
      );
      return;
    }

    final controller = ref.read(exportControllerProvider.notifier);
    final outcome = await controller.export(
      records,
      share: share,
      shareOrigin: origin,
    );

    if (!context.mounted) return;
    if (outcome != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Exported ${outcome.count} record${outcome.count == 1 ? '' : 's'} to ${outcome.fileName}.',
            ),
          ),
        );
      return;
    }
    final state = ref.read(exportControllerProvider);
    final message =
        state.whenOrNull(error: (e, _) => AppException.from(e).userMessage) ??
        'Export was cancelled.';
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncAsync = ref.watch(syncControllerProvider);
    final statsAsync = ref.watch(recordStatsProvider);
    final syncState = syncAsync.value ?? const SyncState();
    final stats = statsAsync.value ?? RecordStats.empty;
    final exportAsync = ref.watch(exportControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          SyncStatusCard(
            syncState: syncState,
            stats: stats,
            onSync: () => ref.read(syncControllerProvider.notifier).syncNow(),
          ),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle(context, 'Google Sheets connection'),
          const SizedBox(height: AppSpacing.md),
          _ConnectionCard(
            exporting: exportAsync.isLoading,
            onTest: () => ref.invalidate(connectionStatusProvider),
          ),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle(context, 'Export records'),
          const SizedBox(height: AppSpacing.md),
          _ExportCard(
            count: stats.total,
            exporting: exportAsync.isLoading,
            onShare: (origin) =>
                _export(context, ref, share: true, origin: origin),
            onSave: () => _export(context, ref, share: false),
          ),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle(context, 'Appearance'),
          const SizedBox(height: AppSpacing.md),
          const _ThemeSelector(),
          const SizedBox(height: AppSpacing.xl),
          _sectionTitle(context, 'Privacy'),
          const SizedBox(height: AppSpacing.md),
          const _PrivacyCard(),
          const SizedBox(height: AppSpacing.xxl),
          Center(
            child: Text(
              'RecordVault ${_appVersion()}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  static String _appVersion() => '1.0.0';
}

class _ConnectionCard extends ConsumerWidget {
  const _ConnectionCard({required this.exporting, required this.onTest});

  final bool exporting;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = ref.watch(connectionStatusProvider);

    final (IconData, Color, String) resolved = status.when(
      loading: () =>
          (Icons.sync, theme.colorScheme.primary, 'Checking connection…'),
      error: (_, _) => (
        Icons.help_outline,
        theme.colorScheme.tertiary,
        'Connection status unknown. Test the connection.',
      ),
      data: (reachable) => reachable
          ? (
              Icons.check_circle,
              const Color(0xFF2E7D32),
              'Endpoint is reachable',
            )
          : (
              Icons.error_outline,
              theme.colorScheme.error,
              'Endpoint did not return usable data',
            ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  resolved.$2 == theme.colorScheme.error
                      ? Icons.warning_amber_rounded
                      : resolved.$1,
                  size: 20,
                  color: resolved.$2,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    resolved.$3,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: exporting ? null : onTest,
                  child: const Text('Test'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Endpoint: script.google.com',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              ApiConfig.hasCustomEndpoint
                  ? 'A custom endpoint is configured via RECORD_VAULT_SHEETS_URL.'
                  : 'Using the default shared endpoint. Treat it as untrusted.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({
    required this.count,
    required this.exporting,
    required this.onShare,
    required this.onSave,
  });

  final int count;
  final bool exporting;
  final ValueChanged<Rect> onShare;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count record${count == 1 ? '' : 's'} will be exported.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Creates an .xlsx workbook containing every supported field.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Builder(
              builder: (context) {
                return Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: exporting
                            ? null
                            : () {
                                final box =
                                    context.findRenderObject() as RenderBox?;
                                final origin = box == null
                                    ? null
                                    : box.localToGlobal(Offset.zero) & box.size;
                                if (origin != null) onShare(origin);
                              },
                        icon: const Icon(Icons.ios_share, size: 18),
                        label: const Text('Share'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: exporting ? null : onSave,
                        icon: const Icon(Icons.save_alt, size: 18),
                        label: const Text('Save file'),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (exporting)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.md),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSelector extends ConsumerWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto),
              label: Text('System'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode),
              label: Text('Light'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode),
              label: Text('Dark'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (selection) {
            ref.read(themeModeProvider.notifier).setMode(selection.first);
          },
        ),
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  Future<void> _showDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy & security'),
        content: const SingleChildScrollView(
          child: Text(
            '• RecordVault stores records in a private SQLite database on your '
            'device. Nothing leaves the device unless you sync or export.\n\n'
            '• The default Google Sheets endpoint is a PUBLIC web app. Anyone '
            'with the URL can read or write what it exposes. Only enable sync '
            'after an authenticated, access-controlled backend is deployed.\n\n'
            '• Profile photos are stored only in the app’s private storage.\n\n'
            '• Export files contain personal information. Share them only with '
            'trusted recipients and delete temporary copies afterwards.\n\n'
            '• RecordVault does not collect or request Aadhaar or other '
            'government identifiers.\n\n'
            '• Deleted records are queued and only removed after the server '
            'confirms the deletion.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
        title: const Text('Privacy & security'),
        subtitle: const Text('How your data is stored, synced and protected.'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showDialog(context),
      ),
    );
  }
}
