import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'package:simple_ide/shared/tokens.dart';

const Map<String, List<String>> _languageSnippets = {
  'c': [
    'include', 'define', 'printf', 'scanf', 'fprintf', 'sprintf', 'malloc', 'calloc',
    'realloc', 'free', 'sizeof', 'struct', 'typedef', 'enum', 'union', 'return',
    'switch', 'case', 'default', 'break', 'continue', 'while', 'for', 'const',
    'static', 'extern', 'void', 'int', 'char', 'float', 'double', 'long', 'size_t',
    'NULL', 'stdin', 'stdout', 'stderr',
  ],
  'cpp': [
    'include', 'define', 'namespace', 'using', 'class', 'struct', 'public', 'private',
    'protected', 'virtual', 'override', 'template', 'typename', 'auto', 'constexpr',
    'const', 'nullptr', 'return', 'switch', 'case', 'break', 'continue', 'while',
    'for', 'std::cout', 'std::cin', 'std::endl', 'std::string', 'std::vector',
    'std::map', 'std::unordered_map', 'std::unique_ptr', 'std::shared_ptr',
    'size_t', 'void', 'bool', 'true', 'false',
  ],
  'python': [
    'def', 'class', 'return', 'import', 'from', 'as', 'if', 'elif', 'else', 'for',
    'while', 'break', 'continue', 'pass', 'try', 'except', 'finally', 'raise',
    'with', 'async', 'await', 'lambda', 'yield', 'True', 'False', 'None',
    'print', 'input', 'len', 'range', 'enumerate', 'zip', 'list', 'dict', 'set',
    'tuple', 'str', 'int', 'float', 'bool', 'isinstance', 'open',
  ],
  'java': [
    'public', 'private', 'protected', 'class', 'interface', 'enum', 'extends',
    'implements', 'static', 'final', 'void', 'return', 'new', 'this', 'super',
    'import', 'package', 'try', 'catch', 'finally', 'throw', 'throws', 'if',
    'else', 'for', 'while', 'switch', 'case', 'break', 'continue', 'true', 'false',
    'null', 'String', 'Scanner', 'System.out.println', 'ArrayList', 'HashMap',
  ],
  'javascript': [
    'const', 'let', 'var', 'function', 'return', 'async', 'await', 'class',
    'extends', 'import', 'export', 'default', 'if', 'else', 'for', 'while',
    'switch', 'case', 'break', 'continue', 'try', 'catch', 'finally', 'throw',
    'true', 'false', 'null', 'undefined', 'console.log', 'Promise', 'Array', 'Object',
  ],
  'typescript': [
    'const', 'let', 'function', 'return', 'async', 'await', 'interface', 'type',
    'class', 'implements', 'extends', 'import', 'export', 'default', 'enum',
    'public', 'private', 'readonly', 'string', 'number', 'boolean', 'void',
    'unknown', 'never', 'console.log', 'Promise',
  ],
  'dart': [
    'class', 'extends', 'implements', 'with', 'mixin', 'abstract', 'final', 'const',
    'var', 'late', 'void', 'return', 'async', 'await', 'Future', 'Stream', 'if',
    'else', 'for', 'while', 'switch', 'case', 'break', 'continue', 'try', 'catch',
    'import', 'package', 'required', 'override', 'Widget', 'BuildContext', 'print',
  ],
  'go': [
    'package', 'import', 'func', 'return', 'var', 'const', 'type', 'struct',
    'interface', 'if', 'else', 'for', 'range', 'switch', 'case', 'default',
    'defer', 'go', 'chan', 'select', 'map', 'make', 'len', 'append', 'fmt.Println',
    'nil', 'true', 'false', 'error',
  ],
  'rust': [
    'fn', 'let', 'mut', 'const', 'struct', 'enum', 'impl', 'trait', 'pub', 'use',
    'mod', 'crate', 'match', 'if', 'else', 'for', 'in', 'while', 'loop', 'break',
    'continue', 'return', 'Some', 'None', 'Ok', 'Err', 'Option', 'Result', 'Vec',
    'String', 'println!', 'true', 'false',
  ],
};

