/// XY plot widget for the Data Logger.
///
/// Displays Peak-to-Peak voltage (left Y-axis) and Frequency (right Y-axis)
/// over time (X-axis) for channels 1 and/or 2. Features auto-scaling for
/// both Y-axes and a legend in the top-right corner.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'data_logger_models.dart';

// =============================================================================
// Colors (consistent with oscilloscope display conventions)
// =============================================================================

const Color _ch1Color = Color(0xFFFFFF00); // Yellow
const Color _ch2Color = Color(0xFFFF20FF); // Magenta
const Color _gridColor = Color(0xFF1E3A5F);
const Color _axisColor = Color(0xFF475569);
const Color _labelColor = Color(0xFF94A3B8);
const Color _bgColor = Color(0xFF0A192F);

// =============================================================================
// Main Plot Widget
// =============================================================================

/// XY plot widget for Data Logger measurements.
///
/// Renders Peak-to-Peak voltage (left Y-axis) and Frequency (right Y-axis)
/// as functions of elapsed time (X-axis). Both axes auto-scale to fit data.
class DataLoggerPlot extends StatelessWidget {
  final List<DataLoggerPoint> points;
  final bool ch1VppEnabled;
  final bool ch1FreqEnabled;
  final bool ch2VppEnabled;
  final bool ch2FreqEnabled;
  final DataLoggerStatus status;

  /// Total configured recording duration in seconds.
  /// Used to fix the X-axis range so it doesn't shift during recording.
  final double totalDurationSeconds;

  /// Set of line IDs that are currently hidden.
  /// Possible values: "ch1_vpp", "ch1_freq", "ch2_vpp", "ch2_freq".
  final Set<String> hiddenLines;

  /// Called when a legend line is tapped.
  final ValueChanged<String>? onToggleLine;

  /// Called on mouse hover with (time_seconds, local_x, local_y).
  final void Function(double time, double localX, double localY)? onHover;

