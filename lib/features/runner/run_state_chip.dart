import 'package:flutter/material.dart';

import 'package:simple_ide/features/runner/runner.dart';
import 'package:simple_ide/shared/tokens.dart';

/**
 * Live state of the current run: what's running, for how long, and how it
 * ended. Shared by the console header and the status bar.
 */
class RunStateChip extends StatelessWidget {
  const RunStateChip({super.key, required this.runner, this.compact = false});

  final Runner runner;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = runner.target ?? '';
    final time = Runner.formatElapsed(runner.elapsed);
    final (String label, Color color, bool live) = switch (runner.status) {
      RunStatus.idle => ('Ready', Tk.textFaint, false),
      RunStatus.building => ('Building $t  $time', Tk.accent, true),
      RunStatus.running => ('Running $t  $time', Tk.accent, true),
      RunStatus.succeeded => ('Finished $t in $time', Tk.success, false),
      RunStatus.failed => (
          runner.exitCode == null ? 'Couldn\'t run $t' : 'Exit code ${runner.exitCode}  $t',
          Tk.error,
          false
        ),
      RunStatus.stopped => ('Stopped $t', Tk.textMuted, false),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Pulse(color: color, live: live),
        const SizedBox(width: 7),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 260 : 420),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Tk.uiSmall.copyWith(
                color: live ? Tk.textStrong : Tk.textMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/**
 * Status dot. Breathes while a process is alive; still otherwise.
 */
class _Pulse extends StatefulWidget {
  const _Pulse({required this.color, required this.live});

  final Color color;
  final bool live;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_Pulse old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (widget.live && !reduce) {
      if (!_a.isAnimating) _a.repeat(reverse: true);
    } else {
      _a
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withValues(alpha: 0.45 + 0.55 * _a.value),
        ),
      ),
    );
  }
}
