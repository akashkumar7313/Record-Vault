import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/records/screens/records_screen.dart';
import '../../features/settings/screens/settings_screen.dart';

/// Currently selected bottom-navigation tab. Exposed so dashboard actions can
/// switch tabs without an imperative controller.
final navigationTabProvider = NotifierProvider<NavigationTabController, int>(
  NavigationTabController.new,
);

class NavigationTabController extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

/// Root scaffold hosting the three primary destinations.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, this.initialIndex});

  final int? initialIndex;

  static const List<Widget> _destinations = [
    DashboardScreen(),
    RecordsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(navigationTabProvider);

    return Scaffold(
      body: IndexedStack(index: index, children: _destinations),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) =>
            ref.read(navigationTabProvider.notifier).select(value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_copy_outlined),
            selectedIcon: Icon(Icons.folder_copy),
            label: 'Records',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
