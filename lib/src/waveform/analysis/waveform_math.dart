/// Mathematical helpers of the waveform classification engine.
///
/// The module is Flutter-free and dependency-free apart from `fftea`, which is
/// already used by the spectrum analysis. It contains the FFT wrapper,
/// autocorrelation fundamental estimation, normalised cross-correlation,
/// banded dynamic time warping and the exponential/envelope fits used by the
/// feature extractor.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import 'waveform_analysis_models.dart';

/// Single-sided FFT magnitude spectrum of a real signal.
class FftSpectrum {
  /// Frequencies of [amplitudes] in hertz.
  final Float64List frequencies;

  /// Single-sided peak amplitudes in the units of the input samples.
  final Float64List amplitudes;

  /// Frequency spacing of the padded FFT in hertz.
  final double resolutionHz;

  /// Number of samples used for the FFT before zero padding.
  final int sampleCount;

  const FftSpectrum({
    required this.frequencies,
    required this.amplitudes,
    required this.resolutionHz,
    required this.sampleCount,
  });

  /// Frequency of the largest non-DC bin, or `null` for an empty spectrum.
  double? get dominantFrequency {
    if (amplitudes.length < 3) return null;
    var bestIndex = 1;
    var best = amplitudes[1];
    for (var i = 2; i < amplitudes.length; i++) {
      if (amplitudes[i] > best) {
        best = amplitudes[i];
        bestIndex = i;
      }
    }
    return interpolatedPeakFrequency(bestIndex);
  }

  /// Parabolic interpolation of the peak frequency around [index].
  double? interpolatedPeakFrequency(int index) {
    if (index <= 0 || index >= amplitudes.length) return null;
    final y1 = amplitudes[index - 1];
    final y2 = amplitudes[index];
    final y3 = index + 1 < amplitudes.length ? amplitudes[index + 1] : y2;
    final denominator = y1 - 2 * y2 + y3;
    final delta = denominator.abs() < 1e-15
        ? 0.0
        : 0.5 * (y1 - y3) / denominator;
    final refined = index + delta.clamp(-0.5, 0.5);
    return refined * resolutionHz;
  }

  /// Amplitude of the bin nearest to [frequencyHz] within [binTolerance]
  /// bins, or `null` when the frequency is outside the spectrum.
  double? amplitudeNear(double frequencyHz, {int binTolerance = 2}) {
    if (resolutionHz <= 0 || amplitudes.isEmpty) return null;
    final center = (frequencyHz / resolutionHz).round();
    if (center < 0) return null;
    final lower = math.max(0, center - binTolerance);
    final upper = math.min(amplitudes.length - 1, center + binTolerance);
    if (lower > upper) return null;
    var best = amplitudes[lower];
    for (var i = lower + 1; i <= upper; i++) {
      if (amplitudes[i] > best) best = amplitudes[i];
    }
    return best;
  }
}

/// Returns the smallest power of two greater than or equal to [value].
int nextPowerOfTwo(int value) {
  if (value <= 1) return 1;
  var result = 1;
  while (result < value) {
    result <<= 1;
  }
  return result;
}

