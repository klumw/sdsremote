import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../spectrum/spectrum_models.dart';
import '../waveform/waveform_models.dart' show waveformChannelColor;

/// Formats a frequency for the spectrum axes and labels.
String formatSpectrumFrequency(double hz) {
  if (!hz.isFinite) return '-';
  final abs = hz.abs();
  if (abs >= 1e9) return '${(hz / 1e9).toStringAsFixed(2)} GHz';
  if (abs >= 1e6) return '${(hz / 1e6).toStringAsFixed(2)} MHz';
  if (abs >= 1e3) return '${(hz / 1e3).toStringAsFixed(2)} kHz';
  return '${hz.toStringAsFixed(0)} Hz';
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
  });

  final SpectrumResult? result;
  final String detailChannel;

  /// Draws every acquired trace; when false only [detailChannel] is drawn.
  final bool showAllChannels;

  final bool logFrequency;

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

    const double left = 50;
    const double right = 12;
    const double top = 12;
    const double bottom = 28;
    final plot = Rect.fromLTWH(
      left,
      top,
      size.width - left - right,
      size.height - top - bottom,
    );
    if (plot.width < 20 || plot.height < 20) return;

    final nyquist = traces
        .map((trace) => trace.sampleRate / 2)
        .reduce(math.max);
    final minPositive = _minPositiveFrequency(traces);
    final useLog = logFrequency && minPositive > 0 && nyquist > minPositive;
    final xMin = useLog ? minPositive : 0.0;
    final xMax = nyquist;
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
      _drawTrace(canvas, plot, trace, mapX, mapY);
    }

    if (detail != null) {
      _drawPeakMarkers(canvas, plot, detail, mapX, mapY);
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
          text: formatSpectrumFrequency(frequency),
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
  ) {
    final path = Path();
    var started = false;
    for (var i = 0; i < trace.dbfs.length; i++) {
      final frequency = trace.frequenciesHz[i];
      if (logFrequency && frequency <= 0) continue;
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
  ) {
    final color = waveformChannelColor(trace.channel);
    final linePaint = Paint()
      ..color = color.withAlpha(120)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()..color = color;

    for (final peak in trace.peaks) {
      final x = mapX(peak.frequencyHz);
      final y = mapY(peak.dbfs);
      canvas.save();
      canvas.clipRect(plot);
      canvas.drawLine(Offset(x, y), Offset(x, plot.bottom), linePaint);
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
      canvas.restore();

      final label = TextPainter(
        text: TextSpan(
          text: '${peak.marker}  ${formatSpectrumFrequency(peak.frequencyHz)}',
          style: TextStyle(color: color, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (x - label.width / 2).clamp(
        plot.left,
        plot.right - label.width,
      );
      final dy = (y - label.height - 4).clamp(
        plot.top,
        plot.bottom - label.height,
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

  double _minPositiveFrequency(List<SpectrumTrace> traces) {
    var min = double.infinity;
    for (final trace in traces) {
      for (final frequency in trace.frequenciesHz) {
        if (frequency > 0 && frequency < min) min = frequency;
      }
    }
    return min.isFinite ? min : 1;
  }

  @override
  bool shouldRepaint(SpectrumPainter oldDelegate) =>
      oldDelegate.result != result ||
      oldDelegate.detailChannel != detailChannel ||
      oldDelegate.showAllChannels != showAllChannels ||
      oldDelegate.logFrequency != logFrequency;
}
