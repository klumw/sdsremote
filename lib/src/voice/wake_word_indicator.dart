import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated equalizer bars shown next to the microphone button after a
/// wakeword detection.
///
/// The indicator stays invisible until [detectionCount] changes, animates for
/// [visibleDuration], and then fades out again.
class WakeWordIndicator extends StatefulWidget {
  const WakeWordIndicator({
    super.key,
    required this.detectionCount,
    this.active = true,
    this.persistent = false,
    this.color = Colors.cyanAccent,
    this.visibleDuration = const Duration(milliseconds: 2500),
  });

  /// Increments on every detection. A change restarts the animation.
  final int detectionCount;

  /// Whether the detector is currently listening. When it turns false, any
  /// visible bars are hidden immediately.
  final bool active;

  /// Whether the bars stay visible for as long as [active] is true. Used
  /// while the microphone records a spoken command after the wakeword.
  final bool persistent;

  /// Color of the animated bars.
  final Color color;

  /// How long the bars stay visible after the last detection.
  final Duration visibleDuration;

  @override
  State<WakeWordIndicator> createState() => _WakeWordIndicatorState();
}

class _WakeWordIndicatorState extends State<WakeWordIndicator>
    with SingleTickerProviderStateMixin {
  static const int _barCount = 4;
  static const double _width = 34;
  static const double _height = 26;
  static const Duration _animationDuration = Duration(milliseconds: 900);

  late final AnimationController _controller;
  Timer? _hideTimer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );
  }

  @override
  void didUpdateWidget(covariant WakeWordIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) {
      _hide();
      return;
    }
    if (widget.persistent) {
      _show(persistent: true);
      return;
    }
    if (widget.detectionCount > oldWidget.detectionCount) {
      _show(persistent: false);
      return;
    }
    if (oldWidget.persistent) {
      _hide();
    }
  }

  void _show({required bool persistent}) {
    if (!widget.active) return;
    _hideTimer?.cancel();
    _hideTimer = null;
    if (!_visible) {
      setState(() => _visible = true);
    }
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
    if (!persistent) {
      _hideTimer = Timer(widget.visibleDuration, () {
        if (!mounted) return;
        _hide();
      });
    }
  }

  void _hide() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _controller.stop();
    if (_visible) {
      setState(() => _visible = false);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 180),
      child: SizedBox(
        width: _width,
        height: _height,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final phase = _controller.value * math.pi * 2;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(_barCount, (index) {
                final wave = math.sin(phase + index * math.pi / 2);
                final height = 6.0 + 12.0 * (0.5 + 0.5 * wave);
                return Container(
                  width: 4,
                  height: height,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
