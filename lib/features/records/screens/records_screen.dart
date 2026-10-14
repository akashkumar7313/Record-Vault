import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/sync_status_chip.dart';
import '../../../data/models/personal_record.dart';
import '../../../data/models/sync_status.dart';
import '../providers/records_providers.dart';
import '../widgets/record_card.dart';
import '../widgets/record_search_field.dart';

/// Full records list with search, edit, delete and add actions.
class RecordsScreen extends ConsumerWidget {
  const RecordsScreen({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PersonalRecord record,
  ) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete record?',
      message:
          'This will remove "${record.fullName}" from RecordVault and queue '
          'the deletion for the next sync. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    await ref.read(recordsProvider.notifier).softDelete(record.aadhaarNumber);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Record deleted locally. Deletion will sync later.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(recordsProvider);
    final statsAsync = ref.watch(recordStatsProvider);
    final counts = statsAsync.value ?? RecordStats.empty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Records'),
        actions: [
          if (counts.pending > 0)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Center(
                child: SyncStatusChip(status: SyncStatus.pending, dense: true),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: RecordSearchField(
              focusNode: FocusNode(),
              onSubmitted: (_) {},
            ),
          ),
          Expanded(
            child: recordsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => ErrorView.fromError(
                error,
                onRetry: () => ref.read(recordsProvider.notifier).refresh(),
              ),
              data: (records) {
                if (records.isEmpty) {
                  final query = ref.watch(searchQueryProvider).trim();
                  return EmptyState(
                    icon: Icons.person_search,
                    title: query.isEmpty
                        ? 'No records yet'
                        : 'No matching records',
                    message: query.isEmpty
                        ? 'Tap the + button to add your first record.'
                        : 'Try a different name, mobile number or Aadhaar number.',
                    actionLabel: query.isEmpty ? 'Add record' : null,
                    onAction: query.isEmpty ? () => _openCreate(context) : null,
                  );
                }
                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    120,
                  ),
                  itemCount: records.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return RecordCard(
                      record: record,
                      onTap: () => _openDetails(context, record.aadhaarNumber),
                      onEdit: () => _openEdit(context, record),
                      onDelete: () => _confirmDelete(context, ref, record),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'records_add_record',
        onPressed: () => _openCreate(context),
        icon: const Icon(Icons.add),
        label: const Text('Add record'),
      ),
    );
  }

  void _openCreate(BuildContext context) {
    Navigator.of(context).pushNamed(AppRoutes.recordForm);
  }

  void _openEdit(BuildContext context, PersonalRecord record) {
    Navigator.of(context).pushNamed(
      AppRoutes.recordForm,
      arguments: RecordFormArgs(record: record),
    );
  }

  void _openDetails(BuildContext context, String aadhaarNumber) {
    Navigator.of(context)
        .pushNamed(AppRoutes.recordDetails, arguments: aadhaarNumber);
  }
}
