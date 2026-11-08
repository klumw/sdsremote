import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'waveform_interpolation.dart';
import 'waveform_models.dart';

/// Pixel trace of one waveform for the current view window.
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
  }) => buildRaster(
    data: data,
    size: size,
    visibleTMin: visibleTMin,
    visibleTMax: visibleTMax,
    visibleVMin: visibleVMin,
    visibleVMax: visibleVMax,
    vdiv: vdiv,
    xShiftPx: xShiftPx,
    yShiftPx: yShiftPx,
  ).trace;

  /// Builds the raster including its horizontal-offset handling.
  ///
  /// Samples that belong to the same pixel column but sit at different
  /// vertical positions are horizontally offset: a jittery edge moves its
  /// samples between neighbouring columns, so the one-vertex-per-column line
  /// jumps up and down and draws a jagged "saw". This method keeps the exact
  /// vertical extent of every column and separates two renderings:
  ///
  ///  - [WaveformRaster.crisp] holds the normal (smoothed) centre line
  ///    wherever the samples agree, so clean signals are drawn exactly as
  ///    before, and
  ///  - [WaveformRaster.soft] holds a robust centre line (the local mean of
  ///    the per-column means) next to [WaveformRaster.band], the min/max
  ///    envelope of the samples, wherever horizontal offsets are detected.
  ///
  /// The envelope is exact - no sample amplitude is lost - while the jitter is
  /// drawn as a translucent band instead of a spike, i.e. the trace becomes
  /// deliberately soft where the data points are far apart horizontally.
  static WaveformRaster buildRaster({
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
    if (data.points.length < 2) return WaveformRaster.empty;

    final double visibleTRange = visibleTMax - visibleTMin;
    final double visibleVRange = visibleVMax - visibleVMin;
    if (visibleTRange <= 0 || visibleVRange <= 0) return WaveformRaster.empty;

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

    final int sampleCount = data.points.length;
    final int columns = math.max(2, size.width.round());

    // Screen position of a sample. Without trigger metadata a record that is
    // much shorter than the window is spread evenly over the display and its
    // time values are not used; otherwise the time axis maps it.
    double xAt(int i) => expandToDisplay
        ? i / (sampleCount - 1) * size.width + xShiftPx
        : (data.points[i].$1 - visibleTMin) / visibleTRange * size.width +
              xShiftPx;
    double yAt(int i) =>
        (visibleVMax - data.points[i].$2) / visibleVRange * size.height +
        yShiftPx;

    // One vertex per pixel column, taken from the straight line between the
    // surrounding samples. Connecting every acquired sample directly instead
    // would make the anti-aliased polyline break up into a blocky, dotted band
    // - dozens of vertices per column that mostly draw over each other.
    // Samples outside the visible window are still used as the ends of the
    // interpolation segments at the plot edges; only columns inside the
    // graticule produce vertices.
    final Float64List raw = WaveformInterpolation.resample(
      count: sampleCount,
      columns: columns,
      xAt: xAt,
      yAt: yAt,
    );

    // The interpolated vertices are smoothed over a few pixels: the 8 bit
    // quantisation of the oscilloscope turns a slowly changing signal into
    // stair steps several pixels wide, and a straight line through those steps
    // looks jittery. The moving average reconstructs the smooth signal behind
    // them, but only while the trace stays continuous: the window is filled
    // outwards from each vertex and stops at any single jump larger than a few
    // ADC steps. Stair steps (one step each) are averaged away, a square wave
    // flank - a single jump of several divisions - is never crossed, so it
    // keeps its position and stays vertical.
    // The smoothing window adapts to the signal period: a fast sine with a
    // few dozen pixels per period needs a short window or its tops flatten
    // into plateaus, while a slow sine (hundreds of pixels per period) needs
    // a wider window to remove the visible ADC stair steps.
    final double periodPx = _estimatePeriodPx(raw);
    final double smoothingWidthPx = periodPx > 0
        ? (periodPx * 0.08).clamp(4.0, 18.0)
        : 4.0;
    // A wider window also needs a higher step limit for slow signals;
    // otherwise a two- or three-code quantisation transition stops the
    // window and leaves a visible discontinuity. Square-wave flanks are an
    // order of magnitude larger and are still never crossed.
    final double smoothingMaxSteps = periodPx > 100 ? 6.0 : 2.0;
    // One step of the instrument's 8 bit ADC, expressed in pixels.
    final double adcStepPx = (vdiv / 25.0) / visibleVRange * size.height;
    final Float64List smoothed = WaveformInterpolation.smooth(
      raw,
      smoothingWidth: smoothingWidthPx,
      maxStep: adcStepPx * smoothingMaxSteps,
    );

    return _withHorizontalOffsetHandling(
      data: data,
      raw: raw,
      smoothed: smoothed,
      columns: columns,
      xAt: xAt,
      yAt: yAt,
      adcStepPx: adcStepPx,
      periodPx: periodPx,
    );
  }
}