/// Computes a Hann-windowed single-sided amplitude spectrum.
///
/// Zero padding to the next power of two interpolates the spectrum. The
/// amplitudes are corrected for the window's coherent gain (the Hann window
/// attenuates a tone by a factor of 0.5).
FftSpectrum computeSpectrum(
  Float64List samples,
  double sampleRate, {
  bool window = true,
}) {
  if (samples.isEmpty || sampleRate <= 0) {
    return FftSpectrum(
      frequencies: Float64List(0),
      amplitudes: Float64List(0),
      resolutionHz: 0,
      sampleCount: samples.length,
    );
  }
  final count = samples.length;
  final paddedSize = math.max(8, nextPowerOfTwo(count));
  final windowed = Float64List(paddedSize);
  var windowSum = 0.0;
  for (var i = 0; i < count; i++) {
    final weight = window && count > 1
        ? 0.5 * (1 - math.cos(2 * math.pi * i / (count - 1)))
        : 1.0;
    windowed[i] = samples[i] * weight;
    windowSum += weight;
  }
  if (windowSum <= 0) windowSum = 1;

  final complex = FFT(paddedSize).realFft(windowed);
  final bins = paddedSize ~/ 2 + 1;
  final frequencies = Float64List(bins);
  final amplitudes = Float64List(bins);
  final resolution = sampleRate / paddedSize;
  for (var k = 0; k < bins; k++) {
    frequencies[k] = k * resolution;
    final z = complex[k];
    final magnitude = math.sqrt(z.x * z.x + z.y * z.y);
    amplitudes[k] = k == 0
        ? magnitude / windowSum
        : (k == paddedSize ~/ 2 && paddedSize.isEven)
        ? magnitude / windowSum
        : 2 * magnitude / windowSum;
  }
  return FftSpectrum(
    frequencies: frequencies,
    amplitudes: amplitudes,
    resolutionHz: resolution,
    sampleCount: count,
  );
}

/// Estimates the fundamental frequency with a normalised autocorrelation.
///
/// The first local maximum above [minimumPeak] is interpreted as one period.
/// A monotonically decaying signal (for example an exponential decay) has no
/// local maximum and returns `null`.
double? estimateFundamentalHz(
  Float64List samples,
  double sampleIntervalSeconds, {
  double minimumPeak = 0.45,
  int minimumLag = 3,
}) {
  final n = samples.length;
  if (n < 12 || sampleIntervalSeconds <= 0) return null;
  final maxLag = math.min(n - 4, (n * 0.85).floor());
  if (maxLag <= minimumLag) return null;

  final prefixSquares = Float64List(n + 1);
  for (var i = 0; i < n; i++) {
    prefixSquares[i + 1] = prefixSquares[i] + samples[i] * samples[i];
  }

  final correlation = Float64List(maxLag + 1);
  for (var lag = minimumLag; lag <= maxLag; lag++) {
    final overlap = n - lag;
    if (overlap < 8) break;
    var sum = 0.0;
    for (var i = 0; i < overlap; i++) {
      sum += samples[i] * samples[i + lag];
    }
    final energyA = prefixSquares[overlap];
    final energyB = prefixSquares[n] - prefixSquares[lag];
    final denominator = math.sqrt(energyA * energyB);
    if (denominator > 0) correlation[lag] = sum / denominator;
  }

  // Local maxima of the autocorrelation. Noise creates tiny local bumps near
  // lag zero; the topographic prominence keeps them from being mistaken for
  // the fundamental period.
  final maxima = <int>[];
  for (var lag = minimumLag + 1; lag < maxLag; lag++) {
    final value = correlation[lag];
    if (value < minimumPeak) continue;
    if (value >= correlation[lag - 1] && value > correlation[lag + 1]) {
      maxima.add(lag);
    }
  }
  if (maxima.isEmpty) return null;

  // Noise can split one period peak into two adjacent peaks. Merge maxima
  // that are only a few samples apart and keep the highest of each cluster.
  final mergeDistance = math.max(2, math.min(20, (maxLag * 0.005).round()));
  final mergedMaxima = <int>[];
  for (final maximum in maxima) {
    if (mergedMaxima.isEmpty || maximum - mergedMaxima.last > mergeDistance) {
      mergedMaxima.add(maximum);
    } else if (correlation[maximum] > correlation[mergedMaxima.last]) {
      mergedMaxima[mergedMaxima.length - 1] = maximum;
    }
  }

  double? bestLag;
  for (var index = 0; index < mergedMaxima.length; index++) {
    final peak = mergedMaxima[index];
    final leftBoundary = index == 0 ? minimumLag : mergedMaxima[index - 1] + 1;
    final rightBoundary = index == mergedMaxima.length - 1
        ? maxLag
        : mergedMaxima[index + 1] - 1;
    var leftMinimum = correlation[peak];
    for (var lag = leftBoundary; lag < peak; lag++) {
      if (correlation[lag] < leftMinimum) leftMinimum = correlation[lag];
    }
    var rightMinimum = correlation[peak];
    for (var lag = peak + 1; lag <= rightBoundary; lag++) {
      if (correlation[lag] < rightMinimum) rightMinimum = correlation[lag];
    }
    final prominence = correlation[peak] - math.max(leftMinimum, rightMinimum);
    if (prominence >= 0.05) {
      bestLag = peak.toDouble();
      break;
    }
  }
  if (bestLag == null) return null;

  final peakIndex = bestLag.round();
  var refinedLag = bestLag;
  if (peakIndex > minimumLag && peakIndex < maxLag) {
    final y1 = correlation[peakIndex - 1];
    final y2 = correlation[peakIndex];
    final y3 = correlation[peakIndex + 1];
    final denominator = y1 - 2 * y2 + y3;
    if (denominator.abs() > 1e-15) {
      final delta = 0.5 * (y1 - y3) / denominator;
      refinedLag += delta.clamp(-0.5, 0.5);
    }
  }
  if (refinedLag <= 0) return null;
  final frequency = 1 / (refinedLag * sampleIntervalSeconds);
  return frequency.isFinite && frequency > 0 ? frequency : null;
}

