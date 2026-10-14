import 'package:flutter/material.dart';

import '../data/models/personal_record.dart';
import '../features/records/screens/record_details_screen.dart';
import '../features/records/screens/record_form_screen.dart';
import 'shell/home_shell.dart';

/// Named route identifiers.
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String recordForm = '/record/form';
  static const String recordDetails = '/record/details';
}

/// Arguments for the record form route. A null [record] means "create new".
class RecordFormArgs {
  const RecordFormArgs({this.record});

  final PersonalRecord? record;
}

/// Central route generation, keeping navigation wiring out of screens.
class AppRouter {
  AppRouter._();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.recordForm:
        final args = settings.arguments;
        final record = args is RecordFormArgs
            ? args.record
            : args as PersonalRecord?;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => RecordFormScreen(existing: record),
        );
      case AppRoutes.recordDetails:
        final id = settings.arguments as String;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => RecordDetailsScreen(recordId: id),
        );
      case AppRoutes.home:
      default:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const HomeShell(),
        );
    }
  }
}
