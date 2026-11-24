import 'dart:io';

import 'package:path/path.dart' as p;

/**
 * One changed file reported by `git status --porcelain`.
 */
class GitChange {
  const GitChange({
    required this.path,
    required this.relativePath,
    required this.indexStatus,
    required this.workTreeStatus,
  });

  final String path;
  final String relativePath;
  final String indexStatus;
  final String workTreeStatus;

  bool get staged => indexStatus != ' ' && indexStatus != '?';
  bool get untracked => indexStatus == '?' && workTreeStatus == '?';

  /** Single-letter badge shown beside the file in the Git panel. */
  String get code {
    if (untracked) return 'U';
    final s = workTreeStatus != ' ' ? workTreeStatus : indexStatus;
    return s;
  }
}

/**
 * Snapshot of a workspace's Git state.
 */
class GitStatus {
  const GitStatus({
    required this.gitAvailable,
    required this.isRepo,
    this.branch,
    this.remoteUrl,
    this.changes = const [],
    this.error,
  });

  final bool gitAvailable;
  final bool isRepo;
  final String? branch;
  final String? remoteUrl;
  final List<GitChange> changes;
  final String? error;
}

/**
 * Result of running a Git action (commit, push, pull, init).
 */
class GitResult {
  const GitResult({required this.ok, required this.message});
  final bool ok;
  final String message;
}

/**
 * Thin wrapper around the host's `git` CLI for the sidebar Source Control panel.
 */
class GitService {
  /**
   * Parses `git status --porcelain=v1` output relative to [repoRoot].
   *
   * @param output   stdout from `git status --porcelain`
   * @param repoRoot workspace root directory
   * @return parsed file changes
   */
  static List<GitChange> parseStatus(String output, String repoRoot) {
    final out = <GitChange>[];
    for (final raw in output.split(RegExp(r'\r?\n'))) {
      if (raw.length < 4) continue;
      final index = raw[0];
      final work = raw[1];
      var rel = raw.substring(3).trim();
      if (rel.startsWith('"') && rel.endsWith('"') && rel.length >= 2) {
        rel = rel.substring(1, rel.length - 1);
      }
      final arrow = rel.indexOf(' -> ');
      if (arrow >= 0) rel = rel.substring(arrow + 4);
      out.add(GitChange(
        path: p.normalize(p.join(repoRoot, rel)),
        relativePath: rel,
        indexStatus: index,
        workTreeStatus: work,
      ));
    }
    return out;
  }

  static Future<ProcessResult?> _run(List<String> args, String cwd) async {
    try {
      return await Process.run('git', args, workingDirectory: cwd, runInShell: Platform.isWindows)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      return null;
    }
  }

  /**
   * Inspects the repository state for [root].
   */
  static Future<GitStatus> inspect(String root) async {
    final ver = await _run(['--version'], root);
    if (ver == null || ver.exitCode != 0) {
      return const GitStatus(gitAvailable: false, isRepo: false);
    }
    final inside = await _run(['rev-parse', '--is-inside-work-tree'], root);
    if (inside == null || inside.exitCode != 0 || inside.stdout.toString().trim() != 'true') {
      return const GitStatus(gitAvailable: true, isRepo: false);
    }
    final branchRes = await _run(['rev-parse', '--abbrev-ref', 'HEAD'], root);
    final branch = branchRes != null && branchRes.exitCode == 0 ? branchRes.stdout.toString().trim() : 'HEAD';

    final remoteRes = await _run(['remote', 'get-url', 'origin'], root);
    final remote = remoteRes != null && remoteRes.exitCode == 0 ? remoteRes.stdout.toString().trim() : null;

    final statusRes = await _run(['status', '--porcelain'], root);
    if (statusRes == null || statusRes.exitCode != 0) {
      return GitStatus(
        gitAvailable: true,
        isRepo: true,
        branch: branch,
        remoteUrl: remote,
        error: statusRes?.stderr.toString().trim(),
      );
    }
    return GitStatus(
      gitAvailable: true,
      isRepo: true,
      branch: branch,
      remoteUrl: remote,
      changes: parseStatus(statusRes.stdout.toString(), root),
    );
  }

