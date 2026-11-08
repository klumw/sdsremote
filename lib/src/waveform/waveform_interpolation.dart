import 'dart:typed_data';

/// Resamples a waveform onto the pixel raster by linear interpolation.
///
/// Connecting every acquired sample directly is what makes a trace look
/// "pixelated": with dozens of samples per pixel column the anti-aliased
/// polyline breaks up into a dotted, fuzzy band instead of a thin line, and
/// the vertices do not sit on the pixel grid. Evaluating the piecewise linear
/// signal once per pixel column (at the column centre) yields exactly one
/// vertex per column, so the trace is drawn as a crisp line on the raster -
/// the same straight-line reconstruction the instrument shows on its own
/// screen (interpolation = linear, i.e. `SXSA OFF` on a Siglent scope).
/// Values between two samples are the values of the straight line connecting
/// them; nothing is smoothed or invented.
/// Vertical statistics of the samples that fall into one pixel column.
///
/// The per-column limits are what distinguish a genuine signal feature from
/// horizontally offset (jittered) samples: a jittered edge moves its samples
/// up and down *within* the column while the interpolated centre jumps
/// between neighbouring columns. Keeping the exact vertical extent preserves
/// the amplitude of the jitter - it is shown as a band instead of a spike.
class WaveformColumnStats {
  const WaveformColumnStats({
    required this.counts,
    required this.lows,
    required this.highs,
    required this.means,
  });

  /// Number of samples mapped into each column.
  final Int32List counts;

  /// Smallest and largest screen y of the samples in each column.
  final Float64List lows;
  final Float64List highs;

  /// Mean screen y of the samples in each column (`NaN` when empty).
  final Float64List means;
}

class WaveformInterpolation {
  WaveformInterpolation._();

  /// Collects the vertical statistics of [count] samples per pixel column.
  ///
  /// [xAt] and [yAt] map a sample index to screen coordinates, exactly as in
  /// [resample]. Samples outside the raster are ignored.
  static WaveformColumnStats columnStats({
    required int count,
    required int columns,
    required double Function(int index) xAt,
    required double Function(int index) yAt,
  }) {
    final int cols = columns < 1 ? 1 : columns;
    final counts = Int32List(cols);
    final sums = Float64List(cols);
    final lows = Float64List(cols);
    final highs = Float64List(cols);
    lows.fillRange(0, cols, double.infinity);
    highs.fillRange(0, cols, double.negativeInfinity);

    for (var i = 0; i < count; i++) {
      final double x = xAt(i);
      if (!x.isFinite) continue;
      final int c = x.floor();
      if (c < 0 || c >= cols) continue;
      final double y = yAt(i);
      if (!y.isFinite) continue;
      counts[c]++;
      sums[c] += y;
      if (y < lows[c]) lows[c] = y;
      if (y > highs[c]) highs[c] = y;
    }

    final means = Float64List(cols);
    for (var c = 0; c < cols; c++) {
      means[c] = counts[c] > 0 ? sums[c] / counts[c] : double.nan;
    }
    return WaveformColumnStats(
      counts: counts,
      lows: lows,
      highs: highs,
      means: means,
    );
  }

  /// Median of the finite values in the window of ±[halfWidth] around every
  /// entry.
  ///
  /// A median filter removes spikes a few columns wide while keeping ramps and
  /// edges in place: on a monotonic run the median is the centre value, so a
  /// real edge is not moved. Used to recover the smooth centre of a signal
  /// from per-column means that are displaced by horizontal jitter. Entries
  /// without any finite neighbour stay `NaN`.
  static Float64List medianFilter(Float64List values, int halfWidth) {
    final int n = values.length;
    final out = Float64List(n);
    if (halfWidth < 1) {
      out.setAll(0, values);
      return out;
    }
    final window = <double>[];
    for (var i = 0; i < n; i++) {
      final int lo = i - halfWidth < 0 ? 0 : i - halfWidth;
      final int hi = i + halfWidth >= n ? n - 1 : i + halfWidth;
      window.clear();
      for (var k = lo; k <= hi; k++) {
        final double v = values[k];
        if (v.isFinite) window.add(v);
      }
      if (window.isEmpty) {
        out[i] = double.nan;
        continue;
      }
      window.sort();
      out[i] = window[window.length ~/ 2];
    }
    return out;
  }

