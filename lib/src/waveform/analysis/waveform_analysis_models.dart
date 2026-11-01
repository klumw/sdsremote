/// Data models shared by the waveform classification and reference
/// comparison engine.
///
/// This library is intentionally free of Flutter dependencies so the engine
/// runs in unit tests, in a background isolate and inside AI tool callbacks.
/// All result models implement [toMap] with JSON-safe values (`null` instead
/// of NaN or infinity), so they can cross an isolate boundary and be handed to
/// the Waveform AI Agent unchanged.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Reference signal types supported by the classification engine.
enum WaveformSignalType {
  sine('sine', 'Sine wave'),
  square('square', 'Square wave'),
  triangle('triangle', 'Triangle wave'),
  sawtooth('sawtooth', 'Sawtooth wave'),
  pulse('pulse', 'Pulse'),
  exponentialDecay('exponential_decay', 'Exponential decay'),
  dampedOscillation('damped_oscillation', 'Damped oscillation'),
  clippedSine('clipped_sine', 'Clipped sine wave'),
  noisySine('noisy_sine', 'Noisy sine wave'),
  pwm('pwm', 'PWM signal');

  const WaveformSignalType(this.id, this.label);

  /// Stable identifier used in tool calls, options and result maps.
  final String id;

  /// Human-readable name shown in the UI and quoted by the AI agent.
  final String label;

  /// Parses an [id], [name] or label (case-insensitive).
  static WaveformSignalType? parse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final type in values) {
      if (type.id == normalized ||
          type.label.toLowerCase() == normalized ||
          type.name.toLowerCase() == normalized) {
        return type;
      }
    }
    return null;
  }
}

/// Similarity-based confidence band of a classification result.
///
/// These bands describe the similarity score; they are not calibrated
/// statistical probabilities.
enum ClassificationConfidence {
  veryHigh('Very high'),
  high('High'),
  moderate('Moderate'),
  low('Low'),
  uncertain('Uncertain');

  const ClassificationConfidence(this.label);

  final String label;

  static ClassificationConfidence fromScore(double score) {
    if (score >= 90) return veryHigh;
    if (score >= 75) return high;
    if (score >= 60) return moderate;
    if (score >= 40) return low;
    return uncertain;
  }
}

/// Severity of a detected waveform anomaly.
enum AnomalySeverity {
  info('Info'),
  minor('Minor'),
  moderate('Moderate'),
  severe('Severe');

  const AnomalySeverity(this.label);

  final String label;
}

/// A time-domain waveform as parallel time and voltage arrays.
///
/// The original samples are kept; normalisation is only applied to derived
/// copies used for shape comparison.
class WaveformTrace {
  final Float64List times;
  final Float64List volts;
  final String? channel;

  WaveformTrace({required this.times, required this.volts, this.channel})
    : assert(times.length == volts.length);

  /// Builds a trace from `(time, voltage)` pairs.
  ///
  /// Non-finite values are removed, the samples are sorted by time and
  /// duplicate timestamps are collapsed.
  factory WaveformTrace.fromPoints(
    Iterable<(double, double)> points, {
    String? channel,
  }) {
    final valid = <(double, double)>[];
    for (final (time, voltage) in points) {
      if (time.isFinite && voltage.isFinite) valid.add((time, voltage));
    }
    valid.sort((a, b) => a.$1.compareTo(b.$1));

    final times = <double>[];
    final volts = <double>[];
    for (final (time, voltage) in valid) {
      if (times.isNotEmpty && time <= times.last) continue;
      times.add(time);
      volts.add(voltage);
    }
    return WaveformTrace(
      times: Float64List.fromList(times),
      volts: Float64List.fromList(volts),
      channel: channel,
    );
  }

  /// Builds a trace with an index-based time axis and a fixed interval.
  factory WaveformTrace.synthetic(
    List<double> values, {
    double sampleIntervalSeconds = 1,
    String? channel,
  }) {
    return WaveformTrace(
      times: Float64List.fromList([
        for (var i = 0; i < values.length; i++) i * sampleIntervalSeconds,
      ]),
      volts: Float64List.fromList(values),
      channel: channel,
    );
  }

  int get length => volts.length;

  bool get isEmpty => volts.isEmpty;

  bool get isNotEmpty => volts.isNotEmpty;

  bool get isValid => length >= 2 && durationSeconds > 0;

  double? get startTime => times.isEmpty ? null : times.first;

  double? get endTime => times.isEmpty ? null : times.last;

  double get durationSeconds => times.length < 2 ? 0 : times.last - times.first;

  /// Median interval between consecutive samples, or `null` when unknown.
  double? get sampleIntervalSeconds {
    if (times.length < 2) return null;
    final differences = <double>[];
    final limit = math.min(times.length - 1, 2000);
    for (var i = 0; i < limit; i++) {
      final dt = times[i + 1] - times[i];
      if (dt.isFinite && dt > 0) differences.add(dt);
    }
    if (differences.isEmpty) return null;
    differences.sort();
    final middle = differences.length ~/ 2;
    return differences.length.isOdd
        ? differences[middle]
        : (differences[middle - 1] + differences[middle]) / 2;
  }

  List<(double, double)> get points => [
    for (var i = 0; i < volts.length; i++) (times[i], volts[i]),
  ];

  WaveformTrace copyWithChannel(String? channel) =>
      WaveformTrace(times: times, volts: volts, channel: channel);
}

/// Parameters of a generated reference waveform.
class ReferenceParameters {
  final double frequencyHz;
  final double amplitudeVolts;
  final double offsetVolts;
  final double phaseRadians;
  final double sampleRateHz;
  final double durationSeconds;

  /// High-time fraction for square, pulse and PWM references.
  final double dutyCycle;

  /// RMS noise as a percentage of [amplitudeVolts] (noisy sine).
  final double noiseLevelPercent;

  /// Envelope decay rate in 1/s (damped oscillation).
  final double dampingPerSecond;

  /// Time constant in seconds (exponential decay/rise).
  final double timeConstantSeconds;

  /// Symmetric clipping level as a fraction of [amplitudeVolts].
  final double clippingLevel;

  /// Separate lower clipping level (1.0 = no clipping).
  final double lowerClipLevel;

