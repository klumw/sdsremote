/// Feature extraction for waveform classification.
///
/// Extracts time-domain, frequency-domain and shape features from a
/// preprocessed capture. All values come from the samples; a feature that
/// cannot be measured is `null` and never silently reported as zero.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'reference_waveform_generator.dart';
import 'waveform_analysis_models.dart';
import 'waveform_differential.dart';
import 'waveform_math.dart';
import 'waveform_preprocessor.dart';

/// Extracts the complete feature set of [preprocessed].
WaveformFeatures extractWaveformFeatures(
  PreprocessedWaveform preprocessed, {
  int harmonicCount = 5,
}) {
  final trace = preprocessed.analysis;
  final n = trace.length;
  if (n == 0) {
    return const WaveformFeatures(sampleCount: 0, durationSeconds: 0);
  }

  final values = trace.volts;
  final times = trace.times;
  final duration = trace.durationSeconds;
  final dt =
      trace.sampleIntervalSeconds ??
      preprocessed.sampleIntervalSeconds ??
      (n > 1 ? duration / (n - 1) : 1.0);
  final sampleRate = dt > 0 ? 1 / dt : 0.0;

  var vMin = values.first;
  var vMax = values.first;
  var sum = 0.0;
  var sumSquares = 0.0;
  for (final value in values) {
    if (value < vMin) vMin = value;
    if (value > vMax) vMax = value;
    sum += value;
    sumSquares += value * value;
  }
  final vMean = sum / n;
  final vRms = math.sqrt(sumSquares / n);
  final variance = math.max(0.0, sumSquares / n - vMean * vMean);
  final vStdDev = math.sqrt(variance);
  final vPp = vMax - vMin;
  final vTop = percentileOf(values, 0.95);
  final vBase = percentileOf(values, 0.05);
  final amplitude = vTop - vBase;
  final absPeak = math.max((vMax - vMean).abs(), (vMean - vMin).abs());
  final crestFactor = vRms > 0 ? absPeak / vRms : null;

  final centered = Float64List(n);
  for (var i = 0; i < n; i++) {
    centered[i] = values[i] - vMean;
  }

  final levels = amplitude > 0
      ? _analyseLevels(trace, vTop, vBase)
      : const _LevelAnalysis.empty();
  final meanPeriod = levels.periods.isEmpty ? null : _mean(levels.periods);
  final frequency =
      preprocessed.estimatedFundamentalHz ??
      (meanPeriod != null && meanPeriod > 0 ? 1 / meanPeriod : null);
  final periodSeconds =
      meanPeriod ?? (frequency != null && frequency > 0 ? 1 / frequency : null);

  final periodVariation = coefficientOfVariation(levels.periods);
  final periodMaxRatio = _periodMaxRatio(levels.periods);
  final dutyPercent = levels.dutyRatios.isEmpty
      ? null
      : _mean(levels.dutyRatios)! * 100;
  final dutyCycleVariation = coefficientOfVariation(levels.dutyRatios);
  final amplitudeVariation = coefficientOfVariation(levels.perPeriodVpp);
  final pulseWidth = levels.highDurations.isEmpty
      ? null
      : _mean(levels.highDurations);

  final slope = _analyseSlopes(
    values,
    times,
    amplitude: amplitude,
    frequency: frequency,
    sampleRate: sampleRate,
  );
  final symmetry = amplitude > 0 ? _waveformSymmetry(centered, dt) : null;

  final peakCount = _countPositivePeaks(centered, amplitude);
  final zeroCrossings = _countZeroCrossings(centered, amplitude);

  final spectral = _analyseSpectrum(
    values,
    sampleRate: sampleRate,
    fundamentalHz: frequency,
    harmonicCount: harmonicCount,
  );

  final shape = _shapeCorrelations(values, dt: dt, fundamentalHz: frequency);

  final expFit = fitExponential(values, times);
  final linearFit = fitLinear(times, values);
  final envelope = fitEnvelopeDecay(
    values,
    times,
    minimumProminence: amplitude * 0.02,
  );

  final clipping = _clippingFeatures(
    trace,
    vMax: vMax,
    vMin: vMin,
    amplitude: amplitude,
    frequency: frequency,
  );
  final flatness = _flatnessFeatures(
    values,
    vTop: vTop,
    vBase: vBase,
    amplitude: amplitude,
  );
  final residual = _sineResidualFeatures(
    centered,
    times,
    sampleRate: sampleRate,
    fundamentalHz: frequency,
    harmonicCount: harmonicCount,
  );

  // Differential sign statistics (section 4 of Xiao et al., Electronics 2026).
  // They are extracted from the same analysis samples, so a generated
  // reference and the capture are described in the same feature space.
  final differential = extractDifferentialFeatures(
    values,
    sampleIntervalSeconds: dt,
    fundamentalHz: frequency,
  );

  final logarithmicDecrement =
      envelope != null &&
          envelope.decayRatePerSecond > 0 &&
          periodSeconds != null &&
          periodSeconds > 0
      ? envelope.decayRatePerSecond * periodSeconds
      : null;

  final rampLinearity = slope.rampLinearity;
  final oscillationRegularity = periodVariation == null
      ? null
      : clamp01(1 - periodVariation);

  final periodCount = levels.periods.length;

  return WaveformFeatures(
    sampleCount: n,
    durationSeconds: duration,
    sampleIntervalSeconds: dt,
    vMin: vMin,
    vMax: vMax,
    vPp: vPp,
    vMean: vMean,
    vRms: vRms,
    vStdDev: vStdDev,
    vTop: vTop,
    vBase: vBase,
    crestFactor: crestFactor,
    frequencyHz: frequency,
    periodSeconds: periodSeconds,
    periodCount: periodCount,
    periodVariation: periodVariation,
    periodMaxRatio: periodMaxRatio,
    dutyPercent: dutyPercent,
    dutyCycleVariation: dutyCycleVariation,
    pulseWidthSeconds: pulseWidth,
    riseTimeSeconds: levels.riseTimeSeconds,
    fallTimeSeconds: levels.fallTimeSeconds,
    edgeSteepness: slope.edgeSteepness,
    positiveSlopeVoltsPerSecond: slope.positiveSlope,
    negativeSlopeVoltsPerSecond: slope.negativeSlope,
    slopeSymmetry: slope.slopeSymmetry,
    symmetry: symmetry,
    peakCount: peakCount,
    zeroCrossingCount: zeroCrossings,
    risingEdgeCount: levels.risingTimes.length,
    fallingEdgeCount: levels.fallingTimes.length,
    pulseCount: levels.pulseCount,
    amplitudeVariation: amplitudeVariation,
    dominantFrequencyHz: spectral.dominantFrequencyHz,
    harmonicAmplitudes: spectral.harmonics,
    thdPercent: spectral.thdPercent,
    thdDb: spectral.thdDb,
    snrDb: spectral.snrDb,
    spectralCentroidHz: spectral.centroidHz,
    lowBandEnergyRatio: spectral.lowBandRatio,
    midBandEnergyRatio: spectral.midBandRatio,
    highBandEnergyRatio: spectral.highBandRatio,
    noiseFloorVolts: spectral.noiseFloorVolts,
    sineCorrelation: shape.sine,
    squareCorrelation: shape.square,
    triangleCorrelation: shape.triangle,
    sawtoothCorrelation: shape.sawtooth,
    plateauStability: flatness.plateauStability,
    twoLevelRatio: flatness.twoLevelRatio,
    rampLinearity: rampLinearity,
    exponentialFitR2: expFit?.r2,
    exponentialTauSeconds: expFit?.tauSeconds,
    exponentialRising: expFit?.rising ?? (values.last > values.first),
    linearFitR2: linearFit.r2,
    envelopeDecayRate: envelope?.decayRatePerSecond,
    envelopeDecayR2: envelope?.r2,
    oscillationRegularity: oscillationRegularity,
    clippingRatio: clipping.totalRatio,
    upperClippingRatio: clipping.upperRatio,
    lowerClippingRatio: clipping.lowerRatio,
    clippedRegionCount: clipping.regionCount,
    monotonicFraction: monotonicRunFraction(values),
    resetRatio: slope.resetRatio,
    sineResidualRmsRatio: residual.rmsRatio,
    sineResidualSnrDb: residual.snrDb,
    residualSpectralFlatness: residual.spectralFlatness,
    residualHarmonicEnergyRatio: residual.harmonicEnergyRatio,
    sinePhaseRadians: residual.phaseRadians,
    logarithmicDecrement: logarithmicDecrement,
    differential: differential,
    periods: levels.periods,
    dutyRatios: levels.dutyRatios,
    perPeriodVpp: levels.perPeriodVpp,
    risingEdgeTimes: levels.risingTimes,
    fallingEdgeTimes: levels.fallingTimes,
    clippedRegions: clipping.regions,
  );
}

