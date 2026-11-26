import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/**
 * Per-project run and build configuration persisted in `.simple_ide.json`
 * at the workspace root.
 */
class ProjectRunConfig {
  const ProjectRunConfig({
    this.runCommand,
    this.buildCommand,
    this.cwd,
    this.env = const {},
  });

  static const String fileName = '.simple_ide.json';

  final String? runCommand;
  final String? buildCommand;
  final String? cwd;
  final Map<String, String> env;

  bool get isEmpty =>
      (runCommand == null || runCommand!.trim().isEmpty) &&
      (buildCommand == null || buildCommand!.trim().isEmpty) &&
      (cwd == null || cwd!.trim().isEmpty) &&
      env.isEmpty;

  String resolveCwd(String root) {
    final c = cwd?.trim();
    if (c == null || c.isEmpty) return root;
    return p.isAbsolute(c) ? p.normalize(c) : p.normalize(p.join(root, c));
  }

  static ProjectRunConfig load(String root) {
    final file = File(p.join(root, fileName));
    if (!file.existsSync()) return const ProjectRunConfig();
    try {
      final raw = jsonDecode(file.readAsStringSync());
      if (raw is! Map<String, dynamic>) return const ProjectRunConfig();
      final envMap = <String, String>{};
      if (raw['env'] is Map) {
        for (final entry in (raw['env'] as Map).entries) {
          final k = entry.key.toString().trim();
          if (k.isNotEmpty) envMap[k] = entry.value?.toString() ?? '';
        }
      }
      String? clean(dynamic v) {
        final s = v?.toString().trim();
        return (s == null || s.isEmpty) ? null : s;
      }

      return ProjectRunConfig(
        runCommand: clean(raw['runCommand']),
        buildCommand: clean(raw['buildCommand']),
        cwd: clean(raw['cwd']),
        env: envMap,
      );
    } catch (_) {
      return const ProjectRunConfig();
    }
  }

  Future<void> save(String root) async {
    final file = File(p.join(root, fileName));
    if (isEmpty) {
      if (file.existsSync()) await file.delete();
      return;
    }
    final data = <String, dynamic>{
      if (runCommand != null && runCommand!.trim().isNotEmpty) 'runCommand': runCommand!.trim(),
      if (buildCommand != null && buildCommand!.trim().isNotEmpty) 'buildCommand': buildCommand!.trim(),
      if (cwd != null && cwd!.trim().isNotEmpty) 'cwd': cwd!.trim(),
      if (env.isNotEmpty) 'env': env,
    };
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(data)}\n');
  }
}
