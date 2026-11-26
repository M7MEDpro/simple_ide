import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/features/diagnostics/diagnostic_layers.dart';
import 'package:simple_ide/features/diagnostics/diagnostics.dart';
import 'package:simple_ide/features/editor/code_suggestions.dart';
import 'package:simple_ide/features/editor/document.dart';
import 'package:simple_ide/features/editor/find_panel.dart';
import 'package:simple_ide/features/editor/git_gutter.dart';
import 'package:simple_ide/features/git/git_service.dart';
import 'package:simple_ide/features/runner/languages.dart';
import 'package:simple_ide/features/settings/settings.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/shared/widgets.dart';

export 'package:simple_ide/features/editor/go_to_line_dialog.dart';

final _themeModes = {for (final e in highlightModes.entries) e.key: CodeHighlightThemeMode(mode: e.value)};

/**
 * Editor area for the active document: breadcrumb plus the code editor.
 */
class EditorPane extends ConsumerWidget {
  const EditorPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ide = ref.watch(ideProvider);
    final doc = ide.active!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Breadcrumb(doc: doc, root: ide.workspace?.root),
        Expanded(
          child: doc.binary ? const _BinaryNotice() : CodeView(key: ObjectKey(doc), doc: doc),
        ),
      ],
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.doc, required this.root});

  final EditorDocument doc;
  final String? root;

  @override
  Widget build(BuildContext context) {
    final rel = root != null && p.isWithin(root!, doc.path) ? p.relative(doc.path, from: root) : doc.path;
    final parts = p.split(rel);
    return Container(
      height: 24,
      color: Tk.editor,
      padding: const EdgeInsets.only(left: 14, right: 12),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < parts.length; i++) ...[
                    if (i > 0) const Icon(Icons.chevron_right_rounded, size: 14, color: Tk.textFaint),
                    Text(parts[i], style: Tk.uiSmall.copyWith(color: i == parts.length - 1 ? Tk.text : Tk.textMuted)),
                  ],
                ],
              ),
            ),
          ),
          if (doc.readOnly && !doc.binary) ...[
            const SizedBox(width: 12),
            Text('Read-only: file is larger than 8 MB', style: Tk.uiSmall.copyWith(color: Tk.warning)),
          ],
        ],
      ),
    );
  }
}

class _BinaryNotice extends StatelessWidget {
  const _BinaryNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Tk.editor,
      alignment: Alignment.center,
      child: Text(
        'This file is binary, so it isn\'t shown in the text editor.',
        style: Tk.ui.copyWith(color: Tk.textMuted),
      ),
    );
  }
}

/**
 * Wraps [CodeEditor] with the IDE's theme, find panel, autocomplete,
 * context menu, and per-document scroll restoration.
 */
class CodeView extends ConsumerStatefulWidget {
  const CodeView({super.key, required this.doc});

  final EditorDocument doc;

  @override
  ConsumerState<CodeView> createState() => _CodeViewState();
}

class _CodeViewState extends ConsumerState<CodeView> {
  late final CodeScrollController _scroll;
  late final CodeFindController _find;
  late final IdePromptsBuilder _prompts;
  final _focus = FocusNode(debugLabel: 'code');
  final _stackKey = GlobalKey();
  final _gutterKey = GlobalKey();
  CodeIndicatorValueNotifier? _indicator;
  IdeController? _ide;
  Map<int, GitLineChange> _gitChanges = const {};
  Timer? _gitTimer;

