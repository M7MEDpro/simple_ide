import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/features/runner/console_input_row.dart';
import 'package:simple_ide/features/runner/console_line_view.dart';
import 'package:simple_ide/features/runner/run_state_chip.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/features/diagnostics/problems_view.dart';
import 'package:simple_ide/shared/widgets.dart';

export 'package:simple_ide/features/runner/run_state_chip.dart';

/**
 * Bottom dock: program output, compiler diagnostics, and an input line that
 * feeds the running program's stdin, or runs a command when idle.
 */
class ConsolePanel extends ConsumerStatefulWidget {
  const ConsolePanel({super.key});

  @override
  ConsumerState<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends ConsumerState<ConsolePanel> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode(debugLabel: 'console-input');
  final _scroll = ScrollController();
  final List<String> _history = [];
  int _historyPos = 0;
  IdeController? _ide;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ide = ref.read(ideProvider);
    if (!identical(ide, _ide)) {
      _ide?.focusConsoleRequest.removeListener(_focusInput);
      _ide = ide..focusConsoleRequest.addListener(_focusInput);
    }
  }

  void _focusInput() {
    if (mounted) _inputFocus.requestFocus();
  }

  @override
  void dispose() {
    _ide?.focusConsoleRequest.removeListener(_focusInput);
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit(IdeController ide) {
    final text = _input.text;
    if (text.trim().isNotEmpty && (_history.isEmpty || _history.last != text)) _history.add(text);
    _historyPos = _history.length;
    _input.clear();
    ide.submitConsole(text);
    _inputFocus.requestFocus();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  KeyEventResult _onKey(KeyEvent e, IdeController ide) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (k == LogicalKeyboardKey.arrowUp && _history.isNotEmpty) {
      _historyPos = (_historyPos - 1).clamp(0, _history.length - 1);
      _setInput(_history[_historyPos]);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown && _history.isNotEmpty) {
      _historyPos = (_historyPos + 1).clamp(0, _history.length);
      _setInput(_historyPos == _history.length ? '' : _history[_historyPos]);
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyC && ide.runner.busy && _input.selection.isCollapsed) {
      ide.stopRun();
      return KeyEventResult.handled;
    }
    if (ctrl && (k == LogicalKeyboardKey.keyZ || k == LogicalKeyboardKey.keyD) && ide.runner.acceptsInput && _input.text.isEmpty) {
      ide.runner.sendEof();
      return KeyEventResult.handled;
    }
    if (ctrl && k == LogicalKeyboardKey.keyL) {
      ide.console.clear();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _setInput(String v) {
    _input.value = TextEditingValue(text: v, selection: TextSelection.collapsed(offset: v.length));
  }

  @override
  Widget build(BuildContext context) {
    final ide = ref.watch(ideProvider);
    return Container(
      color: Tk.sidebar,
      child: ValueListenableBuilder<BottomTab>(
        valueListenable: ide.bottomTab,
        builder: (context, tab, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(ide: ide, tab: tab),
            if (tab == BottomTab.problems)
              const Expanded(child: ProblemsView())
            else ...[
              Expanded(child: _output(ide)),
              ListenableBuilder(
                listenable: ide.runner,
                builder: (context, _) => ConsoleInputRow(
                  controller: _input,
                  focusNode: _inputFocus,
                  ide: ide,
                  onSubmit: () => _submit(ide),
                  onKey: (e) => _onKey(e, ide),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _output(IdeController ide) {
    return ListenableBuilder(
              listenable: ide.console,
              builder: (context, _) {
                final lines = ide.console.lines;
                if (lines.isEmpty) return const SizedBox.expand();
                return SelectionArea(
                  child: Scrollbar(
                    controller: _scroll,
                    child: ListView.builder(
                      controller: _scroll,
                      reverse: true, // newest line pinned to the bottom
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
                      itemCount: lines.length,
                      itemBuilder: (context, i) => ConsoleLineView(
                        line: lines[lines.length - 1 - i],
                        fontSize: (ide.settings.fontSize - 1).clamp(10, 28),
                        onOpen: (l) => ide.openFile(l.path, line: l.line, column: l.column),
                      ),
                    ),
                  ),
                );
              },
            );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.ide, required this.tab});
  final IdeController ide;
  final BottomTab tab;

  @override
  Widget build(BuildContext context) {
    final console = tab == BottomTab.console;
    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 6, right: 6),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Tk.border))),
      child: LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TabLabel(label: 'Console', active: console, onTap: () => ide.bottomTab.value = BottomTab.console),
                    ListenableBuilder(
                      listenable: ide.diagnostics,
                      builder: (context, _) {
                        final n = ide.diagnostics.errorCount + ide.diagnostics.warningCount;
                        return _TabLabel(
                          label: 'Problems',
                          count: n,
                          countColor: ide.diagnostics.errorCount > 0 ? Tk.error : Tk.warning,
                          active: !console,
                          onTap: () => ide.bottomTab.value = BottomTab.problems,
                        );
                      },
                    ),
                    if (box.maxWidth >= 320) ...[
                      const SizedBox(width: 12),
                      ListenableBuilder(
                        listenable: ide.runner,
                        builder: (context, _) => RunStateChip(runner: ide.runner, compact: box.maxWidth < 480),
                      ),
                    ],
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListenableBuilder(
                      listenable: ide.runner,
                      builder: (context, _) => ide.runner.busy
                          ? IconBtn(icon: Icons.stop_rounded, tooltip: 'Stop (Shift+F5)', color: Tk.error, onPressed: ide.stopRun)
                          : const SizedBox.shrink(),
                    ),
                    if (console) ...[
                      IconBtn(
                        icon: Icons.copy_all_rounded,
                        tooltip: 'Copy all output',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: ide.console.plainText));
                          ide.notify('Console output copied');
                        },
                      ),
                      IconBtn(icon: Icons.block_rounded, tooltip: 'Clear (Ctrl+L)', onPressed: ide.console.clear),
                    ],
                    IconBtn(icon: Icons.keyboard_arrow_down_rounded, tooltip: 'Hide panel (Ctrl+J)', onPressed: ide.toggleConsole),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/**
 * Tool-window tab in the bottom panel header.
 */
class _TabLabel extends StatefulWidget {
  const _TabLabel({required this.label, required this.active, required this.onTap, this.count = 0, this.countColor});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int count;
  final Color? countColor;

  @override
  State<_TabLabel> createState() => _TabLabelState();
}

class _TabLabelState extends State<_TabLabel> {
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
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: widget.active ? Tk.textStrong : Colors.transparent, width: 2)),
          ),
          alignment: Alignment.center,
          child: Row(
            children: [
              Text(
                widget.label,
                style: Tk.ui.copyWith(color: widget.active || _hover ? Tk.textStrong : Tk.textMuted),
              ),
              if (widget.count > 0) ...[
                const SizedBox(width: 6),
                Text('${widget.count}', style: Tk.uiSmall.copyWith(color: widget.countColor ?? Tk.textMuted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
