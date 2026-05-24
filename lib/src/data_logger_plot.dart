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
  final bool ch1Enabled;
  final bool ch2Enabled;
  final DataLoggerStatus status;

  /// Total configured recording duration in seconds.
  /// Used to fix the X-axis range so it doesn't shift during recording.
  final double totalDurationSeconds;

  const DataLoggerPlot({
    super.key,
    required this.points,
    required this.ch1Enabled,
    required this.ch2Enabled,
    required this.status,
    this.totalDurationSeconds = 60,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bgColor,
        border: Border.all(color: _axisColor, width: 1.0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: CustomPaint(
          painter: _DataLoggerPlotPainter(
            points: points,
            ch1Enabled: ch1Enabled,
            ch2Enabled: ch2Enabled,
            status: status,
            totalDurationSeconds: totalDurationSeconds,
          ),
          child: const SizedBox.expand(),
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
  double get niceMinVpp => _niceMin(minVpp);
  double get niceMaxVpp => _niceMax(maxVpp);
  double get niceMinFreq => _niceMin(minFreq);
  double get niceMaxFreq => _niceMax(maxFreq);

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
    // Use the total configured recording duration for the X-axis max,
    // so the axis doesn't shift as data is collected during recording.
    double maxTime = totalDurationSeconds;
    double minVpp = double.infinity;
    double maxVpp = double.negativeInfinity;
    double minFreq = double.infinity;
    double maxFreq = double.negativeInfinity;

    for (final p in points) {
      if (p.elapsedSeconds > maxTime) maxTime = p.elapsedSeconds;
      if (p.ch1Vpp != null) {
        if (p.ch1Vpp! < minVpp) minVpp = p.ch1Vpp!;
        if (p.ch1Vpp! > maxVpp) maxVpp = p.ch1Vpp!;
      }
      if (p.ch2Vpp != null) {
        if (p.ch2Vpp! < minVpp) minVpp = p.ch2Vpp!;
        if (p.ch2Vpp! > maxVpp) maxVpp = p.ch2Vpp!;
      }
      if (p.ch1Freq != null) {
        if (p.ch1Freq! < minFreq) minFreq = p.ch1Freq!;
        if (p.ch1Freq! > maxFreq) maxFreq = p.ch1Freq!;
      }
      if (p.ch2Freq != null) {
        if (p.ch2Freq! < minFreq) minFreq = p.ch2Freq!;
        if (p.ch2Freq! > maxFreq) maxFreq = p.ch2Freq!;
      }
    }

    // Handle empty or single-point lists gracefully
    if (minVpp == double.infinity) {
      minVpp = 0;
      maxVpp = 1;
    }
    if (minFreq == double.infinity) {
      minFreq = 0;
      maxFreq = 1;
    }

    // Ensure axis limits always have enough headroom so data lines
    // are comfortably within the chart area. Always at least 15% of
    // the max value as minimum margin, or 30% of the range, whichever
    // is larger.
    double _padRange(double min, double max) {
      final range = max - min;
      final rangeMargin = range * 0.3;
      final absoluteMargin = (max.abs() > 0.001) ? max.abs() * 0.15 : 1.0;
      return rangeMargin > absoluteMargin ? rangeMargin : absoluteMargin;
    }

    final vppMargin = _padRange(minVpp, maxVpp);
    maxVpp += vppMargin;
    minVpp -= vppMargin;

    final freqMargin = _padRange(minFreq, maxFreq);
    maxFreq += freqMargin;
    minFreq -= freqMargin;

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
  final bool ch1Enabled;
  final bool ch2Enabled;
  final DataLoggerStatus status;
  final double totalDurationSeconds;

  _DataLoggerPlotPainter({
    required this.points,
    required this.ch1Enabled,
    required this.ch2Enabled,
    required this.status,
    this.totalDurationSeconds = 60,
  });

  // Layout constants
  static const double _marginLeft = 60.0;   // Left Y-axis labels + ticks
  static const double _marginRight = 60.0;  // Right Y-axis labels + ticks
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

  void _drawGrid(Canvas canvas, Rect plotRect, _AxisRanges ranges) {
    final gridPaint = Paint()
      ..color = _gridColor
      ..strokeWidth = 0.5;

    // Horizontal grid lines (Vpp / Freq)
    const int numGridLines = 5;
    for (int i = 0; i <= numGridLines; i++) {
      final y = plotRect.top + (plotRect.height * i / numGridLines);
      canvas.drawLine(Offset(plotRect.left, y), Offset(plotRect.right, y), gridPaint);
    }

    // Vertical grid lines (Time)
    for (int i = 0; i <= numGridLines; i++) {
      final x = plotRect.left + (plotRect.width * i / numGridLines);
      canvas.drawLine(Offset(x, plotRect.top), Offset(x, plotRect.bottom), gridPaint);
    }
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
    if (ch1Enabled) {
      final ch1VppPts = <Offset>[];
      final ch1FreqPts = <Offset>[];
      for (final p in points) {
        if (p.ch1Vpp != null) {
          ch1VppPts.add(Offset(
            mapTime(p.elapsedSeconds),
            mapVpp(p.ch1Vpp!),
          ));
        }
        if (p.ch1Freq != null) {
          ch1FreqPts.add(Offset(
            mapTime(p.elapsedSeconds),
            mapFreq(p.ch1Freq!),
          ));
        }
      }
      drawLine(ch1VppPts, _ch1Color, 'CH1 Vpp', dashed: false);
      drawLine(ch1FreqPts, _ch1Color, 'CH1 Freq', dashed: true);
    }

    // Build line segments for CH2 Vpp
    if (ch2Enabled) {
      final ch2VppPts = <Offset>[];
      final ch2FreqPts = <Offset>[];
      for (final p in points) {
        if (p.ch2Vpp != null) {
          ch2VppPts.add(Offset(
            mapTime(p.elapsedSeconds),
            mapVpp(p.ch2Vpp!),
          ));
        }
        if (p.ch2Freq != null) {
          ch2FreqPts.add(Offset(
            mapTime(p.elapsedSeconds),
            mapFreq(p.ch2Freq!),
          ));
        }
      }
      drawLine(ch2VppPts, _ch2Color, 'CH2 Vpp', dashed: false);
      drawLine(ch2FreqPts, _ch2Color, 'CH2 Freq', dashed: true);
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

    // X-axis label (Time)
    textPainter.text = TextSpan(text: 'Time (s)', style: textStyle);
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        plotRect.left + (plotRect.width - textPainter.width) / 2,
        size.height - textPainter.height - 2,
      ),
    );

    // Y-axis tick labels (left: Vpp)
    textPainter.text = TextSpan(
      text: _formatAxisValue(ranges.niceMaxVpp),
      style: textStyle,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(plotRect.left - textPainter.width - 4, plotRect.top - textPainter.height / 2),
    );

    textPainter.text = TextSpan(
      text: _formatAxisValue(ranges.niceMinVpp),
      style: textStyle,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(plotRect.left - textPainter.width - 4, plotRect.bottom - textPainter.height / 2),
    );

    // Y-axis tick labels (right: Freq)
    textPainter.text = TextSpan(
      text: _formatAxisValue(ranges.niceMaxFreq),
      style: textStyle,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(plotRect.right + 4, plotRect.top - textPainter.height / 2),
    );

    textPainter.text = TextSpan(
      text: _formatAxisValue(ranges.niceMinFreq),
      style: textStyle,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(plotRect.right + 4, plotRect.bottom - textPainter.height / 2),
    );

    // X-axis tick labels
    textPainter.text = TextSpan(text: '0', style: textStyle);
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(plotRect.left - textPainter.width / 2, plotRect.bottom + 4),
    );

    textPainter.text = TextSpan(
      text: _formatAxisValue(ranges.niceMaxTime),
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

    if (ch1Enabled) {
      items.add(_LegendItem('CH1 Vpp', _ch1Color, false));
      items.add(_LegendItem('CH1 Freq', _ch1Color, true));
    }
    if (ch2Enabled) {
      items.add(_LegendItem('CH2 Vpp', _ch2Color, false));
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
        oldDelegate.ch1Enabled != ch1Enabled ||
        oldDelegate.ch2Enabled != ch2Enabled ||
        oldDelegate.status != status ||
        oldDelegate.totalDurationSeconds != totalDurationSeconds;
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