  const DataLoggerPlot({
    super.key,
    required this.points,
    this.ch1VppEnabled = true,
    this.ch1FreqEnabled = true,
    this.ch2VppEnabled = false,
    this.ch2FreqEnabled = false,
    required this.status,
    this.totalDurationSeconds = 60,
    this.hiddenLines = const {},
    this.onToggleLine,
    this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final ranges = _AxisRanges.compute(points, totalDurationSeconds: totalDurationSeconds);
    final maxTime = ranges.niceMaxTime;

    return Container(
      decoration: BoxDecoration(
        color: _bgColor,
        border: Border.all(color: _axisColor, width: 1.0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: MouseRegion(
          onHover: (event) {
            if (onHover != null && maxTime > 0) {
              final plotWidth = context.size?.width ?? 1;
              final plotAreaWidth = plotWidth - 75 - 75; // _marginLeft + _marginRight
              if (plotAreaWidth > 0) {
                final relX = (event.localPosition.dx - 60) / plotAreaWidth;
                final time = (relX.clamp(0.0, 1.0)) * maxTime;
                onHover!(time, event.localPosition.dx, event.localPosition.dy);
              }
            }
          },
          onExit: (_) {
            if (onHover != null) onHover!(-1, 0, 0);
          },
          child: CustomPaint(
            painter: _DataLoggerPlotPainter(
              points: points,
              ch1VppEnabled: ch1VppEnabled,
              ch1FreqEnabled: ch1FreqEnabled,
              ch2VppEnabled: ch2VppEnabled,
              ch2FreqEnabled: ch2FreqEnabled,
              status: status,
              totalDurationSeconds: totalDurationSeconds,
              hiddenLines: hiddenLines,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Axis Range Helper
// =============================================================================

/// Computed ranges for auto-scaling the plot axes.
class _AxisRanges {
  final double maxTime;
  final double minVpp;
  final double maxVpp;
  final double minFreq;
  final double maxFreq;

  const _AxisRanges({
    required this.maxTime,
    required this.minVpp,
    required this.maxVpp,
    required this.minFreq,
    required this.maxFreq,
  });

  // Use the exact configured maxTime (recording duration) without nice-rounding,
  // so a 60-second recording shows exactly 0-60s on the X-axis.
  double get niceMaxTime => maxTime;
  double get niceMinVpp => minVpp;
  double get niceMaxVpp => maxVpp;
  double get niceMinFreq => minFreq;
  double get niceMaxFreq => maxFreq;

  /// Compute a "nice" maximum value that rounds up to a clean number.
  static double _niceMax(double value, {bool allowZero = false}) {
    if (value <= 0 && allowZero) return 0.0;
    if (value <= 0) return 0.0;
    final magnitude = math.pow(10, (math.log(value) / math.ln10).floor()).toDouble();
    final fraction = value / magnitude;
    if (fraction <= 1.0) return magnitude;
    if (fraction <= 2.0) return 2.0 * magnitude;
    if (fraction <= 5.0) return 5.0 * magnitude;
    return 10.0 * magnitude;
  }

  /// Compute a "nice" minimum value that rounds down to a clean number.
  static double _niceMin(double value) {
    if (value >= 0) return 0.0;
    final abs = value.abs();
    final magnitude = math.pow(10, (math.log(abs) / math.ln10).floor()).toDouble();
    final fraction = abs / magnitude;
    final niceAbs = fraction <= 1.0 ? magnitude : (fraction <= 2.0 ? 2.0 * magnitude : (fraction <= 5.0 ? 5.0 * magnitude : 10.0 * magnitude));
    return -niceAbs;
  }

  static _AxisRanges compute(List<DataLoggerPoint> points, {double totalDurationSeconds = 60}) {
    // X-axis: Use the total configured recording duration for the X-axis max,
    // so the axis doesn't shift as data is collected during recording, but
    // expand it if any recorded points exceed totalDurationSeconds.
    double maxTime = totalDurationSeconds;
    for (final p in points) {
      if (p.elapsedSeconds > maxTime) {
        maxTime = p.elapsedSeconds;
      }
    }

    // Find the peak (maximum) Vpp and Frequency among the recorded points.
    double peakVpp = 0.0;
    double peakFreq = 0.0;

    for (final p in points) {
      if (p.ch1Vpp != null && p.ch1Vpp! > peakVpp) peakVpp = p.ch1Vpp!;
      if (p.ch2Vpp != null && p.ch2Vpp! > peakVpp) peakVpp = p.ch2Vpp!;
      if (p.ch1Freq != null && p.ch1Freq! > peakFreq) peakFreq = p.ch1Freq!;
      if (p.ch2Freq != null && p.ch2Freq! > peakFreq) peakFreq = p.ch2Freq!;
    }

    // Y-axes dynamic scaling: Scale so that the full Y-axis area minus a 20% margin
    // off the peak value is used: peak = 80% of max => max = peak * 1.2
    double minVpp = 0.0;
    double maxVpp = peakVpp > 0 ? peakVpp * 1.2 : 1.0;

    double minFreq = 0.0;
    double maxFreq = peakFreq > 0 ? peakFreq * 1.2 : 1.0;

    return _AxisRanges(
      maxTime: maxTime,
      minVpp: minVpp,
      maxVpp: maxVpp,
      minFreq: minFreq,
      maxFreq: maxFreq,
    );
  }
}

// =============================================================================
// Custom Painter
// =============================================================================

class _DataLoggerPlotPainter extends CustomPainter {
  final List<DataLoggerPoint> points;
  final bool ch1VppEnabled;
  final bool ch1FreqEnabled;
  final bool ch2VppEnabled;
  final bool ch2FreqEnabled;
  final DataLoggerStatus status;
  final double totalDurationSeconds;
  final Set<String> hiddenLines;

  _DataLoggerPlotPainter({
    required this.points,
    required this.ch1VppEnabled,
    required this.ch1FreqEnabled,
    required this.ch2VppEnabled,
    required this.ch2FreqEnabled,
    required this.status,
    this.totalDurationSeconds = 60,
    this.hiddenLines = const {},
  });

  // Layout constants
  static const double _marginLeft = 75.0;   // Left Y-axis labels + ticks
  static const double _marginRight = 75.0;  // Right Y-axis labels + ticks
  static const double _marginTop = 16.0;
  static const double _marginBottom = 40.0; // X-axis labels
  static const double _legendWidth = 140.0;
  static const double _legendPadding = 8.0;
  static const double _legendItemHeight = 16.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      _drawEmptyState(canvas, size);
      return;
    }

    final ranges = _AxisRanges.compute(points, totalDurationSeconds: totalDurationSeconds);
    final plotRect = Rect.fromLTWH(
      _marginLeft,
      _marginTop,
      size.width - _marginLeft - _marginRight,
      size.height - _marginTop - _marginBottom,
    );

    if (plotRect.width <= 0 || plotRect.height <= 0) return;

    // Draw grid
    _drawGrid(canvas, plotRect, ranges);

    // Draw data lines
    _drawDataLines(canvas, plotRect, ranges);

    // Draw axes labels
    _drawAxesLabels(canvas, plotRect, ranges, size);

    // Draw legend
    _drawLegend(canvas, plotRect, size);

    // Draw border
    final borderPaint = Paint()
      ..color = _axisColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(plotRect, borderPaint);
  }

  void _drawEmptyState(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: status == DataLoggerStatus.running
            ? 'Waiting for first sample...'
            : 'No data recorded',
        style: const TextStyle(color: _labelColor, fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );
  }

  /// Compute a "nice" tick step size for an axis range.
  /// E.g. range=5 → step=1, range=2000 → step=500, range=10 → step=2.
  static double _tickStep(double min, double max) {
    final rawRange = max - min;
    if (rawRange <= 0) return 1.0;
    // Target ~5 ticks
    final rough = rawRange / 5;
    final magnitude = math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
    final fraction = rough / magnitude;
    if (fraction <= 1.5) return magnitude;
    if (fraction <= 3.5) return 2.0 * magnitude;
    if (fraction <= 7.5) return 5.0 * magnitude;
    return 10.0 * magnitude;
  }

  /// Return X-axis tick positions (in raw seconds) that align on integer
  /// display values after conversion by [timeFactor]. Used for both vertical
  /// grid lines and tick labels so they stay consistent.
  static List<double> _timeTickPositions(double maxTime, double timeFactor) {
    final displayMax = maxTime / timeFactor;
    final roughStep = displayMax / 5;
    int step;
    if (roughStep <= 1) {
      step = 1;
    } else if (roughStep <= 2) {
      step = 2;
    } else if (roughStep <= 5) {
      step = 5;
    } else if (roughStep <= 10) {
      step = 10;
    } else if (roughStep <= 15) {
      step = 15;
    } else if (roughStep <= 30) {
      step = 30;
    } else if (roughStep <= 60) {
      step = 60;
    } else {
      step = ((roughStep / 60).ceil()) * 60;
    }

    final positions = <double>[];
    for (int v = 0; v <= displayMax.round(); v += step) {
      positions.add(v * timeFactor);
    }
    return positions;
  }

  void _drawGrid(Canvas canvas, Rect plotRect, _AxisRanges ranges) {
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 0.5;

    // Horizontal grid lines — use Vpp ticks (they align with left Y-axis)
    final vppStep = _tickStep(ranges.niceMinVpp, ranges.niceMaxVpp);
    double v = ranges.niceMinVpp;
    while (v <= ranges.niceMaxVpp + 0.001) {
      final y = _mapValueToY(v, ranges.niceMinVpp, ranges.niceMaxVpp, plotRect);
      canvas.drawLine(Offset(plotRect.left, y), Offset(plotRect.right, y), gridPaint);
      v += vppStep;
    }

    // Vertical grid lines (Time) — integer display values converted back
    // to raw seconds for positioning, so grid lines align with integer labels.
    final (timeFactor, _) = _timeUnitInfo(ranges.niceMaxTime);
    final tickPositions = _timeTickPositions(ranges.niceMaxTime, timeFactor);
    for (final t in tickPositions) {
      final x = plotRect.left + (t / ranges.niceMaxTime) * plotRect.width;
      canvas.drawLine(Offset(x, plotRect.top), Offset(x, plotRect.bottom), gridPaint);
    }
  }

  double _mapValueToY(double value, double axisMin, double axisMax, Rect plotRect) {
    return plotRect.bottom - ((value - axisMin) / (axisMax - axisMin)) * plotRect.height;
  }

  void _drawDataLines(Canvas canvas, Rect plotRect, _AxisRanges ranges) {
    if (points.length < 2) return;

    final vppRange = ranges.niceMaxVpp - ranges.niceMinVpp;
    final freqRange = ranges.niceMaxFreq - ranges.niceMinFreq;
    final timeRange = ranges.niceMaxTime;

    /// Map data value to pixel coordinate.
    double mapTime(double t) =>
        plotRect.left + (t / timeRange) * plotRect.width;
    double mapVpp(double v) =>
        plotRect.bottom - ((v - ranges.niceMinVpp) / vppRange) * plotRect.height;
    double mapFreq(double f) =>
        plotRect.bottom - ((f - ranges.niceMinFreq) / freqRange) * plotRect.height;

    void drawLine(
      List<Offset> pts,
      Color color,
      String label, {
      bool dashed = false,
    }) {
      if (pts.length < 2) return;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      if (dashed) {
        final path = Path();
        path.addPolygon(pts, false);
        canvas.drawPath(
          _dashPath(path, 6, 4),
          paint,
        );
      } else {
        final path = Path();
        path.addPolygon(pts, false);
        canvas.drawPath(path, paint);
      }
    }

    // Build line segments for CH1 Vpp
    if (ch1VppEnabled) {
      if (!hiddenLines.contains('ch1_vpp')) {
        final ch1VppPts = <Offset>[];
        for (final p in points) {
          if (p.ch1Vpp != null) {
            ch1VppPts.add(Offset(
              mapTime(p.elapsedSeconds),
              mapVpp(p.ch1Vpp!),
            ));
          }
        }
        drawLine(ch1VppPts, _ch1Color, 'CH1 Vpp', dashed: false);
      }
    }
    if (ch1FreqEnabled) {
      if (!hiddenLines.contains('ch1_freq')) {
        final ch1FreqPts = <Offset>[];
        for (final p in points) {
          if (p.ch1Freq != null) {
            ch1FreqPts.add(Offset(
              mapTime(p.elapsedSeconds),
              mapFreq(p.ch1Freq!),
            ));
          }
        }
        drawLine(ch1FreqPts, _ch1Color, 'CH1 Freq', dashed: true);
      }
    }

    // Build line segments for CH2 Vpp
    if (ch2VppEnabled) {
      if (!hiddenLines.contains('ch2_vpp')) {
        final ch2VppPts = <Offset>[];
        for (final p in points) {
          if (p.ch2Vpp != null) {
            ch2VppPts.add(Offset(
              mapTime(p.elapsedSeconds),
              mapVpp(p.ch2Vpp!),
            ));
          }
        }
        drawLine(ch2VppPts, _ch2Color, 'CH2 Vpp', dashed: false);
      }
    }
    if (ch2FreqEnabled) {
      if (!hiddenLines.contains('ch2_freq')) {
        final ch2FreqPts = <Offset>[];
        for (final p in points) {
          if (p.ch2Freq != null) {
            ch2FreqPts.add(Offset(
              mapTime(p.elapsedSeconds),
              mapFreq(p.ch2Freq!),
            ));
          }
        }
        drawLine(ch2FreqPts, _ch2Color, 'CH2 Freq', dashed: true);
      }
    }
  }

  Path _dashPath(Path source, double dashLength, double gapLength) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashLength;
        result.addPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          Offset.zero,
        );
        distance = next + gapLength;
      }
    }
    return result;
  }

  /// Returns (conversionFactor, unitSuffix) for the X-axis time unit
  /// based on the total recording duration.
  ///
  /// - < 2 min → seconds
  /// - 2 min up to < 2 hours → minutes
  /// - >= 2 hours → hours
  static (double, String) _timeUnitInfo(double totalDurationSeconds) {
    if (totalDurationSeconds >= 7200) {
      return (3600.0, 'h');
    } else if (totalDurationSeconds >= 120) {
      return (60.0, 'min');
    } else {
      return (1.0, 's');
    }
  }

  void _drawAxesLabels(
    Canvas canvas,
    Rect plotRect,
    _AxisRanges ranges,
    Size size,
  ) {
    final textStyle = TextStyle(color: _labelColor, fontSize: 10);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Left Y-axis label (Vpp)
    textPainter.text = TextSpan(text: 'Vpp (V)', style: textStyle);
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        4,
        plotRect.top + (plotRect.height - textPainter.height) / 2,
      ),
    );

    // Right Y-axis label (Frequency)
    textPainter.text = TextSpan(text: 'Freq (Hz)', style: textStyle);
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        size.width - textPainter.width - 4,
        plotRect.top + (plotRect.height - textPainter.height) / 2,
      ),
    );

