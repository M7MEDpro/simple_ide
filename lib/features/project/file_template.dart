import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:simple_ide/features/runner/languages.dart';

/**
 * Template kind shown in the New File popup.
 */
class NewFileKind {
  const NewFileKind({
    required this.id,
    required this.label,
    required this.badgePath,
    this.langId,
    this.supportsNamespace = false,
    this.isCppClass = false,
  });

  final String id;
  final String label;
  final String badgePath;
  final String? langId;
  final bool supportsNamespace;
  final bool isCppClass;
}

const List<NewFileKind> allNewFileKinds = [
  NewFileKind(id: 'cpp_class', label: 'C++ Class', badgePath: 'x.cpp', langId: 'cpp', supportsNamespace: true, isCppClass: true),
  NewFileKind(id: 'cpp_header', label: 'C++ Header', badgePath: 'x.hpp', langId: 'cpp', supportsNamespace: true),
  NewFileKind(id: 'cpp_source', label: 'C++ Source', badgePath: 'x.cpp', langId: 'cpp', supportsNamespace: true),
  NewFileKind(id: 'cpp_namespace', label: 'C++ Namespace', badgePath: 'x.hpp', langId: 'cpp', supportsNamespace: true),
  NewFileKind(id: 'c_source', label: 'C Source', badgePath: 'x.c', langId: 'c'),
  NewFileKind(id: 'c_header', label: 'C Header', badgePath: 'x.h', langId: 'c'),
  NewFileKind(id: 'py_file', label: 'Python File', badgePath: 'x.py', langId: 'python'),
  NewFileKind(id: 'py_pkg', label: 'Python Package', badgePath: 'x.py', langId: 'python'),
  NewFileKind(id: 'java_class', label: 'Java Class', badgePath: 'x.java', langId: 'java'),
  NewFileKind(id: 'java_interface', label: 'Java Interface', badgePath: 'x.java', langId: 'java'),
  NewFileKind(id: 'java_enum', label: 'Java Enum', badgePath: 'x.java', langId: 'java'),
  NewFileKind(id: 'js_file', label: 'JavaScript File', badgePath: 'x.js', langId: 'javascript'),
  NewFileKind(id: 'dart_file', label: 'Dart File', badgePath: 'x.dart', langId: 'dart'),
  NewFileKind(id: 'dart_class', label: 'Dart Class', badgePath: 'x.dart', langId: 'dart'),
  NewFileKind(id: 'go_file', label: 'Go File', badgePath: 'x.go', langId: 'go'),
  NewFileKind(id: 'rust_mod', label: 'Rust File', badgePath: 'x.rs', langId: 'rust'),
  NewFileKind(id: 'empty', label: 'Empty File', badgePath: 'x.txt'),
];

/**
 * Infers the dominant language id for a workspace/directory from its files
 * and the currently active document.
 */
