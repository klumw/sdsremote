import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Rotating arrows icon used as the application-wide busy indicator.
///
/// The Data Logger toolbar button introduced this animation; all other
/// progress indicators use the same widget so busy feedback looks identical
/// throughout the application. The arrows rotate while [animate] is true and
/// rest in their upright position otherwise.
class AnimatedSyncIcon extends StatefulWidget {
  /// Edge length of the icon in logical pixels.
  final double size;

  /// Icon color.
  final Color color;

  /// Whether the arrows rotate.
  final bool animate;

  const AnimatedSyncIcon({
    super.key,
    this.size = 20,
    this.color = Colors.white,
    this.animate = true,
  });

  @override
  State<AnimatedSyncIcon> createState() => _AnimatedSyncIconState();
}

class _AnimatedSyncIconState extends State<AnimatedSyncIcon>
    with SingleTickerProviderStateMixin {
  /// One full rotation takes the same time as in the Data Logger button.
  static const _rotationPeriod = Duration(seconds: 2);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _rotationPeriod);
    if (widget.animate) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedSyncIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    if (widget.animate) {
      _controller.repeat();
    } else {
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.rotate(
        angle: widget.animate ? _controller.value * 2 * math.pi : 0,
        child: child,
      ),
      child: Icon(Icons.sync, size: widget.size, color: widget.color),
    );
  }
}