/// Builds a lightweight preprocessed view of a generated reference.
///
/// The known reference frequency is passed directly, so no autocorrelation is
/// needed for the many reference variants generated per classification.
PreprocessedWaveform preprocessedReference(
  ReferenceWaveform reference, {
  int maxAnalysisPoints = 4096,
}) {
  final trace = reference.trace;
  final stride = math.max(
    1,
    (trace.length / math.max(8, maxAnalysisPoints)).ceil(),
  );
  final analysis = stride == 1
      ? trace
      : WaveformTrace(
          times: Float64List.fromList([
            for (var i = 0; i < trace.length; i += stride) trace.times[i],
          ]),
          volts: Float64List.fromList([
            for (var i = 0; i < trace.length; i += stride) trace.volts[i],
          ]),
        );
  final periodic = switch (reference.type) {
    WaveformSignalType.sine ||
    WaveformSignalType.square ||
    WaveformSignalType.triangle ||
    WaveformSignalType.sawtooth ||
    WaveformSignalType.pulse ||
    WaveformSignalType.pwm ||
    WaveformSignalType.clippedSine ||
    WaveformSignalType.noisySine ||
    WaveformSignalType.dampedOscillation => reference.parameters.frequencyHz,
    WaveformSignalType.exponentialDecay => null,
  };
  return PreprocessedWaveform(
    original: trace,
    cleaned: trace,
    analysis: analysis,
    normalized: zScore(analysis.volts),
    sampleIntervalSeconds: analysis.sampleIntervalSeconds,
    estimatedFundamentalHz: periodic,
    removedSamples: 0,
    cleanedSampleCount: trace.length,
    warnings: const [],
    sufficient: analysis.length >= 16 && analysis.durationSeconds > 0,
  );
}