    // X-axis label (Time) — choose seconds / minutes / hours based on duration
    final (timeFactor, timeUnit) = _timeUnitInfo(totalDurationSeconds);
    textPainter.text = TextSpan(text: 'Time ($timeUnit)', style: textStyle);
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        plotRect.left + (plotRect.width - textPainter.width) / 2,
        size.height - textPainter.height - 2,
      ),
    );

    // Y-axis tick labels (left: Vpp at each tick)
    final vppStep = _tickStep(ranges.niceMinVpp, ranges.niceMaxVpp);
    double v = ranges.niceMinVpp;
    while (v <= ranges.niceMaxVpp + 0.001) {
      final y = _mapValueToY(v, ranges.niceMinVpp, ranges.niceMaxVpp, plotRect);
      textPainter.text = TextSpan(
        text: _formatAxisValue(v),
        style: textStyle,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(plotRect.left - textPainter.width - 4, y - textPainter.height / 2),
      );
      v += vppStep;
    }

    // Y-axis tick labels (right: Freq at each tick)
    final freqStep = _tickStep(ranges.niceMinFreq, ranges.niceMaxFreq);
    double f = ranges.niceMinFreq;
    while (f <= ranges.niceMaxFreq + 0.001) {
      final y = _mapValueToY(f, ranges.niceMinFreq, ranges.niceMaxFreq, plotRect);
      textPainter.text = TextSpan(
        text: _formatAxisValue(f),
        style: textStyle,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(plotRect.right + 4, y - textPainter.height / 2),
      );
      f += freqStep;
    }

    // X-axis tick labels — integer display values (s/min/h), grid lines
    // are already aligned from _drawGrid.
    final tickPositions = _timeTickPositions(ranges.niceMaxTime, timeFactor);
    for (final t in tickPositions) {
      final x = plotRect.left + (t / ranges.niceMaxTime) * plotRect.width;
      final displayVal = (t / timeFactor).round();
      textPainter.text = TextSpan(
        text: displayVal.toString(),
        style: textStyle,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, plotRect.bottom + 4),
      );
    }

    // Always show the total duration as the final X-axis tick label.
    final lastDisplayVal = (ranges.niceMaxTime / timeFactor).round();
    textPainter.text = TextSpan(
      text: lastDisplayVal.toString(),
      style: textStyle,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(plotRect.right - textPainter.width / 2, plotRect.bottom + 4),
    );
  }

  void _drawLegend(Canvas canvas, Rect plotRect, Size size) {
    final items = <_LegendItem>[];

    if (ch1VppEnabled) {
      items.add(_LegendItem('CH1 Vpp', _ch1Color, false));
    }
    if (ch1FreqEnabled) {
      items.add(_LegendItem('CH1 Freq', _ch1Color, true));
    }
    if (ch2VppEnabled) {
      items.add(_LegendItem('CH2 Vpp', _ch2Color, false));
    }
    if (ch2FreqEnabled) {
      items.add(_LegendItem('CH2 Freq', _ch2Color, true));
    }

    if (items.isEmpty) return;

    final legendHeight = items.length * _legendItemHeight + _legendPadding * 2;
    final legendRect = Rect.fromLTWH(
      plotRect.right - _legendWidth - 8,
      plotRect.top + 8,
      _legendWidth,
      legendHeight,
    );

    // Background
    final bgPaint = Paint()
      ..color = const Color(0xB00A192F);
    canvas.drawRRect(
      RRect.fromRectAndRadius(legendRect, const Radius.circular(4)),
      bgPaint,
    );

    // Border
    canvas.drawRRect(
      RRect.fromRectAndRadius(legendRect, const Radius.circular(4)),
      Paint()
        ..color = _axisColor.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    // Items
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      final y = legendRect.top + _legendPadding + i * _legendItemHeight;

      // Line sample
      final lineStart = Offset(legendRect.left + 8, y + _legendItemHeight / 2 - 1);
      final lineEnd = Offset(legendRect.left + 28, y + _legendItemHeight / 2 - 1);
      final linePaint = Paint()
        ..color = item.color
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      if (item.dashed) {
        final path = Path();
        path.moveTo(lineStart.dx, lineStart.dy);
        path.lineTo(lineEnd.dx, lineEnd.dy);
        canvas.drawPath(_dashPath(path, 4, 3), linePaint);
      } else {
        canvas.drawLine(lineStart, lineEnd, linePaint);
      }

      // Label
      textPainter.text = TextSpan(
        text: item.label,
        style: const TextStyle(color: Colors.white70, fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(lineEnd.dx + 6, y),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DataLoggerPlotPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.points.length != points.length ||
        oldDelegate.ch1VppEnabled != ch1VppEnabled ||
        oldDelegate.ch1FreqEnabled != ch1FreqEnabled ||
        oldDelegate.ch2VppEnabled != ch2VppEnabled ||
        oldDelegate.ch2FreqEnabled != ch2FreqEnabled ||
        oldDelegate.status != status ||
        oldDelegate.totalDurationSeconds != totalDurationSeconds ||
        oldDelegate.hiddenLines != hiddenLines;
  }
}

// =============================================================================
// Legend Item
// =============================================================================

class _LegendItem {
  final String label;
  final Color color;
  final bool dashed;

  const _LegendItem(this.label, this.color, this.dashed);
}

// =============================================================================
// Formatting Helpers
// =============================================================================

String _formatAxisValue(double value) {
  if (value == 0) return '0';
  if (value.abs() >= 1e6) {
    return '${(value / 1e6).toStringAsFixed(1)}M';
  } else if (value.abs() >= 1e3) {
    return '${(value / 1e3).toStringAsFixed(1)}k';
  } else if (value.abs() >= 1) {
    return value.toStringAsFixed(1);
  } else if (value.abs() >= 1e-3) {
    return '${(value * 1e3).toStringAsFixed(1)}m';
  } else if (value.abs() >= 1e-6) {
    return '${(value * 1e6).toStringAsFixed(1)}µ';
  } else {
    return value.toStringAsExponential(1);
  }
}