  @override
  void initState() {
    super.initState();
    final d = widget.doc;
    d.decorateLine = _decorate;
    d.addListener(_scheduleGitDiff);
    _scroll = CodeScrollController(
      verticalScroller: ScrollController(initialScrollOffset: d.scrollTop),
      horizontalScroller: ScrollController(initialScrollOffset: d.scrollLeft),
    );
    _scroll.verticalScroller.addListener(_remember);
    _scroll.horizontalScroller.addListener(_remember);
    _find = CodeFindController(d.controller);
    _prompts = IdePromptsBuilder(languageId: d.language.id, controller: d.controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ide = ref.read(ideProvider);
    if (!identical(ide, _ide)) {
      _gitTimer?.cancel();
    widget.doc.removeListener(_scheduleGitDiff);
    _ide?.focusEditorRequest.removeListener(_takeFocus);
      _ide?.diagnostics.removeListener(_onProblems);
      _ide = ide
        ..focusEditorRequest.addListener(_takeFocus)
        ..diagnostics.addListener(_onProblems);
      _refreshGitDiff();
    }
  }

  void _scheduleGitDiff() {
    _gitTimer?.cancel();
    _gitTimer = Timer(const Duration(milliseconds: 500), _refreshGitDiff);
  }

  Future<void> _refreshGitDiff() async {
    final root = _ide?.workspace?.root;
    if (root == null) return;
    final map = await GitService.diffLines(root, widget.doc.path);
    if (!mounted) return;
    setState(() => _gitChanges = map);
  }

  List<Diagnostic> get _problems => _ide?.diagnostics.forFile(widget.doc.path) ?? const [];
  bool get _stale => _ide?.diagnostics.isStale(widget.doc.path) ?? false;

  void _onProblems() {
    if (!mounted) return;
    widget.doc.repaintLines();
    setState(() {});
  }

  TextSpan _decorate(int index, String text, TextSpan span, TextStyle style) {
    Diagnostic? worst;
    for (final d in _problems) {
      if (d.line - 1 == index && (worst == null || d.severity.index < worst.severity.index)) worst = d;
    }
    if (worst == null) return span;
    final range = underlineRange(text, worst.column);
    if (range == null) return span;
    final color = severityColor(worst.severity).withValues(alpha: _stale ? 0.45 : 1);
    return underlineSpan(span, style, range, color);
  }

  Offset _gutterOrigin() {
    final g = _gutterKey.currentContext?.findRenderObject() as RenderBox?;
    final s = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (g == null || s == null || !g.attached || !s.attached) return Offset.zero;
    return g.localToGlobal(Offset(g.size.width, 0), ancestor: s);
  }

  void _takeFocus() {
    if (mounted) _focus.requestFocus();
  }

  void _remember() {
    final v = _scroll.verticalScroller;
    final h = _scroll.horizontalScroller;
    if (v.hasClients) widget.doc.scrollTop = v.offset;
    if (h.hasClients) widget.doc.scrollLeft = h.offset;
  }

  @override
  void dispose() {
    _gitTimer?.cancel();
    widget.doc.removeListener(_scheduleGitDiff);
    _ide?.focusEditorRequest.removeListener(_takeFocus);
    _ide?.diagnostics.removeListener(_onProblems);
    if (widget.doc.decorateLine == _decorate) widget.doc.decorateLine = null;
    _scroll.verticalScroller.removeListener(_remember);
    _scroll.horizontalScroller.removeListener(_remember);
    _scroll.verticalScroller.dispose();
    _scroll.horizontalScroller.dispose();
    _find.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ide = ref.watch(ideProvider);
    final s = ide.settings;
    final lang = widget.doc.language;
    final codeStyle = Tk.code.copyWith(fontSize: s.fontSize);
    final indicator = _indicator;
    return Stack(
      key: _stackKey,
      children: [
        _editor(ide, s, lang, codeStyle),
        if (indicator != null)
          Positioned.fill(
            child: InlineDiagnostics(
              notifier: indicator,
              problems: _problems,
              stale: _stale,
              textLeft: () => _gutterOrigin().dx + 1,
              top: () => _gutterOrigin().dy,
              fontSize: s.fontSize,
              repaint: _scroll.horizontalScroller,
            ),
          ),
      ],
    );
  }

  Widget _editor(IdeController ide, Settings s, Language lang, TextStyle codeStyle) {
    final editor = CodeEditor(
      controller: widget.doc.controller,
      scrollController: _scroll,
      findController: _find,
      focusNode: _focus,
      autofocus: true,
      readOnly: widget.doc.readOnly,
      wordWrap: s.wordWrap,
      padding: const EdgeInsets.only(left: 6, right: 12, top: 6, bottom: 120),
      style: CodeEditorStyle(
        fontSize: s.fontSize,
        fontFamily: Tk.codeFont,
        fontFamilyFallback: Tk.codeFallback,
        fontHeight: 1.5,
        textColor: Tk.text,
        hintTextColor: Tk.textFaint,
        backgroundColor: Tk.editor,
        selectionColor: Tk.selection,
        highlightColor: Tk.accent.withValues(alpha: 0.22),
        cursorColor: Tk.accent,
        cursorWidth: 2,
        cursorLineColor: Tk.activeLine,
        chunkIndicatorColor: Tk.textFaint,
        codeTheme: CodeHighlightTheme(
          languages: lang.mode == null ? const {} : {lang.id: _themeModes[lang.id]!},
          theme: kSyntaxTheme,
        ),
      ),
      commentFormatter: DefaultCodeCommentFormatter(
        singleLinePrefix: lang.lineComment ?? '//',
        multiLinePrefix: lang.blockComment?.$1 ?? '/*',
        multiLineSuffix: lang.blockComment?.$2 ?? '*/',
      ),
      indicatorBuilder: (context, editing, chunk, notifier) {
        if (!identical(notifier, _indicator)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _indicator = notifier);
          });
        }
        return Row(
          key: _gutterKey,
          children: [
            DiagnosticGutter(notifier: notifier, problems: () => _problems, stale: () => _stale),
            DefaultCodeLineNumber(
              controller: editing,
              notifier: notifier,
              minNumberCount: 3,
              textStyle: codeStyle.copyWith(color: Tk.textFaint, height: 1.5),
              focusedTextStyle: codeStyle.copyWith(color: Tk.text, height: 1.5),
            ),
            GitGutter(notifier: notifier, changes: () => _gitChanges),
            DefaultCodeChunkIndicator(width: 18, controller: chunk, notifier: notifier),
          ],
        );
      },
      findBuilder: (context, controller, readOnly) => FindPanel(controller: controller, readOnly: readOnly),
      toolbarController: _EditorMenu(onRun: ide.runActive),
      shortcutOverrideActions: {
        CodeShortcutSaveIntent: CallbackAction<CodeShortcutSaveIntent>(onInvoke: (_) => ide.saveActive()),
      },
      scrollbarBuilder: (context, child, details) =>
          Scrollbar(controller: details.controller, thickness: 10, child: child),
    );
    if (widget.doc.readOnly) return editor;
    return CodeAutocomplete(
      promptsBuilder: _prompts,
      viewBuilder: (context, notifier, onSelected) => AutocompletePopup(
        notifier: notifier,
        onSelected: onSelected,
      ),
      child: editor,
    );
  }
}

class _EditorMenu implements SelectionToolbarController {
  _EditorMenu({required this.onRun});
  final VoidCallback onRun;

  @override
  void hide(BuildContext context) {}

  @override
  void show({
    required BuildContext context,
    required CodeLineEditingController controller,
    required TextSelectionToolbarAnchors anchors,
    Rect? renderRect,
    required LayerLink layerLink,
    required ValueNotifier<bool> visibility,
  }) {
    final hasSel = !controller.selection.isCollapsed;
    showContextMenu(context, anchors.primaryAnchor, [
      ContextItem('Cut', hasSel ? controller.cut : null, shortcut: 'Ctrl+X'),
      ContextItem('Copy', hasSel ? controller.copy : null, shortcut: 'Ctrl+C'),
      ContextItem('Paste', controller.paste, shortcut: 'Ctrl+V'),
      const ContextItem.divider(),
      ContextItem('Select all', controller.selectAll, shortcut: 'Ctrl+A'),
      ContextItem('Toggle line comment', () {
        Actions.maybeInvoke(context, const CodeShortcutCommentIntent(true));
      }, shortcut: 'Ctrl+/'),
      const ContextItem.divider(),
      ContextItem('Run file', onRun, shortcut: 'F5'),
    ]);
  }
}
