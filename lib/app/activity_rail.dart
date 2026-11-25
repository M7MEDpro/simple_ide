import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:simple_ide/app/ide_controller.dart';
import 'package:simple_ide/app/shell_actions.dart';
import 'package:simple_ide/shared/tokens.dart';

/**
 * Narrow vertical strip on the far left for switching sidebar panels.
 */
class ActivityRail extends ConsumerWidget {
  const ActivityRail({super.key, required this.actions});

  final ShellActions actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ide = ref.watch(ideProvider);
    final hasWs = ide.workspace != null;
    return Container(
      width: 46,
      decoration: const BoxDecoration(
        color: Tk.chrome,
        border: Border(right: BorderSide(color: Tk.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 6),
          _RailItem(
            icon: Icons.folder_copy_outlined,
            tooltip: hasWs ? 'Explorer (Ctrl+B)' : 'Open folder (Ctrl+O)',
            active: hasWs && ide.settings.sidebarVisible && ide.sidebarTab == SidebarTab.explorer,
            onTap: hasWs ? () => ide.selectSidebar(SidebarTab.explorer) : actions.openFolder,
          ),
          _RailItem(
            icon: Icons.manage_search_rounded,
            tooltip: 'Search in project (Ctrl+Shift+F)',
            active: hasWs && ide.settings.sidebarVisible && ide.sidebarTab == SidebarTab.search,
            onTap: hasWs ? () => ide.selectSidebar(SidebarTab.search) : null,
          ),
          _RailItem(icon: Icons.search_rounded, tooltip: 'Go to file (Ctrl+P)', onTap: hasWs ? actions.quickOpen : null),
          _RailItem(
            icon: Icons.call_split_rounded,
            tooltip: 'Source Control (Ctrl+Shift+G)',
            active: hasWs && ide.settings.sidebarVisible && ide.sidebarTab == SidebarTab.git,
            onTap: hasWs ? () => ide.selectSidebar(SidebarTab.git) : null,
          ),
          _RailItem(
            icon: Icons.chat_bubble_outline_rounded,
            tooltip: 'Agent CLI (Ctrl+Shift+A)',
            active: hasWs && ide.settings.sidebarVisible && ide.sidebarTab == SidebarTab.agent,
            onTap: hasWs ? () => ide.selectSidebar(SidebarTab.agent) : null,
          ),
          _RailItem(
            icon: Icons.terminal_rounded,
            tooltip: 'Console (Ctrl+J)',
            active: hasWs && ide.settings.consoleVisible,
            onTap: hasWs ? ide.toggleConsole : null,
          ),
          const Spacer(),
          _RailItem(icon: Icons.settings_outlined, tooltip: 'Settings (Ctrl+,)', onTap: actions.settings),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({required this.icon, required this.tooltip, required this.onTap, this.active = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return Tooltip(
      message: widget.tooltip,
      preferBelow: false,
      verticalOffset: 0,
      margin: const EdgeInsets.only(left: 50),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: widget.active ? Tk.accent : Colors.transparent, width: 2)),
            ),
            alignment: Alignment.center,
            child: Icon(
              widget.icon,
              size: 21,
              color: !enabled
                  ? Tk.textFaint.withValues(alpha: 0.5)
                  : widget.active || _hover
                      ? Tk.textStrong
                      : Tk.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
