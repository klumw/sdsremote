/// Deterministic time-domain helpers for the audio analysis tools.
///
/// All functions operate on the full, uniformly sampled voltage record. They
/// never extrapolate and return `null` for values that cannot be measured.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../../../waveform/analysis/waveform_math.dart';
import 'audio_analysis_context.dart';

/// Basic level and amplitude statistics of one channel.
class AudioTimeStats {
  const AudioTimeStats({
    required this.sampleCount,
    required this.durationSeconds,
    required this.sampleRateHz,
    required this.minVolts,
    required this.maxVolts,
    required this.meanVolts,
    required this.rmsVolts,
    required this.acRmsVolts,
    required this.peakVolts,
    required this.peakToPeakVolts,
    required this.stdDevVolts,
    this.crestFactor,
    this.crestFactorDb,
  });

  const AudioTimeStats.empty()
    : sampleCount = 0,
      durationSeconds = 0,
      sampleRateHz = 0,
      minVolts = 0,
      maxVolts = 0,
      meanVolts = 0,
      rmsVolts = 0,
      acRmsVolts = 0,
      peakVolts = 0,
      peakToPeakVolts = 0,
      stdDevVolts = 0,
      crestFactor = null,
      crestFactorDb = null;

  final int sampleCount;
  final double durationSeconds;
  final double sampleRateHz;
  final double minVolts;
  final double maxVolts;
  final double meanVolts;
  final double rmsVolts;
  final double acRmsVolts;
  final double peakVolts;
  final double peakToPeakVolts;
  final double stdDevVolts;
  final double? crestFactor;
  final double? crestFactorDb;

  double? get dcOffsetVolts => meanVolts;
}

/// Computes level, DC offset and crest factor from the full record.
AudioTimeStats computeAudioTimeStats(AudioChannelData channel) {
  final values = channel.samples;
  final n = values.length;
  if (n == 0) return const AudioTimeStats.empty();

  var min = values.first;
  var max = values.first;
  var sum = 0.0;
  var sumSquares = 0.0;
  for (final value in values) {
    if (value < min) min = value;
    if (value > max) max = value;
    sum += value;
    sumSquares += value * value;
  }
  final mean = sum / n;
  final rms = math.sqrt(sumSquares / n);
  final variance = math.max(0.0, sumSquares / n - mean * mean);
  final stdDev = math.sqrt(variance);
  final peak = math.max((max - mean).abs(), (mean - min).abs());
  final crest = rms > 0 ? peak / rms : null;
  return AudioTimeStats(
    sampleCount: n,
    durationSeconds: channel.durationSeconds,
    sampleRateHz: channel.sampleRateHz,
    minVolts: min,
    maxVolts: max,
    meanVolts: mean,
    rmsVolts: rms,
    acRmsVolts: stdDev,
    peakVolts: peak,
    peakToPeakVolts: max - min,
    stdDevVolts: stdDev,
    crestFactor: crest,
    crestFactorDb: crest == null ? null : _db(crest),
  );
}

/// Fundamental frequency from the normalized autocorrelation.
///
/// The record is centred first. Returns `null` for non-periodic signals.
///
/// The autocorrelation is O(n²). It is therefore limited to short records;
/// for a full oscilloscope capture the FFT fundamental is the primary
/// measurement and this cross-check is skipped. Without the guard a 233k
/// sample capture blocked the UI isolate for minutes.
double? autocorrelationFundamentalHz(
  AudioChannelData channel, {
  int maxSamples = 4096,
}) {
  final values = channel.samples;
  final n = values.length;
  if (n < 12 || n > maxSamples || channel.sampleRateHz <= 0) return null;
  var mean = 0.0;
  for (final value in values) {
    mean += value;
  }
  mean /= n;
  final centered = Float64List(n);
  for (var i = 0; i < n; i++) {
    centered[i] = values[i] - mean;
  }
  return estimateFundamentalHz(centered, channel.sampleIntervalSeconds);
}

