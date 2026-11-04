/// Deterministic spectrum helpers for the audio analysis tools.
///
/// The FFT, window and metric formulas mirror the application's spectrum
/// analysis so the audio tools report the same kind of values as the Spectrum
/// tab. All functions are pure and take an [AudioChannelData] snapshot.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import '../../../spectrum/fft.dart';
import '../../../spectrum/spectrum_models.dart';
import '../../../spectrum/windows.dart';
import 'audio_analysis_context.dart';

/// Lowest reported level, matching the application's spectrum analysis.
const double audioMinDb = -200.0;

/// One computed spectrum with its peaks and metrics.
class AudioSpectrum {
  const AudioSpectrum({
    required this.channel,
    required this.fftSize,
    required this.sampleRateHz,
    required this.resolutionHz,
    required this.fullScaleVolts,
    required this.window,
    required this.frequenciesHz,
    required this.amplitudesVpk,
    required this.powers,
    required this.dbfs,
    required this.peaks,
    required this.metrics,
  });

  final String channel;
  final int fftSize;
  final double sampleRateHz;
  final double resolutionHz;
  final double fullScaleVolts;
  final SpectrumWindowInfo window;
  final Float64List frequenciesHz;
  final Float64List amplitudesVpk;

  /// Normalised power per bin (sum over all bins ≈ signal power).
  final Float64List powers;
  final Float64List dbfs;
  final List<SpectrumPeak> peaks;
  final SpectrumMetrics metrics;

  double get nyquistHz => sampleRateHz / 2;
  int get binCount => frequenciesHz.length;
}

/// Computes a Hann-windowed FFT and the standard distortion/noise metrics.
///
/// Returns `null` when the channel has too few samples, an invalid sample
/// rate or no full scale. [requestedFftSize] 0 selects the largest power of
/// two that fits, bounded by [maxFftSize].
AudioSpectrum? computeAudioSpectrum(
  AudioChannelData channel, {
  int requestedFftSize = 0,
  SpectrumWindow window = SpectrumWindow.hann,
  int peakCount = 10,
  int harmonicCount = 10,
  int maxFftSize = 1 << 20,
}) {
  final samples = channel.samples;
  if (samples.length < 16 ||
      channel.sampleRateHz <= 0 ||
      channel.fullScaleVolts <= 0) {
    return null;
  }

  var limit = maxFftSize;
  if (requestedFftSize > 0 && requestedFftSize < limit) {
    limit = requestedFftSize;
  }
  final usable = samples.length < limit ? samples.length : limit;
  final fftSize = _largestPowerOfTwo(usable);
  if (fftSize < 16) return null;

  final windowInfo = buildWindow(window, fftSize);
  final data = Float64List(fftSize);
  var mean = 0.0;
  for (var i = 0; i < fftSize; i++) {
    data[i] = samples[i];
    mean += data[i];
  }
  mean /= fftSize;
  for (var i = 0; i < fftSize; i++) {
    data[i] = (data[i] - mean) * windowInfo.coefficients[i];
  }

  final squared = SpectrumFft(fftSize).squaredMagnitudes(data);
  final binCount = fftSize ~/ 2 + 1;
  final fullScale = channel.fullScaleVolts;
  final binWidthHz = channel.sampleRateHz / fftSize;

  final frequencies = Float64List(binCount);
  final amplitudes = Float64List(binCount);
  final dbfs = Float64List(binCount);
  final powers = Float64List(binCount);
  final amplitudeScale = 1.0 / (fftSize * windowInfo.coherentGain);
  final powerScale = 1.0 / (fftSize * windowInfo.sumSquares);

  for (var k = 0; k < binCount; k++) {
    frequencies[k] = k * binWidthHz;
    final isEdge = k == 0 || k == fftSize ~/ 2;
    final factor = isEdge ? 1.0 : 2.0;
    final magnitude = math.sqrt(squared[k]);
    amplitudes[k] = magnitude * factor * amplitudeScale;
    powers[k] = squared[k] * factor * powerScale;
    dbfs[k] = _amplitudeToDbfs(amplitudes[k], fullScale);
  }

  final peaks = _findPeaks(
    dbfs: dbfs,
    frequencies: frequencies,
    amplitudes: amplitudes,
    fullScale: fullScale,
    windowInfo: windowInfo,
    peakCount: peakCount,
  );
  final metrics = _computeMetrics(
    peaks: peaks,
    powers: powers,
    binWidthHz: binWidthHz,
    sampleRate: channel.sampleRateHz,
    fftSize: fftSize,
    binCount: binCount,
    fullScale: fullScale,
    windowInfo: windowInfo,
    harmonicCount: harmonicCount,
  );

  return AudioSpectrum(
    channel: channel.label,
    fftSize: fftSize,
    sampleRateHz: channel.sampleRateHz,
    resolutionHz: binWidthHz,
    fullScaleVolts: fullScale,
    window: windowInfo,
    frequenciesHz: frequencies,
    amplitudesVpk: amplitudes,
    powers: powers,
    dbfs: dbfs,
    peaks: peaks,
    metrics: metrics,
  );
}