/// Result of a normalised cross-correlation with lag search.
class CorrelationResult {
  /// Pearson correlation coefficient in [-1, 1].
  final double coefficient;

  /// Lag of [b] relative to [a] in samples. Positive values mean that [b] is
  /// delayed relative to [a].
  final int lagSamples;

  const CorrelationResult({
    required this.coefficient,
    required this.lagSamples,
  });
}

/// Maximum normalised cross-correlation of two equal-length signals.
///
/// [a] and [b] are expected to be standardised, but the function recentres
/// every overlap window, so any scale works. Lags from `-maxLag` to `maxLag`
/// are searched; a positive lag shifts [b] to later indices.
CorrelationResult maxNormalizedCrossCorrelation(
  Float64List a,
  Float64List b, {
  int? maxLag,
  int? minimumOverlap,
}) {
  if (a.length != b.length || a.length < 4) {
    return const CorrelationResult(coefficient: 0, lagSamples: 0);
  }
  final n = a.length;
  final minOverlap = (minimumOverlap ?? math.max(4, (n * 0.25).round())).clamp(
    4,
    n,
  );
  final limit = (maxLag ?? (n - minOverlap)).clamp(0, n - minOverlap);
  var best = -2.0;
  var bestLag = 0;
  for (var lag = -limit; lag <= limit; lag++) {
    final startA = math.max(0, -lag);
    final startB = math.max(0, lag);
    final length = n - lag.abs();
    if (length < minOverlap) continue;

    var sumA = 0.0;
    var sumB = 0.0;
    var sumAB = 0.0;
    var sumA2 = 0.0;
    var sumB2 = 0.0;
    for (var i = 0; i < length; i++) {
      final va = a[startA + i];
      final vb = b[startB + i];
      sumA += va;
      sumB += vb;
      sumAB += va * vb;
      sumA2 += va * va;
      sumB2 += vb * vb;
    }
    final covariance = length * sumAB - sumA * sumB;
    final varianceA = length * sumA2 - sumA * sumA;
    final varianceB = length * sumB2 - sumB * sumB;
    final denominator = math.sqrt(varianceA * varianceB);
    if (denominator <= 1e-15) continue;
    final coefficient = covariance / denominator;
    if (coefficient > best) {
      best = coefficient;
      bestLag = lag;
    }
  }
  if (best < -1.5) {
    return const CorrelationResult(coefficient: 0, lagSamples: 0);
  }
  return CorrelationResult(
    coefficient: best.clamp(-1.0, 1.0),
    lagSamples: bestLag,
  );
}

/// Result of a banded DTW alignment.
class DtwResult {
  /// Path-normalised absolute distance of the standardised samples.
  final double distance;