class _LevelAnalysis {
  final List<double> risingTimes;
  final List<double> fallingTimes;
  final List<double> periods;
  final List<double> dutyRatios;
  final List<double> highDurations;
  final List<double> perPeriodVpp;
  final double? riseTimeSeconds;
  final double? fallTimeSeconds;
  final int pulseCount;

  const _LevelAnalysis({
    this.risingTimes = const [],
    this.fallingTimes = const [],
    this.periods = const [],
    this.dutyRatios = const [],
    this.highDurations = const [],
    this.perPeriodVpp = const [],
    this.riseTimeSeconds,
    this.fallTimeSeconds,
    this.pulseCount = 0,
  });

  const _LevelAnalysis.empty()
    : risingTimes = const [],
      fallingTimes = const [],
      periods = const [],
      dutyRatios = const [],
      highDurations = const [],
      perPeriodVpp = const [],
      riseTimeSeconds = null,
      fallTimeSeconds = null,
      pulseCount = 0;
}

_LevelAnalysis _analyseLevels(WaveformTrace trace, double vTop, double vBase) {
  final values = trace.volts;
  final times = trace.times;
  final n = values.length;
  final amplitude = vTop - vBase;
  if (n < 8 || amplitude <= 0) return const _LevelAnalysis.empty();

  final mid = (vTop + vBase) / 2;
  final hysteresis = amplitude * 0.05;
  final lowArmedThreshold = mid - hysteresis;
  final highArmedThreshold = mid + hysteresis;

  final risingTimes = <double>[];
  final fallingTimes = <double>[];
  final risingIndices = <int>[];
  final fallingIndices = <int>[];

  var lowArmed = false;
  var highArmed = false;
  double? previousTime;
  double? previousValue;

  for (var i = 0; i < n; i++) {
    final value = values[i];
    final time = times[i];
    if (previousValue != null) {
      if (previousValue < mid && value >= mid && lowArmed) {
        risingTimes.add(
          _interpolateTime(previousTime!, previousValue, time, value, mid),
        );
        risingIndices.add(i);
      } else if (previousValue >= mid && value < mid && highArmed) {
        fallingTimes.add(
          _interpolateTime(previousTime!, previousValue, time, value, mid),
        );
        fallingIndices.add(i);
      }
    }
    if (value < lowArmedThreshold) {
      lowArmed = true;
      highArmed = false;
    } else if (value > highArmedThreshold) {
      highArmed = true;
      lowArmed = false;
    }
    previousTime = time;
    previousValue = value;
  }

  final periods = <double>[];
  for (var i = 1; i < risingTimes.length; i++) {
    final period = risingTimes[i] - risingTimes[i - 1];
    if (period > 0 && period.isFinite) periods.add(period);
  }

  final dutyRatios = <double>[];
  final highDurations = <double>[];
  var pulseCount = 0;
  for (var i = 0; i < risingTimes.length; i++) {
    final rise = risingTimes[i];
    double? fall;
    for (final candidate in fallingTimes) {
      if (candidate > rise) {
        fall = candidate;
        break;
      }
    }
    if (fall == null) continue;
    pulseCount++;
    double? period;
    if (i + 1 < risingTimes.length) {
      period = risingTimes[i + 1] - rise;
    } else if (periods.isNotEmpty) {
      period = periods.last;
    }
    final high = fall - rise;
    if (high <= 0) continue;
    highDurations.add(high);
    if (period != null && period > 0) {
      dutyRatios.add((high / period).clamp(0.0, 1.0));
    }
  }

  final perPeriodVpp = <double>[];
  for (var i = 1; i < risingIndices.length; i++) {
    final start = risingIndices[i - 1];
    final end = math.min(n - 1, risingIndices[i]);
    if (end <= start) continue;
    var min = values[start];
    var max = values[start];
    for (var j = start; j <= end; j++) {
      if (values[j] < min) min = values[j];
      if (values[j] > max) max = values[j];
    }
    perPeriodVpp.add(max - min);
  }

  final periodSamples = periods.isNotEmpty
      ? (periods.reduce((a, b) => a + b) / periods.length / _dt(trace))
      : null;
  final window = periodSamples == null
      ? math.max(8, n ~/ 4)
      : math.max(8, (periodSamples / 2).round());

  final riseDurations = <double>[];
  for (final index in risingIndices) {
    final duration = _risingDuration(
      values,
      times,
      index,
      lowReference: vBase + 0.1 * amplitude,
      highReference: vBase + 0.9 * amplitude,
      window: window,
    );
    if (duration != null && duration > 0) riseDurations.add(duration);
  }
  final fallDurations = <double>[];
  for (final index in fallingIndices) {
    final duration = _fallingDuration(
      values,
      times,
      index,
      lowReference: vBase + 0.1 * amplitude,
      highReference: vBase + 0.9 * amplitude,
      window: window,
    );
    if (duration != null && duration > 0) fallDurations.add(duration);
  }

  return _LevelAnalysis(
    risingTimes: risingTimes,
    fallingTimes: fallingTimes,
    periods: periods,
    dutyRatios: dutyRatios,
    highDurations: highDurations,
    perPeriodVpp: perPeriodVpp,
    riseTimeSeconds: riseDurations.isEmpty ? null : _mean(riseDurations),
    fallTimeSeconds: fallDurations.isEmpty ? null : _mean(fallDurations),
    pulseCount: pulseCount,
  );
}

