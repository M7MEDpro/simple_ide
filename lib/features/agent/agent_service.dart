import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:simple_ide/features/runner/languages.dart';

/**
 * Supported external AI coding CLI preset.
 */
class AgentPreset {
  const AgentPreset({
    required this.id,
    required this.name,
    required this.command,
    required this.argsTemplate,
  });

  final String id;
  final String name;
  final String command;
  final List<String> argsTemplate;
}

const List<AgentPreset> agentPresets = [
  AgentPreset(id: 'claude', name: 'Claude Code', command: 'claude', argsTemplate: ['-p', r'${prompt}']),
  AgentPreset(id: 'gemini', name: 'Gemini CLI', command: 'gemini', argsTemplate: ['-p', r'${prompt}']),
  AgentPreset(id: 'codex', name: 'Codex CLI', command: 'codex', argsTemplate: ['exec', r'${prompt}']),
  AgentPreset(id: 'aider', name: 'Aider', command: 'aider', argsTemplate: ['--message', r'${prompt}', '--yes-always']),
  AgentPreset(id: 'custom', name: 'Custom CLI', command: '', argsTemplate: []),
];

enum ChatRole { user, assistant, system }

/**
 * One message bubble in the Agent CLI side chat.
 */
class AgentMessage {
  AgentMessage({required this.role, required this.text, this.streaming = false});
  final ChatRole role;
  String text;
  bool streaming;
}

/**
 * Detects installed AI CLI tools and runs prompts against them in the
 * workspace directory, streaming output into [messages].
 */
class AgentController extends ChangeNotifier {
  final List<AgentMessage> messages = [];
  final Set<String> availableIds = {};
  String selectedId = 'claude';
  String customTemplate = r'ollama run llama3 "${prompt}"';
  bool busy = false;
  bool checked = false;
  bool _disposed = false;
  Process? _proc;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  AgentPreset get currentPreset =>
      agentPresets.firstWhere((a) => a.id == selectedId, orElse: () => agentPresets.first);

  /**
   * Probes PATH for known agent CLIs and picks the first available one.
   */
  Future<void> detectAgents({Map<String, String> extraEnv = const {}}) async {
    availableIds.clear();
    final env = extraEnv.isEmpty ? null : extraEnv;
    await Future.wait(
      agentPresets.where((a) => a.command.isNotEmpty).map((a) async {
        try {
          final r = await Process.run(
            Platform.isWindows ? 'where' : 'which',
            [a.command],
            environment: env,
            runInShell: Platform.isWindows,
          ).timeout(const Duration(seconds: 4));
          if (r.exitCode == 0) availableIds.add(a.id);
        } catch (_) {}
      }),
    );
    if (!availableIds.contains(selectedId) && availableIds.isNotEmpty) {
      selectedId = availableIds.first;
    }
    checked = true;
    _notify();
  }

  void selectAgent(String id) {
    selectedId = id;
    notifyListeners();
  }

  void setCustomTemplate(String template) {
    customTemplate = template;
    notifyListeners();
  }

  void clear() {
    messages.clear();
    notifyListeners();
  }

  /**
   * Builds the `(executable, arguments)` pair for [prompt].
   */
  List<String> buildCommand(String prompt) {
    if (selectedId == 'custom') {
      final raw = customTemplate.trim();
      if (raw.isEmpty) return const [];
      if (raw.contains(r'${prompt}')) {
        return splitCommandLine(raw.replaceAll(r'${prompt}', prompt));
      }
      return [...splitCommandLine(raw), prompt];
    }
    final preset = currentPreset;
    return [
      preset.command,
      for (final arg in preset.argsTemplate) arg.replaceAll(r'${prompt}', prompt),
    ];
  }

  /**
   * Sends [prompt] to the selected agent CLI inside [cwd] and streams its output.
   */
  Future<void> send(String prompt, {required String cwd, Map<String, String> extraEnv = const {}}) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty || busy) return;

    final argv = buildCommand(trimmed);
    if (argv.isEmpty) {
      messages.add(AgentMessage(role: ChatRole.system, text: 'Enter a custom CLI command first.'));
      notifyListeners();
      return;
    }

    messages.add(AgentMessage(role: ChatRole.user, text: trimmed));
    final reply = AgentMessage(role: ChatRole.assistant, text: '', streaming: true);
    messages.add(reply);
    if (messages.length > 100) messages.removeRange(0, messages.length - 100);
    busy = true;
    notifyListeners();

    try {
      final proc = await Process.start(
        argv.first,
        argv.sublist(1),
        workingDirectory: cwd,
        environment: extraEnv.isEmpty ? null : extraEnv,
        runInShell: Platform.isWindows,
      );
      _proc = proc;

      void append(String chunk) {
        if (reply.text.length >= 65536) return;
        reply.text += chunk;
        notifyListeners();
      }

      final out = proc.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(append);
      final err = proc.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(append);
      final code = await proc.exitCode;
      await Future.wait([out.asFuture<void>(), err.asFuture<void>()]).timeout(
        const Duration(seconds: 2),
        onTimeout: () => const [],
      );
      if (reply.text.trim().isEmpty) {
        reply.text = code == 0 ? '(No output)' : 'Exited with code $code.';
      }
    } catch (e) {
      reply.text = "Couldn't run \"${argv.first}\": $e";
    } finally {
      reply.streaming = false;
      _proc = null;
      busy = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final proc = _proc;
    if (proc == null) return;
    if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '${proc.pid}', '/T', '/F']);
    } else {
      proc.kill(ProcessSignal.sigkill);
    }
    _proc = null;
    busy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _proc?.kill();
    super.dispose();
  }
}