/// Maximum normalized cross-correlation and lag between two channels.
///
/// The lag is limited to [maxDelaySeconds] and the analysis uses at most
/// [maxSamples] samples, keeping the quadratic search bounded.
({double coefficient, int lagSamples})? audioChannelCorrelation(
  AudioChannelData a,
  AudioChannelData b, {
  int maxSamples = 4096,
  double maxDelaySeconds = 0.02,
}) {
  if (a.sampleRateHz <= 0 || a.sampleRateHz != b.sampleRateHz) return null;
  final length = math.min(math.min(a.sampleCount, b.sampleCount), maxSamples);
  if (length < 8) return null;
  final valuesA = Float64List.fromList(a.samples.sublist(0, length));
  final valuesB = Float64List.fromList(b.samples.sublist(0, length));
  final maxLag = math.max(
    1,
    math.min(length - 8, (maxDelaySeconds * a.sampleRateHz).round()),
  );
  final result = maxNormalizedCrossCorrelation(
    valuesA,
    valuesB,
    maxLag: maxLag,
  );
  return (coefficient: result.coefficient, lagSamples: result.lagSamples);
}

/// Period, duty and per-period amplitude measurements.
class AudioPeriodMeasurements {
  const AudioPeriodMeasurements({
    required this.lowLevelVolts,
    required this.highLevelVolts,
    required this.thresholdVolts,
    required this.periods,
    required this.dutyRatios,
    required this.vppValues,
    required this.risingTimes,
    required this.fallingTimes,
  });

  const AudioPeriodMeasurements.empty()
    : lowLevelVolts = 0,
      highLevelVolts = 0,
      thresholdVolts = 0,
      periods = const [],
      dutyRatios = const [],
      vppValues = const [],
      risingTimes = const [],
      fallingTimes = const [];

  final double lowLevelVolts;
  final double highLevelVolts;
  final double thresholdVolts;
  final List<double> periods;
  final List<double> dutyRatios;
  final List<double> vppValues;
  final List<double> risingTimes;
  final List<double> fallingTimes;
}

/// Detects periods with a Schmitt trigger around the midpoint.
AudioPeriodMeasurements measureAudioPeriods(
  AudioChannelData channel, {
  int maxPeriods = 2000,
}) {
  final values = channel.samples;
  if (values.length < 16 || channel.sampleRateHz <= 0) {
    return const AudioPeriodMeasurements.empty();
  }

  final low = percentileOf(values, 0.05);
  final high = percentileOf(values, 0.95);
  final amplitude = high - low;
  if (!(amplitude > 0)) {
    return const AudioPeriodMeasurements.empty();
  }
  final mid = (low + high) / 2;
  final hysteresis = amplitude * 0.05;
  final periods = <double>[];
  final duties = <double>[];
  final vpps = <double>[];
  final risingTimes = <double>[];
  final fallingTimes = <double>[];

  var isHigh = values.first > mid;
  double? previousRising;
  double? lastFall;
  var periodMin = values.first;
  var periodMax = values.first;

  for (var i = 1; i < values.length; i++) {
    final previous = values[i - 1];
    final current = values[i];

    if (!isHigh && current > mid + hysteresis) {
      final crossing = _crossingTime(
        previous,
        current,
        mid,
        i - 1,
        channel.sampleRateHz,
      );
      risingTimes.add(crossing);
      if (previousRising != null) {
        final period = crossing - previousRising;
        if (period > 0) {
          periods.add(period);
          if (lastFall != null &&
              lastFall > previousRising &&
              lastFall < crossing) {
            duties.add(((lastFall - previousRising) / period).clamp(0.0, 1.0));
          }
          vpps.add(periodMax - periodMin);
        }
      }
      previousRising = crossing;
      periodMin = current;
      periodMax = current;
      isHigh = true;
      if (periods.length >= maxPeriods) break;
    } else if (isHigh && current < mid - hysteresis) {
      final crossing = _crossingTime(
        previous,
        current,
        mid,
        i - 1,
        channel.sampleRateHz,
      );
      fallingTimes.add(crossing);
      lastFall = crossing;
      isHigh = false;
    }

    if (current < periodMin) periodMin = current;
    if (current > periodMax) periodMax = current;
  }

  return AudioPeriodMeasurements(
    lowLevelVolts: low,
    highLevelVolts: high,
    thresholdVolts: mid,
    periods: periods,
    dutyRatios: duties,
    vppValues: vpps,
    risingTimes: risingTimes,
    fallingTimes: fallingTimes,
  );
}