  /// Separate upper clipping level (1.0 = no clipping).
  final double upperClipLevel;

  /// Full transition width of rectangular signals as a fraction of a period.
  final double rectangularEdgeFraction;

  /// Direction of an exponential segment.
  final bool directionIsRising;

  /// Seed for deterministic reference noise.
  final int seed;

  const ReferenceParameters({
    this.frequencyHz = 1000,
    this.amplitudeVolts = 1,
    this.offsetVolts = 0,
    this.phaseRadians = 0,
    this.sampleRateHz = 100000,
    this.durationSeconds = 0.01,
    this.dutyCycle = 0.5,
    this.noiseLevelPercent = 0,
    this.dampingPerSecond = 0,
    this.timeConstantSeconds = 0.001,
    this.clippingLevel = 1,
    this.lowerClipLevel = 1,
    this.upperClipLevel = 1,
    this.rectangularEdgeFraction = 0.02,
    this.directionIsRising = false,
    this.seed = 1,
  });

  /// Upper bound for safely materialising a reference in memory.
  static const int maxSampleCount = 2000000;

  int get sampleCount {
    final count = (sampleRateHz * durationSeconds).round();
    return math.max(2, math.min(maxSampleCount, count + 1));
  }

  ReferenceParameters copyWith({
    double? frequencyHz,
    double? amplitudeVolts,
    double? offsetVolts,
    double? phaseRadians,
    double? sampleRateHz,
    double? durationSeconds,
    double? dutyCycle,
    double? noiseLevelPercent,
    double? dampingPerSecond,
    double? timeConstantSeconds,
    double? clippingLevel,
    double? lowerClipLevel,
    double? upperClipLevel,
    double? rectangularEdgeFraction,
    bool? directionIsRising,
    int? seed,
  }) {
    return ReferenceParameters(
      frequencyHz: frequencyHz ?? this.frequencyHz,
      amplitudeVolts: amplitudeVolts ?? this.amplitudeVolts,
      offsetVolts: offsetVolts ?? this.offsetVolts,
      phaseRadians: phaseRadians ?? this.phaseRadians,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      dutyCycle: dutyCycle ?? this.dutyCycle,
      noiseLevelPercent: noiseLevelPercent ?? this.noiseLevelPercent,
      dampingPerSecond: dampingPerSecond ?? this.dampingPerSecond,
      timeConstantSeconds: timeConstantSeconds ?? this.timeConstantSeconds,
      clippingLevel: clippingLevel ?? this.clippingLevel,
      lowerClipLevel: lowerClipLevel ?? this.lowerClipLevel,
      upperClipLevel: upperClipLevel ?? this.upperClipLevel,
      rectangularEdgeFraction:
          rectangularEdgeFraction ?? this.rectangularEdgeFraction,
      directionIsRising: directionIsRising ?? this.directionIsRising,
      seed: seed ?? this.seed,
    );
  }

  Map<String, dynamic> toMap() => {
    'frequencyHz': _finite(frequencyHz),
    'amplitudeVolts': _finite(amplitudeVolts),
    'offsetVolts': _finite(offsetVolts),
    'phaseRadians': _finite(phaseRadians),
    'sampleRateHz': _finite(sampleRateHz),
    'durationSeconds': _finite(durationSeconds),
    'dutyCycle': _finite(dutyCycle),
    'noiseLevelPercent': _finite(noiseLevelPercent),
    'dampingPerSecond': _finite(dampingPerSecond),
    'timeConstantSeconds': _finite(timeConstantSeconds),
    'clippingLevel': _finite(clippingLevel),
    'lowerClipLevel': _finite(lowerClipLevel),
    'upperClipLevel': _finite(upperClipLevel),
    'rectangularEdgeFraction': _finite(rectangularEdgeFraction),
    'directionIsRising': directionIsRising,
    'seed': seed,
  };

  factory ReferenceParameters.fromMap(Map<String, dynamic> map) {
    double read(String key, double fallback) =>
        _readDouble(map[key]) ?? fallback;
    return ReferenceParameters(
      frequencyHz: read('frequencyHz', 1000),
      amplitudeVolts: read('amplitudeVolts', 1),
      offsetVolts: read('offsetVolts', 0),
      phaseRadians: read('phaseRadians', 0),
      sampleRateHz: read('sampleRateHz', 100000),
      durationSeconds: read('durationSeconds', 0.01),
      dutyCycle: read('dutyCycle', 0.5),
      noiseLevelPercent: read('noiseLevelPercent', 0),
      dampingPerSecond: read('dampingPerSecond', 0),
      timeConstantSeconds: read('timeConstantSeconds', 0.001),
      clippingLevel: read('clippingLevel', 1),
      lowerClipLevel: read('lowerClipLevel', 1),
      upperClipLevel: read('upperClipLevel', 1),
      rectangularEdgeFraction: read('rectangularEdgeFraction', 0.02),
      directionIsRising: map['directionIsRising'] == true,
      seed: (map['seed'] as num?)?.toInt() ?? 1,
    );
  }
}

/// A generated reference signal.
class ReferenceWaveform {
  final WaveformSignalType type;
  final ReferenceParameters parameters;
  final WaveformTrace trace;

  const ReferenceWaveform({
    required this.type,
    required this.parameters,
    required this.trace,
  });
}

/// Sign statistics of the first and second discrete differences.
///
/// Follows the differential feature representation of Xiao, Chen and Lv,
/// "A Lightweight Waveform Recognition Algorithm Based on Differential
/// Features and Its FPGA Implementation", Electronics 2026, 15(17), 4044.
/// The fractions are computed over a window of up to eight periods; the
/// reversal fraction is the share of adjacent second-difference samples whose
/// signs are opposite. `waveform_differential.dart` performs the extraction.
class DifferentialFeatures {
  final double firstPositiveFraction;
  final double firstZeroFraction;
  final double firstNegativeFraction;
  final double secondPositiveFraction;
  final double secondZeroFraction;
  final double secondNegativeFraction;
  final double secondSignReversalFraction;

  /// Number of samples in the resampled differential window.
  final int sampleCount;

  /// Number of periods inside the window (`0` for non-periodic captures).
  final int periodsUsed;

