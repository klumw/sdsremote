import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../spectrum/spectrum_models.dart';
import '../spectrum/spectrum_viewport.dart';
import '../waveform/waveform_models.dart' show waveformChannelColor;

/// Plot insets shared by the painter and the interactive spectrum view.
const double spectrumPlotLeftPadding = 50;
const double spectrumPlotRightPadding = 12;
const double spectrumPlotTopPadding = 12;
const double spectrumPlotBottomPadding = 28;

/// Formats a frequency for the spectrum axes and labels.
String formatSpectrumFrequency(double hz) {
  if (!hz.isFinite) return '-';
  final abs = hz.abs();
  if (abs >= 1e9) return '${(hz / 1e9).toStringAsFixed(2)} GHz';
  if (abs >= 1e6) return '${(hz / 1e6).toStringAsFixed(2)} MHz';
  if (abs >= 1e3) return '${(hz / 1e3).toStringAsFixed(2)} kHz';
  return '${hz.toStringAsFixed(0)} Hz';
}

/// Frequency label with enough decimals for a zoomed axis of [span] hertz.
String formatSpectrumFrequencyForSpan(double hz, double span) {
  if (!hz.isFinite) return '-';
  if (span.isFinite && span > 0 && span < 1e3) {
    return '${hz.toStringAsFixed(2)} Hz';
  }
  if (span.isFinite && span > 0 && span < 1e6) {
    final digits = span < 1e4 ? 3 : 2;
    return '${(hz / 1e3).toStringAsFixed(digits)} kHz';
  }
  if (span.isFinite && span > 0 && span < 1e9) {
    final digits = span < 1e7 ? 3 : 2;
    return '${(hz / 1e6).toStringAsFixed(digits)} MHz';
  }
  return formatSpectrumFrequency(hz);
}

/// Short label of a spectrum level unit (`dBFS`, `dBV`, `dBm`).
String spectrumUnitLabel(SpectrumUnit unit) => switch (unit) {
  SpectrumUnit.dbfs => 'dBFS',
  SpectrumUnit.dbv => 'dBV',
  SpectrumUnit.dbm50 => 'dBm',
};

/// Paints the overlaid spectra, grid, axis labels and peak markers.
class SpectrumPainter extends CustomPainter {
  SpectrumPainter({
    required this.result,
    required this.detailChannel,
    required this.showAllChannels,
    required this.logFrequency,
    this.viewport = const SpectrumViewport(),
  });

  final SpectrumResult? result;
  final String detailChannel;

  /// Draws every acquired trace; when false only [detailChannel] is drawn.
  final bool showAllChannels;

  final bool logFrequency;

