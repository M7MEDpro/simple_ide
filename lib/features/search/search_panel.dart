import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/features/search/project_search.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/shared/widgets.dart';

/**
 * Sidebar panel for global search and replace across the open workspace.
 */
class SearchPanel extends ConsumerStatefulWidget {
  const SearchPanel({super.key});

  @override
  ConsumerState<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<SearchPanel> {
  final _query = TextEditingController();
  final _replace = TextEditingController();
  Timer? _debounce;
  bool _caseSensitive = false;
  bool _showReplace = false;
  bool _searching = false;
  List<FileSearchGroup> _groups = const [];
  final Set<String> _collapsed = {};

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _replace.dispose();
    super.dispose();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), _runSearch);
  }

  Future<void> _runSearch() async {
    final ide = ref.read(ideProvider);
    final ws = ide.workspace;
    final q = _query.text;
    if (ws == null || q.isEmpty) {
      if (mounted) {
        setState(() {
          _groups = const [];
          _searching = false;
        });
      }
      return;
    }
    setState(() => _searching = true);
    final files = ws.allFiles(limit: 2000);
    final res = await searchInProject(files, q, caseSensitive: _caseSensitive);
    if (!mounted || _query.text != q) return;
    setState(() {
      _groups = res;
      _searching = false;
    });
  }

  Future<void> _replaceAll() async {
    final ide = ref.read(ideProvider);
    final q = _query.text;
    if (q.isEmpty || _groups.isEmpty) return;
    final total = _groups.fold<int>(0, (sum, g) => sum + g.matches.length);
    final ok = await showConfirm(
      context,
      title: 'Replace All',
      message: 'Replace $total occurrence(s) of "$q" across ${_groups.length} file(s)?',
      action: 'Replace All',
    );
    if (!ok || !mounted) return;
    await ide.saveAll();
    final count = await replaceInFiles(
      _groups,
      q,
      _replace.text,
      caseSensitive: _caseSensitive,
      onFileUpdated: (path) async {
        for (final doc in ide.docs) {
          if (doc.path == path) await doc.reloadIfClean();
        }
      },
    );
    ide.notify('Replaced $count occurrence(s)');
    await _runSearch();
  }

  @override
  Widget build(BuildContext context) {
    final ide = ref.watch(ideProvider);
    final root = ide.workspace?.root ?? '';
    final totalHits = _groups.fold<int>(0, (s, g) => s + g.matches.length);

    return Container(
      color: Tk.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(totalHits),
          _buildInputs(),
          const Divider(height: 1, color: Tk.border),
          Expanded(
            child: _searching
                ? const Center(
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : _query.text.isEmpty
                    ? Center(
                        child: Text(
                          'Type to search in project',
                          style: Tk.uiSmall.copyWith(color: Tk.textFaint),
                        ),
                      )
                    : _groups.isEmpty
                        ? Center(
                            child: Text(
                              'No results found',
                              style: Tk.uiSmall.copyWith(color: Tk.textFaint),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            children: [
                              for (final group in _groups) ...[
                                _FileGroupHeader(
                                  relPath: relativeDisplayPath(root, group.path),
                                  filePath: group.path,
                                  count: group.matches.length,
                                  collapsed: _collapsed.contains(group.path),
                                  onToggle: () => setState(() {
                                    if (!_collapsed.add(group.path)) {
                                      _collapsed.remove(group.path);
                                    }
                                  }),
                                ),
                                if (!_collapsed.contains(group.path))
                                  for (final m in group.matches)
                                    _MatchRow(
                                      match: m,
                                      onTap: () => ide.openFile(m.path, line: m.line, column: m.column),
                                    ),
                              ],
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(int totalHits) {
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: 14, right: 6),
      child: Row(
        children: [
          const Text(
            'SEARCH',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.9, color: Tk.textMuted),
          ),
          if (totalHits > 0) ...[
            const SizedBox(width: 8),
            Text('$totalHits', style: Tk.uiSmall.copyWith(color: Tk.textFaint)),
          ],
          const Spacer(),
          IconBtn(
            icon: _showReplace ? Icons.unfold_less_rounded : Icons.find_replace_rounded,
            tooltip: _showReplace ? 'Hide replace' : 'Show replace',
            onPressed: () => setState(() => _showReplace = !_showReplace),
          ),
          IconBtn(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh search',
            onPressed: _runSearch,
          ),
        ],
      ),
    );
  }

  Widget _buildInputs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _query,
                  autofocus: true,
                  style: Tk.code.copyWith(fontSize: 12.5),
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  ),
                  onChanged: (_) => _scheduleSearch(),
                  onSubmitted: (_) => _runSearch(),
                ),
              ),
              const SizedBox(width: 6),
              OptionPill(
                label: 'Aa',
                active: _caseSensitive,
                onTap: () {
                  setState(() => _caseSensitive = !_caseSensitive);
                  _runSearch();
                },
              ),
            ],
          ),
          if (_showReplace) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replace,
                    style: Tk.code.copyWith(fontSize: 12.5),
                    decoration: const InputDecoration(
                      hintText: 'Replace',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                    ),
                    onSubmitted: (_) => _replaceAll(),
                  ),
                ),
                const SizedBox(width: 6),
                GhostButton(
                  label: 'All',
                  onPressed: _groups.isEmpty ? null : _replaceAll,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FileGroupHeader extends StatelessWidget {
  const _FileGroupHeader({
    required this.relPath,
    required this.filePath,
    required this.count,
    required this.collapsed,
    required this.onToggle,
  });

  final String relPath;
  final String filePath;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right_rounded : Icons.expand_more_rounded,
              size: 16,
              color: Tk.textMuted,
            ),
            const SizedBox(width: 4),
            LangBadge(path: filePath),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                relPath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tk.uiSmall.copyWith(color: Tk.textStrong, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 6),
            Text('$count', style: Tk.uiSmall.copyWith(color: Tk.textFaint)),
          ],
        ),
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, required this.onTap});

  final SearchMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final trimmed = match.lineText.trimLeft();
    final shift = match.lineText.length - trimmed.length;
    final relStart = (match.matchStart - shift).clamp(0, trimmed.length);
    final relEnd = (relStart + match.matchLength).clamp(0, trimmed.length);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 3, 10, 3),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '${match.line}',
                style: Tk.code.copyWith(fontSize: 11, color: Tk.textFaint),
              ),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: Tk.code.copyWith(fontSize: 11.5, color: Tk.textMuted),
                  children: [
                    TextSpan(text: trimmed.substring(0, relStart)),
                    TextSpan(
                      text: trimmed.substring(relStart, relEnd),
                      style: TextStyle(
                        color: Tk.textStrong,
                        backgroundColor: Tk.accent.withValues(alpha: 0.28),
                      ),
                    ),
                    TextSpan(text: trimmed.substring(relEnd)),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