/// The raster of one waveform, rendered either crisp or uniformly soft.
///
/// [trace] is the complete centre line, exactly the vertices the previous
/// single-path renderer used. When no horizontal offset is found, [crisp]
/// holds that line and [soft]/[band] are empty. Otherwise the whole trace is
/// rendered softly: [soft] is the robust centre line and [band] the exact
/// vertical envelope of the samples as interleaved `x, top, bottom` triplets.
class WaveformRaster {
  WaveformRaster({
    required this.trace,
    required this.crisp,
    Float64List? soft,
    Float64List? band,
  }) : soft = soft ?? _empty,
       band = band ?? _empty;

  static final Float64List _empty = Float64List(0);

  /// An empty raster, used when there is nothing to draw.
  static final WaveformRaster empty = WaveformRaster(
    trace: _empty,
    crisp: _empty,
  );

  /// Complete centre line, interleaved `x, y`.
  final Float64List trace;

  /// Crisp centre line, interleaved `x, y`; empty in the soft rendering.
  final Float64List crisp;

  /// Robust centre line of the soft rendering, interleaved `x, y`.
  final Float64List soft;

  /// Vertical envelope of the soft rendering, interleaved `x, top, bottom`.
  final Float64List band;

  /// Whether horizontal offsets were found and the soft rendering is active.
  bool get hasBand => band.isNotEmpty;
}