  /// Effective points per period after block averaging.
  final double pointsPerPeriod;

  /// First-difference sign threshold in volts (noise-derived).
  final double firstThresholdVolts;

  /// Second-difference sign threshold in volts (noise-derived).
  final double secondThresholdVolts;

  const DifferentialFeatures({
    required this.firstPositiveFraction,
    required this.firstZeroFraction,
    required this.firstNegativeFraction,
    required this.secondPositiveFraction,
    required this.secondZeroFraction,
    required this.secondNegativeFraction,
    required this.secondSignReversalFraction,
    this.sampleCount = 0,
    this.periodsUsed = 0,
    this.pointsPerPeriod = 0,
    this.firstThresholdVolts = 0,
    this.secondThresholdVolts = 0,
  });

  /// Balance of the first-difference signs: 1 means equal positive and
  /// negative shares, 0 means the signal only rises or only falls.
  double get firstBalance =>
      1 - (firstPositiveFraction - firstNegativeFraction).abs();

  Map<String, dynamic> toMap() => {
    'firstDifferencePositiveFraction': _finite(firstPositiveFraction),
    'firstDifferenceZeroFraction': _finite(firstZeroFraction),
    'firstDifferenceNegativeFraction': _finite(firstNegativeFraction),
    'secondDifferencePositiveFraction': _finite(secondPositiveFraction),
    'secondDifferenceZeroFraction': _finite(secondZeroFraction),
    'secondDifferenceNegativeFraction': _finite(secondNegativeFraction),
    'secondDifferenceSignReversalFraction': _finite(secondSignReversalFraction),
    'sampleCount': sampleCount,
    'periodsUsed': periodsUsed,
    'pointsPerPeriod': _finite(pointsPerPeriod),
    'firstThresholdVolts': _finite(firstThresholdVolts),
    'secondThresholdVolts': _finite(secondThresholdVolts),
  };

  factory DifferentialFeatures.fromMap(Map<String, dynamic> map) {
    double read(String key) => _readDouble(map[key]) ?? 0;
    return DifferentialFeatures(
      firstPositiveFraction: read('firstDifferencePositiveFraction'),
      firstZeroFraction: read('firstDifferenceZeroFraction'),
      firstNegativeFraction: read('firstDifferenceNegativeFraction'),
      secondPositiveFraction: read('secondDifferencePositiveFraction'),
      secondZeroFraction: read('secondDifferenceZeroFraction'),
      secondNegativeFraction: read('secondDifferenceNegativeFraction'),
      secondSignReversalFraction: read('secondDifferenceSignReversalFraction'),
      sampleCount: (map['sampleCount'] as num?)?.toInt() ?? 0,
      periodsUsed: (map['periodsUsed'] as num?)?.toInt() ?? 0,
      pointsPerPeriod: read('pointsPerPeriod'),
      firstThresholdVolts: read('firstThresholdVolts'),
      secondThresholdVolts: read('secondThresholdVolts'),
    );
  }
}

/// Complete feature set of a waveform.
///
/// Absolute voltage fields describe the capture; shape fields are independent
/// of amplitude and offset. Derived lists (periods, edges, clipped regions)
/// are kept for the anomaly detector and are not serialized.
class WaveformFeatures {
  final int sampleCount;
  final double durationSeconds;
  final double? sampleIntervalSeconds;

  // Time-domain features.
  final double? vMin;
  final double? vMax;
  final double? vPp;
  final double? vMean;
  final double? vRms;
  final double? vStdDev;
  final double? vTop;
  final double? vBase;
  final double? crestFactor;
  final double? frequencyHz;
  final double? periodSeconds;
  final int periodCount;
  final double? periodVariation;
  final double? periodMaxRatio;
  final double? dutyPercent;
  final double? dutyCycleVariation;
  final double? pulseWidthSeconds;
  final double? riseTimeSeconds;
  final double? fallTimeSeconds;
  final double? edgeSteepness;
  final double? positiveSlopeVoltsPerSecond;
  final double? negativeSlopeVoltsPerSecond;
  final double? slopeSymmetry;
  final double? symmetry;
  final int peakCount;
  final int zeroCrossingCount;
  final int risingEdgeCount;
  final int fallingEdgeCount;
  final int pulseCount;
  final double? amplitudeVariation;

  // Frequency-domain features.
  final double? dominantFrequencyHz;
  final List<double> harmonicAmplitudes;
  final double? thdPercent;
  final double? thdDb;
  final double? snrDb;
  final double? spectralCentroidHz;
  final double? lowBandEnergyRatio;
  final double? midBandEnergyRatio;
  final double? highBandEnergyRatio;
  final double? noiseFloorVolts;

  // Shape features.
  final double? sineCorrelation;
  final double? squareCorrelation;
  final double? triangleCorrelation;
  final double? sawtoothCorrelation;
  final double? plateauStability;
  final double? twoLevelRatio;
  final double? rampLinearity;
  final double? exponentialFitR2;
  final double? exponentialTauSeconds;
  final bool exponentialRising;
  final double? linearFitR2;
  final double? envelopeDecayRate;
  final double? envelopeDecayR2;
  final double? oscillationRegularity;
  final double? clippingRatio;
  final double? upperClippingRatio;
  final double? lowerClippingRatio;
  final int clippedRegionCount;
  final double? monotonicFraction;
  final double? resetRatio;
  final double? sineResidualRmsRatio;
  final double? sineResidualSnrDb;
  final double? residualSpectralFlatness;
  final double? residualHarmonicEnergyRatio;

  /// Phase of the fitted fundamental sine in radians.
  final double? sinePhaseRadians;

  /// Logarithmic decrement of a damped oscillation (`decay rate * period`).
  final double? logarithmicDecrement;

  /// Differential sign statistics used by the paper-based classifier.
  final DifferentialFeatures? differential;

  // Derived detail data for the anomaly detector (not serialized).
  final List<double> periods;
  final List<double> dutyRatios;
  final List<double> perPeriodVpp;
  final List<double> risingEdgeTimes;
  final List<double> fallingEdgeTimes;
  final List<(double, double)> clippedRegions;

