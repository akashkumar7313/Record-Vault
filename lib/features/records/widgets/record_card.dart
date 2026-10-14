import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/record_avatar.dart';
import '../../../core/widgets/sync_status_chip.dart';
import '../../../data/models/personal_record.dart';
import '../../../core/utils/formatters.dart';

/// Attractive summary card used in the records list and dashboard.
class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.record,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.showMenu = true,
  });

  final PersonalRecord record;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = record.mobileNumber.isNotEmpty
        ? record.mobileNumber
        : (record.email.isNotEmpty ? record.email : 'No contact details');

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              RecordAvatar(
                name: record.fullName,
                photoPath: record.photoPath,
                radius: 26,
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
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        SyncStatusChip(status: record.syncStatus, dense: true),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            'Updated ${Formatters.dateTime(record.updatedAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (showMenu && (onEdit != null || onDelete != null))
                PopupMenuButton<String>(
                  tooltip: 'Actions',
                  onSelected: (value) {
                    if (value == 'edit') onEdit?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (context) => [
                    if (onEdit != null)
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    if (onDelete != null)
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.error,
                          ),
                          title: Text(
                            'Delete',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                  ],
                )
              else
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
