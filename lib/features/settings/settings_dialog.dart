import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/features/runner/languages.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/features/project/folder_picker.dart';
import 'package:simple_ide/shared/widgets.dart';

const _runnableExts = ['.c', '.cpp', '.py', '.java', '.js', '.ts', '.dart', '.go', '.rs', '.bat', '.ps1', '.sh'];

Future<void> showSettings(BuildContext context) {
  return showDialog(
    context: context,
    barrierColor: Colors.black45,
    builder: (_) => Consumer(builder: (_, ref, _) => _SettingsDialog(ide: ref.read(ideProvider))),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.ide});
  final IdeController ide;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final List<String> _exts = [
    ..._runnableExts,
    ...widget.ide.settings.runOverrides.keys.where((k) => !_runnableExts.contains(k)),
  ];
  late final Map<String, TextEditingController> _cmds = {
    for (final ext in _exts) ext: TextEditingController(text: _effective(ext)),
  };
  final TextEditingController _pathInput = TextEditingController();
  final TextEditingController _newExtInput = TextEditingController();

  String _effective(String ext) {
    final o = widget.ide.settings.runOverrides[ext];
    if (o != null) return o;
    return _default(ext);
  }

  static String _default(String ext) {
    final l = languageFor('x$ext');
    return [if (l.build != null) l.build!, if (l.run != null) l.run!].join(' && ');
  }

  @override
  void dispose() {
    _pathInput.dispose();
    _newExtInput.dispose();
    for (final c in _cmds.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _addCustomExtension(String raw) {
    var ext = raw.trim().toLowerCase();
    if (ext.isEmpty) return;
    if (!ext.startsWith('.')) ext = '.$ext';
    if (!_exts.contains(ext)) {
      setState(() {
        _exts.add(ext);
        _cmds[ext] = TextEditingController(text: _effective(ext));
      });
    }
    _newExtInput.clear();
  }

  void _addPath(String raw) {
    final dir = raw.trim().replaceAll('"', '');
    if (dir.isEmpty) return;
    if (!Directory(dir).existsSync()) {
      widget.ide.notify('Folder does not exist: $dir', error: true);
      return;
    }
    widget.ide.updateSettings((s) {
      if (!s.extraPath.any((e) => e.toLowerCase() == dir.toLowerCase())) {
        s.extraPath.add(dir);
      }
    });
    _pathInput.clear();
  }

  Future<void> _browsePath() async {
    final picked = await pickFolder(context);
    if (picked != null) _addPath(picked);
  }

  void _saveCommands() {
    widget.ide.updateSettings((s) {
      for (final e in _cmds.entries) {
        final v = e.value.text.trim();
        if (v.isEmpty || v == _default(e.key)) {
          s.runOverrides.remove(e.key);
        } else {
          s.runOverrides[e.key] = v;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ide = widget.ide;
    return PopScope(
      onPopInvokedWithResult: (_, _) => _saveCommands(),
      child: Dialog(
        child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: ListenableBuilder(
          listenable: ide,
          builder: (context, _) {
            final s = ide.settings;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 16, 8),
                  child: Row(
                    children: [
                      Text('Settings', style: Tk.ui.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.textStrong)),
                      const Spacer(),
                      IconBtn(icon: Icons.close_rounded, tooltip: 'Close', onPressed: () {
                        _saveCommands();
                        Navigator.pop(context);
                      }),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
                    children: [
                      const _Section('Editor'),
                      _SettingRow(
                        title: 'Font size',
                        detail: 'Also Ctrl+= and Ctrl+-',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconBtn(icon: Icons.remove_rounded, tooltip: 'Smaller', onPressed: () => ide.zoom(-1)),
                            SizedBox(width: 40, child: Text('${s.fontSize.round()}', textAlign: TextAlign.center, style: Tk.ui)),
                            IconBtn(icon: Icons.add_rounded, tooltip: 'Larger', onPressed: () => ide.zoom(1)),
                          ],
                        ),
                      ),
                      _SettingRow(
                        title: 'Word wrap',
                        detail: 'Wrap long lines to the editor width (Alt+Z)',
                        child: Switch(value: s.wordWrap, onChanged: (_) => ide.toggleWordWrap()),
                      ),
                      const _Section('Saving'),
                      _SettingRow(
                        title: 'Auto-save delay',
                        detail: 'Files are saved automatically after you stop typing and before every run',
                        child: DropdownButton<int>(
                          value: const [300, 800, 2000, 5000].contains(s.autoSaveDelayMs) ? s.autoSaveDelayMs : 800,
                          underline: const SizedBox.shrink(),
                          dropdownColor: Tk.raised,
                          style: Tk.ui,
                          items: const [
                            DropdownMenuItem(value: 300, child: Text('0.3 seconds')),
                            DropdownMenuItem(value: 800, child: Text('0.8 seconds')),
                            DropdownMenuItem(value: 2000, child: Text('2 seconds')),
                            DropdownMenuItem(value: 5000, child: Text('5 seconds')),
                          ],
                          onChanged: (v) => ide.updateSettings((x) => x.autoSaveDelayMs = v!),
                        ),
                      ),
                      const _Section('Console'),
                      _SettingRow(
                        title: 'Clear before each run',
                        detail: 'Start every run with an empty console',
                        child: Switch(value: s.clearConsoleOnRun, onChanged: (v) => ide.updateSettings((x) => x.clearConsoleOnRun = v)),
                      ),
                      const _Section('Extra PATH folders'),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'Folders added here are prepended to PATH when SimpleIDE checks toolchains, runs syntax checks, or executes your code.',
                          style: Tk.uiSmall.copyWith(height: 1.5),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _pathInput,
                              style: Tk.code.copyWith(fontSize: 12.5),
                              decoration: const InputDecoration(hintText: r'e.g. C:\Go\bin or C:\msys64\ucrt64\bin'),
                              onSubmitted: _addPath,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GhostButton(label: 'Add', onPressed: () => _addPath(_pathInput.text)),
                          const SizedBox(width: 6),
                          GhostButton(label: 'Browse…', onPressed: _browsePath),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < s.extraPath.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.folder_outlined, size: 15, color: Tk.textMuted),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  s.extraPath[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Tk.code.copyWith(fontSize: 12.5, color: Tk.text),
                                ),
                              ),
                              IconBtn(
                                icon: Icons.close_rounded,
                                tooltip: 'Remove from PATH',
                                onPressed: () => ide.updateSettings((x) => x.extraPath.removeAt(i)),
                              ),
                            ],
                          ),
                        ),
                      const _Section('Run commands'),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          'SimpleIDE hands your file to these programs. Separate a build step from the run step with &&. '
                          r'Placeholders: ${file} full path, ${dir} folder, ${name} file name without extension, ${out} build output.',
                          style: Tk.uiSmall.copyWith(height: 1.5),
                        ),
                      ),
                      for (final ext in _exts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              SizedBox(width: 22, child: LangBadge(path: 'x$ext')),
                              SizedBox(width: 58, child: Text(ext, style: Tk.code.copyWith(fontSize: 12.5, color: Tk.textMuted))),
                              Expanded(
                                child: TextField(
                                  controller: _cmds[ext],
                                  style: Tk.code.copyWith(fontSize: 12),
                                  onEditingComplete: _saveCommands,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconBtn(
                                icon: Icons.restart_alt_rounded,
                                tooltip: 'Reset to default',
                                onPressed: () => setState(() => _cmds[ext]!.text = _default(ext)),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          SizedBox(
                            width: 140,
                            child: TextField(
                              controller: _newExtInput,
                              style: Tk.code.copyWith(fontSize: 12),
                              decoration: const InputDecoration(hintText: 'Add ext (e.g. .rb)'),
                              onSubmitted: _addCustomExtension,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GhostButton(label: 'Add extension', onPressed: () => _addCustomExtension(_newExtInput.text)),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Tk.border))),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      PrimaryButton(
                        label: 'Done',
                        onPressed: () {
                          _saveCommands();
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(title, style: Tk.ui.copyWith(fontWeight: FontWeight.w600, color: Tk.textStrong)),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.title, required this.detail, required this.child});
  final String title;
  final String detail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Tk.ui.copyWith(color: Tk.textStrong)),
                const SizedBox(height: 2),
                Text(detail, style: Tk.uiSmall),
              ],
            ),
          ),
          const SizedBox(width: 16),
          child,
        ],
      ),
    );
  }
}
