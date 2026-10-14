import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../data/providers/data_providers.dart';

/// Persisted theme mode. Defaults to the system setting.
final themeModeProvider = AsyncNotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final repository = ref.watch(recordRepositoryProvider);
    final raw = await repository.getMeta(AppConstants.metaKeyThemeMode);
    return _parse(raw);
  }

  Future<void> setMode(ThemeMode mode) async {
    state = AsyncData(mode);
    await ref
        .read(recordRepositoryProvider)
        .setMeta(AppConstants.metaKeyThemeMode, mode.name);
  }

  /// Cycles system -> light -> dark -> system.
  Future<void> cycle() async {
    final current = state.value ?? ThemeMode.system;
    final next = switch (current) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await setMode(next);
  }

  static ThemeMode _parse(String? raw) {
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}