/// 10–90 % rise and fall times from the full record.
class AudioEdgeMeasurements {
  const AudioEdgeMeasurements({
    required this.lowLevelVolts,
    required this.highLevelVolts,
    required this.lowThresholdVolts,
    required this.highThresholdVolts,
    required this.riseTimesSeconds,
    required this.fallTimesSeconds,
    required this.warnings,
  });

  const AudioEdgeMeasurements.empty({this.warnings = const []})
    : lowLevelVolts = 0,
      highLevelVolts = 0,
      lowThresholdVolts = 0,
      highThresholdVolts = 0,
      riseTimesSeconds = const [],
      fallTimesSeconds = const [];

  final double lowLevelVolts;
  final double highLevelVolts;
  final double lowThresholdVolts;
  final double highThresholdVolts;
  final List<double> riseTimesSeconds;
  final List<double> fallTimesSeconds;
  final List<String> warnings;
}

/// Measures 10–90 % edge times over the full record.
AudioEdgeMeasurements measureAudioEdges(
  AudioChannelData channel, {
  int maxEdges = 500,
}) {
  final values = channel.samples;
  if (values.length < 16 || channel.sampleRateHz <= 0) {
    return const AudioEdgeMeasurements.empty(
      warnings: ['fewer than 16 samples'],
    );
  }
  final low = percentileOf(values, 0.05);
  final high = percentileOf(values, 0.95);
  final amplitude = high - low;
  if (!(amplitude > 0)) {
    return const AudioEdgeMeasurements.empty(warnings: ['flat signal']);
  }
  final lowThreshold = low + 0.1 * amplitude;
  final highThreshold = low + 0.9 * amplitude;
  final riseTimes = <double>[];
  final fallTimes = <double>[];
  var state = values.first >= highThreshold ? 2 : 0;
  double? lowCross;
  double? highCross;

  for (var i = 1; i < values.length; i++) {
    final previous = values[i - 1];
    final current = values[i];
    switch (state) {
      case 0: // waiting for a low-threshold upward crossing
        if (previous < lowThreshold && current >= lowThreshold) {
          lowCross = _crossingTime(
            previous,
            current,
            lowThreshold,
            i - 1,
            channel.sampleRateHz,
          );
          state = 1;
        }
      case 1: // waiting for a high-threshold upward crossing
        if (previous < highThreshold && current >= highThreshold) {
          highCross = _crossingTime(
            previous,
            current,
            highThreshold,
            i - 1,
            channel.sampleRateHz,
          );
          if (lowCross != null && highCross > lowCross) {
            riseTimes.add(highCross - lowCross);
          }
          state = 2;
        }
      case 2: // waiting for a high-threshold downward crossing
        if (previous > highThreshold && current <= highThreshold) {
          highCross = _crossingTime(
            previous,
            current,
            highThreshold,
            i - 1,
            channel.sampleRateHz,
          );
          state = 3;
        }
      case 3: // waiting for a low-threshold downward crossing
        if (previous > lowThreshold && current <= lowThreshold) {
          lowCross = _crossingTime(
            previous,
            current,
            lowThreshold,
            i - 1,
            channel.sampleRateHz,
          );
          if (highCross != null && lowCross > highCross) {
            fallTimes.add(lowCross - highCross);
          }
          state = 0;
        }
    }
    if (riseTimes.length >= maxEdges && fallTimes.length >= maxEdges) break;
  }

  final warnings = <String>[];
  if (riseTimes.isEmpty && fallTimes.isEmpty) {
    warnings.add('no complete 10-90 % edge found');
  }
  return AudioEdgeMeasurements(
    lowLevelVolts: low,
    highLevelVolts: high,
    lowThresholdVolts: lowThreshold,
    highThresholdVolts: highThreshold,
    riseTimesSeconds: riseTimes,
    fallTimesSeconds: fallTimes,
    warnings: warnings,
  );
}

