import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'waveform_models.dart';

class WaveformBasePainter extends CustomPainter {
  final WaveformData? ch1;
  final WaveformData? ch2;
  final DeviceParams params;
  final bool ch1Enabled;
  final bool ch2Enabled;
  final ZoomState zoom;

  static const int _hDivisions = 14;
  static const int _vDivisions = 8;

  WaveformBasePainter({
    this.ch1,
    this.ch2,
    required this.params,
    this.ch1Enabled = true,
    this.ch2Enabled = true,
    this.zoom = const ZoomState(),
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fill background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0A192F),
    );

    _drawGrid(canvas, size);

    final hasData = (ch1 != null && ch1!.points.isNotEmpty) ||
        (ch2 != null && ch2!.points.isNotEmpty);

    if (!hasData) {
      _drawNoDataHint(canvas, size);
      return;
    }

    // Determine the full data time range from available channel data.
    double dataTMin = double.infinity;
    double dataTMax = double.negativeInfinity;
    if (ch1 != null && ch1!.points.isNotEmpty) {
      dataTMin = ch1!.points.first.$1;
      dataTMax = ch1!.points.last.$1;
    }
    if (ch2 != null && ch2!.points.isNotEmpty) {
      dataTMin = dataTMin < ch2!.points.first.$1 ? dataTMin : ch2!.points.first.$1;
      dataTMax = dataTMax > ch2!.points.last.$1 ? dataTMax : ch2!.points.last.$1;
    }
    if (dataTMin == double.infinity) return;

    final double dataTRange = dataTMax - dataTMin;
    if (dataTRange <= 0) return;

    // At zoom 1.0, the full data range fills the entire widget width
    // (original behavior). At zoom > 1.0, we zoom into the data centered
    // around the panX position.
    final double centerTime = dataTMin + zoom.panX * dataTRange;
    final double visibleTSpan = dataTRange / zoom.zoomFactor;
    final double visibleTMin = centerTime - visibleTSpan / 2;
    final double visibleTMax = centerTime + visibleTSpan / 2;

    if (ch1Enabled && ch1 != null && ch1!.points.isNotEmpty) {
      final double vdiv = params.vdivCh1 ?? 1.0;
      final double voffset = params.voffsetCh1 ?? 0.0;
      final double vMax = voffset + 4 * vdiv;
      final double vMin = voffset - 4 * vdiv;
      final double vRange = vMax - vMin;
      final double centerVoltage = vMin + zoom.panY * vRange;
      final double visibleVRange = vRange / zoom.zoomFactor;
      final double visibleVMin = centerVoltage - visibleVRange / 2;
      final double visibleVMax = centerVoltage + visibleVRange / 2;
      _drawWaveform(canvas, size, ch1!, Colors.yellow,
          visibleTMin, visibleTMax, visibleVMin, visibleVMax);
    }