/// Peak amplitude in volts near [frequencyHz].
///
/// The largest bin inside the window main lobe is returned. This is robust
/// against leakage and matches the spectrum's peak amplitudes.
double amplitudeAtFrequency(
  AudioSpectrum spectrum,
  double frequencyHz, {
  double? toleranceHz,
}) {
  if (!frequencyHz.isFinite || frequencyHz <= 0) return 0;
  if (frequencyHz >= spectrum.nyquistHz) return 0;
  final bin = (frequencyHz / spectrum.resolutionHz).round();
  var halfWidth = spectrum.window.halfMainLobeBins;
  if (toleranceHz != null && toleranceHz > 0) {
    halfWidth = math.max(
      halfWidth,
      (toleranceHz / spectrum.resolutionHz).ceil(),
    );
  }
  final low = math.max(1, bin - halfWidth);
  final high = math.min(spectrum.binCount - 2, bin + halfWidth);
  var best = 0.0;
  for (var k = low; k <= high; k++) {
    if (spectrum.amplitudesVpk[k] > best) best = spectrum.amplitudesVpk[k];
  }
  return best;
}

/// Strongest bin near [frequencyHz], or `null` when the range is outside the
/// spectrum.
({double amplitudeVpk, double frequencyHz})? peakNearFrequency(
  AudioSpectrum spectrum,
  double frequencyHz, {
  double toleranceHz = 1.0,
}) {
  if (!frequencyHz.isFinite || frequencyHz <= 0) return null;
  final lowHz = math.max(0.0, frequencyHz - toleranceHz);
  final highHz = math.min(spectrum.nyquistHz, frequencyHz + toleranceHz);
  final lowBin = math.max(1, (lowHz / spectrum.resolutionHz).floor());
  final highBin = math.min(
    spectrum.binCount - 2,
    (highHz / spectrum.resolutionHz).ceil(),
  );
  if (lowBin > highBin) return null;
  var bestBin = lowBin;
  for (var k = lowBin + 1; k <= highBin; k++) {
    if (spectrum.amplitudesVpk[k] > spectrum.amplitudesVpk[bestBin]) {
      bestBin = k;
    }
  }
  return (
    amplitudeVpk: spectrum.amplitudesVpk[bestBin],
    frequencyHz: bestBin * spectrum.resolutionHz,
  );
}

/// Level of [amplitudeVpk] relative to the fundamental in dBc.
double? dbcRelativeToFundamental(AudioSpectrum spectrum, double amplitudeVpk) {
  final fundamental = spectrum.metrics.fundamentalVpk;
  if (!fundamental.isFinite || fundamental <= 0 || amplitudeVpk <= 0) {
    return null;
  }
  return dbRatio(amplitudeVpk / fundamental);
}