/// One detected transient or dropout event.
class AudioEnvelopeEvent {
  const AudioEnvelopeEvent({
    required this.startSeconds,
    required this.endSeconds,
    required this.peakVolts,
    required this.rmsVolts,
    required this.ratioToMedian,
  });

  final double startSeconds;
  final double endSeconds;
  final double peakVolts;
  final double rmsVolts;
  final double ratioToMedian;
}

/// Envelope event list with its reference values.
class AudioEnvelopeResult {
  const AudioEnvelopeResult({
    required this.events,
    required this.medianRmsVolts,
    required this.thresholdVolts,
    required this.windowSeconds,
    required this.warnings,
  });

  final List<AudioEnvelopeEvent> events;
  final double medianRmsVolts;
  final double thresholdVolts;
  final double windowSeconds;
  final List<String> warnings;
}

/// Detects short bursts whose window RMS exceeds [thresholdFactor] times the
/// median window RMS.
AudioEnvelopeResult detectAudioTransients(
  AudioChannelData channel, {
  double thresholdFactor = 4.0,
  double maxDurationSeconds = 0.01,
  double windowSeconds = 0.001,
}) {
  final windows = _windowRms(channel, windowSeconds);
  if (windows.isEmpty) {
    return AudioEnvelopeResult(
      events: const [],
      medianRmsVolts: 0,
      thresholdVolts: 0,
      windowSeconds: windowSeconds,
      warnings: const ['record is shorter than one analysis window'],
    );
  }
  final median = _median([for (final w in windows) w.rms]);
  if (median <= 0) {
    return AudioEnvelopeResult(
      events: const [],
      medianRmsVolts: median,
      thresholdVolts: 0,
      windowSeconds: windowSeconds,
      warnings: const ['median window RMS is zero; no transient threshold'],
    );
  }
  final threshold = median * thresholdFactor;
  final events = <AudioEnvelopeEvent>[];
  var start = -1;

  for (var i = 0; i <= windows.length; i++) {
    final above = i < windows.length && windows[i].rms > threshold;
    if (above && start < 0) {
      start = i;
    } else if (!above && start >= 0) {
      final end = i - 1;
      final duration = windows[end].end - windows[start].start;
      if (duration <= maxDurationSeconds) {
        final event = _eventForWindowRange(
          channel,
          windows,
          start,
          end,
          median,
        );
        events.add(event);
      }
      start = -1;
    }
  }

  return AudioEnvelopeResult(
    events: events,
    medianRmsVolts: median,
    thresholdVolts: threshold,
    windowSeconds: windowSeconds,
    warnings: events.isEmpty
        ? const ['no transient above the threshold']
        : const [],
  );
}

/// Detects intervals whose window RMS falls below [thresholdFactor] times the
/// median window RMS for at least [minDurationSeconds].
AudioEnvelopeResult detectAudioDropouts(
  AudioChannelData channel, {
  double thresholdFactor = 0.1,
  double minDurationSeconds = 0.001,
  double windowSeconds = 0.001,
}) {
  final windows = _windowRms(channel, windowSeconds);
  if (windows.isEmpty) {
    return AudioEnvelopeResult(
      events: const [],
      medianRmsVolts: 0,
      thresholdVolts: 0,
      windowSeconds: windowSeconds,
      warnings: const ['record is shorter than one analysis window'],
    );
  }
  final median = _median([for (final w in windows) w.rms]);
  if (median <= 0) {
    return AudioEnvelopeResult(
      events: const [],
      medianRmsVolts: median,
      thresholdVolts: 0,
      windowSeconds: windowSeconds,
      warnings: const ['median window RMS is zero; the signal is silent'],
    );
  }
  final threshold = median * thresholdFactor;
  final events = <AudioEnvelopeEvent>[];
  var start = -1;

  for (var i = 0; i <= windows.length; i++) {
    final below = i < windows.length && windows[i].rms < threshold;
    if (below && start < 0) {
      start = i;
    } else if (!below && start >= 0) {
      final end = i - 1;
      final duration = windows[end].end - windows[start].start;
      if (duration >= minDurationSeconds) {
        events.add(_eventForWindowRange(channel, windows, start, end, median));
      }
      start = -1;
    }
  }

  return AudioEnvelopeResult(
    events: events,
    medianRmsVolts: median,
    thresholdVolts: threshold,
    windowSeconds: windowSeconds,
    warnings: events.isEmpty
        ? const ['no dropout below the threshold']
        : const [],
  );
}