double _dt(WaveformTrace trace) {
  final interval = trace.sampleIntervalSeconds;
  if (interval != null && interval > 0) return interval;
  return trace.length > 1 ? trace.durationSeconds / (trace.length - 1) : 1;
}

double? _risingDuration(
  Float64List values,
  Float64List times,
  int crossingIndex, {
  required double lowReference,
  required double highReference,
  required int window,
}) {
  final n = values.length;
  var lowIndex = crossingIndex;
  final lowStop = math.max(0, crossingIndex - window);
  while (lowIndex > lowStop && values[lowIndex] > lowReference) {
    lowIndex--;
  }
  if (values[lowIndex] > lowReference || lowIndex + 1 >= n) return null;

  var highIndex = crossingIndex;
  final highStop = math.min(n - 1, crossingIndex + window);
  while (highIndex < highStop && values[highIndex] < highReference) {
    highIndex++;
  }
  if (values[highIndex] < highReference || highIndex == 0) return null;

  final lowTime = _interpolateTime(
    times[lowIndex],
    values[lowIndex],
    times[lowIndex + 1],
    values[lowIndex + 1],
    lowReference,
  );
  final highTime = _interpolateTime(
    times[highIndex - 1],
    values[highIndex - 1],
    times[highIndex],
    values[highIndex],
    highReference,
  );
  return highTime - lowTime;
}

double? _fallingDuration(
  Float64List values,
  Float64List times,
  int crossingIndex, {
  required double lowReference,
  required double highReference,
  required int window,
}) {
  final n = values.length;
  var highIndex = crossingIndex;
  final highStop = math.max(0, crossingIndex - window);
  while (highIndex > highStop && values[highIndex] < highReference) {
    highIndex--;
  }
  if (values[highIndex] < highReference || highIndex + 1 >= n) return null;

  var lowIndex = crossingIndex;
  final lowStop = math.min(n - 1, crossingIndex + window);
  while (lowIndex < lowStop && values[lowIndex] > lowReference) {
    lowIndex++;
  }
  if (values[lowIndex] > lowReference || lowIndex == 0) return null;

  final highTime = _interpolateTime(
    times[highIndex],
    values[highIndex],
    times[highIndex + 1],
    values[highIndex + 1],
    highReference,
  );
  final lowTime = _interpolateTime(
    times[lowIndex - 1],
    values[lowIndex - 1],
    times[lowIndex],
    values[lowIndex],
    lowReference,
  );
  return lowTime - highTime;
}

class _SlopeAnalysis {
  final double? rampLinearity;
  final double? positiveSlope;
  final double? negativeSlope;
  final double? slopeSymmetry;
  final double? resetRatio;
  final double? edgeSteepness;

  const _SlopeAnalysis({
    this.rampLinearity,
    this.positiveSlope,
    this.negativeSlope,
    this.slopeSymmetry,
    this.resetRatio,
    this.edgeSteepness,
  });
}

_SlopeAnalysis _analyseSlopes(
  Float64List values,
  Float64List times, {
  required double amplitude,
  required double? frequency,
  required double sampleRate,
}) {
  final n = values.length;
  if (n < 8 || sampleRate <= 0) return const _SlopeAnalysis();
  final dt = 1 / sampleRate;
  final derivatives = Float64List(n - 1);
  final positive = <double>[];
  final negative = <double>[];
  for (var i = 0; i < n - 1; i++) {
    final derivative = (values[i + 1] - values[i]) * sampleRate;
    derivatives[i] = derivative;
    if (derivative > 0) positive.add(derivative);
    if (derivative < 0) negative.add(-derivative);
  }
  if (positive.isEmpty && negative.isEmpty) return const _SlopeAnalysis();

  final positiveSlope = positive.isEmpty
      ? null
      : _mean(_topValues(positive, 0.02));
  final negativeSlope = negative.isEmpty
      ? null
      : _mean(_topValues(negative, 0.02));
  final slopeSymmetry = _symmetryOf(positiveSlope, negativeSlope);
  final resetRatio = _ratioOf(positiveSlope, negativeSlope);

  final sortedAbs = Float64List(n - 1);
  for (var i = 0; i < n - 1; i++) {
    sortedAbs[i] = derivatives[i].abs();
  }
  final topCount = math.max(1, (sortedAbs.length * 0.01).round());
  final topValues = _topValues(sortedAbs.toList(), 0.01);
  final edgeSlope = topCount == 0 || topValues.isEmpty
      ? 0.0
      : topValues.reduce((a, b) => a + b) / topValues.length;
  double? edgeSteepness;
  if (amplitude > 0 && frequency != null && frequency > 0) {
    edgeSteepness = edgeSlope / (amplitude * frequency);
  } else if (amplitude > 0) {
    edgeSteepness = edgeSlope / (amplitude / dt);
  }

  final runs = _monotonicRuns(values, tolerance: amplitude * 0.005);
  final linearities = <double>[];
  for (final run in runs) {
    if (run.end - run.start < math.max(4, n ~/ 100)) continue;
    final length = run.end - run.start + 1;
    final x = Float64List(length);
    final y = Float64List(length);
    for (var i = 0; i < length; i++) {
      x[i] = times[run.start + i];
      y[i] = values[run.start + i];
    }
    final fit = fitLinear(x, y);
    if (fit.r2.isFinite) linearities.add(fit.r2);
  }

  return _SlopeAnalysis(
    rampLinearity: linearities.isEmpty ? null : _mean(linearities),
    positiveSlope: positiveSlope,
    negativeSlope: negativeSlope,
    slopeSymmetry: slopeSymmetry,
    resetRatio: resetRatio,
    edgeSteepness: edgeSteepness?.isFinite == true ? edgeSteepness : null,
  );
}

