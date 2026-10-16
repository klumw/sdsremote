import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'waveform_interpolation.dart';
import 'waveform_models.dart';

/// Builds the pixel trace of one waveform for the current view window.
///
/// This is the mapping from the signal domain onto the raster: one vertex per
/// pixel column, taken from the straight line between the surrounding samples,
/// then smoothed over a few pixels. It is a pure function of the data and the
/// window, so the mapping - including the manual reference alignment - can be
/// tested without a canvas.
class WaveformTrace {
  WaveformTrace._();

  /// Resamples [data] onto the raster of a [size]-sized display area showing
  /// the window `visibleTMin..visibleTMax` / `visibleVMin..visibleVMax`.
  ///
  /// [xShiftPx] and [yShiftPx] move the whole trace by that many pixels
  /// (positive = right/down). They are applied in *both* mappings below: a
  /// record whose own time span is far shorter than the window is drawn spread
  /// over the display width, where its time values are not used at all and a
  /// shift of the window would be silently ignored.
  ///
  /// Returns interleaved `[x0, y0, x1, y1, ...]` coordinates, empty if there
  /// is nothing to draw. [vdiv] is the vertical scale, needed to tell the
  /// instrument's 8 bit quantisation step from the signal when smoothing.
  static Float64List build({
    required WaveformData data,
    required Size size,
    required double visibleTMin,
    required double visibleTMax,
    required double visibleVMin,
    required double visibleVMax,
    required double vdiv,
    double xShiftPx = 0.0,
    double yShiftPx = 0.0,
  }) {
    if (data.points.length < 2) return Float64List(0);

    final double visibleTRange = visibleTMax - visibleTMin;
    final double visibleVRange = visibleVMax - visibleVMin;
    if (visibleTRange <= 0 || visibleVRange <= 0) return Float64List(0);

    // Check the time span of the data itself. If the acquired/loaded data
    // covers a much smaller time window than the visible range (for example
    // due to missing trigger/sample metadata, a mismatch between sample timing
    // and display timebase, or a reference whose record is far shorter than
    // the current screen), the waveform would appear bunched into one small
    // area of the graticule. As a robust fallback, the points are then
    // distributed evenly across the visible time range so the waveform fills
    // the full 14 divisions (preserving relative order).
    final double dataTRange = data.points.last.$1 - data.points.first.$1;
    final bool expandToDisplay =
        dataTRange <= 0 || dataTRange < visibleTRange * 0.25;

    // One vertex per pixel column, taken from the straight line between the
    // surrounding samples. Connecting every acquired sample directly instead
    // would make the anti-aliased polyline break up into a blocky, dotted band
    // - dozens of vertices per column that mostly draw over each other.
    final int columns = math.max(2, size.width.round());
    final Float64List trace;
    if (expandToDisplay) {
      // Evenly spread points across the visible span; their time values are
      // not used here.
      final int n = data.points.length;
      trace = WaveformInterpolation.resample(
        count: n,
        columns: columns,
        xAt: (i) => i / (n - 1) * size.width + xShiftPx,
        yAt: (i) =>
            (visibleVMax - data.points[i].$2) / visibleVRange * size.height +
            yShiftPx,
      );
    } else {
      // Samples outside the visible window are still used as the ends of the
      // interpolation segments at the plot edges; only columns inside the
      // graticule produce vertices.
      trace = WaveformInterpolation.resample(
        count: data.points.length,
        columns: columns,
        xAt: (i) =>
            (data.points[i].$1 - visibleTMin) / visibleTRange * size.width +
            xShiftPx,
        yAt: (i) =>
            (visibleVMax - data.points[i].$2) / visibleVRange * size.height +
            yShiftPx,
      );
    }

    // The interpolated vertices are smoothed over a few pixels: the 8 bit
    // quantisation of the oscilloscope turns a slowly changing signal into
    // stair steps several pixels wide, and a straight line through those steps
    // looks jittery. The moving average reconstructs the smooth signal behind
    // them, but only while the trace stays continuous: the window is filled
    // outwards from each vertex and stops at any single jump larger than a few
    // ADC steps. Stair steps (one step each) are averaged away, a square wave
    // flank - a single jump of several divisions - is never crossed, so it
    // keeps its position and stays vertical.
    const double smoothingWidthPx = 14.0;
    const double smoothingMaxSteps = 6.0;
    // One step of the instrument's 8 bit ADC, expressed in pixels.
    final double adcStepPx = (vdiv / 25.0) / visibleVRange * size.height;
    return WaveformInterpolation.smooth(
      trace,
      smoothingWidth: smoothingWidthPx,
      maxStep: adcStepPx * smoothingMaxSteps,
    );
  }
}
