import 'package:flutter/material.dart';

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/features/project/project_config.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/shared/widgets.dart';

/**
 * Opens the per-project Run & Build configuration dialog (`.simple_ide.json`).
 */
Future<void> showProjectConfigDialog(BuildContext context, IdeController ide) async {
  final ws = ide.workspace;
  if (ws == null) {
    ide.notify('Open a project folder first to configure project run settings.');
    return;
  }
  final updated = await showDialog<ProjectRunConfig>(
    context: context,
    barrierColor: Colors.black45,
    builder: (ctx) => _ProjectConfigDialog(initial: ide.projectConfig, projectName: ws.name),
  );
  if (updated == null) return;
  await ide.saveProjectConfig(updated);
  ide.notify(updated.isEmpty ? 'Cleared .simple_ide.json' : 'Saved .simple_ide.json');
}

class _ProjectConfigDialog extends StatefulWidget {
  const _ProjectConfigDialog({required this.initial, required this.projectName});

  final ProjectRunConfig initial;
  final String projectName;

  @override
  State<_ProjectConfigDialog> createState() => _ProjectConfigDialogState();
}

class _ProjectConfigDialogState extends State<_ProjectConfigDialog> {
  late final TextEditingController _run = TextEditingController(text: widget.initial.runCommand ?? '');
  late final TextEditingController _build = TextEditingController(text: widget.initial.buildCommand ?? '');
  late final TextEditingController _cwd = TextEditingController(text: widget.initial.cwd ?? '');
  late final TextEditingController _env = TextEditingController(
    text: widget.initial.env.entries.map((e) => '${e.key}=${e.value}').join('\n'),
  );

  @override
  void dispose() {
    _run.dispose();
    _build.dispose();
    _cwd.dispose();
    _env.dispose();
    super.dispose();
  }

  Map<String, String> _parseEnv() {
    final map = <String, String>{};
    for (final line in _env.text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final key = trimmed.substring(0, eq).trim();
      final val = trimmed.substring(eq + 1).trim();
      if (key.isNotEmpty) map[key] = val;
    }
    return map;
  }

  void _save() {
    String? clean(String s) => s.trim().isEmpty ? null : s.trim();
    Navigator.of(context).pop(
      ProjectRunConfig(
        runCommand: clean(_run.text),
        buildCommand: clean(_build.text),
        cwd: clean(_cwd.text),
        env: _parseEnv(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 480),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DialogHeader(
              title: 'Run Config — ${widget.projectName}',
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Saved in .simple_ide.json at the project root. Leave fields blank to use defaults.',
                      style: Tk.uiSmall.copyWith(color: Tk.textMuted),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _run,
                      style: Tk.code.copyWith(fontSize: 12.5),
                      decoration: const InputDecoration(
                        labelText: 'Run command (overrides F5)',
                        hintText: 'e.g. python main.py --port 8080',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _build,
                      style: Tk.code.copyWith(fontSize: 12.5),
                      decoration: const InputDecoration(
                        labelText: 'Build command (overrides primary Build)',
                        hintText: 'e.g. cmake --build build --config Release',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cwd,
                      style: Tk.code.copyWith(fontSize: 12.5),
                      decoration: const InputDecoration(
                        labelText: 'Working directory (relative or absolute)',
                        hintText: 'Leave empty for project root',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _env,
                      minLines: 3,
                      maxLines: 5,
                      style: Tk.code.copyWith(fontSize: 12.5),
                      decoration: const InputDecoration(
                        labelText: 'Environment variables (KEY=VALUE per line)',
                        hintText: 'PORT=8080\nDEBUG=1',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Tk.border))),
              child: Row(
                children: [
                  GhostButton(
                    label: 'Reset',
                    onPressed: () => Navigator.of(context).pop(const ProjectRunConfig()),
                  ),
                  const Spacer(),
                  GhostButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(width: 8),
                  PrimaryButton(label: 'Save', onPressed: _save),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
