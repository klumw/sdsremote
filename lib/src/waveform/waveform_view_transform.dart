import 'dart:ui' show Size;

import 'waveform_models.dart';

/// Maps between the pixels of the waveform display area and the signal domain.
///
/// The display shows the instrument's graticule — [_hDivisions] horizontal and
/// [_vDivisions] vertical divisions — scaled by [ZoomState]. The mapping is
/// needed both for drawing and for turning pointer movement into a signal
/// shift; keeping it in one place is what makes a dragged reference follow the
/// pointer exactly, at any zoom and pan position, instead of by a separately
/// derived approximation.
///
/// The conversion is offered in device divisions, the unit [ReferenceOffset]
/// is stored in, so callers never have to re-derive the timebase or V/div
/// scaling themselves.
class WaveformViewTransform {
  static const int _hDivisions = 14;
  static const int _vDivisions = 8;

  /// Visible time window in seconds.
  final double tMin;
  final double tMax;

  /// Visible voltage window in volts, in the vertical scale [vdiv].
  final double vMin;
  final double vMax;

  /// Horizontal scale the window was computed for (s/div).
  final double timebase;

  /// Vertical scale the window was computed for (V/div).
  final double vdiv;

  /// Size of the display area in logical pixels; must not be empty.
  final Size size;

  const WaveformViewTransform._({
    required this.tMin,
    required this.tMax,
    required this.vMin,
    required this.vMax,
    required this.timebase,
    required this.vdiv,
    required this.size,
  });

  /// Transform for a channel displayed at [vdiv] per division and offset by
  /// [voffset] volts, as the waveform painter draws it.
  factory WaveformViewTransform.forChannel({
    required DeviceParams params,
    required ZoomState zoom,
    required Size size,
    required double vdiv,
    required double voffset,
  }) {
    final double displaySpan = params.timebase * _hDivisions;
    final double centerTime = params.trdl + (zoom.panX - 0.5) * displaySpan;
    final double visibleTSpan = displaySpan / zoom.zoomFactor;

    final double vMax = -voffset + _vDivisions / 2 * vdiv;
    final double vMin = -voffset - _vDivisions / 2 * vdiv;
    final double vRange = vMax - vMin;
    final double centerVoltage = vMin + zoom.panY * vRange;
    final double visibleVRange = vRange / zoom.zoomFactor;

    return WaveformViewTransform._(
      tMin: centerTime - visibleTSpan / 2,
      tMax: centerTime + visibleTSpan / 2,
      vMin: centerVoltage - visibleVRange / 2,
      vMax: centerVoltage + visibleVRange / 2,
      timebase: params.timebase,
      vdiv: vdiv,
      size: size,
    );
  }

  /// Transform for the reference overlay, which is drawn in the V/div of the
  /// channel it was loaded from ([origin], `'ch1'` or `'ch2'`) — the same
  /// scale [WaveformBasePainter] uses for it.
  factory WaveformViewTransform.forReference({
    required DeviceParams params,
    required ZoomState zoom,
    required Size size,
    required String? origin,
  }) {
    final bool fromCh1 = origin == 'ch1';
    return WaveformViewTransform.forChannel(
      params: params,
      zoom: zoom,
      size: size,
      vdiv: (fromCh1 ? params.vdivCh1 : params.vdivCh2) ?? 1.0,
      voffset: (fromCh1 ? params.voffsetCh1 : params.voffsetCh2) ?? 0.0,
    );
  }

  /// Seconds covered by one pixel column.
  double get secondsPerPixel => (tMax - tMin) / size.width;

  /// Volts covered by one pixel row.
  double get voltsPerPixel => (vMax - vMin) / size.height;

  /// Horizontal shift in divisions per pixel of pointer movement.
  double get dxDivPerPixel => secondsPerPixel / timebase;

  /// Vertical shift in divisions per pixel of pointer movement.
  double get dyDivPerPixel => voltsPerPixel / vdiv;
}