    if (ch2Enabled && ch2 != null && ch2!.points.isNotEmpty) {
      final double vdiv = params.vdivCh2 ?? 1.0;
      final double voffset = params.voffsetCh2 ?? 0.0;
      final double vMax = voffset + 4 * vdiv;
      final double vMin = voffset - 4 * vdiv;
      final double vRange = vMax - vMin;
      final double centerVoltage = vMin + zoom.panY * vRange;
      final double visibleVRange = vRange / zoom.zoomFactor;
      final double visibleVMin = centerVoltage - visibleVRange / 2;
      final double visibleVMax = centerVoltage + visibleVRange / 2;
      _drawWaveform(canvas, size, ch2!, const Color(0xFFFF20FF),
          visibleTMin, visibleTMax, visibleVMin, visibleVMax);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withAlpha(77)
      ..strokeWidth = 1.0
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;

    for (int i = 0; i <= _vDivisions; i++) {
      final y = size.height * i / _vDivisions;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    for (int i = 0; i <= _hDivisions; i++) {
      final x = size.width * i / _hDivisions;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _drawWaveform(Canvas canvas, Size size, WaveformData data,
      Color color,
      double visibleTMin, double visibleTMax,
      double visibleVMin, double visibleVMax) {
    if (data.points.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final visibleTRange = visibleTMax - visibleTMin;
    final visibleVRange = visibleVMax - visibleVMin;
    if (visibleTRange <= 0 || visibleVRange <= 0) return;

    // Restrict waveform drawing to the grid area to prevent
    // overflow beyond the grid when zoom factor > 1.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    bool first = true;
    for (final point in data.points) {
      if (point.$1 < visibleTMin || point.$1 > visibleTMax) continue;
      final px = (point.$1 - visibleTMin) / visibleTRange * size.width;
      final py = (visibleVMax - point.$2) / visibleVRange * size.height;
      if (first) {
        path.moveTo(px, py);
        first = false;
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  void _drawNoDataHint(Canvas canvas, Size size) {
    const text = 'No waveform data';
    final textPainter = TextPainter(
      text: const TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white54,
          fontSize: 16,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final offset = Offset(
      (size.width - textPainter.width) / 2,
      (size.height - textPainter.height) / 2,
    );
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(WaveformBasePainter oldDelegate) {
    return oldDelegate.ch1 != ch1 ||
        oldDelegate.ch2 != ch2 ||
        oldDelegate.params != params ||
        oldDelegate.ch1Enabled != ch1Enabled ||
        oldDelegate.ch2Enabled != ch2Enabled ||
        oldDelegate.zoom != zoom;
  }
}

class CursorPainter extends CustomPainter {
  final CursorState cursors;
  final DeviceParams params;
  final ZoomState zoom;
  final double? dataTMin;
  final double? dataTMax;

  static const int _hDivisions = 14;

  CursorPainter({
    required this.cursors,
    required this.params,
    this.zoom = const ZoomState(),
    this.dataTMin,
    this.dataTMax,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawCursors(canvas, size, cursors);
    if (cursors.cursorsXEnabled || cursors.cursorsYEnabled) {
      _drawCursorInfoPanel(canvas, size, cursors);
    }
  }

  void _drawCursors(Canvas canvas, Size size, CursorState cursors) {
    if (cursors.cursorsXEnabled) {
      _drawDashedLine(
        canvas,
        Offset(size.width * cursors.cursorX1, 0),
        Offset(size.width * cursors.cursorX1, size.height),
        Paint()
          ..color = Colors.cyanAccent
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
        6.0,
        4.0,
      );
      _drawDashedLine(
        canvas,
        Offset(size.width * cursors.cursorX2, 0),
        Offset(size.width * cursors.cursorX2, size.height),
        Paint()
          ..color = Colors.cyanAccent
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
        6.0,
        4.0,
      );
    }

    if (cursors.cursorsYEnabled) {
      _drawDashedLine(
        canvas,
        Offset(0, size.height * cursors.cursorY1),
        Offset(size.width, size.height * cursors.cursorY1),
        Paint()
          ..color = Colors.orangeAccent
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
        6.0,
        4.0,
      );
      _drawDashedLine(
        canvas,
        Offset(0, size.height * cursors.cursorY2),
        Offset(size.width, size.height * cursors.cursorY2),
        Paint()
          ..color = Colors.orangeAccent
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
        6.0,
        4.0,
      );
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset p1,
    Offset p2,
    Paint paint,
    double dashLength,
    double gapLength,
  ) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final totalLength = math.sqrt(dx * dx + dy * dy);
    if (totalLength == 0) return;

    final unitX = dx / totalLength;
    final unitY = dy / totalLength;

    double drawn = 0;
    bool drawingDash = true;

    while (drawn < totalLength) {
      final segmentLength = drawingDash ? dashLength : gapLength;
      final remaining = totalLength - drawn;
      final actualLength = segmentLength < remaining ? segmentLength : remaining;

      if (drawingDash) {
        canvas.drawLine(
          Offset(p1.dx + unitX * drawn, p1.dy + unitY * drawn),
          Offset(p1.dx + unitX * (drawn + actualLength), p1.dy + unitY * (drawn + actualLength)),
          paint,
        );
      }

      drawn += actualLength;
      drawingDash = !drawingDash;
    }
  }

  double _timeAtX(double relX) {
    // Cursor time values must be consistent with WaveformBasePainter,
    // which uses the screen time span (timebase * 14 divisions) as its basis.
    final double displaySpan = params.timebase * _hDivisions;
    final double centerTime = params.trdl + (zoom.panX - 0.5) * displaySpan;
    final double zoomedSpan = displaySpan / zoom.zoomFactor;
    return centerTime + (relX - 0.5) * zoomedSpan;
  }

  void _drawCursorInfoPanel(Canvas canvas, Size size, CursorState cursors) {
    final double vdiv = params.vdivCh1 ?? 1.0;
    final double voffset = params.voffsetCh1 ?? 0.0;

    double voltageAtY(double relY) {
      final vMax = voffset + 4 * vdiv;
      final vMin = voffset - 4 * vdiv;
      final vRange = vMax - vMin;
      final centerVoltage = vMin + zoom.panY * vRange;
      final zoomedRange = vRange / zoom.zoomFactor;
      return (centerVoltage + zoomedRange / 2) - relY * zoomedRange;
    }

    final yV1 = cursors.cursorsYEnabled ? voltageAtY(cursors.cursorY1) : null;
    final yV2 = cursors.cursorsYEnabled ? voltageAtY(cursors.cursorY2) : null;
    final yDelta = (yV1 != null && yV2 != null) ? (yV1 - yV2).abs() : null;

    double? timeDelta;
    double? frequency;
    if (cursors.cursorsXEnabled) {
      final t1 = _timeAtX(cursors.cursorX1);
      final t2 = _timeAtX(cursors.cursorX2);
      timeDelta = (t2 - t1).abs();
      if (timeDelta > 0) {
        frequency = 1.0 / timeDelta;
      }
    }

    String fmtVoltage(double v) {
      final abs = v.abs();
      double scaled;
      String prefix;
      if (abs >= 1e3) {
        scaled = v / 1e3;
        prefix = 'k';
      } else if (abs >= 1) {
        scaled = v;
        prefix = '';
      } else if (abs >= 1e-3) {
        scaled = v * 1e3;
        prefix = 'm';
      } else if (abs >= 1e-6) {
        scaled = v * 1e6;
        prefix = 'µ';
      } else {
        scaled = v * 1e9;
        prefix = 'n';
      }
      String s = scaled.toStringAsFixed(3);
      if (s.contains('.')) {
        s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      }
      return '$s ${prefix}V';
    }

    String fmtFrequency(double f) {
      final abs = f.abs();
      double scaled;
      String prefix;
      if (abs >= 1e9) {
        scaled = f / 1e9;
        prefix = 'G';
      } else if (abs >= 1e6) {
        scaled = f / 1e6;
        prefix = 'M';
      } else if (abs >= 1e3) {
        scaled = f / 1e3;
        prefix = 'k';
      } else if (abs >= 1) {
        scaled = f;
        prefix = '';
      } else if (abs >= 1e-3) {
        scaled = f * 1e3;
        prefix = 'm';
      } else {
        scaled = f * 1e6;
        prefix = 'µ';
      }
      String s = scaled.toStringAsFixed(3);
      if (s.contains('.')) {
        s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      }
      return '$s ${prefix}Hz';
    }

    String fmtTime(double t) {
      final abs = t.abs();
      double scaled;
      String prefix;
      if (abs >= 1) {
        scaled = t;
        prefix = 's';
      } else if (abs >= 1e-3) {
        scaled = t * 1e3;
        prefix = 'ms';
      } else if (abs >= 1e-6) {
        scaled = t * 1e6;
        prefix = 'µs';
      } else {
        scaled = t * 1e9;
        prefix = 'ns';
      }
      String s = scaled.toStringAsFixed(3);
      if (s.contains('.')) {
        s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      }
      return '$s $prefix';
    }

    const double panelWidth = 200.0;
    const double panelPadding = 12.0;
    const double rowHeight = 20.0;
    const double headerHeight = 24.0;
    const double sectionGap = 8.0;
    final int yRows = cursors.cursorsYEnabled ? 3 : 0;
    final int xRows = cursors.cursorsXEnabled ? 2 : 0;
    final double sectionsGap = (yRows > 0 && xRows > 0) ? sectionGap : 0;
    final double panelHeight = headerHeight +
        (yRows + xRows) * rowHeight +
        sectionsGap +
        panelPadding * 2;

    final double panelX = size.width - panelWidth - 12 + cursors.cursorInfoOffset.dx;
    final double panelY = 12 + cursors.cursorInfoOffset.dy;

    final bgPaint = Paint()
      ..color = const Color(0xCC0D1117)
      ..style = PaintingStyle.fill;
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(panelX, panelY, panelWidth, panelHeight),
      const Radius.circular(8),
    );
    canvas.drawRRect(bgRect, bgPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF475569)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(bgRect, borderPaint);

    double curY = panelY + panelPadding;

    void drawRow(String label, String value, Color labelColor, Color valueColor) {
      final labelPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final valuePainter = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: valueColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      labelPainter.paint(canvas, Offset(panelX + panelPadding, curY));
      valuePainter.paint(
        canvas,
        Offset(panelX + panelWidth - panelPadding - valuePainter.width, curY),
      );
      curY += rowHeight;
    }

    final headerPainter = TextPainter(
      text: const TextSpan(
        text: 'Cursor Info',
        style: TextStyle(
          color: Colors.blueAccent,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    headerPainter.paint(canvas, Offset(panelX + panelPadding, curY));
    curY += headerHeight;

    if (cursors.cursorsYEnabled) {
      drawRow('Y1:', fmtVoltage(yV1!), Colors.orangeAccent, Colors.orangeAccent);
      drawRow('Y2:', fmtVoltage(yV2!), Colors.orangeAccent, Colors.orangeAccent);
      drawRow('ΔY:', fmtVoltage(yDelta!), Colors.white70, Colors.yellowAccent);
      curY += sectionGap;
    }

    if (cursors.cursorsXEnabled) {
      drawRow(
        'Δt:',
        timeDelta != null ? fmtTime(timeDelta) : '---',
        Colors.cyanAccent,
        Colors.cyanAccent,
      );
      drawRow(
        'Freq:',
        frequency != null ? fmtFrequency(frequency) : '---',
        Colors.white70,
        Colors.yellowAccent,
      );
    }
  }

  @override
  bool shouldRepaint(CursorPainter oldDelegate) {
    return oldDelegate.cursors != cursors ||
        oldDelegate.params != params ||
        oldDelegate.zoom != zoom ||
        oldDelegate.dataTMin != dataTMin ||
        oldDelegate.dataTMax != dataTMax;
  }
}