/// Amplitude and phase of a single frequency component.
///
/// Uses a Hann-windowed DFT at exactly [frequencyHz], so it is independent of
/// the FFT bin grid. The result is in volts peak and degrees.
({double amplitudeVpk, double phaseDeg})? componentAtFrequency(
  AudioChannelData channel,
  double frequencyHz, {
  int maxSamples = 1 << 16,
}) {
  final samples = channel.samples;
  final n = math.min(samples.length, maxSamples);
  if (n < 8 || channel.sampleRateHz <= 0) return null;
  if (!frequencyHz.isFinite ||
      frequencyHz <= 0 ||
      frequencyHz >= channel.sampleRateHz / 2) {
    return null;
  }

  final omega = 2 * math.pi * frequencyHz / channel.sampleRateHz;
  var real = 0.0;
  var imaginary = 0.0;
  var windowSum = 0.0;
  for (var i = 0; i < n; i++) {
    final window = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
    final value = samples[i] * window;
    real += value * math.cos(omega * i);
    imaginary -= value * math.sin(omega * i);
    windowSum += window;
  }
  if (windowSum <= 0) return null;
  final amplitude =
      2 * math.sqrt(real * real + imaginary * imaginary) / windowSum;
  final phase = math.atan2(imaginary, real) * 180 / math.pi;
  return (amplitudeVpk: amplitude, phaseDeg: phase);
}

/// Phase difference `b − a` at [frequencyHz], wrapped to −180°…180°.
double? phaseDifferenceAtFrequency(
  AudioChannelData a,
  AudioChannelData b,
  double frequencyHz,
) {
  final componentA = componentAtFrequency(a, frequencyHz);
  final componentB = componentAtFrequency(b, frequencyHz);
  if (componentA == null || componentB == null) return null;
  return wrapDegrees(componentB.phaseDeg - componentA.phaseDeg);
}

/// Wraps an angle in degrees to −180°…180°.
double wrapDegrees(double degrees) {
  var value = degrees % 360;
  if (value > 180) value -= 360;
  if (value <= -180) value += 360;
  return value;
}

/// `20 · log10(ratio)`, or `null` for non-positive ratios.
double? dbRatio(double ratio) {
  if (!ratio.isFinite || ratio <= 0) return null;
  return 20 * math.log(ratio) / math.ln10;
}

/// Level of [amplitude] in dBFS relative to [fullScaleVolts].
double? dbfsFromAmplitude(double amplitude, double fullScaleVolts) {
  if (!amplitude.isFinite ||
      !fullScaleVolts.isFinite ||
      amplitude <= 0 ||
      fullScaleVolts <= 0) {
    return null;
  }
  return 20 * math.log(amplitude / fullScaleVolts) / math.ln10;
}

/// RMS value of a sine with peak amplitude [amplitudeVpk].
double rmsFromPeak(double amplitudeVpk) => amplitudeVpk / math.sqrt(2);

/// Magnitude-squared coherence between two channels.
class AudioCoherenceResult {
  const AudioCoherenceResult({
    required this.meanCoherence,
    required this.coherenceAtFundamental,
    required this.bandCoherence,
    required this.fftSize,
    required this.segmentCount,
    required this.resolutionHz,
    required this.warnings,
  });

  final double? meanCoherence;
  final double? coherenceAtFundamental;
  final Map<String, double?> bandCoherence;
  final int fftSize;
  final int segmentCount;
  final double resolutionHz;
  final List<String> warnings;
}