class _MonotonicRun {
  final int start;
  final int end;

  const _MonotonicRun(this.start, this.end);
}

List<_MonotonicRun> _monotonicRuns(
  Float64List values, {
  required double tolerance,
}) {
  final runs = <_MonotonicRun>[];
  if (values.length < 2) return runs;
  var start = 0;
  var direction = 0;
  for (var i = 1; i < values.length; i++) {
    final delta = values[i] - values[i - 1];
    if (delta.abs() <= tolerance) continue;
    final sign = delta > 0 ? 1 : -1;
    if (direction == 0) {
      direction = sign;
    } else if (sign != direction) {
      if (i - 1 > start) runs.add(_MonotonicRun(start, i - 1));
      start = i - 1;
      direction = sign;
    }
  }
  if (values.length - 1 > start) {
    runs.add(_MonotonicRun(start, values.length - 1));
  }
  return runs;
}

List<double> _topValues(List<double> values, double fraction) {
  if (values.isEmpty) return const [];
  final sorted = [...values]..sort((a, b) => b.compareTo(a));
  final count = math.max(1, (sorted.length * fraction).round());
  return sorted.sublist(0, math.min(count, sorted.length));
}

class _ShapeCorrelations {
  final double? sine;
  final double? square;
  final double? triangle;
  final double? sawtooth;

  const _ShapeCorrelations({
    this.sine,
    this.square,
    this.triangle,
    this.sawtooth,
  });
}

_ShapeCorrelations _shapeCorrelations(
  Float64List values, {
  required double dt,
  required double? fundamentalHz,
}) {
  if (fundamentalHz == null ||
      fundamentalHz <= 0 ||
      values.length < 8 ||
      dt <= 0) {
    return const _ShapeCorrelations();
  }
  final n = values.length;
  final phaseStep = fundamentalHz * dt;

  Float64List ideal(WaveformSignalType type, {bool rising = true}) {
    final result = Float64List(n);
    for (var i = 0; i < n; i++) {
      result[i] = ReferenceWaveformGenerator.shapeValue(
        type,
        i * phaseStep,
        directionIsRising: rising,
      );
    }
    return result;
  }

  double correlation(Float64List other) {
    final target = math.min(512, math.min(values.length, other.length));
    final capture = resampleValues(values, target);
    final reference = resampleValues(other, target);
    final minimumOverlap = math.max(8, (target / 3).round());
    return clamp01(
      maxNormalizedCrossCorrelation(
        capture,
        reference,
        maxLag: target - minimumOverlap,
        minimumOverlap: minimumOverlap,
      ).coefficient,
    );
  }

  final sawtoothRising = correlation(
    ideal(WaveformSignalType.sawtooth, rising: true),
  );
  final sawtoothFalling = correlation(
    ideal(WaveformSignalType.sawtooth, rising: false),
  );

  return _ShapeCorrelations(
    sine: correlation(ideal(WaveformSignalType.sine)),
    square: correlation(ideal(WaveformSignalType.square)),
    triangle: correlation(ideal(WaveformSignalType.triangle)),
    sawtooth: math.max(sawtoothRising, sawtoothFalling),
  );
}

class _SpectrumFeatures {
  final double? dominantFrequencyHz;
  final List<double> harmonics;
  final double? thdPercent;
  final double? thdDb;
  final double? snrDb;
  final double? centroidHz;
  final double? lowBandRatio;
  final double? midBandRatio;
  final double? highBandRatio;
  final double? noiseFloorVolts;

  const _SpectrumFeatures({
    this.dominantFrequencyHz,
    this.harmonics = const [],
    this.thdPercent,
    this.thdDb,
    this.snrDb,
    this.centroidHz,
    this.lowBandRatio,
    this.midBandRatio,
    this.highBandRatio,
    this.noiseFloorVolts,
  });
}

