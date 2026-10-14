import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record_vault/app/theme/app_theme.dart';
import 'package:record_vault/core/widgets/confirm_dialog.dart';
import 'package:record_vault/core/widgets/empty_state.dart';
import 'package:record_vault/core/widgets/record_avatar.dart';
import 'package:record_vault/core/widgets/sync_status_chip.dart';
import 'package:record_vault/data/models/gender.dart';
import 'package:record_vault/data/models/personal_record.dart';
import 'package:record_vault/data/models/sync_status.dart';
import 'package:record_vault/features/records/providers/records_providers.dart';
import 'package:record_vault/features/records/widgets/record_card.dart';
import 'package:record_vault/features/settings/providers/settings_providers.dart';
import 'package:record_vault/features/settings/widgets/sync_status_card.dart';

PersonalRecord sampleRecord({SyncStatus status = SyncStatus.synced}) {
  return PersonalRecord(
    aadhaarNumber: '123456789012',
    fullName: 'Asha Verma',
    mobileNumber: '9876543210',
    email: 'asha@example.com',
    address: '12 Main Street',
    dateOfBirth: DateTime.utc(1990, 5, 20),
    gender: Gender.female,
    createdAt: DateTime.utc(2024, 1, 1),
    updatedAt: DateTime.utc(2024, 1, 1),
    syncStatus: status,
  );
}

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('SyncStatusChip', () {
    testWidgets('renders a label for every status', (tester) async {
      for (final entry in {
        SyncStatus.synced: 'Synced',
        SyncStatus.pending: 'Pending',
        SyncStatus.failed: 'Failed',
        SyncStatus.conflict: 'Conflict',
      }.entries) {
        await tester.pumpWidget(host(SyncStatusChip(status: entry.key)));
        expect(find.text(entry.value), findsOneWidget);
      }
    });
  });

  group('RecordAvatar', () {
    testWidgets('shows initials when there is no photo', (tester) async {
      await tester.pumpWidget(host(const RecordAvatar(name: 'Asha Verma')));
      expect(find.text('AV'), findsOneWidget);
    });

    testWidgets('falls back gracefully for an empty name', (tester) async {
      await tester.pumpWidget(host(const RecordAvatar(name: '')));
      expect(find.text('?'), findsOneWidget);
    });
  });

  group('EmptyState', () {
    testWidgets('shows title, message and triggers the action', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        host(
          EmptyState(
            icon: Icons.person,
            title: 'No records yet',
            message: 'Add your first record.',
            actionLabel: 'Add record',
            onAction: () => tapped = true,
          ),
        ),
      );

      expect(find.text('No records yet'), findsOneWidget);
      expect(find.text('Add your first record.'), findsOneWidget);
      await tester.tap(find.text('Add record'));
      expect(tapped, isTrue);
    });
  });

  group('RecordCard', () {
    testWidgets('shows name, mobile and sync status', (tester) async {
      await tester.pumpWidget(
        host(
          RecordCard(
            record: sampleRecord(status: SyncStatus.pending),
            onTap: () {},
            onEdit: () {},
            onDelete: () {},
          ),
        ),
      );

      expect(find.text('Asha Verma'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('menu exposes edit and delete', (tester) async {
      await tester.pumpWidget(
        host(
          RecordCard(record: sampleRecord(), onEdit: () {}, onDelete: () {}),
        ),
      );

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('ConfirmDialog', () {
    testWidgets('returns true when confirmed', (tester) async {
      bool? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await ConfirmDialog.show(
                    context,
                    title: 'Delete record?',
                    message: 'This cannot be undone.',
                    confirmLabel: 'Delete',
                    destructive: true,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Delete record?'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('returns false when cancelled', (tester) async {
      bool? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await ConfirmDialog.show(
                    context,
                    title: 'Delete?',
                    message: 'msg',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });

  group('SyncStatusCard', () {
    Widget themedHost(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    );

    Future<void> pumpCard(WidgetTester tester) async {
      await tester.pumpWidget(
        themedHost(
          SyncStatusCard(
            syncState: const SyncState(),
            stats: const RecordStats(
              total: 3,
              byStatus: <SyncStatus, int>{
                SyncStatus.synced: 2,
                SyncStatus.pending: 1,
              },
            ),
            onSync: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('lays out without infinite-width constraints', (tester) async {
      await pumpCard(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders at a narrow phone width without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpCard(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Sync'), findsOneWidget);
    });
  });
}