/// Detects horizontally offset samples and builds the soft rendering.
///
/// The signal behind a jittery edge still moves smoothly; the *samples* of one
/// pixel column, however, end up at different heights, and the interpolated
/// one-vertex-per-column line jumps between them. Comparing that line with the
/// smoothed mean of the per-column means separates the two: a clean trace stays
/// close to the mean, a horizontally offset one crosses it repeatedly.
///
/// A clean edge, however steep or rounded, has a single peak in its slope. A
/// horizontally offset edge is a staircase: its slope rises and falls several
/// times, so two or more slope peaks point in the same direction. Narrow
/// pulses have one positive and one negative peak, and square-wave flanks and
/// rounded edges one peak in total, so they stay crisp. When the offsets are
/// found, the *whole* trace is rendered softly: a blurred centre line plus the
/// exact min/max band of every column. Applying the soft style only to the
/// detected spans made the trace look inconsistent (sharp and soft pieces),
/// while a jittery signal should look uniformly soft. Clean signals keep the
/// crisp line unchanged.
WaveformRaster _withHorizontalOffsetHandling({
  required WaveformData data,
  required Float64List raw,
  required Float64List smoothed,
  required int columns,
  required double Function(int) xAt,
  required double Function(int) yAt,
  required double adcStepPx,
  required double periodPx,
}) {
  // With fewer samples than columns there is no within-column spread that
  // could be drawn as a band; the existing line already represents the data.
  if (data.points.length < columns * 2) {
    return WaveformRaster(trace: smoothed, crisp: smoothed);
  }

  final stats = WaveformInterpolation.columnStats(
    count: data.points.length,
    columns: columns,
    xAt: xAt,
    yAt: yAt,
  );
  // The trend has to be wider than one jitter excursion so that the offsets
  // average out. The window follows the signal period; a short median guards
  // the mean against single outliers while preserving real edges.
  final int halfWidth = periodPx > 0
      ? (periodPx * 0.04).round().clamp(2, 8)
      : 4;
  final robust = WaveformInterpolation.meanFilter(
    WaveformInterpolation.medianFilter(stats.means, 1),
    halfWidth,
  );

  // The interpolated centre of every column. It picks one point inside the
  // column, which is why a horizontally jittered edge makes it jump.
  final displayByColumn = Float64List(columns);
  final rawByColumn = Float64List(columns);
  displayByColumn.fillRange(0, columns, double.nan);
  rawByColumn.fillRange(0, columns, double.nan);
  for (var i = 0; i + 1 < raw.length; i += 2) {
    final int c = raw[i].floor();
    if (c < 0 || c >= columns) continue;
    if (!rawByColumn[c].isFinite) rawByColumn[c] = raw[i + 1];
    if (!displayByColumn[c].isFinite) displayByColumn[c] = smoothed[i + 1];
  }

  // A residual beyond one and three quarter ADC steps cannot be explained by
  // the quantisation of a clean trace.
  final double threshold = math.max(2.5, adcStepPx * 1.75);
  final residual = Float64List(columns);
  residual.fillRange(0, columns, double.nan);
  final exceeds = List<bool>.filled(columns, false);
  for (var c = 0; c < columns; c++) {
    if (stats.counts[c] == 0) continue;
    final double centre = displayByColumn[c];
    final double trend = robust[c];
    if (!centre.isFinite || !trend.isFinite) continue;
    final double value = centre - trend;
    residual[c] = value;
    exceeds[c] = value.abs() > threshold;
  }

  // A clean edge - however steep or rounded - has a single peak in its slope.
  // A horizontally offset edge is a staircase: its slope rises and falls
  // several times, separated by dips back to the steepest value. Two such
  // peaks in the same direction identify the offset; a flat slope plateau
  // (linear edge) is not counted twice, so trapezoidal flanks stay crisp,
  // and narrow pulses have one positive and one negative peak.
  const int minSameSignPeaks = 2;
  final double bigJump = threshold * 2;
  var horizontallyOffset = false;
  for (var c = 0; c < columns;) {
    if (!exceeds[c]) {
      c++;
      continue;
    }
    final int start = c;
    var last = c;
    var probe = c;
    while (probe < columns && probe - last <= 2) {
      if (exceeds[probe]) last = probe;
      probe++;
    }
    final int scanStart = math.max(0, start - 2);
    final int scanEnd = math.min(columns - 1, last + 2);

    var positivePeaks = 0;
    var negativePeaks = 0;
    var lastPositive = -10;
    var lastNegative = -10;
    var lastPositiveValue = 0.0;
    var lastNegativeValue = 0.0;
    var minPositiveSince = double.infinity;
    var minNegativeSince = double.infinity;
    final int firstSlope = math.max(1, scanStart);
    final int lastSlope = math.min(columns - 3, scanEnd);
    for (var j = firstSlope; j <= lastSlope; j++) {
      final double a = displayByColumn[j - 1];
      final double b = displayByColumn[j];
      final double c2 = displayByColumn[j + 1];
      final double d = displayByColumn[j + 2];
      if (!a.isFinite || !b.isFinite || !c2.isFinite || !d.isFinite) {
        continue;
      }
      final double slope = c2 - b;
      final double magnitude = slope.abs();
      if (magnitude < minPositiveSince) minPositiveSince = magnitude;
      if (magnitude < minNegativeSince) minNegativeSince = magnitude;
      if (magnitude < bigJump ||
          magnitude < (b - a).abs() ||
          magnitude < (d - c2).abs()) {
        continue;
      }
      if (slope > 0) {
        final bool accepted =
            positivePeaks == 0 ||
            (j - lastPositive > 2 &&
                minPositiveSince <
                    0.6 * math.min(magnitude, lastPositiveValue));
        if (accepted) positivePeaks++;
        lastPositive = j;
        lastPositiveValue = magnitude;
        minPositiveSince = double.infinity;
      } else {
        final bool accepted =
            negativePeaks == 0 ||
            (j - lastNegative > 2 &&
                minNegativeSince <
                    0.6 * math.min(magnitude, lastNegativeValue));
        if (accepted) negativePeaks++;
        lastNegative = j;
        lastNegativeValue = magnitude;
        minNegativeSince = double.infinity;
      }
    }

    if (positivePeaks >= minSameSignPeaks ||
        negativePeaks >= minSameSignPeaks) {
      horizontallyOffset = true;
      break;
    }
    c = last + 1;
  }
  if (!horizontallyOffset) {
    return WaveformRaster(trace: smoothed, crisp: smoothed);
  }

  // Render the complete trace softly: the robust centre line plus the exact
  // min/max envelope of every column. Blurred edges of the band and the
  // blurred line give the waveform the uniform out-of-focus look of a
  // jittery signal.
  final soft = <double>[];
  final band = <double>[];
  for (var i = 0; i + 1 < raw.length; i += 2) {
    final double x = raw[i];
    final double display = smoothed[i + 1];
    final int c = x.floor();
    double centre = display;
    double top = display;
    double bottom = display;
    if (c >= 0 && c < columns && stats.counts[c] > 0) {
      final double trend = robust[c];
      if (trend.isFinite) centre = trend;
      top = stats.lows[c];
      bottom = stats.highs[c];
      final int lo = math.max(0, c - 1);
      final int hi = math.min(columns - 1, c + 1);
      for (var k = lo; k <= hi; k++) {
        final double value = rawByColumn[k];
        if (!value.isFinite) continue;
        if (value < top) top = value;
        if (value > bottom) bottom = value;
      }
      if (display < top) top = display;
      if (display > bottom) bottom = display;
      if (centre < top) top = centre;
      if (centre > bottom) bottom = centre;
    }
    soft.add(x);
    soft.add(centre);
    if (bottom > top) {
      band.add(x);
      band.add(top);
      band.add(bottom);
    }
  }

  return WaveformRaster(
    trace: smoothed,
    crisp: Float64List(0),
    soft: Float64List.fromList(soft),
    band: Float64List.fromList(band),
  );
}