  const WaveformFeatures({
    required this.sampleCount,
    required this.durationSeconds,
    this.sampleIntervalSeconds,
    this.vMin,
    this.vMax,
    this.vPp,
    this.vMean,
    this.vRms,
    this.vStdDev,
    this.vTop,
    this.vBase,
    this.crestFactor,
    this.frequencyHz,
    this.periodSeconds,
    this.periodCount = 0,
    this.periodVariation,
    this.periodMaxRatio,
    this.dutyPercent,
    this.dutyCycleVariation,
    this.pulseWidthSeconds,
    this.riseTimeSeconds,
    this.fallTimeSeconds,
    this.edgeSteepness,
    this.positiveSlopeVoltsPerSecond,
    this.negativeSlopeVoltsPerSecond,
    this.slopeSymmetry,
    this.symmetry,
    this.peakCount = 0,
    this.zeroCrossingCount = 0,
    this.risingEdgeCount = 0,
    this.fallingEdgeCount = 0,
    this.pulseCount = 0,
    this.amplitudeVariation,
    this.dominantFrequencyHz,
    this.harmonicAmplitudes = const [],
    this.thdPercent,
    this.thdDb,
    this.snrDb,
    this.spectralCentroidHz,
    this.lowBandEnergyRatio,
    this.midBandEnergyRatio,
    this.highBandEnergyRatio,
    this.noiseFloorVolts,
    this.sineCorrelation,
    this.squareCorrelation,
    this.triangleCorrelation,
    this.sawtoothCorrelation,
    this.plateauStability,
    this.twoLevelRatio,
    this.rampLinearity,
    this.exponentialFitR2,
    this.exponentialTauSeconds,
    this.exponentialRising = false,
    this.linearFitR2,
    this.envelopeDecayRate,
    this.envelopeDecayR2,
    this.oscillationRegularity,
    this.clippingRatio,
    this.upperClippingRatio,
    this.lowerClippingRatio,
    this.clippedRegionCount = 0,
    this.monotonicFraction,
    this.resetRatio,
    this.sineResidualRmsRatio,
    this.sineResidualSnrDb,
    this.residualSpectralFlatness,
    this.residualHarmonicEnergyRatio,
    this.sinePhaseRadians,
    this.logarithmicDecrement,
    this.differential,
    this.periods = const [],
    this.dutyRatios = const [],
    this.perPeriodVpp = const [],
    this.risingEdgeTimes = const [],
    this.fallingEdgeTimes = const [],
    this.clippedRegions = const [],
  });

  bool get hasData => sampleCount > 0;

  /// Feature map for the AI tools and the UI.
  Map<String, dynamic> toMap() => {
    'sampleCount': sampleCount,
    'durationSeconds': _finite(durationSeconds),
    'sampleIntervalSeconds': _finite(sampleIntervalSeconds),
    'vMinVolts': _finite(vMin),
    'vMaxVolts': _finite(vMax),
    'vppVolts': _finite(vPp),
    'meanVolts': _finite(vMean),
    'rmsVolts': _finite(vRms),
    'stdDevVolts': _finite(vStdDev),
    'topVolts': _finite(vTop),
    'baseVolts': _finite(vBase),
    'crestFactor': _finite(crestFactor),
    'frequencyHz': _finite(frequencyHz),
    'periodSeconds': _finite(periodSeconds),
    'periodCount': periodCount,
    'periodVariation': _finite(periodVariation),
    'periodMaxRatio': _finite(periodMaxRatio),
    'dutyPercent': _finite(dutyPercent),
    'dutyCycleVariation': _finite(dutyCycleVariation),
    'pulseWidthSeconds': _finite(pulseWidthSeconds),
    'riseTimeSeconds': _finite(riseTimeSeconds),
    'fallTimeSeconds': _finite(fallTimeSeconds),
    'edgeSteepness': _finite(edgeSteepness),
    'positiveSlopeVoltsPerSecond': _finite(positiveSlopeVoltsPerSecond),
    'negativeSlopeVoltsPerSecond': _finite(negativeSlopeVoltsPerSecond),
    'slopeSymmetry': _finite(slopeSymmetry),
    'symmetry': _finite(symmetry),
    'peakCount': peakCount,
    'zeroCrossingCount': zeroCrossingCount,
    'risingEdgeCount': risingEdgeCount,
    'fallingEdgeCount': fallingEdgeCount,
    'pulseCount': pulseCount,
    'amplitudeVariation': _finite(amplitudeVariation),
    'dominantFrequencyHz': _finite(dominantFrequencyHz),
    'harmonicAmplitudesVolts': [
      for (final value in harmonicAmplitudes) _finite(value),
    ],
    'thdPercent': _finite(thdPercent),
    'thdDb': _finite(thdDb),
    'snrDb': _finite(snrDb),
    'spectralCentroidHz': _finite(spectralCentroidHz),
    'lowBandEnergyRatio': _finite(lowBandEnergyRatio),
    'midBandEnergyRatio': _finite(midBandEnergyRatio),
    'highBandEnergyRatio': _finite(highBandEnergyRatio),
    'noiseFloorVolts': _finite(noiseFloorVolts),
    'sineCorrelation': _finite(sineCorrelation),
    'squareCorrelation': _finite(squareCorrelation),
    'triangleCorrelation': _finite(triangleCorrelation),
    'sawtoothCorrelation': _finite(sawtoothCorrelation),
    'plateauStability': _finite(plateauStability),
    'twoLevelRatio': _finite(twoLevelRatio),
    'rampLinearity': _finite(rampLinearity),
    'exponentialFitR2': _finite(exponentialFitR2),
    'exponentialTauSeconds': _finite(exponentialTauSeconds),
    'exponentialRising': exponentialRising,
    'linearFitR2': _finite(linearFitR2),
    'envelopeDecayRatePerSecond': _finite(envelopeDecayRate),
    'envelopeDecayR2': _finite(envelopeDecayR2),
    'oscillationRegularity': _finite(oscillationRegularity),
    'clippingRatio': _finite(clippingRatio),
    'upperClippingRatio': _finite(upperClippingRatio),
    'lowerClippingRatio': _finite(lowerClippingRatio),
    'clippedRegionCount': clippedRegionCount,
    'monotonicFraction': _finite(monotonicFraction),
    'resetRatio': _finite(resetRatio),
    'sineResidualRmsRatio': _finite(sineResidualRmsRatio),
    'sineResidualSnrDb': _finite(sineResidualSnrDb),
    'residualSpectralFlatness': _finite(residualSpectralFlatness),
    'residualHarmonicEnergyRatio': _finite(residualHarmonicEnergyRatio),
    'sinePhaseRadians': _finite(sinePhaseRadians),
    'logarithmicDecrement': _finite(logarithmicDecrement),
    'differential': differential?.toMap(),
  };

