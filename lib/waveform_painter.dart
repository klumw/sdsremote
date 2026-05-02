import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'waveform_models.dart';

class WaveformBasePainter extends CustomPainter {
  final WaveformData? ch1;
  final WaveformData? ch2;
  final DeviceParams params;
  final bool ch1Enabled;
  final bool ch2Enabled;

  static const int _hDivisions = 14; 
  static const int _vDivisions = 8; 

  WaveformBasePainter({
    this.ch1,
    this.ch2,
    required this.params,
    this.ch1Enabled = true,
    this.ch2Enabled = true,
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

    if (ch1Enabled && ch1 != null && ch1!.points.isNotEmpty) {
      _drawWaveform(canvas, size, ch1!, Colors.yellow,
          params.vdivCh1 ?? 1.0, params.voffsetCh1 ?? 0.0);
    }

    if (ch2Enabled && ch2 != null && ch2!.points.isNotEmpty) {
      _drawWaveform(canvas, size, ch2!, const Color(0xFFFF20FF),
          params.vdivCh2 ?? 1.0, params.voffsetCh2 ?? 0.0);
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
      Color color, double vdiv, double voffset) {
    if (data.points.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final tMin = data.points.first.$1;
    final tMax = data.points.last.$1;
    final tRange = tMax - tMin;

    final vMax = voffset + 4 * vdiv;
    final vMin = voffset - 4 * vdiv;
    final vRange = vMax - vMin;

    final path = Path();
    bool first = true;
    for (final point in data.points) {
      final px = tRange > 0 ? (point.$1 - tMin) / tRange * size.width : size.width / 2;
      final py = vRange > 0 ? (vMax - point.$2) / vRange * size.height : size.height / 2;
      if (first) {
        path.moveTo(px, py);
        first = false;
      } else {
        path.lineTo(px, py);
      }
    }
    canvas.drawPath(path, paint);
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
        oldDelegate.ch2Enabled != ch2Enabled;
  }
}

class CursorPainter extends CustomPainter {
  final CursorState cursors;
  final DeviceParams params;

  static const int _hDivisions = 14;

  CursorPainter({
    required this.cursors,
    required this.params,
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
    final displaySpan = params.timebase * _hDivisions;
    return params.trdl + (relX - 0.5) * displaySpan;
  }

  void _drawCursorInfoPanel(Canvas canvas, Size size, CursorState cursors) {
    final double vdiv = params.vdivCh1 ?? 1.0;
    final double voffset = params.voffsetCh1 ?? 0.0;

    double voltageAtY(double relY) {
      final vMax = voffset + 4 * vdiv;
      final vMin = voffset - 4 * vdiv;
      final vRange = vMax - vMin;
      return vMax - relY * vRange;
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
    return oldDelegate.cursors != cursors || oldDelegate.params != params;
  }
}
