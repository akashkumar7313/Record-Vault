import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../data/models/sync_status.dart';

/// Compact, colour-coded sync status badge.
class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({super.key, required this.status, this.dense = false});

  final SyncStatus status;
  final bool dense;

  String get _label => switch (status) {
    SyncStatus.synced => 'Synced',
    SyncStatus.pending => 'Pending',
    SyncStatus.failed => 'Failed',
    SyncStatus.conflict => 'Conflict',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = AppTheme.statusColor(status, scheme);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AppTheme.statusIcon(status),
            size: dense ? 13 : 15,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            _label,
            style: TextStyle(
              color: color,
              fontSize: dense ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