  factory WaveformFeatures.fromMap(Map<String, dynamic> map) {
    double? read(String key) => _readDouble(map[key]);
    final harmonics = map['harmonicAmplitudesVolts'];
    return WaveformFeatures(
      sampleCount: (map['sampleCount'] as num?)?.toInt() ?? 0,
      durationSeconds: read('durationSeconds') ?? 0,
      sampleIntervalSeconds: read('sampleIntervalSeconds'),
      vMin: read('vMinVolts'),
      vMax: read('vMaxVolts'),
      vPp: read('vppVolts'),
      vMean: read('meanVolts'),
      vRms: read('rmsVolts'),
      vStdDev: read('stdDevVolts'),
      vTop: read('topVolts'),
      vBase: read('baseVolts'),
      crestFactor: read('crestFactor'),
      frequencyHz: read('frequencyHz'),
      periodSeconds: read('periodSeconds'),
      periodCount: (map['periodCount'] as num?)?.toInt() ?? 0,
      periodVariation: read('periodVariation'),
      periodMaxRatio: read('periodMaxRatio'),
      dutyPercent: read('dutyPercent'),
      dutyCycleVariation: read('dutyCycleVariation'),
      pulseWidthSeconds: read('pulseWidthSeconds'),
      riseTimeSeconds: read('riseTimeSeconds'),
      fallTimeSeconds: read('fallTimeSeconds'),
      edgeSteepness: read('edgeSteepness'),
      positiveSlopeVoltsPerSecond: read('positiveSlopeVoltsPerSecond'),
      negativeSlopeVoltsPerSecond: read('negativeSlopeVoltsPerSecond'),
      slopeSymmetry: read('slopeSymmetry'),
      symmetry: read('symmetry'),
      peakCount: (map['peakCount'] as num?)?.toInt() ?? 0,
      zeroCrossingCount: (map['zeroCrossingCount'] as num?)?.toInt() ?? 0,
      risingEdgeCount: (map['risingEdgeCount'] as num?)?.toInt() ?? 0,
      fallingEdgeCount: (map['fallingEdgeCount'] as num?)?.toInt() ?? 0,
      pulseCount: (map['pulseCount'] as num?)?.toInt() ?? 0,
      amplitudeVariation: read('amplitudeVariation'),
      dominantFrequencyHz: read('dominantFrequencyHz'),
      harmonicAmplitudes: harmonics is List
          ? [
              for (final value in harmonics)
                if (_readDouble(value) case final double v) v,
            ]
          : const [],
      thdPercent: read('thdPercent'),
      thdDb: read('thdDb'),
      snrDb: read('snrDb'),
      spectralCentroidHz: read('spectralCentroidHz'),
      lowBandEnergyRatio: read('lowBandEnergyRatio'),
      midBandEnergyRatio: read('midBandEnergyRatio'),
      highBandEnergyRatio: read('highBandEnergyRatio'),
      noiseFloorVolts: read('noiseFloorVolts'),
      sineCorrelation: read('sineCorrelation'),
      squareCorrelation: read('squareCorrelation'),
      triangleCorrelation: read('triangleCorrelation'),
      sawtoothCorrelation: read('sawtoothCorrelation'),
      plateauStability: read('plateauStability'),
      twoLevelRatio: read('twoLevelRatio'),
      rampLinearity: read('rampLinearity'),
      exponentialFitR2: read('exponentialFitR2'),
      exponentialTauSeconds: read('exponentialTauSeconds'),
      exponentialRising: map['exponentialRising'] == true,
      linearFitR2: read('linearFitR2'),
      envelopeDecayRate: read('envelopeDecayRatePerSecond'),
      envelopeDecayR2: read('envelopeDecayR2'),
      oscillationRegularity: read('oscillationRegularity'),
      clippingRatio: read('clippingRatio'),
      upperClippingRatio: read('upperClippingRatio'),
      lowerClippingRatio: read('lowerClippingRatio'),
      clippedRegionCount: (map['clippedRegionCount'] as num?)?.toInt() ?? 0,
      monotonicFraction: read('monotonicFraction'),
      resetRatio: read('resetRatio'),
      sineResidualRmsRatio: read('sineResidualRmsRatio'),
      sineResidualSnrDb: read('sineResidualSnrDb'),
      residualSpectralFlatness: read('residualSpectralFlatness'),
      residualHarmonicEnergyRatio: read('residualHarmonicEnergyRatio'),
      sinePhaseRadians: read('sinePhaseRadians'),
      logarithmicDecrement: read('logarithmicDecrement'),
      differential: map['differential'] is Map
          ? DifferentialFeatures.fromMap(
              Map<String, dynamic>.from(map['differential'] as Map),
            )
          : null,
    );
  }
}

/// Weights of the comparison methods used for the final similarity score.
///
/// The specification suggests 30 % shape, 30 % feature, 20 % frequency and
/// 20 % DTW. The engine uses 24/24/16/16 and adds a 20 % signal-specific rule
/// score, because the detection rules in the specification are a required
/// classifier input. [SimilarityWeights.specSuggested] keeps the original
/// four-way split available.
class SimilarityWeights {
  final double shape;
  final double feature;
  final double frequency;
  final double dtw;
  final double rule;

  const SimilarityWeights({
    this.shape = 0.24,
    this.feature = 0.24,
    this.frequency = 0.16,
    this.dtw = 0.16,
    this.rule = 0.20,
  });

  const SimilarityWeights.specSuggested()
    : shape = 0.30,
      feature = 0.30,
      frequency = 0.20,
      dtw = 0.20,
      rule = 0.0;