/// Period, duty and amplitude stability of a periodic signal.
class AudioStabilityMetrics {
  const AudioStabilityMetrics({
    required this.periodCount,
    this.meanFrequencyHz,
    this.frequencyStdDevHz,
    this.frequencyVariationPercent,
    this.frequencyStabilityPpm,
    this.periodJitterSeconds,
    this.periodJitterPercent,
    this.meanDutyPercent,
    this.dutyStdDevPercent,
    this.dutyVariationPercent,
    this.meanVppVolts,
    this.vppStdDevVolts,
    this.amplitudeVariationPercent,
    this.rmsVariationPercent,
    required this.warnings,
  });

  final int periodCount;
  final double? meanFrequencyHz;
  final double? frequencyStdDevHz;
  final double? frequencyVariationPercent;
  final double? frequencyStabilityPpm;
  final double? periodJitterSeconds;
  final double? periodJitterPercent;
  final double? meanDutyPercent;
  final double? dutyStdDevPercent;
  final double? dutyVariationPercent;
  final double? meanVppVolts;
  final double? vppStdDevVolts;
  final double? amplitudeVariationPercent;
  final double? rmsVariationPercent;
  final List<String> warnings;
}

/// Measures period-to-period and window-to-window stability.
AudioStabilityMetrics measureAudioStability(AudioChannelData channel) {
  final periods = measureAudioPeriods(channel);
  final warnings = <String>[];
  if (periods.periods.length < 2) {
    return AudioStabilityMetrics(
      periodCount: periods.periods.length,
      warnings: const ['fewer than two complete periods detected'],
    );
  }

  final frequencies = [
    for (final period in periods.periods)
      if (period > 0) 1 / period,
  ];
  final meanFrequency = _mean(frequencies);
  final frequencyStd = _stdDev(frequencies);
  final meanPeriod = _mean(periods.periods);
  final periodStd = _stdDev(periods.periods);

  double? meanDuty;
  double? dutyStd;
  if (periods.dutyRatios.isNotEmpty) {
    meanDuty = _mean(periods.dutyRatios);
    dutyStd = _stdDev(periods.dutyRatios);
  }
  double? meanVpp;
  double? vppStd;
  if (periods.vppValues.isNotEmpty) {
    meanVpp = _mean(periods.vppValues);
    vppStd = _stdDev(periods.vppValues);
  }

  final windows = _windowRms(channel, 0.01);
  final rmsValues = [for (final window in windows) window.rms];
  final rmsVariation = rmsValues.length < 2
      ? null
      : _variationPercent(_stdDev(rmsValues), _mean(rmsValues));

  return AudioStabilityMetrics(
    periodCount: periods.periods.length,
    meanFrequencyHz: meanFrequency,
    frequencyStdDevHz: frequencyStd,
    frequencyVariationPercent: _variationPercent(frequencyStd, meanFrequency),
    frequencyStabilityPpm: meanFrequency > 0
        ? frequencyStd / meanFrequency * 1e6
        : null,
    periodJitterSeconds: periodStd,
    periodJitterPercent: _variationPercent(periodStd, meanPeriod),
    meanDutyPercent: meanDuty == null ? null : meanDuty * 100,
    dutyStdDevPercent: dutyStd == null ? null : dutyStd * 100,
    dutyVariationPercent: _variationPercent(dutyStd, meanDuty),
    meanVppVolts: meanVpp,
    vppStdDevVolts: vppStd,
    amplitudeVariationPercent: _variationPercent(vppStd, meanVpp),
    rmsVariationPercent: rmsVariation,
    warnings: warnings,
  );
}

/// One clipping region.
class AudioClippingRegion {
  const AudioClippingRegion({
    required this.type,
    required this.startSeconds,
    required this.endSeconds,
    required this.levelVolts,
    required this.sampleCount,
  });