  /// Similarity in [0, 1] derived from [distance].
  final double similarity;

  const DtwResult({required this.distance, required this.similarity});
}

/// Banded dynamic time warping of two equal-length standardised arrays.
///
/// The Sakoe-Chiba band limits the warping and prevents unrelated signals from
/// being aligned through extreme time distortion.
DtwResult bandedDtw(
  Float64List a,
  Float64List b, {
  int? band,
  double distanceScale = 3.0,
}) {
  if (a.length != b.length || a.length < 4) {
    return const DtwResult(distance: 1, similarity: 0);
  }
  final n = a.length;
  final radius = (band ?? math.max(8, (n * 0.15).round())).clamp(0, n - 1);
  const infinity = double.infinity;
  var previous = Float64List(n)..fillRange(0, n, infinity);
  var current = Float64List(n)..fillRange(0, n, infinity);

  for (var i = 0; i < n; i++) {
    final lower = math.max(0, i - radius);
    final upper = math.min(n - 1, i + radius);
    for (var j = lower; j <= upper; j++) {
      final cost = (a[i] - b[j]).abs();
      if (i == 0 && j == 0) {
        current[j] = cost;
        continue;
      }
      var best = infinity;
      if (i > 0) best = math.min(best, previous[j]);
      if (j > 0 && current[j - 1].isFinite) {
        best = math.min(best, current[j - 1]);
      }
      if (i > 0 && j > 0 && previous[j - 1].isFinite) {
        best = math.min(best, previous[j - 1]);
      }
      current[j] = best.isFinite ? cost + best : infinity;
    }
    final swap = previous;
    previous = current;
    current = swap;
    current.fillRange(0, n, infinity);
  }
  final distance = previous[n - 1];
  if (!distance.isFinite) return const DtwResult(distance: 1, similarity: 0);
  final normalized = distance / n;
  final similarity = 1 / (1 + distanceScale * normalized);
  return DtwResult(distance: normalized, similarity: similarity);
}

/// Standardises [values] to zero mean and unit standard deviation.
Float64List zScore(Float64List values) {
  final result = Float64List(values.length);
  if (values.isEmpty) return result;
  var mean = 0.0;
  for (final value in values) {
    mean += value;
  }
  mean /= values.length;
  var variance = 0.0;
  for (final value in values) {
    final deviation = value - mean;
    variance += deviation * deviation;
  }
  variance /= values.length;
  final deviation = math.sqrt(variance);
  if (deviation <= 1e-15) return result;
  for (var i = 0; i < values.length; i++) {
    result[i] = (values[i] - mean) / deviation;
  }
  return result;
}

/// Linearly resamples [values] to [length] samples over the same time span.
Float64List resampleValues(Float64List values, int length) {
  if (values.length == length) return Float64List.fromList(values);
  if (values.isEmpty || length <= 0) return Float64List(length);
  final result = Float64List(length);
  if (length == 1) {
    result[0] = values.first;
    return result;
  }
  final scale = (values.length - 1) / (length - 1);
  for (var i = 0; i < length; i++) {
    final position = i * scale;
    final index = position.floor();
    if (index >= values.length - 1) {
      result[i] = values.last;
      continue;
    }
    final fraction = position - index;
    result[i] = values[index] + (values[index + 1] - values[index]) * fraction;
  }
  return result;
}

