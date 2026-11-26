import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/**
 * Single match inside a file returned by [searchInProject].
 */
class SearchMatch {
  const SearchMatch({
    required this.path,
    required this.line,
    required this.column,
    required this.lineText,
    required this.matchStart,
    required this.matchLength,
  });

  final String path;
  final int line;
  final int column;
  final String lineText;
  final int matchStart;
  final int matchLength;
}

/**
 * All matches within a single file.
 */
class FileSearchGroup {
  const FileSearchGroup({required this.path, required this.matches});

  final String path;
  final List<SearchMatch> matches;
}

/**
 * Scans [files] in the workspace for [query], skipping binary or oversized
 * files (> 1 MB). Stops after [maxMatches] total hits to keep searches fast.
 */
Future<List<FileSearchGroup>> searchInProject(
  List<String> files,
  String query, {
  bool caseSensitive = false,
  int maxMatches = 500,
}) async {
  if (query.isEmpty) return const [];
  final needle = caseSensitive ? query : query.toLowerCase();
  final groups = <FileSearchGroup>[];
  var total = 0;

  for (final path in files) {
    if (total >= maxMatches) break;
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final stat = await file.stat();
      if (stat.size > 1024 * 1024) continue;
      final bytes = await file.readAsBytes();
      final probeLen = bytes.length < 1024 ? bytes.length : 1024;
      var binary = false;
      for (var i = 0; i < probeLen; i++) {
        if (bytes[i] == 0) {
          binary = true;
          break;
        }
      }
      if (binary) continue;

      final text = utf8.decode(bytes, allowMalformed: true);
      final lines = text.split('\n');
      final matches = <SearchMatch>[];

      for (var i = 0; i < lines.length && total < maxMatches; i++) {
        final rawLine = lines[i].endsWith('\r') ? lines[i].substring(0, lines[i].length - 1) : lines[i];
        final hay = caseSensitive ? rawLine : rawLine.toLowerCase();
        var start = 0;
        while (total < maxMatches) {
          final idx = hay.indexOf(needle, start);
          if (idx < 0) break;
          matches.add(
            SearchMatch(
              path: path,
              line: i + 1,
              column: idx + 1,
              lineText: rawLine,
              matchStart: idx,
              matchLength: query.length,
            ),
          );
          total++;
          start = idx + needle.length;
        }
      }

      if (matches.isNotEmpty) {
        groups.add(FileSearchGroup(path: path, matches: matches));
      }
    } catch (_) {
      // Unreadable files are skipped silently.
    }
  }
  return groups;
}

/**
 * Replaces all occurrences of [query] with [replacement] across the matched
 * files and invokes [onFileUpdated] for each modified path.
 *
 * @return total number of replacements written
 */
Future<int> replaceInFiles(
  List<FileSearchGroup> groups,
  String query,
  String replacement, {
  bool caseSensitive = false,
  Future<void> Function(String path)? onFileUpdated,
}) async {
  if (query.isEmpty) return 0;
  final pattern = RegExp(RegExp.escape(query), caseSensitive: caseSensitive);
  var count = 0;

  for (final group in groups) {
    final file = File(group.path);
    if (!file.existsSync()) continue;
    try {
      final text = await file.readAsString();
      var localCount = 0;
      final updated = text.replaceAllMapped(pattern, (_) {
        localCount++;
        return replacement;
      });
      if (localCount > 0) {
        await file.writeAsString(updated);
        count += localCount;
        if (onFileUpdated != null) await onFileUpdated(group.path);
      }
    } catch (_) {}
  }
  return count;
}

/**
 * Formats a file path relative to [root] with forward slashes for display.
 */
String relativeDisplayPath(String root, String filePath) {
  return p.relative(filePath, from: root).replaceAll('\\', '/');
}