  double get total => shape + feature + frequency + dtw + rule;

  SimilarityWeights normalized() {
    final sum = total;
    if (sum <= 0) return const SimilarityWeights();
    return SimilarityWeights(
      shape: shape / sum,
      feature: feature / sum,
      frequency: frequency / sum,
      dtw: dtw / sum,
      rule: rule / sum,
    );
  }

  Map<String, dynamic> toMap() => {
    'shape': shape,
    'feature': feature,
    'frequency': frequency,
    'dtw': dtw,
    'rule': rule,
  };

  factory SimilarityWeights.fromMap(Map<String, dynamic> map) {
    return SimilarityWeights(
      shape: _readDouble(map['shape']) ?? 0.24,
      feature: _readDouble(map['feature']) ?? 0.24,
      frequency: _readDouble(map['frequency']) ?? 0.16,
      dtw: _readDouble(map['dtw']) ?? 0.16,
      rule: _readDouble(map['rule']) ?? 0.20,
    );
  }
}

/// Options of a classification or comparison run.
class WaveformAnalysisOptions {
  /// Reference types that participate. `null` means all ten types.
  final List<WaveformSignalType>? referenceTypes;

  final SimilarityWeights weights;

  /// Upper bound of samples used by the analysis. The original trace is
  /// preserved; only the analysis copy is decimated.
  final int maxAnalysisPoints;

  /// Number of harmonics used for THD and harmonic-profile features.
  final int harmonicCount;

  /// Scores below this value are reported as uncertain/unknown.
  final double minConfidentScore;

  /// Top two candidates closer than this score (and below 75 %) are reported
  /// as a mixed/ambiguous result.
  final double ambiguityMargin;

  /// Maximum number of parameter variants generated per reference type.
  final int maxReferenceVariants;

  /// Optional light median filtering for very noisy captures.
  final bool smoothing;

  const WaveformAnalysisOptions({
    this.referenceTypes,
    this.weights = const SimilarityWeights(),
    this.maxAnalysisPoints = 4096,
    this.harmonicCount = 5,
    this.minConfidentScore = 40,
    this.ambiguityMargin = 5,
    this.maxReferenceVariants = 3,
    this.smoothing = false,
  });

  List<WaveformSignalType> get enabledTypes =>
      referenceTypes ?? WaveformSignalType.values;

  WaveformAnalysisOptions copyWith({
    List<WaveformSignalType>? referenceTypes,
    SimilarityWeights? weights,
    int? maxAnalysisPoints,
    int? harmonicCount,
    double? minConfidentScore,
    double? ambiguityMargin,
    int? maxReferenceVariants,
    bool? smoothing,
  }) {
    return WaveformAnalysisOptions(
      referenceTypes: referenceTypes ?? this.referenceTypes,
      weights: weights ?? this.weights,
      maxAnalysisPoints: maxAnalysisPoints ?? this.maxAnalysisPoints,
      harmonicCount: harmonicCount ?? this.harmonicCount,
      minConfidentScore: minConfidentScore ?? this.minConfidentScore,
      ambiguityMargin: ambiguityMargin ?? this.ambiguityMargin,
      maxReferenceVariants: maxReferenceVariants ?? this.maxReferenceVariants,
      smoothing: smoothing ?? this.smoothing,
    );
  }

  Map<String, dynamic> toMap() => {
    'referenceTypes': referenceTypes?.map((type) => type.id).toList(),
    'weights': weights.toMap(),
    'maxAnalysisPoints': maxAnalysisPoints,
    'harmonicCount': harmonicCount,
    'minConfidentScore': minConfidentScore,
    'ambiguityMargin': ambiguityMargin,
    'maxReferenceVariants': maxReferenceVariants,
    'smoothing': smoothing,
  };

  factory WaveformAnalysisOptions.fromMap(Map<String, dynamic> map) {
    final types = map['referenceTypes'];
    List<WaveformSignalType>? referenceTypes;
    if (types is List) {
      referenceTypes = [
        for (final value in types) ?WaveformSignalType.parse(value?.toString()),
      ];
      if (referenceTypes.isEmpty) referenceTypes = null;
    }
    final weights = map['weights'];
    return WaveformAnalysisOptions(
      referenceTypes: referenceTypes,
      weights: weights is Map
          ? SimilarityWeights.fromMap(Map<String, dynamic>.from(weights))
          : const SimilarityWeights(),
      maxAnalysisPoints: (map['maxAnalysisPoints'] as num?)?.toInt() ?? 4096,
      harmonicCount: (map['harmonicCount'] as num?)?.toInt() ?? 5,
      minConfidentScore: _readDouble(map['minConfidentScore']) ?? 40,
      ambiguityMargin: _readDouble(map['ambiguityMargin']) ?? 5,
      maxReferenceVariants: (map['maxReferenceVariants'] as num?)?.toInt() ?? 3,
      smoothing: map['smoothing'] == true,
    );
  }
}

/// Breakdown of the individual comparison methods for one candidate.
class SimilarityBreakdown {
  final double shapeSimilarity;
  final double featureSimilarity;
  final double frequencySimilarity;
  final double dtwSimilarity;
  final double ruleSimilarity;
  final double rawCorrelation;
  final int lagSamples;
  final double? lagSeconds;
  final double score;
  final SimilarityWeights weights;

  const SimilarityBreakdown({
    required this.shapeSimilarity,
    required this.featureSimilarity,
    required this.frequencySimilarity,
    required this.dtwSimilarity,
    required this.ruleSimilarity,
    required this.rawCorrelation,
    required this.lagSamples,
    required this.lagSeconds,
    required this.score,
    required this.weights,
  });

  Map<String, dynamic> toMap() => {
    'shapeSimilarityPercent': _finite(shapeSimilarity),
    'featureSimilarityPercent': _finite(featureSimilarity),
    'frequencyDomainSimilarityPercent': _finite(frequencySimilarity),
    'dtwSimilarityPercent': _finite(dtwSimilarity),
    'detectionRuleScorePercent': _finite(ruleSimilarity),
    'rawCorrelation': _finite(rawCorrelation),
    'lagSamples': lagSamples,
    'lagSeconds': _finite(lagSeconds),
    'scorePercent': _finite(score),
    'weights': weights.toMap(),
  };