_SpectrumFeatures _analyseSpectrum(
  Float64List values, {
  required double sampleRate,
  required double? fundamentalHz,
  required int harmonicCount,
}) {
  if (values.length < 8 || sampleRate <= 0) return const _SpectrumFeatures();
  final spectrum = computeSpectrum(values, sampleRate);
  final dominantFrequency = spectrum.dominantFrequency;
  final count = harmonicCount.clamp(1, 10);

  final amplitudes = <double>[];
  if (fundamentalHz != null && fundamentalHz > 0) {
    for (var harmonic = 1; harmonic <= count; harmonic++) {
      amplitudes.add(spectrum.amplitudeNear(harmonic * fundamentalHz) ?? 0.0);
    }
  }

  double? thdPercent;
  double? thdDb;
  if (amplitudes.length >= 2 && amplitudes.first > 1e-12) {
    var harmonicPower = 0.0;
    for (var i = 1; i < amplitudes.length; i++) {
      harmonicPower += amplitudes[i] * amplitudes[i];
    }
    thdPercent = math.sqrt(harmonicPower) / amplitudes.first * 100;
    thdDb = thdPercent > 0 ? 20 * math.log(thdPercent / 100) / math.ln10 : null;
  }

  final bins = spectrum.amplitudes.length;
  var totalPower = 0.0;
  var centroidNumerator = 0.0;
  var centroidDenominator = 0.0;
  var lowPower = 0.0;
  var midPower = 0.0;
  var highPower = 0.0;
  final lowEdge = fundamentalHz != null && fundamentalHz > 0
      ? fundamentalHz / 2
      : sampleRate / 6;
  final midEdge = fundamentalHz != null && fundamentalHz > 0
      ? fundamentalHz * 2
      : sampleRate / 3;
  for (var i = 1; i < bins; i++) {
    final amplitude = spectrum.amplitudes[i];
    if (!amplitude.isFinite) continue;
    final power = amplitude * amplitude / 2;
    totalPower += power;
    centroidNumerator += spectrum.frequencies[i] * amplitude;
    centroidDenominator += amplitude;
    final frequency = spectrum.frequencies[i];
    if (frequency < lowEdge) {
      lowPower += power;
    } else if (frequency < midEdge) {
      midPower += power;
    } else {
      highPower += power;
    }
  }

  double? signalPower;
  if (amplitudes.isNotEmpty) {
    signalPower = 0;
    for (final amplitude in amplitudes) {
      signalPower = signalPower! + amplitude * amplitude / 2;
    }
  }

  double? snrDb;
  if (signalPower != null && signalPower > 0 && totalPower > 0) {
    // Estimate the noise power from the bins outside the fundamental and
    // harmonic main lobes. Including the window leakage of the signal itself
    // in the "noise" would report an unrealistically low SNR for a clean
    // tone (a Hann window spreads several percent of the signal power into
    // its side lobes).
    final excludedBins = <int>{};
    if (fundamentalHz != null && fundamentalHz > 0) {
      for (var harmonic = 1; harmonic <= amplitudes.length; harmonic++) {
        final center = (harmonic * fundamentalHz / spectrum.resolutionHz)
            .round();
        for (var bin = center - 4; bin <= center + 4; bin++) {
          if (bin >= 0 && bin < bins) excludedBins.add(bin);
        }
      }
    }
    var noisePower = 0.0;
    for (var i = 1; i < bins; i++) {
      if (excludedBins.contains(i)) continue;
      final amplitude = spectrum.amplitudes[i];
      if (amplitude.isFinite) noisePower += amplitude * amplitude / 2;
    }
    snrDb = noisePower <= 1e-18
        ? 120.0
        : 10 * math.log(signalPower / noisePower) / math.ln10;
  }

  double? noiseFloor;
  if (bins > 8) {
    final upper = <double>[];
    for (var i = bins ~/ 2; i < bins; i++) {
      upper.add(spectrum.amplitudes[i]);
    }
    if (upper.isNotEmpty) {
      upper.sort();
      noiseFloor = upper[upper.length ~/ 2];
    }
  }

  double? ratio(double power) => totalPower > 0 ? power / totalPower : null;

  return _SpectrumFeatures(
    dominantFrequencyHz: dominantFrequency,
    harmonics: amplitudes,
    thdPercent: thdPercent,
    thdDb: thdDb,
    snrDb: snrDb,
    centroidHz: centroidDenominator > 0
        ? centroidNumerator / centroidDenominator
        : null,
    lowBandRatio: ratio(lowPower),
    midBandRatio: ratio(midPower),
    highBandRatio: ratio(highPower),
    noiseFloorVolts: noiseFloor,
  );
}

class _ResidualFeatures {
  final double? rmsRatio;
  final double? snrDb;
  final double? spectralFlatness;
  final double? harmonicEnergyRatio;
  final double? phaseRadians;

  const _ResidualFeatures({
    this.rmsRatio,
    this.snrDb,
    this.spectralFlatness,
    this.harmonicEnergyRatio,
    this.phaseRadians,
  });
}