  /// Horizontal zoom and pan state.
  final SpectrumViewport viewport;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppColors.panelBackground,
    );

    final allTraces = result?.traces ?? const <SpectrumTrace>[];
    if (allTraces.isEmpty) return;
    final detail = result!.traceFor(detailChannel);
    final traces = showAllChannels ? allTraces : <SpectrumTrace>[?detail];
    if (traces.isEmpty) return;

    const double left = spectrumPlotLeftPadding;
    const double right = spectrumPlotRightPadding;
    const double top = spectrumPlotTopPadding;
    const double bottom = spectrumPlotBottomPadding;
    final plot = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );
    if (plot.width < 20 || plot.height < 20) return;

    final axis = spectrumAxisRange(traces, logFrequency);
    if (!axis.isValid) return;
    final (xMin, xMax) = viewport.visibleRange(
      fullMin: axis.min,
      fullMax: axis.max,
      log: axis.log,
    );
    final useLog = axis.log;
    if (xMax <= xMin) return;

    var maxDb = -200.0;
    for (final trace in traces) {
      for (final value in trace.dbfs) {
        if (value.isFinite && value > maxDb) maxDb = value;
      }
    }
    var yMax = maxDb.isFinite ? (maxDb / 10).ceil() * 10.0 : 0.0;
    if (yMax < -150) yMax = 0;
    var yMin = yMax - 120;
    if (yMin < -160) yMin = -160;
    if (yMax <= yMin) yMax = yMin + 10;

    double mapX(double frequency) {
      if (useLog) {
        final logMin = math.log(xMin);
        final logMax = math.log(xMax);
        return plot.left +
            (math.log(math.max(frequency, xMin)) - logMin) /
                (logMax - logMin) *
                plot.width;
      }
      return plot.left + (frequency - xMin) / (xMax - xMin) * plot.width;
    }

    double mapY(double db) {
      final clamped = db < yMin ? yMin : (db > yMax ? yMax : db);
      return plot.top + (yMax - clamped) / (yMax - yMin) * plot.height;
    }

    _drawGrid(canvas, plot, xMin, xMax, yMin, yMax, useLog, mapX, mapY);

    for (final trace in traces) {
      _drawTrace(canvas, plot, trace, mapX, mapY, useLog);
    }

    // Draw the peak markers of every displayed trace. In "All channels" mode
    // this includes CH1, CH2, …; with a single selected channel [traces]
    // contains only that channel.
    for (final trace in traces) {
      _drawPeakMarkers(canvas, plot, trace, mapX, mapY, xMin, xMax);
    }
    _drawLegend(canvas, plot, traces);
  }

  void _drawGrid(
    Canvas canvas,
    Rect plot,
    double xMin,
    double xMax,
    double yMin,
    double yMax,
    bool useLog,
    double Function(double) mapX,
    double Function(double) mapY,
  ) {
    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(24)
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;
    final axisPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const labelStyle = TextStyle(color: Colors.white54, fontSize: 10);

    for (final frequency in _frequencyTicks(xMin, xMax, useLog)) {
      final x = mapX(frequency);
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
      final text = TextPainter(
        text: TextSpan(
          text: formatSpectrumFrequencyForSpan(frequency, xMax - xMin),
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (x - text.width / 2).clamp(plot.left, plot.right - text.width);
      text.paint(canvas, Offset(dx, plot.bottom + 5));
    }

    for (var i = 0; i <= 4; i++) {
      final db = yMin + (yMax - yMin) * i / 4;
      final y = mapY(db);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final text = TextPainter(
        text: TextSpan(text: db.toStringAsFixed(0), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(
        canvas,
        Offset(plot.left - 6 - text.width, y - text.height / 2),
      );
    }

    canvas.drawRect(plot, axisPaint);

    final unitText = TextPainter(
      text: TextSpan(
        text: spectrumUnitLabel(result!.settings.unit),
        style: labelStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    unitText.paint(canvas, Offset(4, plot.top - unitText.height - 2));
  }

  void _drawTrace(
    Canvas canvas,
    Rect plot,
    SpectrumTrace trace,
    double Function(double) mapX,
    double Function(double) mapY,
    bool useLog,
  ) {
    final path = Path();
    var started = false;
    for (var i = 0; i < trace.dbfs.length; i++) {
      final frequency = trace.frequenciesHz[i];
      if (useLog && frequency <= 0) continue;
      final value = trace.dbfs[i];
      if (!value.isFinite) continue;
      final x = mapX(frequency);
      final y = mapY(value);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    if (!started) return;

    final paint = Paint()
      ..color = waveformChannelColor(trace.channel)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    canvas.save();
    canvas.clipRect(plot);
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _drawPeakMarkers(
    Canvas canvas,
    Rect plot,
    SpectrumTrace trace,
    double Function(double) mapX,
    double Function(double) mapY,
    double xMin,
    double xMax,
  ) {
    // The marker line sits on a black backing so it separates from the trace;
    // the label text and the dot use the channel colour (yellow for CH1).
    final color = waveformChannelColor(trace.channel);
    final lineBackgroundPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.85)
      ..strokeWidth = 2.8
      ..style = PaintingStyle.stroke;
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final dotOutlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.9);
    final dotPaint = Paint()..color = color;

    for (final peak in trace.peaks) {
      if (peak.frequencyHz < xMin || peak.frequencyHz > xMax) continue;
      final x = mapX(peak.frequencyHz);
      final y = mapY(peak.dbfs);
      canvas.save();
      canvas.clipRect(plot);
      canvas.drawLine(
        Offset(x, y),
        Offset(x, plot.bottom),
        lineBackgroundPaint,
      );
      canvas.drawLine(Offset(x, y), Offset(x, plot.bottom), linePaint);
      canvas.drawCircle(Offset(x, y), 3.6, dotOutlinePaint);
      canvas.drawCircle(Offset(x, y), 2.4, dotPaint);
      canvas.restore();

      final label = TextPainter(
        text: TextSpan(
          text: '${peak.marker}  ${formatSpectrumFrequency(peak.frequencyHz)}',
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (x - label.width / 2).clamp(
        plot.left + 3,
        plot.right - label.width - 3,
      );
      final dy = (y - label.height - 4).clamp(
        plot.top + 1,
        plot.bottom - label.height - 1,
      );
      final background = RRect.fromRectAndRadius(
        Rect.fromLTWH(dx - 3, dy - 1, label.width + 6, label.height + 2),
        const Radius.circular(2),
      );
      canvas.drawRRect(
        background,
        Paint()..color = Colors.black.withValues(alpha: 0.7),
      );
      label.paint(canvas, Offset(dx, dy));
    }
  }

  void _drawLegend(Canvas canvas, Rect plot, List<SpectrumTrace> traces) {
    var x = plot.left + 6;
    for (final trace in traces) {
      final color = waveformChannelColor(trace.channel);
      canvas.drawCircle(Offset(x + 3, plot.top + 6), 3, Paint()..color = color);
      final text = TextPainter(
        text: TextSpan(
          text: trace.channel.toUpperCase(),
          style: TextStyle(color: color, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(x + 10, plot.top));
      x += 14 + text.width;
    }
  }

  List<double> _frequencyTicks(double xMin, double xMax, bool useLog) {
    if (xMax <= xMin) return const [];
    if (!useLog) {
      return [for (var i = 0; i <= 4; i++) xMin + (xMax - xMin) * i / 4];
    }
    final ticks = <double>[];
    var decade = math.pow(10, (math.log(xMin) / math.ln10).floor()).toDouble();
    while (decade <= xMax * 1.001) {
      for (final multiplier in const [1.0, 2.0, 5.0]) {
        final frequency = decade * multiplier;
        if (frequency >= xMin * 0.999 && frequency <= xMax * 1.001) {
          ticks.add(frequency);
        }
      }
      decade *= 10;
    }
    if (ticks.length < 3) {
      return [for (var i = 0; i <= 4; i++) xMin + (xMax - xMin) * i / 4];
    }
    return ticks;
  }

  @override
  bool shouldRepaint(SpectrumPainter oldDelegate) =>
      oldDelegate.result != result ||
      oldDelegate.detailChannel != detailChannel ||
      oldDelegate.showAllChannels != showAllChannels ||
      oldDelegate.logFrequency != logFrequency ||
      oldDelegate.viewport != viewport;
}