  final String type;
  final double startSeconds;
  final double endSeconds;
  final double levelVolts;
  final int sampleCount;
}

/// Result of the clipping detector.
class AudioClippingResult {
  const AudioClippingResult({
    required this.clippingDetected,
    required this.clippingRatio,
    required this.upperClippingRatio,
    required this.lowerClippingRatio,
    required this.regionCount,
    required this.adcClippingRatio,
    required this.adcRegionCount,
    required this.regions,
    required this.method,
    required this.warnings,
  });

  final bool clippingDetected;
  final double clippingRatio;
  final double upperClippingRatio;
  final double lowerClippingRatio;
  final int regionCount;
  final double adcClippingRatio;
  final int adcRegionCount;
  final List<AudioClippingRegion> regions;
  final String method;
  final List<String> warnings;
}

/// Detects flat-top clipping and ADC rail clipping.
///
/// The flat-top heuristic follows the application's feature extractor: a
/// clipped signal stays within 0.5 % of its maximum/minimum for much longer
/// than a smooth peak would. [fundamentalHz] makes the natural peak duration
/// explicit; without it the heuristic is conservative and marked as such.
AudioClippingResult detectAudioClipping(
  AudioChannelData channel, {
  double? fundamentalHz,
  double adcThresholdRatio = 0.99,
  int maxRegions = 50,
}) {
  final values = channel.samples;
  final n = values.length;
  if (n < 8 || channel.sampleRateHz <= 0) {
    return const AudioClippingResult(
      clippingDetected: false,
      clippingRatio: 0,
      upperClippingRatio: 0,
      lowerClippingRatio: 0,
      regionCount: 0,
      adcClippingRatio: 0,
      adcRegionCount: 0,
      regions: [],
      method: 'signal_flat_top_and_adc_rail',
      warnings: ['fewer than 8 samples'],
    );
  }

  var vMin = values.first;
  var vMax = values.first;
  for (final value in values) {
    if (value < vMin) vMin = value;
    if (value > vMax) vMax = value;
  }
  final amplitude = vMax - vMin;
  final epsilon = amplitude * 0.005;
  final periodSamples = fundamentalHz != null && fundamentalHz > 0
      ? channel.sampleRateHz / fundamentalHz
      : null;
  final naturalBandSamples = periodSamples == null || amplitude <= 0
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

  final regions = <AudioClippingRegion>[];
  var upperCount = 0;
  var lowerCount = 0;

  void scan(bool upper) {
    var runStart = -1;
    for (var i = 0; i <= n; i++) {
      final inLevel =
          i < n &&
          (upper ? values[i] >= vMax - epsilon : values[i] <= vMin + epsilon);
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
          if (regions.length < maxRegions) {
            regions.add(
              AudioClippingRegion(
                type: upper ? 'upper' : 'lower',
                startSeconds: runStart / channel.sampleRateHz,
                endSeconds: (i - 1) / channel.sampleRateHz,
                levelVolts: upper ? vMax : vMin,
                sampleCount: length,
              ),
            );
          }
        }
        runStart = -1;
      }
    }
  }

  scan(true);
  scan(false);

  var adcCount = 0;
  var adcRegions = 0;
  if (channel.fullScaleVolts > 0) {
    final threshold = channel.fullScaleVolts * adcThresholdRatio;
    var runSign = 0;
    var running = false;
    for (var i = 0; i <= n; i++) {
      final value = i < n ? values[i] : 0.0;
      final sign = i < n && value.abs() >= threshold ? value.sign.toInt() : 0;
      if (sign != 0 && sign == runSign) {
        adcCount++;
        running = true;
      } else {
        if (running) adcRegions++;
        running = sign != 0;
        runSign = sign;
        if (sign != 0) adcCount++;
      }
    }
  }

  final warnings = <String>[];
  if (fundamentalHz == null || fundamentalHz <= 0) {
    warnings.add(
      'no fundamental frequency supplied; the flat-top threshold is '
      'conservative',
    );
  }
  if (regions.isEmpty && adcRegions == 0) {
    warnings.add('no clipping region detected');
  }

  final signalRatio = (upperCount + lowerCount) / n;
  final adcRatio = channel.fullScaleVolts > 0 ? adcCount / n : 0.0;
  return AudioClippingResult(
    clippingDetected: regions.isNotEmpty || adcRegions > 0,
    clippingRatio: signalRatio,
    upperClippingRatio: upperCount / n,
    lowerClippingRatio: lowerCount / n,
    regionCount: regions.length,
    adcClippingRatio: adcRatio,
    adcRegionCount: adcRegions,
    regions: regions,
    method: 'signal_flat_top_and_adc_rail',
    warnings: warnings,
  );
}

