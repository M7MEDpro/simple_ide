import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class FsEntry {
  const FsEntry(this.path, this.isDir);
  final String path;
  final bool isDir;
  String get name => p.basename(path);
  bool get hidden => name.startsWith('.');
}

/**
 * A flattened, visible row of the explorer tree.
 */
class TreeRow {
  const TreeRow(this.entry, this.depth, this.expanded);
  final FsEntry entry;
  final int depth;
  final bool expanded;
}

/**
 * The open project folder: lazily-listed directory tree plus a recursive
 * file-system watcher that keeps it current.
 */
class Workspace extends ChangeNotifier {
  Workspace(this.root) {
    expanded.add(root);
    _watch();
  }

  final String root;
  final Set<String> expanded = {};
  final Map<String, List<FsEntry>> _cache = {};
  StreamSubscription<FileSystemEvent>? _watcher;
  Timer? _debounce;
  final Set<String> _dirtyDirs = {};

  /**
   * Called with paths whose content changed on disk.
   */
  void Function(Set<String> paths)? onFilesChanged;

  static const ignoredDirs = {'.git', '.dart_tool', 'node_modules', '__pycache__', '.idea', '.vs', 'build', 'target', '.venv', 'venv'};

  String get name => p.basename(root);

  List<FsEntry> children(String dir) => _cache[dir] ??= _list(dir);

  static List<FsEntry> _list(String dir) {
    try {
      final items = Directory(dir)
          .listSync(followLinks: false)
          .map((e) => FsEntry(e.path, e is Directory))
          .toList()
        ..sort((a, b) {
          if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      return items;
    } catch (_) {
      return const [];
    }
  }

  List<TreeRow> visibleRows() {
    final rows = <TreeRow>[];
    void walk(String dir, int depth) {
      for (final e in children(dir)) {
        final open = e.isDir && expanded.contains(e.path);
        rows.add(TreeRow(e, depth, open));
        if (open) walk(e.path, depth + 1);
      }
    }

    walk(root, 0);
    return rows;
  }

  void toggle(String dir) {
    if (!expanded.remove(dir)) expanded.add(dir);
    notifyListeners();
  }

  void collapseAll() {
    expanded
      ..clear()
      ..add(root);
    notifyListeners();
  }

  /**
   * Expands every ancestor of [path] so it becomes visible.
   */
  void reveal(String path) {
    var dir = p.dirname(path);
    while (p.isWithin(root, dir) || p.equals(root, dir)) {
      expanded.add(dir);
      if (p.equals(root, dir)) break;
      dir = p.dirname(dir);
    }
    notifyListeners();
  }

  void refresh([String? dir]) {
    if (dir == null) {
      _cache.clear();
    } else {
      _cache.remove(dir);
    }
    notifyListeners();
  }

  /**
   * All files below the root, for quick-open. Skips tooling folders.
   */
  List<String> allFiles({int limit = 10000}) {
    final out = <String>[];
    void walk(String dir) {
      if (out.length >= limit) return;
      for (final e in _list(dir)) {
        if (out.length >= limit) return;
        if (e.isDir) {
          if (!ignoredDirs.contains(e.name) && e.name != 'build') walk(e.path);
        } else {
          out.add(e.path);
        }
      }
    }

    walk(root);
    return out;
  }

  // --- File operations -----------------------------------------------------

  Future<String> createFile(String dir, String name) async {
    final path = p.join(dir, name);
    if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
      throw FileSystemException('A file or folder with that name already exists', path);
    }
    await File(path).create(recursive: true);
    expanded.add(dir);
    refresh(dir);
    return path;
  }

  Future<String> createFolder(String dir, String name) async {
    final path = p.join(dir, name);
    if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
      throw FileSystemException('A file or folder with that name already exists', path);
    }
    await Directory(path).create(recursive: true);
    expanded.add(dir);
    refresh(dir);
    return path;
  }

  Future<String> rename(FsEntry e, String newName) async {
    final target = p.join(p.dirname(e.path), newName);
    if (p.equals(target, e.path)) return target;
    final caseOnly = target.toLowerCase() == e.path.toLowerCase();
    if (!caseOnly && await FileSystemEntity.type(target) != FileSystemEntityType.notFound) {
      throw FileSystemException('A file or folder with that name already exists', target);
    }
    if (e.isDir) {
      await Directory(e.path).rename(target);
      if (expanded.remove(e.path)) expanded.add(target);
    } else {
      await File(e.path).rename(target);
    }
    refresh(p.dirname(e.path));
    return target;
  }

  Future<void> delete(FsEntry e) async {
    if (e.isDir) {
      await Directory(e.path).delete(recursive: true);
      expanded.removeWhere((d) => d == e.path || p.isWithin(e.path, d));
    } else {
      await File(e.path).delete();
    }
    refresh(p.dirname(e.path));
  }

  // --- Watching ------------------------------------------------------------

  void _watch() {
    try {
      _watcher = Directory(root).watch(recursive: true).listen(_onEvent, onError: (_) {});
    } catch (_) {
      // Some network drives can't be watched; manual refresh still works.
    }
  }

  final Set<String> _changedFiles = {};

  void _onEvent(FileSystemEvent e) {
    final parts = p.split(p.relative(e.path, from: root));
    if (parts.any(ignoredDirs.contains)) return;
    if (e is FileSystemModifyEvent) {
      _changedFiles.add(e.path);
    } else {
      _dirtyDirs.add(p.dirname(e.path));
      if (e is FileSystemMoveEvent && e.destination != null) {
        _dirtyDirs.add(p.dirname(e.destination!));
      }
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _flush);
  }

  void _flush() {
    if (_dirtyDirs.isNotEmpty) {
      for (final d in _dirtyDirs) {
        _cache.remove(d);
      }
      _dirtyDirs.clear();
      notifyListeners();
    }
    if (_changedFiles.isNotEmpty) {
      final changed = Set<String>.of(_changedFiles);
      _changedFiles.clear();
      onFilesChanged?.call(changed);
    }
  }

  @override
  void dispose() {
    _watcher?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
