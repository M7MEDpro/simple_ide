import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/app/ide_shell.dart';
import 'package:simple_ide/features/settings/settings.dart';
import 'package:simple_ide/shared/tokens.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final ide = IdeController(Settings.load());
  runApp(SimpleIdeApp(controller: ide));
  ide.restoreSession();
}

class SimpleIdeApp extends StatelessWidget {
  const SimpleIdeApp({super.key, required this.controller});
  final IdeController controller;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [ideProvider.overrideWith((ref) => controller)],
      child: MaterialApp(
        title: 'SimpleIDE',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const IdeShell(),
      ),
    );
  }
}