String? detectProjectLanguage(String dir, {String? activeFilePath, List<String> workspaceFiles = const []}) {
  if (activeFilePath != null) {
    final lang = languageFor(activeFilePath);
    if (lang.id != 'plaintext') return lang.id;
  }
  final counts = <String, int>{};
  final candidates = workspaceFiles.isNotEmpty
      ? workspaceFiles
      : (Directory(dir).existsSync()
          ? Directory(dir).listSync(followLinks: false).whereType<File>().map((f) => f.path).toList()
          : const <String>[]);
  for (final f in candidates.take(200)) {
    final id = languageFor(f).id;
    if (id != 'plaintext') counts[id] = (counts[id] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
}

/**
 * Orders [allNewFileKinds] so templates for [projectLangId] appear first.
 */
List<NewFileKind> orderedKindsFor(String? projectLangId) {
  if (projectLangId == null) return allNewFileKinds;
  final primary = allNewFileKinds.where((k) => k.langId == projectLangId);
  final empty = allNewFileKinds.where((k) => k.id == 'empty');
  final rest = allNewFileKinds.where((k) => k.langId != projectLangId && k.id != 'empty');
  return [...primary, ...empty, ...rest];
}

/**
 * Computes the relative file paths and contents to generate for [kind].
 *
 * @param kind          chosen template kind
 * @param rawName       name entered by the user
 * @param namespace     optional C++ namespace (e.g. `app::core`)
 * @param headerExt     `.h` or `.hpp` for C++ class/header
 * @param createPair    whether `C++ Class` also creates a `.cpp` file
 * @return list of `(relativePath, content)` pairs; first item is opened in editor
 */
List<({String relPath, String content})> planNewFiles({
  required NewFileKind kind,
  required String rawName,
  String namespace = '',
  String headerExt = '.h',
  bool createPair = true,
}) {
  final name = rawName.trim();
  final base = p.basenameWithoutExtension(name);
  final ns = namespace.trim();

  String wrapNs(String body) {
    if (ns.isEmpty) return body;
    return 'namespace $ns {\n\n$body\n} // namespace $ns\n';
  }

  switch (kind.id) {
    case 'cpp_class':
      final hName = '$base$headerExt';
      final hBody = wrapNs(
        'class $base {\n'
        'public:\n'
        '    $base();\n'
        '    ~$base();\n'
        '};\n',
      );
      final header = '#pragma once\n\n$hBody';
      if (!createPair) return [(relPath: hName, content: header)];
      final cppName = '$base.cpp';
      final cppBody = wrapNs(
        '$base::$base() = default;\n\n'
        '$base::~$base() = default;\n',
      );
      final cpp = '#include "$hName"\n\n$cppBody';
      return [(relPath: hName, content: header), (relPath: cppName, content: cpp)];

    case 'cpp_header':
      final hName = p.extension(name).isEmpty ? '$name$headerExt' : name;
      final body = ns.isEmpty ? '// TODO: declarations\n' : wrapNs('// TODO: declarations\n');
      return [(relPath: hName, content: '#pragma once\n\n$body')];

    case 'cpp_source':
      final cppName = p.extension(name).isEmpty ? '$name.cpp' : name;
      final body = ns.isEmpty ? '' : wrapNs('');
      return [(relPath: cppName, content: body)];

    case 'cpp_namespace':
      final hName = p.extension(name).isEmpty ? '$name$headerExt' : name;
      final targetNs = ns.isEmpty ? base : ns;
      return [
        (
          relPath: hName,
          content: '#pragma once\n\nnamespace $targetNs {\n\n// TODO: declarations\n\n} // namespace $targetNs\n',
        ),
      ];

    case 'c_source':
      final cName = p.extension(name).isEmpty ? '$name.c' : name;
      return [(relPath: cName, content: '#include <stdio.h>\n')];

    case 'c_header':
      final hName = p.extension(name).isEmpty ? '$name.h' : name;
      final guard = '${base.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_')}_H';
      return [
        (
          relPath: hName,
          content: '#ifndef $guard\n#define $guard\n\n#endif // $guard\n',
        ),
      ];

    case 'py_file':
      final pyName = p.extension(name).isEmpty ? '$name.py' : name;
      return [(relPath: pyName, content: '')];

    case 'py_pkg':
      return [(relPath: p.join(base, '__init__.py'), content: '')];

    case 'java_class':
      final jName = p.extension(name).isEmpty ? '$name.java' : name;
      return [(relPath: jName, content: 'public class $base {\n    \n}\n')];

    case 'java_interface':
      final jName = p.extension(name).isEmpty ? '$name.java' : name;
      return [(relPath: jName, content: 'public interface $base {\n    \n}\n')];

    case 'java_enum':
      final jName = p.extension(name).isEmpty ? '$name.java' : name;
      return [(relPath: jName, content: 'public enum $base {\n    \n}\n')];

    case 'js_file':
      final jsName = p.extension(name).isEmpty ? '$name.js' : name;
      return [(relPath: jsName, content: '')];

    case 'dart_file':
      final dName = p.extension(name).isEmpty ? '$name.dart' : name;
      return [(relPath: dName, content: '')];

    case 'dart_class':
      final dName = p.extension(name).isEmpty ? '${base.toLowerCase()}.dart' : name;
      return [(relPath: dName, content: 'class $base {\n  \n}\n')];

    case 'go_file':
      final goName = p.extension(name).isEmpty ? '$name.go' : name;
      return [(relPath: goName, content: 'package main\n')];

    case 'rust_mod':
      final rsName = p.extension(name).isEmpty ? '$name.rs' : name;
      return [(relPath: rsName, content: '')];

    default:
      return [(relPath: name, content: '')];
  }
}
