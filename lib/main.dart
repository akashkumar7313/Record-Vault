import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/errors/error_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppErrorHandler.install();
  runApp(const ProviderScope(child: RecordVaultApp()));
}