  /// Resamples [count] source samples onto [columns] pixel columns.
  ///
  /// [xAt] maps a source index to its pixel column position and [yAt] to its
  /// pixel row. The sample positions must be monotonically non-decreasing in
  /// x (acquisitions and loaded CSV files are ordered in time).
  ///
  /// Returns interleaved coordinates `[x0, y0, x1, y1, ...]` - at most one
  /// vertex per column, at `column + 0.5`. Columns the data does not reach
  /// stay empty, so a record that only covers part of the graticule keeps its
  /// true extent instead of being stretched.
  static Float64List resample({
    required int count,
    required int columns,
    required double Function(int index) xAt,
    required double Function(int index) yAt,
  }) {
    final int cols = columns < 1 ? 1 : columns;
    if (count < 2 || cols < 2) return Float64List(0);

    // Guard against degenerate input: a zero sample interval (e.g. a missing
    // sample rate) produces non-finite positions that cannot be interpolated.
    if (!xAt(0).isFinite || !xAt(1).isFinite) return Float64List(0);

    final out = Float64List(cols * 2);
    int n = 0;
    int i = 0; // index of the last sample at or left of the current column

    for (int c = 0; c < cols; c++) {
      final double x = c + 0.5;

      // Move the cursor forward until the segment [i, i + 1] brackets x.
      while (i + 1 < count && xAt(i + 1) < x) {
        i++;
      }

      final double xPrev = xAt(i);
      if (x < xPrev) continue; // column lies before the first sample

      final double yPrev = yAt(i);
      if (i + 1 >= count) {
        // Past the last sample: nothing further to draw.
        if (x > xPrev) break;
        if (yPrev.isFinite) {
          out[n++] = x;
          out[n++] = yPrev;
        }
        continue;
      }

      final double xNext = xAt(i + 1);
      final double yNext = yAt(i + 1);
      // A repeated x position (several samples in one spot) has no slope to
      // interpolate over - keep the sample value.
      final double y = xNext > xPrev
          ? yPrev + (yNext - yPrev) * (x - xPrev) / (xNext - xPrev)
          : yPrev;
      if (!y.isFinite) continue;

      out[n++] = x;
      out[n++] = y;
    }

    return Float64List.sublistView(out, 0, n);
  }

  /// Mean of the finite values in the window of ±[halfWidth] around every
  /// entry.
  ///
  /// Averaging the per-column means over a window wider than one jitter
  /// excursion recovers the smooth signal behind it, because the horizontal
  /// offset averages out while a ramp or curve is followed. Entries without
  /// any finite neighbour stay `NaN`.
  static Float64List meanFilter(Float64List values, int halfWidth) {
    final int n = values.length;
    final out = Float64List(n);
    if (halfWidth < 1) {
      out.setAll(0, values);
      return out;
    }
    for (var i = 0; i < n; i++) {
      final int lo = i - halfWidth < 0 ? 0 : i - halfWidth;
      final int hi = i + halfWidth >= n ? n - 1 : i + halfWidth;
      var sum = 0.0;
      var count = 0;
      for (var k = lo; k <= hi; k++) {
        final double v = values[k];
        if (!v.isFinite) continue;
        sum += v;
        count++;
      }
      out[i] = count > 0 ? sum / count : double.nan;
    }
    return out;
  }

  /// Smooths the y values of a resampled trace with a moving average.
  ///
  /// The x positions stay untouched, only the amplitude is averaged over the
  /// neighbouring vertices. [smoothingWidth] is given in *pixels*, so the
  /// trace is smoothed over the same amount of signal at every zoom level and
  /// the effect fades out on its own where the vertices are further apart than
  /// that width - a zoomed-in view keeps showing the samples as they are.
  ///
  /// Averaging is what removes the stair steps of a dense record: the 8 bit
  /// quantisation of the ADC turns a slow signal into plateaus a few pixels
  /// wide, and a straight line through them looks jittery. A moving average
  /// over a couple of plateaus reconstructs the smooth signal behind them -
  /// with an all-positive kernel, so it never invents overshoot.
  ///
  /// [maxStep] is how large a single jump between two neighbouring vertices may
  /// be (in y pixels) for the trace to count as continuous there. The window is
  /// filled outwards from the sample being smoothed and stops at the first
  /// larger jump, so a signal edge - a square wave flank, several divisions in
  /// one step - is never averaged across and keeps its position, while a smooth
  /// slope, made of many small steps one ADC step at a time, is followed and
  /// averaged over the full width. Without the limit the average would run
  /// through such a flank and shift the plateaus next to it. The default
  /// [double.infinity] averages the whole window.
  static Float64List smooth(
    Float64List trace, {
    double smoothingWidth = 10.0,
    double maxStep = double.infinity,
  }) {
    final int n = trace.length ~/ 2;
    if (n < 3 || smoothingWidth <= 0) return trace;

    final double spacing = (trace[(n - 1) * 2] - trace[0]) / (n - 1);
    if (spacing <= 0) return trace;
    final int half = (smoothingWidth / spacing).round() ~/ 2;
    if (half < 1) return trace;

    final out = Float64List(n * 2);
    for (int i = 0; i < n; i++) {
      int lo = i;
      while (lo > 0 &&
          lo > i - half &&
          (trace[lo * 2 + 1] - trace[(lo - 1) * 2 + 1]).abs() <= maxStep) {
        lo--;
      }
      int hi = i;
      while (hi < n - 1 &&
          hi < i + half &&
          (trace[(hi + 1) * 2 + 1] - trace[hi * 2 + 1]).abs() <= maxStep) {
        hi++;
      }
      double sum = 0;
      for (int k = lo; k <= hi; k++) {
        sum += trace[k * 2 + 1];
      }
      out[i * 2] = trace[i * 2];
      out[i * 2 + 1] = sum / (hi - lo + 1);
    }
    return out;
  }
}