/// Resamples a trace to [count] equally spaced samples over its time span.
WaveformTrace resampleTrace(WaveformTrace trace, int count) {
  if (trace.length < 2 || count < 2) {
    return WaveformTrace(
      times: Float64List(0),
      volts: Float64List(0),
      channel: trace.channel,
    );
  }
  final start = trace.times.first;
  final end = trace.times.last;
  final times = Float64List(count);
  final volts = Float64List(count);
  final span = end - start;
  for (var i = 0; i < count; i++) {
    final position = i / (count - 1);
    times[i] = start + position * span;
  }
  final sourceIndex = 0;
  var segment = sourceIndex;
  for (var i = 0; i < count; i++) {
    final t = times[i];
    while (segment + 1 < trace.length - 1 && trace.times[segment + 1] < t) {
      segment++;
    }
    final t0 = trace.times[segment];
    final t1 = trace.times[segment + 1];
    final v0 = trace.volts[segment];
    final v1 = trace.volts[segment + 1];
    final width = t1 - t0;
    volts[i] = width > 0 ? v0 + (v1 - v0) * (t - t0) / width : v0;
  }
  return WaveformTrace(times: times, volts: volts, channel: trace.channel);
}

/// Least-squares fit of `y = slope * x + intercept`.
class LinearFitResult {
  final double slope;
  final double intercept;
  final double r2;

  const LinearFitResult({
    required this.slope,
    required this.intercept,
    required this.r2,
  });
}

LinearFitResult fitLinear(Float64List x, Float64List y) {
  final n = math.min(x.length, y.length);
  if (n < 2) {
    return const LinearFitResult(slope: 0, intercept: 0, r2: 0);
  }
  var sumX = 0.0;
  var sumY = 0.0;
  var sumXY = 0.0;
  var sumX2 = 0.0;
  for (var i = 0; i < n; i++) {
    sumX += x[i];
    sumY += y[i];
    sumXY += x[i] * y[i];
    sumX2 += x[i] * x[i];
  }
  final denominator = n * sumX2 - sumX * sumX;
  if (denominator.abs() < 1e-15) {
    return const LinearFitResult(slope: 0, intercept: 0, r2: 0);
  }
  final slope = (n * sumXY - sumX * sumY) / denominator;
  final intercept = (sumY - slope * sumX) / n;
  var total = 0.0;
  var residual = 0.0;
  final meanY = sumY / n;
  for (var i = 0; i < n; i++) {
    final predicted = slope * x[i] + intercept;
    total += (y[i] - meanY) * (y[i] - meanY);
    residual += (y[i] - predicted) * (y[i] - predicted);
  }
  final r2 = total <= 1e-15 ? 0.0 : 1 - residual / total;
  return LinearFitResult(
    slope: slope,
    intercept: intercept,
    r2: r2.clamp(0.0, 1.0),
  );
}

/// Result of fitting `y(t) = A * exp(±t / tau) + C`.
class ExponentialFitResult {
  final double amplitude;
  final double tauSeconds;
  final double offset;
  final double r2;
  final bool rising;

  const ExponentialFitResult({
    required this.amplitude,
    required this.tauSeconds,
    required this.offset,
    required this.r2,
    required this.rising,
  });
}

/// Fits an exponential decay and rise and returns the better model.
///
/// `tau` is scanned logarithmically over `duration / 200 … duration * 20`;
/// for every candidate the amplitude and offset follow from a linear
/// least-squares fit of the exponential basis. The coefficient of
/// determination selects the best time constant and direction.
ExponentialFitResult? fitExponential(
  Float64List values,
  Float64List times, {
  int tauSteps = 80,
}) {
  final n = math.min(values.length, times.length);
  if (n < 8) return null;
  final start = times[0];
  final duration = times[n - 1] - start;
  if (duration <= 0) return null;

  ExponentialFitResult? best;
  for (final rising in [false, true]) {
    for (var step = 0; step <= tauSteps; step++) {
      final fraction = step / tauSteps;
      final tau = duration / 200 * math.pow(400, fraction).toDouble();
      if (!tau.isFinite || tau <= 0) continue;
      final fit = _fitExponentialWithTau(
        values,
        times,
        start: start,
        tau: tau,
        rising: rising,
        n: n,
      );
      if (fit == null) continue;
      if (best == null || fit.r2 > best.r2) best = fit;
    }
  }
  if (best == null) return null;

  // Both basis directions can fit the same monotonic curve when the amplitude
  // is allowed to change sign. The direction is therefore taken from the data
  // trend (first versus last part of the record), which is unambiguous for an
  // exponential decay or rise.
  final headLength = math.max(1, n ~/ 5);
  var head = 0.0;
  var tail = 0.0;
  for (var i = 0; i < headLength; i++) {
    head += values[i];
    tail += values[n - 1 - i];
  }
  final trendRising = tail / headLength > head / headLength;
  return ExponentialFitResult(
    amplitude: best.amplitude,
    tauSeconds: best.tauSeconds,
    offset: best.offset,
    r2: best.r2,
    rising: trendRising,
  );
}

