import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import 'package:simple_ide/features/runner/languages.dart';

enum SaveState { saved, dirty, saving, failed }

/**
 * One open file: its buffer, its on-disk state, and the editor context
 * (scroll offsets) that should survive switching tabs.
 */
class EditorDocument extends ChangeNotifier {
  EditorDocument._(this.path, String text, this.lineEnding, {this.binary = false, this.readOnly = false})
      : _savedText = text {
    controller = CodeLineEditingController(
      codeLines: CodeLines.fromText(text),
      spanBuilder: ({required context, required index, required codeLine, required textSpan, required style}) =>
          decorateLine?.call(index, codeLine.text, textSpan, style) ?? textSpan,
    );
    _lastLines = controller.codeLines;
    controller.addListener(_onEdit);
  }

  /**
   * Optional hook that restyles one rendered line, e.g. to underline errors.
   * Receives the 0-based line index, its text, the highlighted span and the
   * base style.
   */
  TextSpan Function(int index, String text, TextSpan span, TextStyle style)? decorateLine;

  bool _disposed = false;

  /**
   * Forces the editor to rebuild its line spans, e.g. after problems change.
   */
  void repaintLines() {
    if (_disposed) return;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    controller.notifyListeners();
  }

  static const maxEditableBytes = 8 * 1024 * 1024;

  /**
   * Reads a file from disk. Binary and oversized files open read-only.
   *
   * @param path absolute path of the file
   * @return the loaded document
   * @throws FileSystemException when the file can't be read
   */
  static Future<EditorDocument> open(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final probe = bytes.length > 8000 ? bytes.sublist(0, 8000) : bytes;
    if (probe.contains(0)) {
      return EditorDocument._(path, '', '\n', binary: true, readOnly: true);
    }
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('ï»¿')) text = text.substring(1);
    final crlf = text.contains('\r\n');
    if (crlf) text = text.replaceAll('\r\n', '\n');
    return EditorDocument._(
      path,
      text,
      crlf ? '\r\n' : '\n',
      readOnly: bytes.length > maxEditableBytes,
    );
  }

  String path;
  late final CodeLineEditingController controller;
  final String lineEnding;
  final bool binary;
  final bool readOnly;

  String _savedText;
  SaveState _state = SaveState.saved;
  String? lastError;

  double scrollTop = 0;
  double scrollLeft = 0;

  String get name => p.basename(path);
  Language get language => languageFor(path);
  SaveState get state => _state;
  bool get isDirty => _dirty;
  bool _dirty = false;
  CodeLines? _lastLines;

  /**
   * Fires when the text (not just the selection) changes.
   */
  VoidCallback? onTextChanged;

  /**
   * Fires after the buffer was written to disk.
   */
  VoidCallback? onSaved;

  void _onEdit() {
    final lines = controller.codeLines;
    if (identical(lines, _lastLines)) return; // selection-only change
    _lastLines = lines;
    _dirty = controller.text != _savedText;
    onTextChanged?.call();
    final next = _dirty ? SaveState.dirty : SaveState.saved;
    if (_state == SaveState.saving) return;
    if (next != _state) {
      _state = next;
      notifyListeners();
    }
  }

  /**
   * Writes the buffer to disk if it differs from what was last saved.
   *
   * @param force write even when the text is unchanged
   * @return false when the write failed; the error is kept in [lastError]
   */
  Future<bool> save({bool force = false}) async {
    if (binary || readOnly) return true;
    final text = controller.text;
    if (!force && text == _savedText) return true;
    _state = SaveState.saving;
    notifyListeners();
    try {
      final out = lineEnding == '\n' ? text : text.replaceAll('\n', lineEnding);
      await File(path).writeAsString(out, flush: true);
      _savedText = text;
      lastError = null;
      _dirty = controller.text != _savedText;
      _state = _dirty ? SaveState.dirty : SaveState.saved;
      notifyListeners();
      onSaved?.call();
      return true;
    } catch (e) {
      lastError = e.toString();
      _state = SaveState.failed;
      notifyListeners();
      return false;
    }
  }

  /**
   * Picks up a change made outside the IDE, but only when the user has no
   * unsaved edits that would be overwritten.
   */
  Future<void> reloadIfClean() async {
    if (binary || _dirty) return;
    try {
      var text = await File(path).readAsString();
      text = text.replaceAll('\r\n', '\n');
      if (text.startsWith('ï»¿')) text = text.substring(1);
      if (text == _savedText) return;
      _savedText = text;
      final sel = controller.selection;
      controller.text = text;
      _dirty = false;
      final maxLine = controller.lineCount - 1;
      if (sel.extentIndex <= maxLine) {
        controller.selection = CodeLineSelection.collapsed(
          index: sel.extentIndex,
          offset: sel.extentOffset.clamp(0, controller.codeLines[sel.extentIndex].text.length),
        );
      }
      _state = SaveState.saved;
      notifyListeners();
    } catch (_) {
      // File may be mid-write by another program; the next event retries.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_onEdit);
    controller.dispose();
    super.dispose();
  }
}