/// Estimates the signal period in pixels from the mean crossings of [trace].
///
/// Returns 0 when the trace has too few crossings or the crossing intervals
/// are too irregular (for example noise).
double _estimatePeriodPx(Float64List trace) {
  final n = trace.length ~/ 2;
  if (n < 16) return 0;

  var minY = double.infinity;
  var maxY = -double.infinity;
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final y = trace[i * 2 + 1];
    if (!y.isFinite) return 0;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;
    sum += y;
  }
  final range = maxY - minY;
  if (range <= 0) return 0;

  final mean = sum / n;
  final hysteresis = range * 0.05;
  final crossings = <double>[];
  var state = 0;
  for (var i = 0; i < n; i++) {
    final y = trace[i * 2 + 1];
    if (state <= 0 && y > mean + hysteresis) {
      if (state == -1) crossings.add(trace[i * 2]);
      state = 1;
    } else if (state >= 0 && y < mean - hysteresis) {
      state = -1;
    }
  }
  if (crossings.length < 4) return 0;

  final intervals = <double>[
    for (var i = 1; i < crossings.length; i++) crossings[i] - crossings[i - 1],
  ];
  final meanInterval = intervals.reduce((a, b) => a + b) / intervals.length;
  if (meanInterval <= 0) return 0;

  var variance = 0.0;
  for (final interval in intervals) {
    final delta = interval - meanInterval;
    variance += delta * delta;
  }
  final coefficientOfVariation =
      math.sqrt(variance / intervals.length) / meanInterval;
  if (coefficientOfVariation > 0.3) return 0;

  intervals.sort();
  return intervals[intervals.length ~/ 2];
}
