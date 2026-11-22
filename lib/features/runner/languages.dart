import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';
import 'package:re_highlight/re_highlight.dart';

/**
 * Everything SimpleIDE knows about a language: how to colour it, how to
 * comment it, and which ready-made host tool runs it.
 */
class Language {
  const Language({
    required this.id,
    required this.name,
    required this.badge,
    required this.badgeColor,
    this.mode,
    this.lineComment,
    this.blockComment,
    this.build,
    this.run,
  });

  final String id;
  final String name;

  /**
   * Short glyph shown in the explorer and tabs.
   */
  final String badge;
  final Color badgeColor;
  final Mode? mode;
  final String? lineComment;
  final (String, String)? blockComment;

  /**
   * Optional compile step. Placeholders: see [expandTemplate].
   */
  final String? build;

  /**
   * Command that runs the program. Null means the file isn't runnable.
   */
  final String? run;

  bool get runnable => run != null;
}

const _plain = Language(
  id: 'plaintext',
  name: 'Plain Text',
  badge: 'TXT',
  badgeColor: Color(0xFF7B8392),
);

final Map<String, Language> _byExtension = () {
  final c = Language(
    id: 'c',
    name: 'C',
    badge: 'C',
    badgeColor: const Color(0xFF7FA6F5),
    mode: langC,
    lineComment: '//',
    blockComment: ('/*', '*/'),
    build: 'gcc -O0 -pipe "\${file}" "\${stdioHelper}" -o "\${out}" -Wall',
    run: '"\${out}"',
  );
  final cpp = Language(
    id: 'cpp',
    name: 'C++',
    badge: 'C++',
    badgeColor: const Color(0xFF6E8FE0),
    mode: langCpp,
    lineComment: '//',
    blockComment: ('/*', '*/'),
    build: 'g++ -std=c++17 -O0 -pipe "\${file}" "\${stdioHelper}" -o "\${out}" -Wall',
    run: '"\${out}"',
  );
  final py = Language(
    id: 'python',
    name: 'Python',
    badge: 'PY',
    badgeColor: const Color(0xFFE6D38A),
    mode: langPython,
    lineComment: '#',
    run: 'python -u "\${file}"',
  );
  final java = Language(
    id: 'java',
    name: 'Java',
    badge: 'JV',
    badgeColor: const Color(0xFFE0A271),
    mode: langJava,
    lineComment: '//',
    blockComment: ('/*', '*/'),
    run: 'java "\${file}"',
  );
  final js = Language(
    id: 'javascript',
    name: 'JavaScript',
    badge: 'JS',
    badgeColor: const Color(0xFFE6D38A),
    mode: langJavascript,
    lineComment: '//',
    blockComment: ('/*', '*/'),
    run: 'node "\${file}"',
  );
  final ts = Language(
    id: 'typescript',
    name: 'TypeScript',
    badge: 'TS',
    badgeColor: const Color(0xFF7FA6F5),
    mode: langTypescript,
    lineComment: '//',
    blockComment: ('/*', '*/'),
    run: 'npx --yes tsx "\${file}"',
  );
  final dart = Language(
    id: 'dart',
    name: 'Dart',
    badge: 'DT',
    badgeColor: const Color(0xFF6FC3C0),
    mode: langDart,
    lineComment: '//',
    blockComment: ('/*', '*/'),
    run: 'dart run "\${file}"',
  );
  final go = Language(
    id: 'go',
    name: 'Go',
    badge: 'GO',
    badgeColor: const Color(0xFF7DCFE0),
    mode: langGo,
    lineComment: '//',
    blockComment: ('/*', '*/'),
    run: 'go run "\${file}"',
  );
  final rust = Language(
    id: 'rust',
    name: 'Rust',
    badge: 'RS',
    badgeColor: const Color(0xFFD4A3A3),
    mode: langRust,
    lineComment: '//',
    blockComment: ('/*', '*/'),
    build: 'rustc "\${file}" -o "\${out}"',
    run: '"\${out}"',
  );
  final cs = Language(
    id: 'csharp',
    name: 'C#',
    badge: 'C#',
    badgeColor: const Color(0xFFC792C9),
    mode: langCsharp,
    lineComment: '//',
    blockComment: ('/*', '*/'),
  );
  final kt = Language(
    id: 'kotlin',
    name: 'Kotlin',
    badge: 'KT',
    badgeColor: const Color(0xFFC792C9),
    mode: langKotlin,
    lineComment: '//',
    blockComment: ('/*', '*/'),
  );
  final bat = Language(
    id: 'bat',
    name: 'Batch',
    badge: 'BAT',
    badgeColor: const Color(0xFF9CC995),
    mode: langBash,
    lineComment: 'REM',
    run: 'cmd /c "\${file}"',
  );
  final ps = Language(
    id: 'powershell',
    name: 'PowerShell',
    badge: 'PS',
    badgeColor: const Color(0xFF7FA6F5),
    mode: langBash,
    lineComment: '#',
    run: 'powershell -NoProfile -ExecutionPolicy Bypass -File "\${file}"',
  );
  final sh = Language(
    id: 'shell',
    name: 'Shell',
    badge: 'SH',
    badgeColor: const Color(0xFF9CC995),
    mode: langBash,
    lineComment: '#',
    run: 'bash "\${file}"',
  );
  final jsonL = Language(
    id: 'json',
    name: 'JSON',
    badge: '{}',
    badgeColor: const Color(0xFFE6D38A),
    mode: langJson,
  );
  final md = Language(
    id: 'markdown',
    name: 'Markdown',
    badge: 'MD',
    badgeColor: const Color(0xFF7DCFE0),
    mode: langMarkdown,
  );
  final xml = Language(
    id: 'xml',
    name: 'XML',
    badge: '<>',
    badgeColor: const Color(0xFFE0A271),
    mode: langXml,
    blockComment: ('<!--', '-->'),
  );
  final html = Language(
    id: 'html',
    name: 'HTML',
    badge: '<>',
    badgeColor: const Color(0xFFE5686B),
    mode: langXml,
    blockComment: ('<!--', '-->'),
  );
  final css = Language(
    id: 'css',
    name: 'CSS',
    badge: '#',
    badgeColor: const Color(0xFF7FA6F5),
    mode: langCss,
    blockComment: ('/*', '*/'),
  );
  final yaml = Language(
    id: 'yaml',
    name: 'YAML',
    badge: 'YML',
    badgeColor: const Color(0xFFD4A3A3),
    mode: langYaml,
    lineComment: '#',
  );
  return {
    '.c': c,
    '.h': c,
    '.cpp': cpp,
    '.cc': cpp,
    '.cxx': cpp,
    '.hpp': cpp,
    '.hh': cpp,
    '.py': py,
    '.pyw': py,
    '.java': java,
    '.js': js,
    '.mjs': js,
    '.cjs': js,
    '.ts': ts,
    '.dart': dart,
    '.go': go,
    '.rs': rust,
    '.cs': cs,
    '.kt': kt,
    '.bat': bat,
    '.cmd': bat,
    '.ps1': ps,
    '.sh': sh,
    '.json': jsonL,
    '.md': md,
    '.xml': xml,
    '.html': html,
    '.htm': html,
    '.css': css,
    '.yaml': yaml,
    '.yml': yaml,
  };
}();