ExponentialFitResult? _fitExponentialWithTau(
  Float64List values,
  Float64List times, {
  required double start,
  required double tau,
  required bool rising,
  required int n,
}) {
  var sumG = 0.0;
  var sumGG = 0.0;
  var sumY = 0.0;
  var sumGY = 0.0;
  for (var i = 0; i < n; i++) {
    final exponent = (times[i] - start) / tau;
    final g = rising ? math.exp(exponent) : math.exp(-exponent);
    if (!g.isFinite) return null;
    sumG += g;
    sumGG += g * g;
    sumY += values[i];
    sumGY += g * values[i];
  }
  final denominator = n * sumGG - sumG * sumG;
  if (denominator.abs() < 1e-15) return null;
  final amplitude = (n * sumGY - sumG * sumY) / denominator;
  final offset = (sumY - amplitude * sumG) / n;
  var total = 0.0;
  var residual = 0.0;
  final mean = sumY / n;
  for (var i = 0; i < n; i++) {
    final exponent = (times[i] - start) / tau;
    final g = rising ? math.exp(exponent) : math.exp(-exponent);
    final predicted = amplitude * g + offset;
    total += (values[i] - mean) * (values[i] - mean);
    residual += (values[i] - predicted) * (values[i] - predicted);
  }
  final r2 = total <= 1e-15 ? 0.0 : 1 - residual / total;
  return ExponentialFitResult(
    amplitude: amplitude,
    tauSeconds: tau,
    offset: offset,
    r2: r2.clamp(0.0, 1.0),
    rising: rising,
  );
}

/// Result of an exponential envelope fit of the oscillation extrema.
class EnvelopeFitResult {
  /// Decay rate in 1/s; positive means the envelope decreases.
  final double decayRatePerSecond;

  /// Coefficient of determination of `ln(envelope)` against time.
  final double r2;

  final int extremaCount;

  const EnvelopeFitResult({
    required this.decayRatePerSecond,
    required this.r2,
    required this.extremaCount,
  });
}

/// Fits an exponential decay to the absolute extrema of an oscillation.
EnvelopeFitResult? fitEnvelopeDecay(
  Float64List values,
  Float64List times, {
  double minimumProminence = 0,
}) {
  final n = math.min(values.length, times.length);
  if (n < 8) return null;
  final extrema = localExtremaIndices(
    values,
    minProminence: minimumProminence,
    minDistance: 3,
  );
  if (extrema.length < 4) return null;

  var mean = 0.0;
  for (var i = 0; i < n; i++) {
    mean += values[i];
  }
  mean /= n;

  final envTimes = <double>[];
  final logEnvelope = <double>[];
  for (final index in extrema) {
    final envelope = (values[index] - mean).abs();
    if (envelope <= 1e-12) continue;
    envTimes.add(times[index]);
    logEnvelope.add(math.log(envelope));
  }
  if (envTimes.length < 4) return null;
  final fit = fitLinear(
    Float64List.fromList(envTimes),
    Float64List.fromList(logEnvelope),
  );
  return EnvelopeFitResult(
    decayRatePerSecond: -fit.slope,
    r2: fit.r2,
    extremaCount: envTimes.length,
  );
}

