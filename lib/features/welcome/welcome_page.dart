import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/features/settings/settings_dialog.dart';
import 'package:simple_ide/features/settings/toolchains.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/shared/widgets.dart';

export 'package:simple_ide/features/welcome/app_mark.dart';
export 'package:simple_ide/features/welcome/empty_editor.dart';

/**
 * Start view shown when no folder is open: actions, recent folders, and
 * which compilers the Run button can use on this machine.
 */
class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key, required this.onOpenFolder, required this.onNewProject});

  final VoidCallback onOpenFolder;
  final VoidCallback onNewProject;

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  Future<List<Toolchain>>? _tools;
  String _lastPathKey = '';

  void _ensureTools(IdeController ide) {
    final key = ide.settings.extraPath.join(';');
    if (_tools == null || key != _lastPathKey) {
      _lastPathKey = key;
      _tools = detectToolchains(extraPath: ide.settings.extraPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ide = ref.watch(ideProvider);
    _ensureTools(ide);
    final recents = ide.settings.recentFolders.where((f) => Directory(f).existsSync()).toList();
    return Container(
      color: Tk.editor,
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(48, 40, 48, 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Section('Start'),
              _Row(label: 'New Project…', trailing: 'Ctrl+Shift+N', onTap: widget.onNewProject),
              _Row(label: 'Open Folder…', trailing: 'Ctrl+O', onTap: widget.onOpenFolder),
              const SizedBox(height: 28),
              const _Section('Recent'),
              if (recents.isEmpty)
                const _Note('No recent folders')
              else
                for (final f in recents.take(8))
                  _Row(
                    label: p.basename(f),
                    trailing: p.dirname(f),
                    onTap: () => ide.openFolder(f, restoreTabs: f == ide.settings.lastFolder),
                    onRemove: () => ide.removeRecent(f),
                  ),
              const SizedBox(height: 28),
              _Section(
                'Toolchains',
                trailing: GestureDetector(
                  onTap: () => showSettings(context),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text('Edit PATH…', style: Tk.uiSmall.copyWith(color: Tk.info)),
                  ),
                ),
              ),
              FutureBuilder<List<Toolchain>>(
                future: _tools,
                builder: (context, snap) {
                  if (!snap.hasData) return const _Note('Checking PATH…');
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [for (final t in snap.data!) _ToolRow(t)],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Tk.border))),
      child: Row(
        children: [
          Text(text, style: Tk.uiSmall.copyWith(fontWeight: FontWeight.w600, color: Tk.textMuted)),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: Tk.ui.copyWith(color: Tk.textFaint)),
      );
}

class _Row extends StatefulWidget {
  const _Row({required this.label, required this.onTap, this.trailing, this.onRemove});

  final String label;
  final String? trailing;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          color: _hover ? Tk.hover : Colors.transparent,
          child: Row(
            children: [
              Text(widget.label, style: Tk.ui.copyWith(color: Tk.info)),
              const SizedBox(width: 16),
              if (widget.trailing != null)
                Expanded(
                  child: Text(
                    widget.trailing!,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tk.uiSmall.copyWith(color: Tk.textFaint),
                  ),
                )
              else
                const Spacer(),
              if (widget.onRemove != null && _hover) ...[
                const SizedBox(width: 6),
                IconBtn(icon: Icons.close_rounded, tooltip: 'Remove from recent', size: 13, box: 20, onPressed: widget.onRemove),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow(this.t);

  final Toolchain t;

  static String _sampleFile(String command) => switch (command) {
        'gcc' => 'a.c',
        'g++' => 'a.cpp',
        'python' => 'a.py',
        'java' => 'A.java',
        'node' => 'a.js',
        'dart' => 'a.dart',
        'go' => 'a.go',
        'rustc' => 'a.rs',
        _ => 'a.txt',
      };

  @override
  Widget build(BuildContext context) {
    final ok = t.found == true;
    return SizedBox(
      height: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            StatusDot(color: ok ? Tk.success : Tk.textFaint.withValues(alpha: 0.5)),
            const SizedBox(width: 10),
            Opacity(
              opacity: ok ? 1 : 0.45,
              child: LangBadge(path: _sampleFile(t.command)),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 100,
              child: Text(t.languages, style: Tk.ui.copyWith(color: ok ? Tk.textStrong : Tk.textFaint)),
            ),
            SizedBox(
              width: 70,
              child: Text(t.command, style: Tk.code.copyWith(fontSize: 12, color: ok ? Tk.info : Tk.textFaint)),
            ),
            Expanded(
              child: Text(
                ok ? t.version ?? 'installed' : 'not on PATH',
                textAlign: TextAlign.right,
                style: Tk.uiSmall.copyWith(color: ok ? Tk.success : Tk.textFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