_ResidualFeatures _sineResidualFeatures(
  Float64List centered,
  Float64List times, {
  required double sampleRate,
  required double? fundamentalHz,
  required int harmonicCount,
}) {
  if (fundamentalHz == null ||
      fundamentalHz <= 0 ||
      sampleRate <= 0 ||
      centered.length < 8) {
    return const _ResidualFeatures();
  }
  final n = centered.length;
  final omega = 2 * math.pi * fundamentalHz;
  var sss = 0.0;
  var scc = 0.0;
  var ssc = 0.0;
  var ssy = 0.0;
  var scy = 0.0;
  for (var i = 0; i < n; i++) {
    final angle = omega * times[i];
    final sine = math.sin(angle);
    final cosine = math.cos(angle);
    sss += sine * sine;
    scc += cosine * cosine;
    ssc += sine * cosine;
    ssy += sine * centered[i];
    scy += cosine * centered[i];
  }
  final determinant = sss * scc - ssc * ssc;
  if (determinant.abs() < 1e-15) return const _ResidualFeatures();
  final a = (ssy * scc - scy * ssc) / determinant;
  final b = (scy * sss - ssy * ssc) / determinant;

  final residual = Float64List(n);
  var fitPower = 0.0;
  var residualPower = 0.0;
  for (var i = 0; i < n; i++) {
    final angle = omega * times[i];
    final fitted = a * math.sin(angle) + b * math.cos(angle);
    final value = centered[i] - fitted;
    residual[i] = value;
    fitPower += fitted * fitted;
    residualPower += value * value;
  }
  final rmsFit = math.sqrt(fitPower / n);
  final rmsResidual = math.sqrt(residualPower / n);
  final signalRms = math.sqrt(
    centered.fold<double>(0, (sum, value) => sum + value * value) / n,
  );
  final rmsRatio = signalRms > 0 ? rmsResidual / signalRms : null;
  final snrDb = rmsResidual > 0
      ? 20 * math.log(math.max(rmsFit, 1e-15) / rmsResidual) / math.ln10
      : 120.0;

  final residualSpectrum = computeSpectrum(residual, sampleRate);
  var total = 0.0;
  for (var i = 2; i < residualSpectrum.amplitudes.length; i++) {
    total += residualSpectrum.amplitudes[i] * residualSpectrum.amplitudes[i];
  }
  var harmonic = 0.0;
  for (var k = 2; k <= harmonicCount.clamp(2, 10); k++) {
    final amplitude = residualSpectrum.amplitudeNear(k * fundamentalHz);
    if (amplitude != null) harmonic += amplitude * amplitude;
  }
  final harmonicRatio = total > 0 ? harmonic / total : null;

  double? flatness;
  if (residualSpectrum.amplitudes.length > 16) {
    var logSum = 0.0;
    var arithmetic = 0.0;
    var count = 0;
    for (var i = 2; i < residualSpectrum.amplitudes.length; i++) {
      final amplitude = residualSpectrum.amplitudes[i];
      if (amplitude <= 1e-18) continue;
      logSum += math.log(amplitude);
      arithmetic += amplitude;
      count++;
    }
    if (count > 0 && arithmetic > 0) {
      final geometric = math.exp(logSum / count);
      flatness = (geometric / (arithmetic / count)).clamp(0.0, 1.0);
    }
  }

  return _ResidualFeatures(
    rmsRatio: rmsRatio,
    snrDb: snrDb,
    spectralFlatness: flatness,
    harmonicEnergyRatio: harmonicRatio,
    phaseRadians: math.atan2(b, a),
  );
}

class _ClippingFeatures {
  final double? totalRatio;
  final double? upperRatio;
  final double? lowerRatio;
  final int regionCount;
  final List<(double, double)> regions;

  const _ClippingFeatures({
    this.totalRatio,
    this.upperRatio,
    this.lowerRatio,
    this.regionCount = 0,
    this.regions = const [],
  });
}

_ClippingFeatures _clippingFeatures(
  WaveformTrace trace, {
  required double vMax,
  required double vMin,
  required double amplitude,
  required double? frequency,
}) {
  final n = trace.length;
  if (n < 8 || amplitude <= 0) return const _ClippingFeatures();
  final epsilon = amplitude * 0.005;
  final dt = trace.sampleIntervalSeconds;
  final periodSamples = frequency != null && frequency > 0 && dt != null
      ? 1 / (frequency * dt)
      : null;
  // A smooth sine spends acos(1 - epsilon / A) / pi of a period inside the
  // epsilon band around its peak. A hard clip stays on the rail for the much
  // longer interval above the clipping level. Requiring at least 1.8 times the
  // natural band duration rejects rounded peaks and 8-bit quantisation
  // plateaus while keeping real clipping.
  final naturalBandSamples = periodSamples == null
      ? null
      : math.acos((1 - epsilon / amplitude).clamp(-1.0, 1.0)) /
            math.pi *
            periodSamples;
  final minimumRun = math.max(
    3,
    math.max(
      (n * 0.005).round(),
      naturalBandSamples == null ? 0 : (naturalBandSamples * 1.8).ceil(),
    ),
  );
  final regions = <(double, double)>[];
  var upperCount = 0;
  var lowerCount = 0;

  void scan(bool upper) {
    var runStart = -1;
    for (var i = 0; i <= n; i++) {
      final inLevel =
          i < n &&
          (upper
              ? trace.volts[i] >= vMax - epsilon
              : trace.volts[i] <= vMin + epsilon);
      if (inLevel && runStart < 0) {
        runStart = i;
      } else if (!inLevel && runStart >= 0) {
        final length = i - runStart;
        if (length >= minimumRun) {
          if (upper) {
            upperCount += length;
          } else {
            lowerCount += length;
          }
          regions.add((trace.times[runStart], trace.times[i - 1]));
        }
        runStart = -1;
      }
    }
  }

  scan(true);
  scan(false);
  return _ClippingFeatures(
    totalRatio: (upperCount + lowerCount) / n,
    upperRatio: upperCount / n,
    lowerRatio: lowerCount / n,
    regionCount: regions.length,
    regions: regions,
  );
}

