import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/features/project/file_template.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/shared/widgets.dart';

export 'package:simple_ide/features/project/file_template.dart';

/**
 * Opens the New File popup for [targetDir] and opens the primary created file
 * in the editor.
 *
 * @return absolute path of the primary created file, or null if cancelled
 */
Future<String?> showNewFileDialog(BuildContext context, IdeController ide, {required String targetDir}) async {
  final ws = ide.workspace;
  final lang = detectProjectLanguage(
    targetDir,
    activeFilePath: ide.active?.path,
    workspaceFiles: ws?.allFiles(limit: 200) ?? const [],
  );
  final created = await showDialog<List<String>>(
    context: context,
    barrierColor: Colors.black38,
    builder: (ctx) => _NewFileDialog(
      targetDir: targetDir,
      relDir: ws == null ? targetDir : p.relative(targetDir, from: p.dirname(ws.root)),
      kinds: orderedKindsFor(lang),
    ),
  );
  if (created == null || created.isEmpty) return null;
  ws?.expanded.add(targetDir);
  ws?.refresh(targetDir);
  await ide.openFile(created.first);
  return created.first;
}

class _NewFileDialog extends StatefulWidget {
  const _NewFileDialog({required this.targetDir, required this.relDir, required this.kinds});

  final String targetDir;
  final String relDir;
  final List<NewFileKind> kinds;

  @override
  State<_NewFileDialog> createState() => _NewFileDialogState();
}

class _NewFileDialogState extends State<_NewFileDialog> {
  final _name = TextEditingController();
  final _namespace = TextEditingController();
  late NewFileKind _selected = widget.kinds.first;
  String _headerExt = '.h';
  bool _createPair = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _namespace.dispose();
    super.dispose();
  }

  void _moveSelection(int delta) {
    final idx = widget.kinds.indexOf(_selected);
    final next = (idx + delta).clamp(0, widget.kinds.length - 1);
    setState(() {
      _selected = widget.kinds[next];
      _error = null;
    });
  }

  Future<void> _submit() async {
    final raw = _name.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    if (RegExp(r'[<>:"|?*]').hasMatch(raw)) {
      setState(() => _error = 'Names can\'t contain < > : " | ? *');
      return;
    }
    final ns = _namespace.text.trim();
    if (ns.isNotEmpty && !RegExp(r'^[A-Za-z_]\w*(::[A-Za-z_]\w*)*$').hasMatch(ns)) {
      setState(() => _error = 'Namespace must look like app or app::core');
      return;
    }
    final planned = planNewFiles(
      kind: _selected,
      rawName: raw,
      namespace: ns,
      headerExt: _headerExt,
      createPair: _createPair,
    );
    for (final item in planned) {
      final full = p.join(widget.targetDir, item.relPath);
      if (File(full).existsSync() || Directory(full).existsSync()) {
        setState(() => _error = '${item.relPath} already exists');
        return;
      }
    }
    try {
      final paths = <String>[];
      for (final item in planned) {
        final full = p.join(widget.targetDir, item.relPath);
        await File(full).create(recursive: true);
        if (item.content.isNotEmpty) await File(full).writeAsString(item.content);
        paths.add(full);
      }
      if (mounted) Navigator.of(context).pop(paths);
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn\'t create file: $e');
    }
  }

  String _previewText() {
    final raw = _name.text.trim();
    if (raw.isEmpty) return 'Target: ${widget.relDir}';
    final planned = planNewFiles(
      kind: _selected,
      rawName: raw,
      namespace: _namespace.text.trim(),
      headerExt: _headerExt,
      createPair: _createPair,
    );
    return 'Creates ${planned.map((e) => e.relPath).join(' + ')}';
  }

  String _subtitleFor(NewFileKind k) => switch (k.id) {
        'cpp_class' => 'Header & source pair with #pragma once',
        'cpp_header' => 'C++ header with #pragma once',
        'cpp_source' => 'C++ implementation file (.cpp)',
        'cpp_namespace' => 'Header with a C++ namespace block',
        'c_source' => 'C source file with <stdio.h>',
        'c_header' => 'C header with #ifndef include guard',
        'py_file' => 'Python module (.py)',
        'py_pkg' => 'Directory with __init__.py',
        'java_class' => 'Public Java class',
        'java_interface' => 'Public Java interface',
        'java_enum' => 'Public Java enum',
        _ => 'Blank file with any extension',
      };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _moveSelection(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _moveSelection(-1),
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DialogHeader(
                title: 'New File in ${widget.relDir}',
                onClose: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildKindList(),
                    Expanded(child: _buildForm()),
                  ],
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKindList() {
    return Container(
      width: 184,
      decoration: const BoxDecoration(
        color: Tk.sidebar,
        border: Border(right: BorderSide(color: Tk.border)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemExtent: 30,
        itemCount: widget.kinds.length,
        itemBuilder: (context, i) {
          final k = widget.kinds[i];
          final sel = k.id == _selected.id;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => setState(() {
                _selected = k;
                _error = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: sel ? Tk.listActive : Colors.transparent,
                  border: Border(left: BorderSide(color: sel ? Tk.accent : Colors.transparent, width: 2)),
                ),
                child: Row(
                  children: [
                    LangBadge(path: k.badgePath),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        k.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tk.ui.copyWith(color: sel ? Tk.textStrong : Tk.text),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _selected.label,
            style: Tk.ui.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.textStrong),
          ),
          const SizedBox(height: 2),
          Text(_subtitleFor(_selected), style: Tk.uiSmall.copyWith(color: Tk.textMuted)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: true,
            style: Tk.code.copyWith(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: _selected.id == 'empty' ? 'main.c, notes.txt, src/util.cpp' : 'Player',
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
          if (_selected.supportsNamespace) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _namespace,
              style: Tk.code.copyWith(fontSize: 12.5),
              decoration: const InputDecoration(
                labelText: 'Namespace (optional)',
                hintText: 'app::core',
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_selected.isCppClass) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                InkWell(
                  onTap: () => setState(() => _createPair = !_createPair),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: Checkbox(
                          value: _createPair,
                          onChanged: (v) => setState(() => _createPair = v ?? true),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('Create .cpp source', style: Tk.uiSmall.copyWith(color: Tk.text)),
                    ],
                  ),
                ),
                const Spacer(),
                OptionPill(label: '.h', active: _headerExt == '.h', onTap: () => setState(() => _headerExt = '.h')),
                const SizedBox(width: 4),
                OptionPill(label: '.hpp', active: _headerExt == '.hpp', onTap: () => setState(() => _headerExt = '.hpp')),
              ],
            ),
          ],
          const Spacer(),
          Text(
            _previewText(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tk.uiSmall.copyWith(color: Tk.textFaint),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Tk.border))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GhostButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
          const SizedBox(width: 8),
          PrimaryButton(label: 'Create', onPressed: _submit),
        ],
      ),
    );
  }
}
