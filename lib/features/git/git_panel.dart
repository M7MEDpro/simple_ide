import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/features/git/git_service.dart';
import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/features/explorer/workspace.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/shared/widgets.dart';

/**
 * Sidebar panel for Git & GitHub operations: status, stage/unstage, commit,
 * pull, push, and remote link.
 */
class GitPanel extends ConsumerStatefulWidget {
  const GitPanel({super.key});

  @override
  ConsumerState<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends ConsumerState<GitPanel> {
  final _commitCtrl = TextEditingController();
  GitStatus? _status;
  bool _loading = true;
  bool _busy = false;
  String? _lastRoot;
  Workspace? _ws;
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ws = ref.read(ideProvider).workspace;
    if (!identical(ws, _ws)) {
      _ws?.removeListener(_scheduleRefresh);
      _ws = ws?..addListener(_scheduleRefresh);
    }
    final root = ws?.root;
    if (root != null && root != _lastRoot) {
      _lastRoot = root;
      _refresh();
    }
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _refresh);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ws?.removeListener(_scheduleRefresh);
    _commitCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final root = _lastRoot;
    if (root == null) return;
    if (mounted) setState(() => _loading = true);
    final st = await GitService.inspect(root);
    if (!mounted || root != _lastRoot) return;
    setState(() {
      _status = st;
      _loading = false;
    });
  }

  Future<void> _runAction(Future<GitResult> Function(String root) action) async {
    final root = _lastRoot;
    if (root == null || _busy) return;
    setState(() => _busy = true);
    final ide = ref.read(ideProvider);
    await ide.saveAll();
    final res = await action(root);
    if (!mounted) return;
    setState(() => _busy = false);
    ide.notify(res.message, error: !res.ok);
    await _refresh();
  }

  Future<void> _commit() async {
    final msg = _commitCtrl.text.trim();
    if (msg.isEmpty) {
      ref.read(ideProvider).notify('Enter a commit message first.', error: true);
      return;
    }
    await _runAction((root) async {
      final r = await GitService.commit(root, msg);
      if (r.ok && mounted) _commitCtrl.clear();
      return r;
    });
  }

  Future<void> _setRemote() async {
    final url = await showTextPrompt(
      context,
      title: 'GitHub / Git Remote (origin)',
      action: 'Save',
      initial: _status?.remoteUrl ?? '',
      hint: 'https://github.com/user/repo.git',
      validate: (v) => v.trim().isEmpty ? 'Enter a repository URL' : null,
    );
    if (url == null) return;
    await _runAction((root) => GitService.setOrigin(root, url.trim()));
  }

  String? _browserUrl(String? remote) {
    if (remote == null) return null;
    if (remote.startsWith('https://') || remote.startsWith('http://')) {
      return remote.endsWith('.git') ? remote.substring(0, remote.length - 4) : remote;
    }
    final ssh = RegExp(r'^git@([^:]+):(.+?)(?:\.git)?$').firstMatch(remote);
    if (ssh != null) return 'https://${ssh[1]}/${ssh[2]}';
    return null;
  }

  void _openInBrowser(String url) {
    if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', url]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = _status;
    final webUrl = _browserUrl(st?.remoteUrl);
    return Container(
      color: Tk.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 34,
            child: Padding(
              padding: const EdgeInsets.only(left: 14, right: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Source Control', style: Tk.ui.copyWith(fontWeight: FontWeight.w600, color: Tk.textStrong)),
                  ),
                  if (webUrl != null)
                    IconBtn(
                      icon: Icons.open_in_new_rounded,
                      tooltip: 'Open on GitHub',
                      onPressed: () => _openInBrowser(webUrl),
                    ),
                  if (st?.isRepo == true) ...[
                    IconBtn(
                      icon: Icons.south_rounded,
                      tooltip: 'Pull',
                      onPressed: _busy ? null : () => _runAction(GitService.pull),
                    ),
                    IconBtn(
                      icon: Icons.north_rounded,
                      tooltip: 'Push',
                      onPressed: _busy ? null : () => _runAction(GitService.push),
                    ),
                  ],
                  IconBtn(icon: Icons.refresh_rounded, tooltip: 'Refresh', onPressed: _busy ? null : _refresh),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Tk.border),
          Expanded(child: _body(st)),
        ],
      ),
    );
  }

  Widget _body(GitStatus? st) {
    if (_loading && st == null) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text('Checking Git status…', style: Tk.ui.copyWith(color: Tk.textMuted)),
      );
    }
    if (st == null || !st.gitAvailable) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          'Git was not found on PATH. Install Git for Windows to manage repositories and push to GitHub.',
          style: Tk.ui.copyWith(color: Tk.textMuted, height: 1.5),
        ),
      );
    }
    if (!st.isRepo) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This folder is not a Git repository yet.', style: Tk.ui.copyWith(color: Tk.textMuted, height: 1.5)),
            const SizedBox(height: 12),
            PrimaryButton(
              label: _busy ? 'Initializing…' : 'Initialize Repository',
              onPressed: _busy ? null : () => _runAction(GitService.init),
            ),
          ],
        ),
      );
    }

    final changes = st.changes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.call_split_rounded, size: 14, color: Tk.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      st.branch ?? 'HEAD',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tk.uiSmall.copyWith(color: Tk.textStrong, fontWeight: FontWeight.w600),
                    ),
                  ),
                  GestureDetector(
                    onTap: _busy ? null : _setRemote,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Text(
                        st.remoteUrl == null ? 'Add remote…' : 'origin',
                        style: Tk.uiSmall.copyWith(color: Tk.info),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _commitCtrl,
                enabled: !_busy,
                style: Tk.ui,
                decoration: const InputDecoration(hintText: 'Commit message'),
                onSubmitted: (_) => _commit(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      label: _busy ? 'Working…' : 'Commit',
                      onPressed: _busy || changes.isEmpty ? null : _commit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Tk.border),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  changes.isEmpty ? 'Working tree clean' : 'Changes (${changes.length})',
                  style: Tk.uiSmall.copyWith(color: Tk.textMuted, fontWeight: FontWeight.w600),
                ),
              ),
              if (changes.isNotEmpty)
                IconBtn(
                  icon: Icons.add_rounded,
                  tooltip: 'Stage all',
                  onPressed: _busy ? null : () => _runAction(GitService.stageAll),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemExtent: 24,
            itemCount: changes.length,
            itemBuilder: (context, i) => _ChangeRow(
              change: changes[i],
              onOpen: () => ref.read(ideProvider).openFile(changes[i].path),
              onToggleStage: _busy
                  ? null
                  : () => _runAction(
                        (root) => changes[i].staged
                            ? GitService.unstage(root, changes[i].path)
                            : GitService.stage(root, changes[i].path),
                      ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChangeRow extends StatefulWidget {
  const _ChangeRow({required this.change, required this.onOpen, required this.onToggleStage});
  final GitChange change;
  final VoidCallback onOpen;
  final VoidCallback? onToggleStage;

  @override
  State<_ChangeRow> createState() => _ChangeRowState();
}

class _ChangeRowState extends State<_ChangeRow> {
  bool _hover = false;

  static Color _codeColor(String code) => switch (code) {
        'U' || 'A' => Tk.success,
        'D' => Tk.error,
        _ => Tk.warning,
      };

  @override
  Widget build(BuildContext context) {
    final c = widget.change;
    final color = _codeColor(c.code);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: Container(
          color: _hover ? Tk.hover : Colors.transparent,
          padding: const EdgeInsets.only(left: 12, right: 6),
          child: Row(
            children: [
              LangBadge(path: c.path),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  p.basename(c.relativePath),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tk.ui.copyWith(color: color),
                ),
              ),
              if (_hover)
                IconBtn(
                  icon: c.staged ? Icons.remove_rounded : Icons.add_rounded,
                  tooltip: c.staged ? 'Unstage' : 'Stage',
                  size: 14,
                  box: 20,
                  onPressed: widget.onToggleStage,
                ),
              const SizedBox(width: 4),
              Text(
                c.staged ? '${c.code}•' : c.code,
                style: Tk.uiSmall.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