/// Indices of local maxima and minima with a minimum prominence and spacing.
///
/// Prominence is measured against the lowest (for a maximum) or highest (for
/// a minimum) value between the neighbouring extrema, not against a small
/// fixed window. This keeps slowly varying oscillations detectable while still
/// rejecting noise ripples.
List<int> localExtremaIndices(
  Float64List values, {
  double minProminence = 0,
  int minDistance = 3,
}) {
  final n = values.length;
  if (n < 3) return const [];
  final candidates = <({int index, bool isMaximum})>[];
  for (var i = 1; i < n - 1; i++) {
    if (values[i] >= values[i - 1] && values[i] > values[i + 1]) {
      candidates.add((index: i, isMaximum: true));
    } else if (values[i] <= values[i - 1] && values[i] < values[i + 1]) {
      candidates.add((index: i, isMaximum: false));
    }
  }
  final selected = <int>[];
  for (
    var candidateIndex = 0;
    candidateIndex < candidates.length;
    candidateIndex++
  ) {
    final candidate = candidates[candidateIndex];
    if (selected.isNotEmpty && candidate.index - selected.last < minDistance) {
      continue;
    }
    if (minProminence > 0) {
      final left = selected.isEmpty ? 0 : selected.last;
      var right = n - 1;
      for (var next = candidateIndex + 1; next < candidates.length; next++) {
        if (candidates[next].index > candidate.index) {
          right = candidates[next].index;
          break;
        }
      }
      var extreme = values[candidate.index];
      for (var i = left; i <= right; i++) {
        if (candidate.isMaximum) {
          if (values[i] < extreme) extreme = values[i];
        } else if (values[i] > extreme) {
          extreme = values[i];
        }
      }
      if ((values[candidate.index] - extreme).abs() < minProminence) continue;
    }
    selected.add(candidate.index);
  }
  return selected;
}

/// Length of the longest strictly monotonic run, divided by the sample count.
double monotonicRunFraction(Float64List values) {
  if (values.length < 2) return 0;
  var best = 1;
  var current = 1;
  var direction = 0;
  for (var i = 1; i < values.length; i++) {
    final delta = values[i] - values[i - 1];
    final sign = delta > 0 ? 1 : (delta < 0 ? -1 : 0);
    if (sign == 0) {
      continue;
    }
    if (sign == direction) {
      current++;
    } else {
      direction = sign;
      current = 2;
    }
    if (current > best) best = current;
  }
  return best / values.length;
}

/// Population coefficient of variation (`stddev / mean`) of a value list.
double? coefficientOfVariation(List<double> values) {
  final finite = values.where((value) => value.isFinite).toList();
  if (finite.length < 2) return null;
  final mean = finite.reduce((a, b) => a + b) / finite.length;
  if (mean.abs() < 1e-12) return null;
  var sum = 0.0;
  for (final value in finite) {
    final deviation = value - mean;
    sum += deviation * deviation;
  }
  return math.sqrt(sum / finite.length) / mean.abs();
}

/// Sorted value at [fraction] (0 = minimum, 1 = maximum).
double percentileOf(Float64List values, double fraction) {
  if (values.isEmpty) return 0;
  final sorted = Float64List.fromList(values)..sort();
  final position = (fraction.clamp(0.0, 1.0)) * (sorted.length - 1);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  final fractionBetween = position - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * fractionBetween;
}

/// Clamps [value] to the unit interval and replaces non-finite values with 0.
double clamp01(double value) =>
    value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;

/// `value / reference`, or `null` when the reference is zero or non-finite.
double? safeRatio(double value, double reference) {
  if (reference.abs() < 1e-12 || !value.isFinite || !reference.isFinite) {
    return null;
  }
  return value / reference;
}

/// A three-sample median filter used only for the optional smoothing step.
Float64List medianFilter3(Float64List values) {
  if (values.length < 3) return Float64List.fromList(values);
  final result = Float64List.fromList(values);
  for (var i = 1; i < values.length - 1; i++) {
    final a = values[i - 1];
    final b = values[i];
    final c = values[i + 1];
    result[i] = math.max(math.min(a, b), math.min(math.max(a, b), c));
  }
  return result;
}
