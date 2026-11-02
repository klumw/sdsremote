import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated equalizer bars shown in the top bar while an AI assistant uses
/// the microphone.
///
/// The bars animate continuously while [active] is true and fade out when the
/// microphone is switched off. The widget keeps its slot in the toolbar in
/// both states so the toolbar does not move.
class VoiceActivityIndicator extends StatefulWidget {
  const VoiceActivityIndicator({
    super.key,
    required this.active,
    this.color = Colors.cyanAccent,
  });

  /// Whether the microphone is currently in use.
  final bool active;

  /// Color of the animated bars.
  final Color color;

  @override
  State<VoiceActivityIndicator> createState() => _VoiceActivityIndicatorState();
}

class _VoiceActivityIndicatorState extends State<VoiceActivityIndicator>
    with SingleTickerProviderStateMixin {
  static const int _barCount = 4;
  static const double _width = 34;
  static const double _height = 26;
  static const Duration _animationDuration = Duration(milliseconds: 900);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _animationDuration,
    );
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant VoiceActivityIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.active ? 1.0 : 0.0,
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
                final barHeight = 6.0 + 12.0 * (0.5 + 0.5 * wave);
                return Container(
                  width: 4,
                  height: barHeight,
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
