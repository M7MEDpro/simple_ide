import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/**
 * Like [ListenableBuilder], but defers rebuilds that arrive mid-frame.
 * The code editor notifies its controller listeners while it is being
 * built, which a plain builder would turn into a setState-during-build.
 */
class FrameSafeBuilder extends StatefulWidget {
  const FrameSafeBuilder({super.key, required this.listenable, required this.builder});

  final Listenable listenable;
  final WidgetBuilder builder;

  @override
  State<FrameSafeBuilder> createState() => _FrameSafeBuilderState();
}

class _FrameSafeBuilderState extends State<FrameSafeBuilder> {
  bool _queued = false;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(FrameSafeBuilder old) {
    super.didUpdateWidget(old);
    if (!identical(old.listenable, widget.listenable)) {
      old.listenable.removeListener(_changed);
      widget.listenable.addListener(_changed);
    }
  }

  void _changed() {
    if (!mounted || _queued) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks || phase == SchedulerPhase.midFrameMicrotasks) {
      _queued = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _queued = false;
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