  factory SimilarityBreakdown.fromMap(Map<String, dynamic> map) {
    double? read(String key) => _readDouble(map[key]);
    final weights = map['weights'];
    return SimilarityBreakdown(
      shapeSimilarity: read('shapeSimilarityPercent') ?? 0,
      featureSimilarity: read('featureSimilarityPercent') ?? 0,
      frequencySimilarity: read('frequencyDomainSimilarityPercent') ?? 0,
      dtwSimilarity: read('dtwSimilarityPercent') ?? 0,
      ruleSimilarity: read('detectionRuleScorePercent') ?? 0,
      rawCorrelation: read('rawCorrelation') ?? 0,
      lagSamples: (map['lagSamples'] as num?)?.toInt() ?? 0,
      lagSeconds: read('lagSeconds'),
      score: read('scorePercent') ?? 0,
      weights: weights is Map
          ? SimilarityWeights.fromMap(Map<String, dynamic>.from(weights))
          : const SimilarityWeights(),
    );
  }
}

/// One reference type in the ranked candidate list.
class ClassificationCandidate {
  final WaveformSignalType type;
  final double score;
  final ClassificationConfidence confidence;
  final SimilarityBreakdown breakdown;
  final ReferenceParameters referenceParameters;
  final List<String> notes;

  const ClassificationCandidate({
    required this.type,
    required this.score,
    required this.confidence,
    required this.breakdown,
    required this.referenceParameters,
    this.notes = const [],
  });

  Map<String, dynamic> toMap() => {
    'referenceType': type.id,
    'referenceLabel': type.label,
    'similarityPercent': _finite(score),
    'confidence': confidence.label.toLowerCase(),
    'breakdown': breakdown.toMap(),
    'referenceParameters': referenceParameters.toMap(),
    'notes': notes,
  };

  factory ClassificationCandidate.fromMap(Map<String, dynamic> map) {
    final type = WaveformSignalType.parse(map['referenceType']?.toString());
    final breakdown = map['breakdown'];
    final parameters = map['referenceParameters'];
    final notes = map['notes'];
    return ClassificationCandidate(
      type: type ?? WaveformSignalType.sine,
      score: _readDouble(map['similarityPercent']) ?? 0,
      confidence: ClassificationConfidence.fromScore(
        _readDouble(map['similarityPercent']) ?? 0,
      ),
      breakdown: breakdown is Map
          ? SimilarityBreakdown.fromMap(Map<String, dynamic>.from(breakdown))
          : const SimilarityBreakdown(
              shapeSimilarity: 0,
              featureSimilarity: 0,
              frequencySimilarity: 0,
              dtwSimilarity: 0,
              ruleSimilarity: 0,
              rawCorrelation: 0,
              lagSamples: 0,
              lagSeconds: null,
              score: 0,
              weights: SimilarityWeights(),
            ),
      referenceParameters: parameters is Map
          ? ReferenceParameters.fromMap(Map<String, dynamic>.from(parameters))
          : const ReferenceParameters(),
      notes: notes is List
          ? [for (final note in notes) note.toString()]
          : const [],
    );
  }
}

/// One distortion or anomaly detected on the captured waveform.
class WaveformAnomaly {
  /// Stable anomaly identifier, e.g. `noise`, `clipping`, `overshoot`.
  final String type;

  final String label;
  final AnomalySeverity severity;
  final double? startSeconds;
  final double? endSeconds;

  /// Measured value with unit, taken from the feature extractor.
  final String? measuredValue;

  /// Value of the ideal reference, when meaningful.
  final String? idealValue;

  final String description;

  const WaveformAnomaly({
    required this.type,
    required this.label,
    required this.severity,
    this.startSeconds,
    this.endSeconds,
    this.measuredValue,
    this.idealValue,
    required this.description,
  });

  Map<String, dynamic> toMap() => {
    'type': type,
    'label': label,
    'severity': severity.name,
    'startSeconds': _finite(startSeconds),
    'endSeconds': _finite(endSeconds),
    'measuredValue': measuredValue,
    'idealValue': idealValue,
    'description': description,
  };

  factory WaveformAnomaly.fromMap(Map<String, dynamic> map) {
    final severityName = map['severity']?.toString();
    final severity = AnomalySeverity.values.firstWhere(
      (value) => value.name == severityName,
      orElse: () => AnomalySeverity.info,
    );
    return WaveformAnomaly(
      type: map['type']?.toString() ?? 'unknown',
      label: map['label']?.toString() ?? 'Unknown anomaly',
      severity: severity,
      startSeconds: _readDouble(map['startSeconds']),
      endSeconds: _readDouble(map['endSeconds']),
      measuredValue: map['measuredValue']?.toString(),
      idealValue: map['idealValue']?.toString(),
      description: map['description']?.toString() ?? '',
    );
  }
}

/// Result of classifying one captured waveform.
class WaveformClassification {
  final String? channel;
  final WaveformSignalType? primaryType;
  final String primaryLabel;
  final double score;
  final ClassificationConfidence confidence;
  final bool uncertain;
  final bool ambiguous;

  /// Whether the assistant should name alternative reference types.
  ///
  /// False for a clear high-confidence result with a sufficient lead over the
  /// second candidate. True for moderate/low/uncertain confidence, a mixed
  /// result, or a close second candidate.
  final bool mentionAlternatives;
  final List<ClassificationCandidate> topCandidates;
  final List<ClassificationCandidate> allCandidates;
  final WaveformFeatures features;
  final List<WaveformAnomaly> anomalies;
  final List<String> secondaryCharacteristics;
  final String explanation;
  final List<String> warnings;
  final ReferenceParameters? referenceParameters;
  final int sampleCount;
  final double durationSeconds;
  final SimilarityWeights weights;

  const WaveformClassification({
    this.channel,
    this.primaryType,
    required this.primaryLabel,
    required this.score,
    required this.confidence,
    required this.uncertain,
    required this.ambiguous,
    required this.mentionAlternatives,
    required this.topCandidates,
    required this.allCandidates,
    required this.features,
    required this.anomalies,
    required this.secondaryCharacteristics,
    required this.explanation,
    required this.warnings,
    this.referenceParameters,
    required this.sampleCount,
    required this.durationSeconds,
    required this.weights,
  });

