import 'dart:math' as math;
import 'dart:typed_data';

import '../waveform/waveform_converter.dart';
import 'fft.dart';
import 'spectrum_models.dart';
import 'windows.dart';

/// Lowest level reported for empty or zero bins.
const double minSpectrumDb = -200.0;

/// Minimum number of usable samples for a spectrum trace.
///
/// Records below this size produce no FFT values; the UI disables the
/// Spectrum view for the same threshold.
const int minSpectrumSamples = 20;

/// Computes the spectrum of every channel in [request].
///
/// The function is pure and isolate-safe: it only uses its arguments and
/// returns plain data structures with typed arrays.
SpectrumResult computeSpectrum(SpectrumRequest request) {
  final traces = <SpectrumTrace>[];
  for (final channel in request.channels) {
    final trace = _analyzeChannel(
      channel,
      request.sampleRate,
      request.settings,
    );
    if (trace != null) traces.add(trace);
  }
  return SpectrumResult(traces: traces, settings: request.settings);
}

SpectrumTrace? _analyzeChannel(
  SpectrumChannelInput channel,
  double sampleRate,
  SpectrumSettings settings,
) {
  final raw = channel.raw;
  if (raw.isEmpty || channel.vdiv <= 0 || sampleRate <= 0) return null;

  final skip = raw.length > settings.leadingSamplesToSkip * 4
      ? settings.leadingSamplesToSkip
      : 0;
  final available = raw.length - skip;
  if (available < minSpectrumSamples) return null;

  var limit = settings.maxFftSize;
  if (settings.fftSize > 0 && settings.fftSize < limit) {
    limit = settings.fftSize;
  }
  final int usable = available < limit ? available : limit;
  final fftSize = _largestPowerOfTwo(usable);
  if (fftSize < 8) return null;

  final windowInfo = buildWindow(settings.window, fftSize);
  final samples = Float64List(fftSize);
  for (var i = 0; i < fftSize; i++) {
    samples[i] = WaveformConverter.toVoltage(
      raw[skip + i],
      channel.vdiv,
      channel.voffset,
    );
  }

  if (settings.removeDc) {
    var mean = 0.0;
    for (final value in samples) {
      mean += value;
    }
    mean /= fftSize;
    for (var i = 0; i < fftSize; i++) {
      samples[i] -= mean;
    }
  }

  for (var i = 0; i < fftSize; i++) {
    samples[i] *= windowInfo.coefficients[i];
  }

  final squared = SpectrumFft(fftSize).squaredMagnitudes(samples);
  final binCount = fftSize ~/ 2 + 1;
  final fullScale = 128.0 * channel.vdiv / 25.0;
  final binWidthHz = sampleRate / fftSize;

  final frequencies = Float64List(binCount);
  final amplitudes = Float64List(binCount);
  final dbfs = Float64List(binCount);
  final levels = Float64List(binCount);
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
    levels[k] = _levelFromAmplitude(amplitudes[k], settings.unit, fullScale);
  }

  final peaks = _findPeaks(
    dbfs: dbfs,
    frequencies: frequencies,
    amplitudes: amplitudes,
    fullScale: fullScale,
    unit: settings.unit,
    windowInfo: windowInfo,
    settings: settings,
  );

  final metrics = _computeMetrics(
    peaks: peaks,
    powers: powers,
    binWidthHz: binWidthHz,
    sampleRate: sampleRate,
    fftSize: fftSize,
    binCount: binCount,
    fullScale: fullScale,
    windowInfo: windowInfo,
    settings: settings,
  );

  return SpectrumTrace(
    channel: channel.label,
    fftSize: fftSize,
    sampleRate: sampleRate,
    fullScaleVolts: fullScale,
    resolutionHz: binWidthHz,
    frequenciesHz: frequencies,
    levelsDb: levels,
    dbfs: dbfs,
    amplitudesVpk: amplitudes,
    peaks: peaks,
    metrics: metrics,
  );
}

List<SpectrumPeak> _findPeaks({
  required Float64List dbfs,
  required Float64List frequencies,
  required Float64List amplitudes,
  required double fullScale,
  required SpectrumUnit unit,
  required SpectrumWindowInfo windowInfo,
  required SpectrumSettings settings,
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
    if (accepted.length >= settings.peakCount) break;
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
        levelDb: _levelFromAmplitude(candidate.amplitudeVpk, unit, fullScale),
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
  final int bin;
  final double frequencyHz;
  final double amplitudeVpk;
  final double dbfs;

  const _Candidate({
    required this.bin,
    required this.frequencyHz,
    required this.amplitudeVpk,
    required this.dbfs,
  });
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
  required SpectrumSettings settings,
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
      noiseFloorDbfs: minSpectrumDb,
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
  for (var h = 2; h <= settings.harmonicCount; h++) {
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
      : minSpectrumDb;

  final thdDb = fundamentalPower > 0 && harmonicPower > 0
      ? 10.0 * math.log(harmonicPower / fundamentalPower) / math.ln10
      : minSpectrumDb;
  final thdPercent = fundamentalPower > 0
      ? 100.0 * math.sqrt(harmonicPower / fundamentalPower)
      : double.nan;
  final thdPlusNDb = fundamentalPower > 0 && (noisePower + harmonicPower) > 0
      ? 10.0 *
            math.log((noisePower + harmonicPower) / fundamentalPower) /
            math.ln10
      : minSpectrumDb;
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
  if (end <= start) return minSpectrumDb;
  final copy = List<double>.of(values.sublist(start, end))..sort();
  return copy[copy.length ~/ 2];
}

int _largestPowerOfTwo(int value) {
  if (value <= 0) return 0;
  return 1 << (value.bitLength - 1);
}

double _amplitudeToDbfs(double amplitude, double fullScale) {
  if (amplitude <= 0 || fullScale <= 0) return minSpectrumDb;
  final db = 20.0 * math.log(amplitude / fullScale) / math.ln10;
  return db < minSpectrumDb ? minSpectrumDb : db;
}

double _levelFromAmplitude(
  double amplitude,
  SpectrumUnit unit,
  double fullScale,
) {
  if (amplitude <= 0) return minSpectrumDb;
  double db;
  switch (unit) {
    case SpectrumUnit.dbfs:
      db = 20.0 * math.log(amplitude / fullScale) / math.ln10;
    case SpectrumUnit.dbv:
      db = 20.0 * math.log(amplitude / math.sqrt(2.0)) / math.ln10;
    case SpectrumUnit.dbm50:
      final power = amplitude * amplitude / 2.0;
      db = 10.0 * math.log(power / 50.0 / 1e-3) / math.ln10;
  }
  return db < minSpectrumDb ? minSpectrumDb : db;
}
