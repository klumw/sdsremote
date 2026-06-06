import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'waveform_models.dart';

class WaveformBasePainter extends CustomPainter {
  final WaveformData? ch1;
  final WaveformData? ch2;
  final WaveformData? ref;          // loaded reference waveform (ghost)
  final bool refVisible;            // whether the reference is visible
  final String? refChannelOrigin;   // 'ch1' or 'ch2' — which channel's V/div to use
  final DeviceParams params;
  final bool ch1Enabled;
  final bool ch2Enabled;
  final ZoomState zoom;

  static const int _hDivisions = 14;
  static const int _vDivisions = 8;

  WaveformBasePainter({
    this.ch1,
    this.ch2,
    this.ref,
    this.refVisible = false,
    this.refChannelOrigin,
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

    final hasRef = refVisible && ref != null && ref!.points.isNotEmpty;
    final hasData = (ch1 != null && ch1!.points.isNotEmpty) ||
        (ch2 != null && ch2!.points.isNotEmpty) ||
        hasRef;

    if (!hasData) {
      _drawGridFallback(canvas, size);
      _drawNoDataHint(canvas, size);
      return;
    }

    // Determine data availability (we still need at least one channel or
    // reference to draw). Also compute a device-centric display time span
    // based on the selected `timebase` and the number of horizontal
    // divisions. This mirrors `CursorPainter` which uses
    // `displaySpan = params.timebase * _hDivisions` so the grid, cursors
    // and waveform mapping all agree with a physical oscilloscope.
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
    if (hasRef) {
      dataTMin = dataTMin < ref!.points.first.$1 ? dataTMin : ref!.points.first.$1;
      dataTMax = dataTMax > ref!.points.last.$1 ? dataTMax : ref!.points.last.$1;
    }
    if (dataTMin == double.infinity) return;

    // Use the device `timebase` multiplied by the horizontal divisions as
    // the canonical display span (time covered by the entire screen at
    // `zoomFactor == 1.0`). This ensures the app shows the same number
    // of cycles as the real oscilloscope for a given timebase setting.
    final double displaySpan = params.timebase * _hDivisions;
    final double centerTime = params.trdl + (zoom.panX - 0.5) * displaySpan;
    final double visibleTSpan = displaySpan / zoom.zoomFactor;
    final double visibleTMin = centerTime - visibleTSpan / 2;
    final double visibleTMax = centerTime + visibleTSpan / 2;

    // Determine the visible voltage range for the grid.
    // Use the first enabled channel with data; prefer CH1 over CH2.
    late final double gridVMin;
    late final double gridVMax;
    if (ch1Enabled && ch1 != null && ch1!.points.isNotEmpty) {
      final double vdiv = params.vdivCh1 ?? 1.0;
      final double voffset = params.voffsetCh1 ?? 0.0;
      final double vMax = voffset + 4 * vdiv;
      final double vMin = voffset - 4 * vdiv;
      final double vRange = vMax - vMin;
      final double centerVoltage = vMin + zoom.panY * vRange;
      final double visibleVRange = vRange / zoom.zoomFactor;
      gridVMin = centerVoltage - visibleVRange / 2;
      gridVMax = centerVoltage + visibleVRange / 2;
    } else {
      final double vdiv = params.vdivCh2 ?? 1.0;
      final double voffset = params.voffsetCh2 ?? 0.0;
      final double vMax = voffset + 4 * vdiv;
      final double vMin = voffset - 4 * vdiv;
      final double vRange = vMax - vMin;
      final double centerVoltage = vMin + zoom.panY * vRange;
      final double visibleVRange = vRange / zoom.zoomFactor;
      gridVMin = centerVoltage - visibleVRange / 2;
      gridVMax = centerVoltage + visibleVRange / 2;
    }

    // Draw zoom/pan-aware grid.
    _drawGrid(canvas, size, visibleTMin, visibleTMax, gridVMin, gridVMax);

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

    // Draw reference waveform as a ghost overlay
    if (hasRef) {
      // Use the voltage range of the channel the reference was loaded from.
      final bool useCh1Range = refChannelOrigin == 'ch1';
      final double vdiv = useCh1Range
          ? (params.vdivCh1 ?? 1.0)
          : (params.vdivCh2 ?? 1.0);
      final double voffset = useCh1Range
          ? (params.voffsetCh1 ?? 0.0)
          : (params.voffsetCh2 ?? 0.0);
      final double vMax = voffset + 4 * vdiv;
      final double vMin = voffset - 4 * vdiv;
      final double vRange = vMax - vMin;
      final double centerVoltage = vMin + zoom.panY * vRange;
      final double visibleVRange = vRange / zoom.zoomFactor;
      final double visibleVMinRef = centerVoltage - visibleVRange / 2;
      final double visibleVMaxRef = centerVoltage + visibleVRange / 2;
      _drawWaveform(canvas, size, ref!, Colors.white.withAlpha(80),
          visibleTMin, visibleTMax, visibleVMinRef, visibleVMaxRef,
          strokeWidth: 1.0);
    }
  }

  /// Draw the grid scaled to the visible time/voltage range.
  ///
  /// The grid always draws exactly [_hDivisions] horizontal and [_vDivisions]
  /// vertical cells using the exact visible range divided by the division
  /// count. Since the widget is constrained to aspectRatio: 14/8 (see
  /// [main.dart]), this guarantees perfectly square grid cells at any
  /// zoom/pan level — like a real oscilloscope graticule.
  ///
  /// Minor sub-division lines (1/5 of the main interval) provide finer
  /// detail when zoomed in.
  void _drawGrid(Canvas canvas, Size size,
      double visibleTMin, double visibleTMax,
      double visibleVMin, double visibleVMax) {
    final double visibleTRange = visibleTMax - visibleTMin;
    final double visibleVRange = visibleVMax - visibleVMin;
    if (visibleTRange <= 0 || visibleVRange <= 0) return;

    // Use exact divisions to guarantee exactly _hDivisions × _vDivisions
    // grid cells. Since the widget is constrained to aspectRatio: 14/8,
    // this produces perfectly square grid cells at any zoom/pan level.
    final double tMajorInterval = visibleTRange / _hDivisions;
    final double vMajorInterval = visibleVRange / _vDivisions;
    final double tMinorInterval = tMajorInterval / 5.0;
    final double vMinorInterval = vMajorInterval / 5.0;

    // Helper: map time → pixel X, voltage → pixel Y.
    double timeToPx(double t) =>
        (t - visibleTMin) / visibleTRange * size.width;
    double voltageToPy(double v) =>
        (visibleVMax - v) / visibleVRange * size.height;

    // --- Minor grid lines (sub-divisions at 1/5 of major interval) ---
    final Paint minorPaint = Paint()
      ..color = Colors.white.withAlpha(30)
      ..strokeWidth = 0.5
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;

    // Find the first minor line inside the visible range.
    final double tMinorStart = (visibleTMin / tMinorInterval).ceil() * tMinorInterval;
    for (double t = tMinorStart; t <= visibleTMax; t += tMinorInterval) {
      // Skip positions that fall on a major line.
      final double remainder = (t / tMajorInterval).roundToDouble();
      if ((t - remainder * tMajorInterval).abs() < tMinorInterval * 0.01) continue;
      final double x = timeToPx(t);
      if (x >= 0 && x <= size.width) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), minorPaint);
      }
    }

    final double vMinorStart = (visibleVMin / vMinorInterval).ceil() * vMinorInterval;
    for (double v = vMinorStart; v <= visibleVMax; v += vMinorInterval) {
      final double remainder = (v / vMajorInterval).roundToDouble();
      if ((v - remainder * vMajorInterval).abs() < vMinorInterval * 0.01) continue;
      final double y = voltageToPy(v);
      if (y >= 0 && y <= size.height) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), minorPaint);
      }
    }

    // --- Major grid lines ---
    final Paint majorPaint = Paint()
      ..color = Colors.white.withAlpha(77)
      ..strokeWidth = 1.0
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;

    // Vertical major lines (time divisions at nice intervals)
    final double tMajorStart = (visibleTMin / tMajorInterval).ceil() * tMajorInterval;
    for (double t = tMajorStart; t <= visibleTMax; t += tMajorInterval) {
      final double x = timeToPx(t);
      if (x >= 0 && x <= size.width) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), majorPaint);
      }
    }

    // Horizontal major lines (voltage divisions at nice intervals)
    final double vMajorStart = (visibleVMin / vMajorInterval).ceil() * vMajorInterval;
    for (double v = vMajorStart; v <= visibleVMax; v += vMajorInterval) {
      final double y = voltageToPy(v);
      if (y >= 0 && y <= size.height) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), majorPaint);
      }
    }

    // --- Center crosshair (slightly brighter) ---
    final Paint centerPaint = Paint()
      ..color = Colors.white.withAlpha(120)
      ..strokeWidth = 1.0
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke;

    // Horizontal center line at 0 V
    const double centerV = 0.0;
    if (centerV >= visibleVMin && centerV <= visibleVMax) {
      final double cy = voltageToPy(centerV);
      canvas.drawLine(Offset(0, cy), Offset(size.width, cy), centerPaint);
    }

    // Vertical center line at t=0 (trigger point)
    const double centerT = 0.0;
    if (centerT >= visibleTMin && centerT <= visibleTMax) {
      final double cx = timeToPx(centerT);
      canvas.drawLine(Offset(cx, 0), Offset(cx, size.height), centerPaint);
    }
  }

  /// Fallback grid drawn when no waveform data is available.
  /// Keeps the original static behaviour.
  void _drawGridFallback(Canvas canvas, Size size) {
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
      double visibleVMin, double visibleVMax, {
      double strokeWidth = 1.5,
    }) {
    if (data.points.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final visibleTRange = visibleTMax - visibleTMin;
    final visibleVRange = visibleVMax - visibleVMin;
    if (visibleTRange <= 0 || visibleVRange <= 0) return;

    // Check the time span of the data itself. If the acquired/loaded data
    // covers a much smaller time window than the visible range (for
    // example due to missing trigger/sample metadata or a mismatch between
    // sample timing and display timebase), the waveform can appear bunched
    // into one small area of the graticule. As a robust fallback, when the
    // data time range is significantly smaller than the visible range,
    // distribute points evenly across the visible time range so the
    // waveform fills the full 14 divisions (preserving relative order).
    final dataTFirst = data.points.first.$1;
    final dataTLast = data.points.last.$1;
    final dataTRange = dataTLast - dataTFirst;
    final bool expandToDisplay = dataTRange <= 0 || dataTRange < visibleTRange * 0.25;

    // Restrict waveform drawing to the grid area to prevent
    // overflow beyond the grid when zoom factor > 1.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    bool first = true;
    if (expandToDisplay) {
      // Evenly spread points across the visible span.
      final int n = data.points.length;
      for (int i = 0; i < n; i++) {
        final point = data.points[i];
        final double rel = n == 1 ? 0.0 : i / (n - 1);
        final double px = rel * size.width;
        final double py = (visibleVMax - point.$2) / visibleVRange * size.height;
        if (first) {
          path.moveTo(px, py);
          first = false;
        } else {
          path.lineTo(px, py);
        }
      }
    } else {
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
        oldDelegate.ref != ref ||
        oldDelegate.refVisible != refVisible ||
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