/**
 * Lightweight, allocation-conscious autocomplete prompts builder. Combines
 * language keywords/builtins with identifiers sampled from the open buffer.
 */
class IdePromptsBuilder implements CodeAutocompletePromptsBuilder {
  IdePromptsBuilder({required this.languageId, required this.controller});

  final String languageId;
  final CodeLineEditingController controller;

  List<String> _docWords = const [];
  DateTime _lastScan = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastLineCount = -1;

  static final _wordTail = RegExp(r'([A-Za-z_][\w:]*)$');
  static final _ident = RegExp(r'\b[A-Za-z_]\w{2,}\b');

  void _refreshDocWordsIfStale() {
    final now = DateTime.now();
    final count = controller.lineCount;
    if (count == _lastLineCount && now.difference(_lastScan).inMilliseconds < 800) return;
    _lastScan = now;
    _lastLineCount = count;

    final seen = <String>{};
    final limit = count < 400 ? count : 400;
    for (var i = 0; i < limit; i++) {
      final text = controller.codeLines[i].text;
      for (final m in _ident.allMatches(text)) {
        seen.add(m.group(0)!);
        if (seen.length >= 250) break;
      }
      if (seen.length >= 250) break;
    }
    _docWords = seen.toList(growable: false);
  }

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    if (!selection.isCollapsed) return null;
    final offset = selection.extentOffset.clamp(0, codeLine.text.length);
    final before = codeLine.text.substring(0, offset);
    final match = _wordTail.firstMatch(before);
    if (match == null) return null;
    final input = match.group(1)!;
    if (input.length < 2) return null;

    _refreshDocWordsIfStale();
    final lower = input.toLowerCase();
    final pool = <String>{
      ...?_languageSnippets[languageId],
      ..._docWords,
    };

    final prefixHits = <String>[];
    final containsHits = <String>[];
    for (final w in pool) {
      if (w == input) continue;
      final wl = w.toLowerCase();
      if (wl.startsWith(lower)) {
        prefixHits.add(w);
      } else if (wl.contains(lower)) {
        containsHits.add(w);
      }
    }
    prefixHits.sort((a, b) => a.length.compareTo(b.length));
    final suggestions = [...prefixHits, ...containsHits].take(10).toList(growable: false);
    if (suggestions.isEmpty) return null;

    return CodeAutocompleteEditingValue(
      input: input,
      prompts: [for (final s in suggestions) CodeKeywordPrompt(word: s)],
      index: 0,
    );
  }
}

/**
 * Compact dark-themed popup listing autocomplete suggestions under the cursor.
 */
class AutocompletePopup extends StatelessWidget implements PreferredSizeWidget {
  const AutocompletePopup({
    super.key,
    required this.notifier,
    required this.onSelected,
  });

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  static const _rowH = 26.0;
  static const _width = 240.0;

  @override
  Size get preferredSize {
    final count = notifier.value.prompts.length.clamp(1, 8);
    return Size(_width, count * _rowH + 8);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CodeAutocompleteEditingValue>(
      valueListenable: notifier,
      builder: (context, value, _) {
        final prompts = value.prompts;
        return Material(
          color: Tk.raised,
          elevation: 10,
          shadowColor: Colors.black,
          shape: const RoundedRectangleBorder(
            borderRadius: Tk.radius,
            side: BorderSide(color: Tk.borderStrong),
          ),
          child: SizedBox(
            width: _width,
            height: (prompts.length.clamp(1, 8)) * _rowH + 8,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemExtent: _rowH,
              itemCount: prompts.length,
              itemBuilder: (context, i) {
                final active = i == value.index;
                return GestureDetector(
                  onTap: () => onSelected(
                    CodeAutocompleteResult(
                      input: value.input,
                      word: prompts[i].word,
                      selection: TextSelection.collapsed(offset: prompts[i].word.length - value.input.length),
                    ),
                  ),
                  child: Container(
                    color: active ? Tk.listActive : Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      prompts[i].word,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Tk.code.copyWith(
                        fontSize: 12.5,
                        color: active ? Tk.textStrong : Tk.text,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
