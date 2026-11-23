import 'dart:io';

import 'package:simple_ide/features/settings/settings.dart';

/**
 * A host compiler or interpreter SimpleIDE can delegate to.
 */
class Toolchain {
  Toolchain(this.name, this.command, this.versionArgs, this.languages);
  final String name;
  final String command;
  final List<String> versionArgs;
  final String languages;
  String? version;
  bool? found;
}

List<Toolchain> knownToolchains() => [
      Toolchain('GCC', 'gcc', ['--version'], 'C'),
      Toolchain('G++', 'g++', ['--version'], 'C++'),
      Toolchain('Python', 'python', ['--version'], 'Python'),
      Toolchain('Java', 'java', ['--version'], 'Java'),
      Toolchain('Node.js', 'node', ['--version'], 'JavaScript'),
      Toolchain('Dart', 'dart', ['--version'], 'Dart'),
      Toolchain('Go', 'go', ['version'], 'Go'),
      Toolchain('Rust', 'rustc', ['--version'], 'Rust'),
    ];

/**
 * Probes each tool by running its version flag. Missing tools resolve
 * with `found == false` rather than throwing.
 */
Future<List<Toolchain>> detectToolchains({List<String> extraPath = const []}) async {
  final tools = knownToolchains();
  final env = extraPath.isEmpty ? null : {'PATH': Settings.buildPath(extraPath)};
  await Future.wait(tools.map((t) async {
    try {
      final r = await Process.run(t.command, t.versionArgs, environment: env, runInShell: Platform.isWindows)
          .timeout(const Duration(seconds: 6));
      final out = '${r.stdout}\n${r.stderr}'.trim();
      t.found = r.exitCode == 0 && out.isNotEmpty && !out.contains('is not recognized');
      if (t.found!) {
        final first = out.split(RegExp(r'[\r\n]+')).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
        final m = RegExp(r'\d+\.\d+(\.\d+)?').firstMatch(first);
        t.version = m?.group(0) ?? first;
      }
    } catch (_) {
      t.found = false;
    }
  }));
  return tools;
}
