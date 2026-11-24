import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/features/agent/agent_service.dart';
import 'package:simple_ide/features/settings/settings_dialog.dart';
import 'package:simple_ide/shared/tokens.dart';
import 'package:simple_ide/shared/widgets.dart';

/**
 * Simple side chat panel for talking to local Agent CLIs (Claude, Gemini,
 * Codex, Aider, or a custom CLI) inside the open workspace.
 */
class AgentPanel extends ConsumerStatefulWidget {
  const AgentPanel({super.key});

  @override
  ConsumerState<AgentPanel> createState() => _AgentPanelState();
}

class _AgentPanelState extends ConsumerState<AgentPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _attachActiveFile = true;
  bool _probed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_probed) {
      _probed = true;
      final ide = ref.read(ideProvider);
      ide.agent.detectAgents(extraEnv: ide.settings.pathEnv);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final ide = ref.read(ideProvider);
    final agent = ide.agent;
    final raw = _input.text.trim();
    if (raw.isEmpty || agent.busy) return;
    final ws = ide.workspace;
    if (ws == null) return;

    _input.clear();
    var prompt = raw;
    final active = ide.active;
    if (_attachActiveFile && active != null && p.isWithin(ws.root, active.path)) {
      final rel = p.relative(active.path, from: ws.root);
      prompt = 'Context file: $rel\n$raw';
    }
    await agent.send(prompt, cwd: ws.root, extraEnv: ide.settings.pathEnv);
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _editCustom() async {
    final agent = ref.read(ideProvider).agent;
    final cmd = await showTextPrompt(
      context,
      title: 'Custom Agent CLI command',
      action: 'Save',
      initial: agent.customTemplate,
      hint: r'e.g. ollama run llama3 "${prompt}"',
      validate: (v) => v.trim().isEmpty ? 'Enter a command' : null,
    );
    if (cmd != null) agent.setCustomTemplate(cmd);
  }

  @override
  Widget build(BuildContext context) {
    final ide = ref.watch(ideProvider);
    final agent = ide.agent;
    final active = ide.active;

    return Container(
      color: Tk.sidebar,
      child: ListenableBuilder(
        listenable: agent,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(ide, agent),
            const Divider(height: 1, color: Tk.border),
            _buildSelectorBar(ide, agent),
            const Divider(height: 1, color: Tk.border),
            Expanded(child: _buildMessages(agent)),
            _buildInputBox(ide, agent, active?.name),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(IdeController ide, AgentController agent) {
    return SizedBox(
      height: 34,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 6),
        child: Row(
          children: [
            Expanded(
              child: Text('Agent CLI', style: Tk.ui.copyWith(fontWeight: FontWeight.w600, color: Tk.textStrong)),
            ),
            if (agent.busy)
              IconBtn(icon: Icons.stop_rounded, tooltip: 'Stop', color: Tk.error, onPressed: agent.stop),
            IconBtn(icon: Icons.delete_outline_rounded, tooltip: 'Clear chat', onPressed: agent.clear),
            IconBtn(
              icon: Icons.refresh_rounded,
              tooltip: 'Re-check installed CLIs',
              onPressed: () => agent.detectAgents(extraEnv: ide.settings.pathEnv),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectorBar(IdeController ide, AgentController agent) {
    final found = agent.availableIds.contains(agent.selectedId) || agent.selectedId == 'custom';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          StatusDot(color: !agent.checked ? Tk.textFaint : (found ? Tk.success : Tk.warning)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<String>(
              value: agent.selectedId,
              isExpanded: true,
              isDense: true,
              underline: const SizedBox.shrink(),
              dropdownColor: Tk.raised,
              style: Tk.uiSmall.copyWith(color: Tk.textStrong),
              items: [
                for (final a in agentPresets)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text(
                      a.command.isEmpty
                          ? a.name
                          : '${a.name}${agent.availableIds.contains(a.id) ? '' : ' (not on PATH)'}',
                      overflow: TextOverflow.ellipsis,
                      style: Tk.uiSmall.copyWith(
                        color: a.command.isEmpty || agent.availableIds.contains(a.id) ? Tk.textStrong : Tk.textFaint,
                      ),
                    ),
                  ),
              ],
              onChanged: agent.busy ? null : (v) => agent.selectAgent(v!),
            ),
          ),
          if (agent.selectedId == 'custom')
            IconBtn(icon: Icons.edit_outlined, tooltip: 'Edit command', onPressed: _editCustom)
          else if (agent.checked && !found)
            GestureDetector(
              onTap: () => showSettings(context),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text('PATH…', style: Tk.uiSmall.copyWith(color: Tk.info)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessages(AgentController agent) {
    if (agent.messages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          'Ask your CLI agent about this project.\n\n'
          'Supported out of the box: claude, gemini, codex, aider, or any custom CLI.',
          style: Tk.uiSmall.copyWith(color: Tk.textMuted, height: 1.5),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      itemCount: agent.messages.length,
      itemBuilder: (context, i) => _MessageBubble(msg: agent.messages[i]),
    );
  }

  Widget _buildInputBox(IdeController ide, AgentController agent, String? activeFileName) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Tk.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (activeFileName != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _attachActiveFile = !_attachActiveFile),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _attachActiveFile ? Tk.accent.withValues(alpha: 0.14) : Tk.editor,
                          borderRadius: Tk.radius,
                          border: Border.all(color: _attachActiveFile ? Tk.accent : Tk.border),
                        ),
                        child: Text(
                          '@$activeFileName',
                          style: Tk.uiSmall.copyWith(color: _attachActiveFile ? Tk.accent : Tk.textFaint),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Focus(
                  onKeyEvent: (_, e) {
                    if (e is KeyDownEvent &&
                        e.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _send();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _input,
                    enabled: !agent.busy,
                    minLines: 1,
                    maxLines: 4,
                    style: Tk.ui,
                    decoration: const InputDecoration(hintText: 'Ask agent… (Enter to send)'),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconBtn(
                icon: Icons.send_rounded,
                tooltip: 'Send',
                color: agent.busy ? Tk.textFaint : Tk.accent,
                box: 32,
                onPressed: agent.busy ? null : _send,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.msg});
  final AgentMessage msg;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == ChatRole.user;
    final isSys = msg.role == ChatRole.system;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: isUser ? Tk.listActive : Tk.editor,
          borderRadius: Tk.radiusLg,
          border: Border.all(color: isSys ? Tk.error.withValues(alpha: 0.5) : Tk.border),
        ),
        child: SelectableText(
          msg.streaming && msg.text.isEmpty ? 'Thinking…' : msg.text,
          style: isUser
              ? Tk.ui.copyWith(color: Tk.textStrong)
              : Tk.code.copyWith(fontSize: 12.2, color: isSys ? Tk.error : Tk.text),
        ),
      ),
    );
  }
}
