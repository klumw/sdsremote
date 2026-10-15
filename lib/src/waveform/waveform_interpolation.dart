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
class WaveformInterpolation {
  WaveformInterpolation._();

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
