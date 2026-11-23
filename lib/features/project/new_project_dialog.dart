import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/features/project/folder_picker.dart';
import 'package:simple_ide/features/project/project_template.dart';
import 'package:simple_ide/features/settings/toolchains.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/shared/widgets.dart';

export 'package:simple_ide/features/project/project_template.dart';

/**
 * Opens the New Project wizard and opens the created project.
 */
Future<void> showNewProjectDialog(BuildContext context, IdeController ide) async {
  final savedDir = ide.settings.lastProjectDir;
  final initialParent = savedDir != null && Directory(savedDir).existsSync() ? savedDir : defaultProjectsParent();
  final result = await showDialog<({String projectDir, String? entryPath})>(
    context: context,
    barrierColor: Colors.black45,
    builder: (ctx) => _NewProjectDialog(initialParent: initialParent),
  );
  if (result == null) return;
  ide.updateSettings((s) => s.lastProjectDir = p.dirname(result.projectDir));
  await ide.openFolder(result.projectDir);
  if (result.entryPath != null) await ide.openFile(result.entryPath!);
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog({required this.initialParent});

  final String initialParent;

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  late final TextEditingController _name;
  late final TextEditingController _location;
  late final Future<List<Toolchain>> _tools = detectToolchains();
  ProjectTemplate _selected = projectTemplates.first;
  String _buildTool = projectTemplates.first.buildTools.first;
  bool _createSample = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _location = TextEditingController(text: widget.initialParent);
    final suggested = suggestProjectName(widget.initialParent);
    _name = TextEditingController(text: suggested)
      ..selection = TextSelection(baseOffset: 0, extentOffset: suggested.length);
  }

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    super.dispose();
  }

  String get _fullPath {
    final loc = _location.text.trim();
    final name = _name.text.trim();
    if (loc.isEmpty) return name;
    if (name.isEmpty) return loc;
    return p.join(loc, name);
  }

  String? _validate() {
    final name = _name.text.trim();
    final loc = _location.text.trim();
    if (name.isEmpty) return 'Enter a project name';
    if (RegExp(r'[<>:"/\\|?*]').hasMatch(name)) return 'Project name can\'t contain < > : " / \\ | ? *';
    if (loc.isEmpty) return 'Choose a location';
    final target = Directory(p.join(loc, name));
    if (target.existsSync() && target.listSync().isNotEmpty) {
      return 'A non-empty folder named "$name" already exists here';
    }
    return null;
  }

  Future<void> _browse() async {
    final current = _location.text.trim();
    final picked = await pickFolder(context, start: Directory(current).existsSync() ? current : null);
    if (picked == null || !mounted) return;
    setState(() {
      _location.text = picked;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await createProject(
        parentDir: _location.text.trim(),
        name: _name.text.trim(),
        template: _selected,
        createSample: _createSample,
        buildTool: _buildTool,
      );
      if (mounted) Navigator.of(context).pop(created);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Couldn\'t create project: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 460),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DialogHeader(title: 'New Project', onClose: () => Navigator.of(context).pop()),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final compact = box.maxWidth < 560;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTemplateList(width: compact ? 140 : 196),
                      Expanded(child: _buildForm(compact: compact)),
                    ],
                  );
                },
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateList({double width = 196}) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: Tk.sidebar,
        border: Border(right: BorderSide(color: Tk.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final t in projectTemplates)
            _TemplateRow(
              template: t,
              selected: t.id == _selected.id,
              onTap: () => setState(() {
                _selected = t;
                _buildTool = t.buildTools.first;
                _error = null;
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildForm({bool compact = false}) {
    final labelW = compact ? 64.0 : 84.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 20, compact ? 16 : 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_selected.name, style: Tk.ui.copyWith(fontSize: 15, fontWeight: FontWeight.w600, color: Tk.textStrong)),
                  const SizedBox(height: 2),
                  Text(_selected.subtitle, style: Tk.uiSmall.copyWith(color: Tk.textMuted)),
                  const SizedBox(height: 18),
                  _FieldRow(
                    label: 'Name',
                    labelWidth: labelW,
                    child: TextField(
                      controller: _name,
                      autofocus: true,
                      style: Tk.code.copyWith(fontSize: 13),
                      onChanged: (_) => setState(() => _error = null),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FieldRow(
                    label: 'Location',
                    labelWidth: labelW,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _location,
                            style: Tk.code.copyWith(fontSize: 13),
                            onChanged: (_) => setState(() => _error = null),
                            onSubmitted: (_) => _submit(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GhostButton(label: 'Browse…', onPressed: _busy ? null : _browse),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: EdgeInsets.only(left: labelW),
                    child: Text(
                      _fullPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tk.uiSmall.copyWith(color: Tk.textFaint),
                    ),
                  ),
                  if (_selected.buildTools.length > 1) ...[
                    const SizedBox(height: 14),
                    _FieldRow(
                      label: 'Build tool',
                      labelWidth: labelW,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final bt in _selected.buildTools)
                            OptionPill(
                              label: bt,
                              active: bt == _buildTool,
                              onTap: () => setState(() => _buildTool = bt),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (_selected.entryFile != null) ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: EdgeInsets.only(left: labelW),
                      child: InkWell(
                        onTap: () => setState(() => _createSample = !_createSample),
                        borderRadius: Tk.radius,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: Checkbox(
                                  value: _createSample,
                                  onChanged: (v) => setState(() => _createSample = v ?? true),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(child: Text('Add sample code (${_selected.entryFile})', style: Tk.ui)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_selected.toolchainCommand != null) ...[
                    const SizedBox(height: 14),
                    _ToolchainStatus(tools: _tools, command: _selected.toolchainCommand!, labelWidth: labelW),
                  ],
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: EdgeInsets.only(left: labelW, top: 8),
              child: Text(_error!, style: Tk.uiSmall.copyWith(color: Tk.error)),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Tk.border))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GhostButton(label: 'Cancel', onPressed: _busy ? null : () => Navigator.of(context).pop()),
          const SizedBox(width: 8),
          PrimaryButton(label: _busy ? 'Creating…' : 'Create', onPressed: _busy ? null : _submit),
        ],
      ),
    );
  }
}

class _TemplateRow extends StatefulWidget {
  const _TemplateRow({required this.template, required this.selected, required this.onTap});

  final ProjectTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TemplateRow> createState() => _TemplateRowState();
}

class _TemplateRowState extends State<_TemplateRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.selected ? Tk.listActive : (_hover ? Tk.hover : Colors.transparent),
            border: Border(left: BorderSide(color: widget.selected ? Tk.accent : Colors.transparent, width: 2)),
          ),
          child: Row(
            children: [
              if (t.entryFile != null)
                LangBadge(path: t.entryFile!)
              else
                const SizedBox(width: 18, child: Icon(Icons.folder_outlined, size: 15, color: Tk.textMuted)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tk.ui.copyWith(color: widget.selected ? Tk.textStrong : Tk.text),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.child, this.labelWidth = 84});

  final String label;
  final Widget child;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: labelWidth,
          child: Text(label, style: Tk.ui.copyWith(color: Tk.textMuted)),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _ToolchainStatus extends StatelessWidget {
  const _ToolchainStatus({required this.tools, required this.command, this.labelWidth = 84});

  final Future<List<Toolchain>> tools;
  final String command;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return _FieldRow(
      label: 'Toolchain',
      labelWidth: labelWidth,
      child: FutureBuilder<List<Toolchain>>(
        future: tools,
        builder: (context, snap) {
          if (!snap.hasData) {
            return Text('Checking PATH for $command…', style: Tk.uiSmall.copyWith(color: Tk.textFaint));
          }
          final match = snap.data!.where((t) => t.command == command).firstOrNull;
          final ok = match?.found == true;
          final label = ok
              ? '${match!.name} ${match.version ?? ''}'.trim()
              : '$command not found on PATH (you can still edit files)';
          return Row(
            children: [
              StatusDot(color: ok ? Tk.success : Tk.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tk.uiSmall.copyWith(color: ok ? Tk.textMuted : Tk.warning),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
