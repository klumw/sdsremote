import 'dart:math' show atan2, pi;

import 'package:flutter/material.dart';

// ===========================================================================
// KnobWithDisplay Widget
// ===========================================================================

class KnobWithDisplay extends StatefulWidget {
  final double size;
  final double initialValue;
  final bool enabled;
  final ValueChanged<double>? onChanged;
  final bool showCounter;
  final VoidCallback? onTap;

  /// Swaps the arrow-button steps. Scale knobs on the oscilloscope count a
  /// positive front-panel step as a decrease, so their arrows are inverted.
  final bool invertArrowDirection;

  const KnobWithDisplay({
    super.key,
    required this.size,
    this.initialValue = 0.5,
    this.enabled = true,
    this.onChanged,
    this.showCounter = true,
    this.onTap,
    this.invertArrowDirection = false,
  });

  @override
  State<KnobWithDisplay> createState() => _KnobWithDisplayState();
}

class _KnobWithDisplayState extends State<KnobWithDisplay> {
  late double _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.initialValue;
  }

  double _lastAngle = 0;
  bool _isPanning = false;

  double _getAngle(Offset position) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final delta = position - center;
    return atan2(delta.dy, delta.dx);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: AbsorbPointer(
        absorbing: !widget.enabled,
        child: Opacity(
          opacity: widget.enabled ? 1.0 : 0.5,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The knob itself with the pan/tap gesture layer.
                  SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: Stack(
                      children: [
                        // Content (visual only)
                        RotaryKnob(
                          value: _currentValue,
                          size: widget.size,
                          knobColor: const Color(0xFF475569),
                          trackColor: const Color(0xFF1E293B),
                          indicatorColor: Colors.blueAccent,
                        ),
                        // Gesture handling layer (Listener for pan, InkWell
                        // for tap). It only covers the knob so the arrow
                        // buttons next to it stay tappable.
                        Positioned.fill(
                          child: Material(
                            color: Colors.transparent,
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (details) {
                                if (!widget.enabled) return;
                                _lastAngle = _getAngle(details.localPosition);
                                _isPanning = true;
                              },
                              onPointerMove: (details) {
                                if (!_isPanning) return;
                                if (!widget.enabled) return;

                                double currentAngle = _getAngle(
                                  details.localPosition,
                                );
                                double delta = currentAngle - _lastAngle;

                                // Correct for wrap around
                                if (delta > pi) delta -= 2 * pi;
                                if (delta < -pi) delta += 2 * pi;

                                // Sensivity adjustment: Increased by 40%
                                double newValue =
                                    _currentValue + (delta / (2 * pi)) * 1.4;
                                setState(() {
                                  _currentValue = newValue;
                                });
                                widget.onChanged?.call(newValue);

                                _lastAngle = currentAngle;
                              },
                              onPointerUp: (_) {
                                _isPanning = false;
                              },
                              onPointerCancel: (_) {
                                _isPanning = false;
                              },
                              child: InkWell(
                                onTap: widget.onTap,
                                borderRadius: BorderRadius.circular(
                                  widget.size / 2,
                                ),
                                splashColor: Colors.blueAccent.withValues(
                                  alpha: 0.3,
                                ),
                                highlightColor: Colors.blueAccent.withValues(
                                  alpha: 0.1,
                                ),
                                child: Container(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.showCounter) const SizedBox(height: 6),
                  if (widget.showCounter)
                    Container(
                      width: widget.size * 0.9,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B2631),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFF8BA9D1),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            offset: const Offset(0, 1),
                            blurRadius: 1,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          (widget.enabled
                              ? ((_currentValue % 1.0).abs() * 100)
                                    .toStringAsFixed(0)
                              : "---"),
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 2),
              // Alternative step input next to the knob.
              Padding(
                padding: EdgeInsets.only(top: _arrowTopPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildArrowButton(
                      Icons.keyboard_arrow_up,
                      widget.invertArrowDirection ? -1 : 1,
                    ),
                    const SizedBox(height: 2),
                    _buildArrowButton(
                      Icons.keyboard_arrow_down,
                      widget.invertArrowDirection ? 1 : -1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const double _arrowButtonSize = 18;
  static const double _arrowColumnHeight = _arrowButtonSize * 2 + 2;

  /// Centers the arrow column on the knob, not on the counter below it.
  double get _arrowTopPadding {
    final padding = (widget.size - _arrowColumnHeight) / 2;
    return padding > 0 ? padding : 0;
  }

  /// Arrow button that advances the knob by one step in [direction].
  Widget _buildArrowButton(IconData icon, double direction) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.enabled ? () => _step(direction) : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: _arrowButtonSize,
          height: _arrowButtonSize,
          decoration: BoxDecoration(
            color: const Color(0xFF1B2631),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFF475569)),
          ),
          child: Icon(icon, size: 15, color: Colors.blueAccent),
        ),
      ),
    );
  }

  /// Advances the knob value by one arrow step and reports it.
  ///
  /// Consumers only use the direction of the reported value, so a small
  /// normalized step maps to exactly one front-panel command.
  void _step(double direction) {
    const step = 0.01;
    final newValue = _currentValue + direction * step;
    setState(() => _currentValue = newValue);
    widget.onChanged?.call(newValue);
  }
}

// ===========================================================================
// RotaryKnob Widget (visual only - no gesture handling)
// ===========================================================================

class RotaryKnob extends StatelessWidget {
  final double value;
  final double size;
  final Color knobColor;
  final Color trackColor;
  final Color indicatorColor;
  final ValueChanged<double>? onChanged;

  const RotaryKnob({
    super.key,
    required this.value,
    required this.size,
    required this.knobColor,
    required this.trackColor,
    required this.indicatorColor,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: trackColor,
        border: Border.all(color: Colors.white12, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            offset: const Offset(1, 1),
          ),
        ],
      ),
      child: Center(
        child: Transform.rotate(
          angle: value * 2 * pi,
          child: Container(
            width: size * 0.85,
            height: size * 0.85,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white38, width: 0.5),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  knobColor.withValues(alpha: 1.0),
                  knobColor.withValues(alpha: 0.7),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 2,
                  offset: const Offset(1, 1),
                ),
              ],
            ),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: 4),
                    width: 3,
                    height: size * 0.2,
                    decoration: BoxDecoration(
                      color: indicatorColor,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: indicatorColor.withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