Language languageFor(String path) =>
    _byExtension[p.extension(path).toLowerCase()] ?? _plain;

/**
 * All modes, keyed by language id, for the highlighter.
 */
Map<String, Mode> get highlightModes => {
      for (final l in _byExtension.values)
        if (l.mode != null) l.id: l.mode!,
    };

/**
 * Replaces `${name}` placeholders in a command template.
 *
 * @param template command text containing placeholders
 * @param vars     placeholder values by name
 * @return the expanded command; unknown placeholders are left as they are
 */
String expandTemplate(String template, Map<String, String> vars) =>
    template.replaceAllMapped(RegExp(r'\$\{(\w+)\}'), (m) => vars[m[1]] ?? m[0]!);

/**
 * Splits a command line into program + arguments, honouring double quotes.
 * Quotes group characters and are removed; there are no escape sequences,
 * so Windows paths with backslashes pass through untouched.
 *
 * @param line the full command line
 * @return the program followed by its arguments
 */
List<String> splitCommandLine(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  var hasToken = false;
  for (final ch in line.runes.map(String.fromCharCode)) {
    if (ch == '"') {
      inQuotes = !inQuotes;
      hasToken = true;
    } else if (!inQuotes && (ch == ' ' || ch == '\t')) {
      if (hasToken) {
        out.add(buf.toString());
        buf.clear();
        hasToken = false;
      }
    } else {
      buf.write(ch);
      hasToken = true;
    }
  }
  if (hasToken) out.add(buf.toString());
  return out;
}