  Map<String, dynamic> toMap() => {
    'channel': channel,
    'primaryType': primaryType?.id,
    'primaryClassification': primaryLabel,
    'similarityPercent': _finite(score),
    'confidence': confidence.label.toLowerCase(),
    'uncertain': uncertain,
    'ambiguous': ambiguous,
    'mentionAlternatives': mentionAlternatives,
    'topCandidates': topCandidates
        .map((candidate) => candidate.toMap())
        .toList(),
    'allCandidates': allCandidates
        .map((candidate) => candidate.toMap())
        .toList(),
    'features': features.toMap(),
    'anomalies': anomalies.map((anomaly) => anomaly.toMap()).toList(),
    'secondaryCharacteristics': secondaryCharacteristics,
    'explanation': explanation,
    'warnings': warnings,
    'referenceParameters': referenceParameters?.toMap(),
    'sampleCount': sampleCount,
    'durationSeconds': _finite(durationSeconds),
    'weights': weights.toMap(),
    'disclaimer':
        'Similarity percentages and confidence bands describe how closely the '
        'capture matches the mathematical references; they are not calibrated '
        'statistical probabilities.',
  };

  factory WaveformClassification.fromMap(Map<String, dynamic> map) {
    final primary = WaveformSignalType.parse(map['primaryType']?.toString());
    final top = map['topCandidates'];
    final all = map['allCandidates'];
    final anomalies = map['anomalies'];
    final features = map['features'];
    final referenceParameters = map['referenceParameters'];
    final weights = map['weights'];
    final warnings = map['warnings'];
    final characteristics = map['secondaryCharacteristics'];
    final score = _readDouble(map['similarityPercent']) ?? 0;
    final confidence = ClassificationConfidence.fromScore(score);
    final mentionAlternatives = map['mentionAlternatives'] is bool
        ? map['mentionAlternatives'] == true
        : confidence != ClassificationConfidence.veryHigh &&
              confidence != ClassificationConfidence.high;
    return WaveformClassification(
      channel: map['channel']?.toString(),
      primaryType: primary,
      primaryLabel:
          map['primaryClassification']?.toString() ??
          primary?.label ??
          'Unknown waveform',
      score: score,
      confidence: confidence,
      uncertain: map['uncertain'] == true,
      ambiguous: map['ambiguous'] == true,
      mentionAlternatives: mentionAlternatives,
      topCandidates: top is List
          ? [
              for (final value in top)
                if (value is Map)
                  ClassificationCandidate.fromMap(
                    Map<String, dynamic>.from(value),
                  ),
            ]
          : const [],
      allCandidates: all is List
          ? [
              for (final value in all)
                if (value is Map)
                  ClassificationCandidate.fromMap(
                    Map<String, dynamic>.from(value),
                  ),
            ]
          : const [],
      features: features is Map
          ? WaveformFeatures.fromMap(Map<String, dynamic>.from(features))
          : const WaveformFeatures(sampleCount: 0, durationSeconds: 0),
      anomalies: anomalies is List
          ? [
              for (final value in anomalies)
                if (value is Map)
                  WaveformAnomaly.fromMap(Map<String, dynamic>.from(value)),
            ]
          : const [],
      secondaryCharacteristics: characteristics is List
          ? [for (final value in characteristics) value.toString()]
          : const [],
      explanation: map['explanation']?.toString() ?? '',
      warnings: warnings is List
          ? [for (final value in warnings) value.toString()]
          : const [],
      referenceParameters: referenceParameters is Map
          ? ReferenceParameters.fromMap(
              Map<String, dynamic>.from(referenceParameters),
            )
          : null,
      sampleCount: (map['sampleCount'] as num?)?.toInt() ?? 0,
      durationSeconds: _readDouble(map['durationSeconds']) ?? 0,
      weights: weights is Map
          ? SimilarityWeights.fromMap(Map<String, dynamic>.from(weights))
          : const SimilarityWeights(),
    );
  }
}

/// Result of comparing two captured waveforms with each other.
class WaveformComparisonResult {
  final String channelA;
  final String channelB;
  final double shapeSimilarity;
  final double correlation;
  final double? lagSeconds;
  final double dtwDistance;
  final double dtwSimilarity;
  final double frequencySimilarity;
  final double featureSimilarity;
  final double overallSimilarity;
  final Map<String, dynamic> amplitudeDifferences;
  final Map<String, dynamic> timingDifferences;
  final String summary;

  const WaveformComparisonResult({
    required this.channelA,
    required this.channelB,
    required this.shapeSimilarity,
    required this.correlation,
    required this.lagSeconds,
    required this.dtwDistance,
    required this.dtwSimilarity,
    required this.frequencySimilarity,
    required this.featureSimilarity,
    required this.overallSimilarity,
    required this.amplitudeDifferences,
    required this.timingDifferences,
    required this.summary,
  });

  Map<String, dynamic> toMap() => {
    'channelA': channelA,
    'channelB': channelB,
    'overallSimilarityPercent': _finite(overallSimilarity),
    'shapeSimilarityPercent': _finite(shapeSimilarity),
    'correlation': _finite(correlation),
    'lagSeconds': _finite(lagSeconds),
    'dtwDistance': _finite(dtwDistance),
    'dtwSimilarityPercent': _finite(dtwSimilarity),
    'frequencySimilarityPercent': _finite(frequencySimilarity),
    'featureSimilarityPercent': _finite(featureSimilarity),
    'amplitudeDifferences': amplitudeDifferences,
    'timingDifferences': timingDifferences,
    'summary': summary,
    'disclaimer':
        'Similarity percentages are descriptive comparisons, not calibrated '
        'statistical probabilities.',
  };
}

double? _finite(double? value) {
  if (value == null || !value.isFinite) return null;
  return value;
}

double? _readDouble(Object? value) {
  if (value is num) {
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }
  if (value is String) {
    final result = double.tryParse(value);
    return result != null && result.isFinite ? result : null;
  }
  return null;
}