/// Welch-style magnitude-squared coherence between [a] and [b].
///
/// The channels must share a sample rate. Segments are Hann-windowed with
/// [overlap] fractional overlap; the cross-spectrum and auto-spectra are
/// averaged before the coherence is computed. A single segment cannot
/// estimate coherence reliably and is reported with a warning.
AudioCoherenceResult? computeAudioCoherence(
  AudioChannelData a,
  AudioChannelData b, {
  int fftSize = 4096,
  double overlap = 0.5,
  double bandStartHz = 20,
  double bandEndHz = 20000,
  double? fundamentalHz,
}) {
  if (a.sampleRateHz <= 0 || a.sampleRateHz != b.sampleRateHz) return null;
  final length = math.min(a.sampleCount, b.sampleCount);
  if (length < 64) return null;

  var size = _largestPowerOfTwo(math.min(fftSize, length));
  if (size < 64) size = _largestPowerOfTwo(length);
  if (size < 64) return null;
  final fractionalOverlap = overlap.clamp(0.0, 0.9).toDouble();
  final hop = math.max(1, (size * (1 - fractionalOverlap)).round());
  final segmentCount = 1 + ((length - size) / hop).floor();
  if (segmentCount < 1) return null;

  final windowInfo = buildWindow(SpectrumWindow.hann, size);
  final binCount = size ~/ 2 + 1;
  final sxx = Float64List(binCount);
  final syy = Float64List(binCount);
  final sxyRe = Float64List(binCount);
  final sxyIm = Float64List(binCount);
  final fft = FFT(size);
  final windowedA = Float64List(size);
  final windowedB = Float64List(size);

  for (var segment = 0; segment < segmentCount; segment++) {
    final start = segment * hop;
    for (var i = 0; i < size; i++) {
      final window = windowInfo.coefficients[i];
      windowedA[i] = a.samples[start + i] * window;
      windowedB[i] = b.samples[start + i] * window;
    }
    final spectrumA = fft.realFft(windowedA);
    final spectrumB = fft.realFft(windowedB);
    for (var k = 0; k < binCount; k++) {
      final ax = spectrumA[k].x;
      final ay = spectrumA[k].y;
      final bx = spectrumB[k].x;
      final by = spectrumB[k].y;
      sxx[k] += ax * ax + ay * ay;
      syy[k] += bx * bx + by * by;
      sxyRe[k] += ax * bx + ay * by;
      sxyIm[k] += ax * by - ay * bx;
    }
  }

  final coherence = Float64List(binCount);
  for (var k = 1; k < binCount; k++) {
    final denominator = sxx[k] * syy[k];
    if (denominator > 0) {
      final cross = sxyRe[k] * sxyRe[k] + sxyIm[k] * sxyIm[k];
      coherence[k] = (cross / denominator).clamp(0.0, 1.0);
    }
  }

  final resolution = a.sampleRateHz / size;
  final nyquist = a.sampleRateHz / 2;
  final start = math.max(1, (bandStartHz / resolution).floor());
  final end = math.min(binCount - 1, (bandEndHz / resolution).ceil());
  double? mean;
  if (end >= start) {
    var sum = 0.0;
    for (var k = start; k <= end; k++) {
      sum += coherence[k];
    }
    mean = sum / (end - start + 1);
  }
  double? atFundamental;
  if (fundamentalHz != null && fundamentalHz > 0) {
    final bin = (fundamentalHz / resolution).round();
    if (bin > 0 && bin < binCount) atFundamental = coherence[bin];
  }

  double? bandMean(double lowHz, double highHz) {
    final low = math.max(1, (lowHz / resolution).floor());
    final high = math.min(binCount - 1, (highHz / resolution).ceil());
    if (high < low) return null;
    var sum = 0.0;
    for (var k = low; k <= high; k++) {
      sum += coherence[k];
    }
    return sum / (high - low + 1);
  }

  final warnings = <String>[];
  if (segmentCount < 4) {
    warnings.add(
      'fewer than four averaging segments; the coherence estimate has a high '
      'variance',
    );
  }
  if (bandEndHz > nyquist) {
    warnings.add('the band extends above Nyquist and was clipped');
  }

  return AudioCoherenceResult(
    meanCoherence: mean,
    coherenceAtFundamental: atFundamental,
    bandCoherence: {
      'low_20_250_hz': bandMean(20, 250),
      'mid_250_2000_hz': bandMean(250, 2000),
      'high_2000_20000_hz': bandMean(2000, 20000),
    },
    fftSize: size,
    segmentCount: segmentCount,
    resolutionHz: resolution,
    warnings: warnings,
  );
}

List<SpectrumPeak> _findPeaks({
  required Float64List dbfs,
  required Float64List frequencies,
  required Float64List amplitudes,
  required double fullScale,
  required SpectrumWindowInfo windowInfo,
  required int peakCount,
}) {
  final binCount = dbfs.length;
  final halfWidth = windowInfo.halfMainLobeBins;
  final start = halfWidth + 1 < binCount - 1 ? halfWidth + 1 : binCount - 1;
  final end = binCount - 1;
  final median = _median(dbfs, start, end);
  final threshold = median + 10.0 > -140.0 ? median + 10.0 : -140.0;

  final candidates = <_Candidate>[];
  for (var k = start; k < end; k++) {
    if (dbfs[k] <= threshold) continue;
    if (dbfs[k] <= dbfs[k - 1] || dbfs[k] < dbfs[k + 1]) continue;
    candidates.add(
      _interpolatePeak(
        k: k,
        dbfs: dbfs,
        binWidthHz: frequencies.length > 1 ? frequencies[1] : 0.0,
        fullScale: fullScale,
      ),
    );
  }
  candidates.sort((a, b) => b.dbfs.compareTo(a.dbfs));

  final accepted = <_Candidate>[];
  for (final candidate in candidates) {
    final overlaps = accepted.any(
      (existing) =>
          (existing.bin - candidate.bin).abs() <= windowInfo.mainLobeBins,
    );
    if (overlaps) continue;
    accepted.add(candidate);
    if (accepted.length >= peakCount) break;
  }

  final peaks = <SpectrumPeak>[];
  for (var i = 0; i < accepted.length; i++) {
    final candidate = accepted[i];
    final isFundamental = i == 0;
    peaks.add(
      SpectrumPeak(
        marker: i + 1,
        frequencyHz: candidate.frequencyHz,
        amplitudeVpk: candidate.amplitudeVpk,
        levelDb: candidate.dbfs,
        dbfs: candidate.dbfs,
        relativeToFundamentalDb: isFundamental
            ? 0.0
            : candidate.dbfs - accepted.first.dbfs,
        isFundamental: isFundamental,
      ),
    );
  }
  return peaks;
}