class _FlatnessFeatures {
  final double? plateauStability;
  final double? twoLevelRatio;

  const _FlatnessFeatures({this.plateauStability, this.twoLevelRatio});
}

_FlatnessFeatures _flatnessFeatures(
  Float64List values, {
  required double vTop,
  required double vBase,
  required double amplitude,
}) {
  final n = values.length;
  if (n < 8 || amplitude <= 0) return const _FlatnessFeatures();
  final twoLevelBand = amplitude * 0.1;
  var twoLevel = 0;
  for (final value in values) {
    if ((value - vTop).abs() <= twoLevelBand ||
        (value - vBase).abs() <= twoLevelBand) {
      twoLevel++;
    }
  }

  final plateauBand = amplitude * 0.05;
  final minimumRun = math.max(3, (n * 0.002).round());
  var plateauSamples = 0;
  bool inLevel(int index) =>
      (values[index] - vTop).abs() <= plateauBand ||
      (values[index] - vBase).abs() <= plateauBand;
  var runStart = -1;
  for (var i = 0; i <= n; i++) {
    final level = i < n && inLevel(i);
    if (level && runStart < 0) {
      runStart = i;
    } else if (!level && runStart >= 0) {
      final length = i - runStart;
      if (length >= minimumRun) plateauSamples += length;
      runStart = -1;
    }
  }

  return _FlatnessFeatures(
    plateauStability: plateauSamples / n,
    twoLevelRatio: twoLevel / n,
  );
}

int _countPositivePeaks(Float64List centered, double amplitude) {
  if (amplitude <= 0 || centered.length < 5) return 0;
  final extrema = localExtremaIndices(
    centered,
    minProminence: amplitude * 0.05,
    minDistance: 3,
  );
  var count = 0;
  for (final index in extrema) {
    if (centered[index] > 0) count++;
  }
  return count;
}

int _countZeroCrossings(Float64List centered, double amplitude) {
  if (amplitude <= 0 || centered.length < 4) return 0;
  final threshold = amplitude * 0.05;
  var armedLow = false;
  var armedHigh = false;
  var count = 0;
  for (final value in centered) {
    if (value < -threshold) {
      if (armedHigh) count++;
      armedLow = true;
      armedHigh = false;
    } else if (value > threshold) {
      if (armedLow) count++;
      armedLow = false;
      armedHigh = true;
    }
  }
  return count;
}

double? _waveformSymmetry(Float64List centered, double dt) {
  if (centered.length < 2 || dt <= 0) return null;
  var positiveArea = 0.0;
  var negativeArea = 0.0;
  for (final value in centered) {
    if (value > 0) {
      positiveArea += value;
    } else {
      negativeArea -= value;
    }
  }
  final total = positiveArea + negativeArea;
  if (total <= 1e-15) return null;
  return 1 - (positiveArea - negativeArea).abs() / total;
}

double? _periodMaxRatio(List<double> periods) {
  if (periods.length < 2) return null;
  final sorted = [...periods]..sort();
  final median = sorted.length.isOdd
      ? sorted[sorted.length ~/ 2]
      : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
  if (median <= 0) return null;
  return sorted.last / median;
}

double? _symmetryOf(double? positive, double? negative) {
  if (positive == null || negative == null) return null;
  final maximum = math.max(positive.abs(), negative.abs());
  if (maximum <= 1e-12) return null;
  return 1 - (positive.abs() - negative.abs()).abs() / maximum;
}

double? _ratioOf(double? positive, double? negative) {
  if (positive == null || negative == null) return null;
  final larger = math.max(positive.abs(), negative.abs());
  final smaller = math.min(positive.abs(), negative.abs());
  if (smaller <= 1e-12) return larger > 1e-12 ? 1000.0 : null;
  return larger / smaller;
}

double _interpolateTime(
  double t0,
  double v0,
  double t1,
  double v1,
  double target,
) {
  final denominator = v1 - v0;
  if (denominator == 0 || !denominator.isFinite) return t0;
  final fraction = ((target - v0) / denominator).clamp(0.0, 1.0).toDouble();
  return t0 + (t1 - t0) * fraction;
}

double? _mean(List<double> values) {
  if (values.isEmpty) return null;
  var sum = 0.0;
  for (final value in values) {
    sum += value;
  }
  return sum / values.length;
}
