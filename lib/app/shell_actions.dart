import 'package:flutter/widgets.dart';

/**
 * Handlers the top bar, rail, and status bar need from the shell.
 */
class ShellActions {
  const ShellActions({
    required this.newProject,
    required this.openFolder,
    required this.newFile,
    required this.quickOpen,
    required this.commandPalette,
    required this.settings,
    required this.goToLine,
    required this.editorIntent,
    required this.shortcuts,
    required this.about,
    required this.exit,
  });

  final VoidCallback newProject;
  final VoidCallback openFolder;
  final VoidCallback newFile;
  final VoidCallback quickOpen;
  final VoidCallback commandPalette;
  final VoidCallback settings;
  final VoidCallback goToLine;
  final void Function(Intent) editorIntent;
  final VoidCallback shortcuts;
  final VoidCallback about;
  final VoidCallback exit;
}