class _Candidate {
  const _Candidate({
    required this.bin,
    required this.frequencyHz,
    required this.amplitudeVpk,
    required this.dbfs,
  });

  final int bin;
  final double frequencyHz;
  final double amplitudeVpk;
  final double dbfs;
}

_Candidate _interpolatePeak({
  required int k,
  required Float64List dbfs,
  required double binWidthHz,
  required double fullScale,
}) {
  final left = dbfs[k - 1];
  final peak = dbfs[k];
  final right = dbfs[k + 1];
  final denominator = left - 2 * peak + right;
  var delta = 0.0;
  if (denominator.abs() > 1e-12) {
    delta = 0.5 * (left - right) / denominator;
    if (delta < -0.5) {
      delta = -0.5;
    } else if (delta > 0.5) {
      delta = 0.5;
    }
  }
  final interpolatedDb = peak - 0.25 * (left - right) * delta;
  final amplitude = fullScale * math.pow(10.0, interpolatedDb / 20.0);
  return _Candidate(
    bin: k,
    frequencyHz: (k + delta) * binWidthHz,
    amplitudeVpk: amplitude.toDouble(),
    dbfs: interpolatedDb,
  );
}

SpectrumMetrics _computeMetrics({
  required List<SpectrumPeak> peaks,
  required Float64List powers,
  required double binWidthHz,
  required double sampleRate,
  required int fftSize,
  required int binCount,
  required double fullScale,
  required SpectrumWindowInfo windowInfo,
  required int harmonicCount,
}) {
  final nyquist = sampleRate / 2.0;
  final resolution = binWidthHz;

  if (peaks.isEmpty) {
    final nan = double.nan;
    return SpectrumMetrics(
      fundamentalHz: nan,
      fundamentalVpk: nan,
      fundamentalDbfs: nan,
      thdPercent: nan,
      thdDb: nan,
      thdPlusNDb: nan,
      snrDb: nan,
      sinadDb: nan,
      enobBits: nan,
      sfdrDb: nan,
      noiseFloorDbfs: audioMinDb,
      harmonicsUsed: 0,
      nyquistHz: nyquist,
      resolutionHz: resolution,
    );
  }

  final fundamental = peaks.first;
  final halfWidth = windowInfo.halfMainLobeBins;
  final fundamentalBin = _clampInt(
    (fundamental.frequencyHz / binWidthHz).round(),
    0,
    binCount - 1,
  );
  final (fundLo, fundHi) = _lobeRange(fundamentalBin, halfWidth, binCount);
  var fundamentalPower = 0.0;
  for (var k = fundLo; k <= fundHi; k++) {
    fundamentalPower += powers[k];
  }

  var harmonicPower = 0.0;
  var harmonicsUsed = 0;
  var excludedNoiseBins = fundHi - fundLo + 1;
  for (var h = 2; h <= harmonicCount; h++) {
    final harmonicHz = h * fundamental.frequencyHz;
    if (harmonicHz >= nyquist - halfWidth * binWidthHz) break;
    final bin = (harmonicHz / binWidthHz).round();
    if (bin <= halfWidth || bin >= binCount - halfWidth) break;
    final (lo, hi) = _lobeRange(bin, halfWidth, binCount);
    for (var k = lo; k <= hi; k++) {
      harmonicPower += powers[k];
    }
    excludedNoiseBins += hi - lo + 1;
    harmonicsUsed++;
  }

  var totalPower = 0.0;
  for (var k = 1; k < binCount; k++) {
    totalPower += powers[k];
  }
  var noisePower = totalPower - fundamentalPower - harmonicPower;
  if (noisePower < 0) noisePower = 0;

  final noiseBins = (binCount - 1) - excludedNoiseBins > 1
      ? (binCount - 1) - excludedNoiseBins
      : 1;
  final fullScalePower = fullScale * fullScale / 2.0;
  final noiseFloor = noisePower > 0 && fullScalePower > 0
      ? 10.0 * math.log(noisePower / noiseBins / fullScalePower) / math.ln10
      : audioMinDb;

  final thdDb = fundamentalPower > 0 && harmonicPower > 0
      ? 10.0 * math.log(harmonicPower / fundamentalPower) / math.ln10
      : audioMinDb;
  final thdPercent = fundamentalPower > 0
      ? 100.0 * math.sqrt(harmonicPower / fundamentalPower)
      : double.nan;
  final thdPlusNDb = fundamentalPower > 0 && (noisePower + harmonicPower) > 0
      ? 10.0 *
            math.log((noisePower + harmonicPower) / fundamentalPower) /
            math.ln10
      : audioMinDb;
  final snrDb = fundamentalPower > 0 && noisePower > 0
      ? 10.0 * math.log(fundamentalPower / noisePower) / math.ln10
      : double.nan;
  final sinadDb = fundamentalPower > 0 && (noisePower + harmonicPower) > 0
      ? 10.0 *
            math.log(fundamentalPower / (noisePower + harmonicPower)) /
            math.ln10
      : double.nan;
  final enobBits = sinadDb.isFinite ? (sinadDb - 1.76) / 6.02 : double.nan;

  var spurPower = 0.0;
  for (final peak in peaks.skip(1)) {
    final bin = _clampInt(
      (peak.frequencyHz / binWidthHz).round(),
      0,
      binCount - 1,
    );
    final (lo, hi) = _lobeRange(bin, halfWidth, binCount);
    var power = 0.0;
    for (var k = lo; k <= hi; k++) {
      power += powers[k];
    }
    if (power > spurPower) spurPower = power;
  }
  final sfdrDb = fundamentalPower > 0 && spurPower > 0
      ? 10.0 * math.log(fundamentalPower / spurPower) / math.ln10
      : double.nan;

  return SpectrumMetrics(
    fundamentalHz: fundamental.frequencyHz,
    fundamentalVpk: fundamental.amplitudeVpk,
    fundamentalDbfs: fundamental.dbfs,
    thdPercent: thdPercent,
    thdDb: thdDb,
    thdPlusNDb: thdPlusNDb,
    snrDb: snrDb,
    sinadDb: sinadDb,
    enobBits: enobBits,
    sfdrDb: sfdrDb,
    noiseFloorDbfs: noiseFloor,
    harmonicsUsed: harmonicsUsed,
    nyquistHz: nyquist,
    resolutionHz: resolution,
  );
}

(int, int) _lobeRange(int bin, int halfWidth, int binCount) {
  final rawLow = bin - halfWidth;
  final lo = rawLow > 1 ? rawLow : 1;
  final rawHigh = bin + halfWidth;
  final hi = rawHigh < binCount - 1 ? rawHigh : binCount - 1;
  return (lo, hi);
}

int _clampInt(int value, int lower, int upper) {
  if (value < lower) return lower;
  if (value > upper) return upper;
  return value;
}

double _median(Float64List values, int start, int end) {
  if (end <= start) return audioMinDb;
  final copy = List<double>.of(values.sublist(start, end))..sort();
  return copy[copy.length ~/ 2];
}

int _largestPowerOfTwo(int value) {
  if (value <= 0) return 0;
  return 1 << (value.bitLength - 1);
}

double _amplitudeToDbfs(double amplitude, double fullScale) {
  if (amplitude <= 0 || fullScale <= 0) return audioMinDb;
  final db = 20.0 * math.log(amplitude / fullScale) / math.ln10;
  return db < audioMinDb ? audioMinDb : db;
}