class _RmsWindow {
  const _RmsWindow(this.start, this.end, this.rms);

  final double start;
  final double end;
  final double rms;
}

List<_RmsWindow> _windowRms(AudioChannelData channel, double windowSeconds) {
  final values = channel.samples;
  final fs = channel.sampleRateHz;
  if (values.isEmpty || fs <= 0) return const [];
  final size = math.max(4, (windowSeconds * fs).round());
  final hop = math.max(1, size ~/ 2);
  final windows = <_RmsWindow>[];
  if (values.length < size) {
    windows.add(
      _RmsWindow(0, values.length / fs, _rmsRange(values, 0, values.length)),
    );
    return windows;
  }
  for (var start = 0; start + size <= values.length; start += hop) {
    windows.add(
      _RmsWindow(
        start / fs,
        (start + size) / fs,
        _rmsRange(values, start, start + size),
      ),
    );
  }
  return windows;
}

AudioEnvelopeEvent _eventForWindowRange(
  AudioChannelData channel,
  List<_RmsWindow> windows,
  int start,
  int end,
  double median,
) {
  final startTime = windows[start].start;
  final endTime = windows[end].end;
  final startIndex = (startTime * channel.sampleRateHz).round().clamp(
    0,
    channel.samples.length - 1,
  );
  final endIndex = (endTime * channel.sampleRateHz).round().clamp(
    0,
    channel.samples.length,
  );
  var peak = 0.0;
  var maxRms = windows[start].rms;
  for (var i = start; i <= end; i++) {
    if (windows[i].rms > maxRms) maxRms = windows[i].rms;
  }
  for (var i = startIndex; i < endIndex; i++) {
    final value = channel.samples[i].abs();
    if (value > peak) peak = value;
  }
  return AudioEnvelopeEvent(
    startSeconds: startTime,
    endSeconds: endTime,
    peakVolts: peak,
    rmsVolts: maxRms,
    ratioToMedian: median > 0 ? maxRms / median : 0,
  );
}

double _rmsRange(Float64List values, int start, int end) {
  var sumSquares = 0.0;
  for (var i = start; i < end; i++) {
    sumSquares += values[i] * values[i];
  }
  final length = end - start;
  return length > 0 ? math.sqrt(sumSquares / length) : 0;
}

double _crossingTime(
  double previous,
  double current,
  double level,
  int previousIndex,
  double sampleRate,
) {
  final delta = current - previous;
  if (delta.abs() <= 1e-15) return previousIndex / sampleRate;
  final fraction = ((level - previous) / delta).clamp(0.0, 1.0);
  return (previousIndex + fraction) / sampleRate;
}

double _mean(List<double> values) {
  if (values.isEmpty) return 0;
  var sum = 0.0;
  for (final value in values) {
    sum += value;
  }
  return sum / values.length;
}

double _stdDev(List<double> values) {
  if (values.length < 2) return 0;
  final mean = _mean(values);
  var sumSquares = 0.0;
  for (final value in values) {
    final delta = value - mean;
    sumSquares += delta * delta;
  }
  return math.sqrt(sumSquares / (values.length - 1));
}

double? _variationPercent(double? stdDev, double? mean) {
  if (stdDev == null || mean == null || mean == 0) return null;
  return stdDev / mean.abs() * 100;
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final copy = List<double>.of(values)..sort();
  final middle = copy.length ~/ 2;
  return copy.length.isOdd
      ? copy[middle]
      : (copy[middle - 1] + copy[middle]) / 2;
}

double _db(double ratio) => 20 * math.log(ratio) / math.ln10;
