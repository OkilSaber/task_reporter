import 'dart:async';

import 'package:flutter/material.dart';

/// Single-line text that slides back and forth when it doesn't fit in the
/// available width. Renders as a plain [Text] when it fits.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// Scrolling speed in logical pixels per second.
  final double speed;

  /// Pause at each end before sliding back.
  final Duration pause;

  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.speed = 40,
    this.pause = const Duration(milliseconds: 1500),
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  final ScrollController _controller = ScrollController();
  // Incremented to cancel the running loop (text changed, no more overflow…).
  int _runId = 0;
  bool _running = false;
  Timer? _pauseTimer;

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.style != widget.style) {
      _stop();
    }
  }

  @override
  void dispose() {
    _runId++;
    _pauseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _stop() {
    _runId++;
    _running = false;
    _pauseTimer?.cancel();
    if (_controller.hasClients) _controller.jumpTo(0);
  }

  // Cancellable delay: a cancelled pause never completes, ending the loop.
  Future<void> _pause() {
    _pauseTimer?.cancel();
    final completer = Completer<void>();
    _pauseTimer = Timer(widget.pause, completer.complete);
    return completer.future;
  }

  Future<void> _run() async {
    final id = ++_runId;
    _running = true;
    bool alive() => mounted && id == _runId && _controller.hasClients;

    while (true) {
      await _pause();
      if (!alive()) return;
      final max = _controller.position.maxScrollExtent;
      if (max <= 0) return;
      final duration =
          Duration(milliseconds: (max / widget.speed * 1000).round());
      await _controller.animateTo(max, duration: duration, curve: Curves.easeInOut);
      if (!alive()) return;
      await _pause();
      if (!alive()) return;
      await _controller.animateTo(0, duration: duration, curve: Curves.easeInOut);
      if (!alive()) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final overflows = painter.width > constraints.maxWidth;
        painter.dispose();

        if (!overflows) {
          if (_running) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _stop());
          }
          return Text(widget.text, style: style, maxLines: 1, softWrap: false);
        }

        if (!_running) {
          _running = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _run());
        }
        return SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Text(widget.text, style: style, maxLines: 1, softWrap: false),
        );
      },
    );
  }
}
