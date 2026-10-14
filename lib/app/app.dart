import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'shell/home_shell.dart';
import 'theme/app_theme.dart';
import 'theme/theme_providers.dart';

/// Root widget. Applies the persisted theme and installs the routing table.
class RecordVaultApp extends ConsumerWidget {
  const RecordVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    return MaterialApp(
      title: 'RecordVault',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      onGenerateRoute: AppRouter.onGenerateRoute,
      home: const HomeShell(),
    );
  }
}