  static Future<GitResult> init(String root) => _execResult(['init'], root, okMsg: 'Initialized Git repository');

  static Future<GitResult> stage(String root, String path) => _execResult(['add', '--', path], root);

  static Future<GitResult> unstage(String root, String path) =>
      _execResult(['restore', '--staged', '--', path], root);

  static Future<GitResult> stageAll(String root) => _execResult(['add', '-A'], root);

  static Future<GitResult> commit(String root, String message, {bool stageAllIfNone = true}) async {
    if (stageAllIfNone) {
      final st = await inspect(root);
      if (st.changes.isNotEmpty && !st.changes.any((c) => c.staged)) {
        final addRes = await stageAll(root);
        if (!addRes.ok) return addRes;
      }
    }
    return _execResult(['commit', '-m', message], root, okMsg: 'Committed changes');
  }

  static Future<GitResult> push(String root) => _execResult(['push'], root, okMsg: 'Pushed to origin');

  static Future<GitResult> pull(String root) => _execResult(['pull'], root, okMsg: 'Pulled from origin');

  static Future<GitResult> setOrigin(String root, String url) async {
    final existing = await _run(['remote', 'get-url', 'origin'], root);
    final args = existing != null && existing.exitCode == 0
        ? ['remote', 'set-url', 'origin', url]
        : ['remote', 'add', 'origin', url];
    return _execResult(args, root, okMsg: 'Saved origin remote');
  }

  static Future<GitResult> _execResult(List<String> args, String root, {String okMsg = 'Done'}) async {
    final r = await _run(args, root);
    if (r == null) return const GitResult(ok: false, message: 'git timed out or failed to start');
    final out = '${r.stdout}\n${r.stderr}'.trim();
    if (r.exitCode == 0) return GitResult(ok: true, message: okMsg);
    return GitResult(ok: false, message: out.isEmpty ? 'git exited with code ${r.exitCode}' : out);
  }

  /**
   * Computes 1-based line change markers for [filePath] against `HEAD`.
   */
  static Future<Map<int, GitLineChange>> diffLines(String root, String filePath) async {
    final r = await _run(['diff', '--unified=0', '--no-color', 'HEAD', '--', filePath], root);
    if (r == null || r.exitCode != 0) return const {};
    return parseUnifiedDiffLines('${r.stdout}');
  }

  /**
   * Parses unified-0 `git diff` hunk headers (`@@ -a,b +c,d @@`) into a map
   * of 1-based line numbers to [GitLineChange].
   */
  static Map<int, GitLineChange> parseUnifiedDiffLines(String diffOutput) {
    final result = <int, GitLineChange>{};
    final hunkRe = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', multiLine: true);
    for (final m in hunkRe.allMatches(diffOutput)) {
      final oldCount = int.tryParse(m.group(2) ?? '1') ?? 1;
      final newStart = int.parse(m.group(3)!);
      final newCount = int.tryParse(m.group(4) ?? '1') ?? 1;

      if (oldCount == 0 && newCount > 0) {
        for (var i = 0; i < newCount; i++) {
          result[newStart + i] = GitLineChange.added;
        }
      } else if (newCount == 0 && oldCount > 0) {
        result[newStart > 0 ? newStart : 1] = GitLineChange.deleted;
      } else {
        final overlap = oldCount < newCount ? oldCount : newCount;
        for (var i = 0; i < overlap; i++) {
          result[newStart + i] = GitLineChange.modified;
        }
        for (var i = overlap; i < newCount; i++) {
          result[newStart + i] = GitLineChange.added;
        }
      }
    }
    return result;
  }
}

enum GitLineChange { added, modified, deleted }
