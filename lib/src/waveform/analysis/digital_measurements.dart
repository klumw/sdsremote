/// Deterministic digital-signal measurements for the DigitalAgent tools.
///
/// The functions operate on [WaveformTrace] time/voltage records or on the
/// scalar [WaveformFeatures] of the existing analysis engine. They contain no
/// file or device I/O, so they are testable with synthetic waveforms.
library;

import 'dart:math' as math;

import 'waveform_analysis_models.dart';

/// Edge times detected on one digital signal.
class DigitalEdgeTimes {
  const DigitalEdgeTimes({required this.rising, required this.falling});

  final List<double> rising;
  final List<double> falling;

  bool get isEmpty => rising.isEmpty && falling.isEmpty;

  List<double> forPolarity(String edge) => switch (edge.toLowerCase()) {
    'falling' => falling,
    'rising' => rising,
    _ => <double>[...rising, ...falling]..sort(),
  };
}

/// One complete high or low pulse between two opposite edges.
class DigitalPulse {
  const DigitalPulse({
    required this.startSeconds,
    required this.endSeconds,
    required this.high,
  });

  final double startSeconds;
  final double endSeconds;
  final bool high;

  double get widthSeconds => endSeconds - startSeconds;
}

/// Detects rising and falling edges with a mid-level threshold and hysteresis.
///
/// The threshold defaults to the midpoint between the minimum and maximum
/// voltage. The hysteresis is [hysteresisFraction] of the peak-to-peak voltage,
/// so ringing inside the band does not create extra edges. Edge times are
/// linearly interpolated at the threshold.
DigitalEdgeTimes detectDigitalEdges(
  WaveformTrace trace, {
  double? thresholdVolts,
  double hysteresisFraction = 0.1,
}) {
  final times = trace.times;
  final volts = trace.volts;
  final count = math.min(times.length, volts.length);
  if (count < 3) {
    return const DigitalEdgeTimes(rising: [], falling: []);
  }

  var vMin = volts[0];
  var vMax = volts[0];
  for (var i = 1; i < count; i++) {
    final value = volts[i];
    if (value < vMin) vMin = value;
    if (value > vMax) vMax = value;
  }
  final amplitude = vMax - vMin;
  if (!amplitude.isFinite || amplitude <= 0) {
    return const DigitalEdgeTimes(rising: [], falling: []);
  }

  final mid = thresholdVolts ?? (vMin + vMax) / 2;
  final hysteresis = amplitude * hysteresisFraction.clamp(0.01, 0.4);
  final rising = <double>[];
  final falling = <double>[];
  var high = volts[0] >= mid;

  for (var i = 1; i < count; i++) {
    final previous = volts[i - 1];
    final current = volts[i];
    if (!high && current > mid + hysteresis) {
      rising.add(_crossingTime(times[i - 1], previous, times[i], current, mid));
      high = true;
    } else if (high && current < mid - hysteresis) {
      falling.add(
        _crossingTime(times[i - 1], previous, times[i], current, mid),
      );
      high = false;
    }
  }
  return DigitalEdgeTimes(rising: rising, falling: falling);
}

/// Detects complete high and low pulses between opposite edges.
List<DigitalPulse> detectDigitalPulses(
  WaveformTrace trace, {
  double? thresholdVolts,
}) {
  final edges = detectDigitalEdges(trace, thresholdVolts: thresholdVolts);
  final ordered = <({double time, bool rising})>[
    for (final time in edges.rising) (time: time, rising: true),
    for (final time in edges.falling) (time: time, rising: false),
  ]..sort((a, b) => a.time.compareTo(b.time));

  final pulses = <DigitalPulse>[];
  for (var i = 0; i + 1 < ordered.length; i++) {
    final start = ordered[i];
    final end = ordered[i + 1];
    if (start.rising == end.rising || end.time <= start.time) continue;
    pulses.add(
      DigitalPulse(
        startSeconds: start.time,
        endSeconds: end.time,
        high: start.rising,
      ),
    );
  }
  return pulses;
}

/// Mean rise and fall time plus the edge counts and slopes.
Map<String, dynamic> digitalRiseFallTime(
  WaveformFeatures features, {
  String? channel,
}) {
  final rise = _finite(features.riseTimeSeconds);
  final fall = _finite(features.fallTimeSeconds);
  if (rise == null && fall == null) {
    return <String, dynamic>{
      'channel': channel,
      'error':
          'No rise or fall edges were detected. Check the channel, the '
          'vertical scale and the trigger.',
    };
  }
  return <String, dynamic>{
    'channel': channel,
    'riseTimeSeconds': rise,
    'fallTimeSeconds': fall,
    'risingEdgeCount': features.risingEdgeCount,
    'fallingEdgeCount': features.fallingEdgeCount,
    'edgeSteepness': _finite(features.edgeSteepness),
    'positiveSlopeVoltsPerSecond': _finite(
      features.positiveSlopeVoltsPerSecond,
    ),
    'negativeSlopeVoltsPerSecond': _finite(
      features.negativeSlopeVoltsPerSecond,
    ),
    'method': 'mean_10_90_percent_levels',
    'notes': const [
      'Rise and fall times are averaged over the detected edges and measured '
          'between the 10 % and 90 % levels.',
    ],
  };
}

/// Mean, minimum and maximum high and low pulse widths.
Map<String, dynamic> digitalPulseWidth(
  WaveformTrace trace, {
  String? channel,
  double? thresholdVolts,
}) {
  final pulses = detectDigitalPulses(trace, thresholdVolts: thresholdVolts);
  if (pulses.isEmpty) {
    return <String, dynamic>{
      'channel': channel ?? trace.channel,
      'error':
          'No complete high or low pulses were detected. Check the channel '
          'and the vertical scale.',
    };
  }
  final high = [
    for (final pulse in pulses)
      if (pulse.high) pulse.widthSeconds,
  ];
  final low = [
    for (final pulse in pulses)
      if (!pulse.high) pulse.widthSeconds,
  ];
  final meanHigh = _mean(high);
  final meanLow = _mean(low);
  final duty = meanHigh != null && meanLow != null && meanHigh + meanLow > 0
      ? meanHigh / (meanHigh + meanLow) * 100
      : null;
  return <String, dynamic>{
    'channel': channel ?? trace.channel,
    'highPulseCount': high.length,
    'lowPulseCount': low.length,
    'highPulseWidthSeconds': meanHigh,
    'highPulseWidthMinSeconds': _min(high),
    'highPulseWidthMaxSeconds': _max(high),
    'lowPulseWidthSeconds': meanLow,
    'lowPulseWidthMinSeconds': _min(low),
    'lowPulseWidthMaxSeconds': _max(low),
    'dutyPercent': duty,
    'periodSeconds': meanHigh != null && meanLow != null
        ? meanHigh + meanLow
        : null,
    'method': 'mid_level_run_length',
    'notes': const [
      'Only complete pulses between two detected edges are included.',
    ],
  };
}

/// Edge distribution, mean interval between edges, minimum and maximum.
Map<String, dynamic> digitalEdgeStatistics(
  WaveformTrace trace, {
  String? channel,
  String edge = 'both',
}) {
  final edges = detectDigitalEdges(trace);
  if (edges.isEmpty) {
    return <String, dynamic>{
      'channel': channel ?? trace.channel,
      'error':
          'No edges were detected. Check the channel and the vertical scale.',
    };
  }
  final selected = edges.forPolarity(edge);
  final intervals = _differences(selected);
  return <String, dynamic>{
    'channel': channel ?? trace.channel,
    'edge': edge,
    'risingEdgeCount': edges.rising.length,
    'fallingEdgeCount': edges.falling.length,
    'selectedEdgeCount': selected.length,
    'intervalCount': intervals.length,
    'meanIntervalSeconds': _mean(intervals),
    'minIntervalSeconds': _min(intervals),
    'maxIntervalSeconds': _max(intervals),
    'stdIntervalSeconds': _std(intervals),
    'edgeTimesSeconds': _limited(selected),
    'method': 'mid_level_crossing_with_hysteresis',
    'notes': const [
      'Intervals are measured between consecutive edges of the selected '
          'polarity. Edge times are relative to the acquisition start.',
    ],
  };
}

/// Period jitter and cycle-to-cycle jitter from rising-edge periods.
Map<String, dynamic> digitalJitter(WaveformTrace trace, {String? channel}) {
  final rising = detectDigitalEdges(trace).rising;
  final periods = _differences(rising);
  if (periods.length < 3) {
    return <String, dynamic>{
      'channel': channel ?? trace.channel,
      'error':
          'Fewer than three periods were detected; jitter cannot be '
          'determined.',
    };
  }
  final meanPeriod = _mean(periods)!;
  final rmsPeriod = _std(periods)!;
  final peakToPeak = _max(periods)! - _min(periods)!;
  final cycleToCycle = _differences(periods);
  final rmsC2C = _std(cycleToCycle);
  final maxC2C = cycleToCycle.isEmpty
      ? null
      : cycleToCycle.map((value) => value.abs()).reduce(math.max);
  return <String, dynamic>{
    'channel': channel ?? trace.channel,
    'periodCount': periods.length,
    'meanPeriodSeconds': meanPeriod,
    'periodJitterRmsSeconds': rmsPeriod,
    'periodJitterPeakToPeakSeconds': peakToPeak,
    'periodJitterPercent': rmsPeriod / meanPeriod * 100,
    'cycleToCycleJitterRmsSeconds': rmsC2C,
    'cycleToCycleJitterMaxSeconds': maxC2C,
    'cycleToCycleJitterPercent': rmsC2C == null
        ? null
        : rmsC2C / meanPeriod * 100,
    'method': 'rising_edge_periods',
    'notes': const [
      'Period jitter is the RMS deviation of the detected periods. '
          'Cycle-to-cycle jitter is the RMS difference between consecutive '
          'periods.',
    ],
  };
}

/// Clock drift and frequency stability from rising-edge periods.
Map<String, dynamic> digitalClockStability(
  WaveformTrace trace, {
  String? channel,
  double? nominalFrequencyHz,
}) {
  final rising = detectDigitalEdges(trace).rising;
  final periods = _differences(rising);
  if (periods.length < 3) {
    return <String, dynamic>{
      'channel': channel ?? trace.channel,
      'error':
          'Fewer than three periods were detected; clock stability cannot be '
          'determined.',
    };
  }
  final frequencies = [
    for (final period in periods)
      if (period > 0) 1 / period,
  ];
  if (frequencies.length < 3) {
    return <String, dynamic>{
      'channel': channel ?? trace.channel,
      'error': 'No valid periods were detected.',
    };
  }
  final meanFrequency = _mean(frequencies)!;
  final rmsFrequency = _std(frequencies)!;
  final minFrequency = _min(frequencies)!;
  final maxFrequency = _max(frequencies)!;
  final midpointTimes = <double>[
    for (var i = 0; i < periods.length; i++) (rising[i] + rising[i + 1]) / 2,
  ];
  final fit = _linearFit(midpointTimes, frequencies);
  final observation = midpointTimes.last - midpointTimes.first;
  final driftPpm = fit != null && observation > 0 && meanFrequency > 0
      ? fit.slope * observation / meanFrequency * 1e6
      : null;
  final errorPpm =
      nominalFrequencyHz != null && nominalFrequencyHz > 0 && meanFrequency > 0
      ? (meanFrequency - nominalFrequencyHz) / nominalFrequencyHz * 1e6
      : null;
  return <String, dynamic>{
    'channel': channel ?? trace.channel,
    'periodCount': periods.length,
    'meanFrequencyHz': meanFrequency,
    'minFrequencyHz': minFrequency,
    'maxFrequencyHz': maxFrequency,
    'frequencyStabilityPpm': rmsFrequency / meanFrequency * 1e6,
    'driftPpm': driftPpm,
    'nominalFrequencyHz': nominalFrequencyHz,
    'frequencyErrorPpm': errorPpm,
    'observationSeconds': observation,
    'method': 'rising_edge_periods_linear_drift',
    'notes': const [
      'Frequency stability is the RMS frequency deviation in ppm. Drift is '
          'the linear frequency trend over the observation window.',
    ],
  };
}

/// Setup and hold times between a clock channel and a data channel.
Map<String, dynamic> digitalSetupHold(
  WaveformTrace clockTrace,
  WaveformTrace dataTrace, {
  String clockEdge = 'rising',
  double? clockThresholdVolts,
  double? dataThresholdVolts,
}) {
  final clockEdges = detectDigitalEdges(
    clockTrace,
    thresholdVolts: clockThresholdVolts,
  ).forPolarity(clockEdge);
  final dataEdges = detectDigitalEdges(
    dataTrace,
    thresholdVolts: dataThresholdVolts,
  );
  final dataTransitions = <double>[...dataEdges.rising, ...dataEdges.falling]
    ..sort();
  if (clockEdges.isEmpty || dataTransitions.isEmpty) {
    return <String, dynamic>{
      'clockChannel': clockTrace.channel,
      'dataChannel': dataTrace.channel,
      'error':
          'The clock or data signal has no detected edges. Check the '
          'channels, thresholds and vertical scale.',
    };
  }

  final setup = <double>[];
  final hold = <double>[];
  var dataIndex = 0;
  double? previousTransition;
  for (final edge in clockEdges) {
    while (dataIndex < dataTransitions.length &&
        dataTransitions[dataIndex] <= edge) {
      previousTransition = dataTransitions[dataIndex];
      dataIndex++;
    }
    final nextTransition = dataIndex < dataTransitions.length
        ? dataTransitions[dataIndex]
        : null;
    if (previousTransition != null) {
      final value = edge - previousTransition;
      if (value > 0) setup.add(value);
    }
    if (nextTransition != null) {
      final value = nextTransition - edge;
      if (value > 0) hold.add(value);
    }
  }

  return <String, dynamic>{
    'clockChannel': clockTrace.channel,
    'dataChannel': dataTrace.channel,
    'clockEdge': clockEdge,
    'clockEdgeCount': clockEdges.length,
    'dataTransitionCount': dataTransitions.length,
    'setupSampleCount': setup.length,
    'setupTimeMinSeconds': _min(setup),
    'setupTimeMeanSeconds': _mean(setup),
    'setupTimeMaxSeconds': _max(setup),
    'holdSampleCount': hold.length,
    'holdTimeMinSeconds': _min(hold),
    'holdTimeMeanSeconds': _mean(hold),
    'holdTimeMaxSeconds': _max(hold),
    'method': 'nearest_data_transition_around_clock_edge',
    'notes': const [
      'Setup is the time from the last data transition before the clock edge '
          'to the clock edge. Hold is the time from the clock edge to the next '
          'data transition. A known data/clock association is required for a '
          'formal protocol timing analysis.',
    ],
  };
}

/// Time offset between corresponding edges of two channels.
Map<String, dynamic> digitalSkew(
  WaveformTrace traceA,
  WaveformTrace traceB, {
  String edge = 'rising',
  double? thresholdA,
  double? thresholdB,
}) {
  final edgesA = detectDigitalEdges(
    traceA,
    thresholdVolts: thresholdA,
  ).forPolarity(edge);
  final edgesB = detectDigitalEdges(
    traceB,
    thresholdVolts: thresholdB,
  ).forPolarity(edge);
  final pairCount = math.min(edgesA.length, edgesB.length);
  if (pairCount == 0) {
    return <String, dynamic>{
      'channelA': traceA.channel,
      'channelB': traceB.channel,
      'edge': edge,
      'error':
          'No matching edges were detected on both channels. Check the '
          'channels, thresholds and vertical scale.',
    };
  }
  final skew = <double>[
    for (var i = 0; i < pairCount; i++) edgesA[i] - edgesB[i],
  ];
  return <String, dynamic>{
    'channelA': traceA.channel,
    'channelB': traceB.channel,
    'edge': edge,
    'pairedEdgeCount': pairCount,
    'skewMinSeconds': _min(skew),
    'skewMeanSeconds': _mean(skew),
    'skewMaxSeconds': _max(skew),
    'skewStdSeconds': _std(skew),
    'method': 'index_paired_edges',
    'notes': const [
      'Skew is channel A minus channel B; a positive value means channel A '
          'occurs later. Edges are paired by their index.',
    ],
  };
}

/// Glitches and pulses narrower than a threshold.
Map<String, dynamic> digitalGlitches(
  WaveformTrace trace, {
  String? channel,
  double? maxPulseWidthSeconds,
  double? thresholdVolts,
}) {
  final pulses = detectDigitalPulses(trace, thresholdVolts: thresholdVolts);
  if (pulses.isEmpty) {
    return <String, dynamic>{
      'channel': channel ?? trace.channel,
      'error':
          'No complete pulses were detected. Check the channel and the '
          'vertical scale.',
    };
  }
  final highWidths = [
    for (final pulse in pulses)
      if (pulse.high) pulse.widthSeconds,
  ];
  final reference = highWidths.isNotEmpty
      ? _median(highWidths)
      : _median([for (final pulse in pulses) pulse.widthSeconds]);
  final threshold =
      maxPulseWidthSeconds ?? (reference != null ? reference * 0.25 : null);
  if (threshold == null || threshold <= 0) {
    return <String, dynamic>{
      'channel': channel ?? trace.channel,
      'error': 'A positive glitch width threshold is required.',
    };
  }
  final glitches = [
    for (final pulse in pulses)
      if (pulse.widthSeconds < threshold) pulse,
  ];
  return <String, dynamic>{
    'channel': channel ?? trace.channel,
    'glitchCount': glitches.length,
    'thresholdSeconds': threshold,
    'medianPulseWidthSeconds': reference,
    'glitches': [
      for (final pulse in glitches.take(50))
        {
          'startSeconds': pulse.startSeconds,
          'widthSeconds': pulse.widthSeconds,
          'polarity': pulse.high ? 'high' : 'low',
        },
    ],
    'method': 'mid_level_run_length',
    'notes': const [
      'By default a glitch is narrower than 25 % of the median high pulse '
          'width. Set maxPulseWidthSeconds to override the threshold.',
    ],
  };
}

/// Overshoot and undershoot relative to the top and base levels.
Map<String, dynamic> digitalOvershootUndershoot(
  WaveformFeatures features, {
  String? channel,
}) {
  final vTop = _finite(features.vTop);
  final vBase = _finite(features.vBase);
  final vMax = _finite(features.vMax);
  final vMin = _finite(features.vMin);
  final vPp = _finite(features.vPp);
  if (vTop == null || vBase == null || vMax == null || vMin == null) {
    return <String, dynamic>{
      'channel': channel,
      'error':
          'The top, base, minimum or maximum level is unavailable. Check the '
          'channel and the vertical scale.',
    };
  }
  final amplitude = vTop - vBase > 0 ? vTop - vBase : vPp;
  if (amplitude == null || amplitude <= 0) {
    return <String, dynamic>{
      'channel': channel,
      'error': 'The signal amplitude is zero; overshoot is undefined.',
    };
  }
  final overshootVolts = vMax > vTop ? vMax - vTop : 0.0;
  final undershootVolts = vBase > vMin ? vBase - vMin : 0.0;
  return <String, dynamic>{
    'channel': channel,
    'vMaxVolts': vMax,
    'vMinVolts': vMin,
    'vTopVolts': vTop,
    'vBaseVolts': vBase,
    'vPpVolts': vPp,
    'overshootVolts': overshootVolts,
    'overshootPercent': overshootVolts / amplitude * 100,
    'undershootVolts': undershootVolts,
    'undershootPercent': undershootVolts / amplitude * 100,
    'method': 'vmax_vmin_vs_top_base',
    'notes': const [
      'The top and base levels are the 95 % and 5 % percentiles of the '
          'capture. Overshoot and undershoot are percentages of top minus '
          'base.',
    ],
  };
}

double _crossingTime(
  double t0,
  double v0,
  double t1,
  double v1,
  double threshold,
) {
  final delta = v1 - v0;
  if (delta.abs() < 1e-15) return t1;
  final fraction = ((threshold - v0) / delta).clamp(0.0, 1.0);
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

double? _std(List<double> values) {
  final mean = _mean(values);
  if (mean == null) return null;
  var sum = 0.0;
  for (final value in values) {
    final difference = value - mean;
    sum += difference * difference;
  }
  return math.sqrt(sum / values.length);
}

double? _min(List<double> values) =>
    values.isEmpty ? null : values.reduce(math.min);

double? _max(List<double> values) =>
    values.isEmpty ? null : values.reduce(math.max);

double? _median(List<double> values) {
  if (values.isEmpty) return null;
  final sorted = List<double>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

List<double> _differences(List<double> values) => [
  for (var i = 1; i < values.length; i++) values[i] - values[i - 1],
];

List<double> _limited(List<double> values) =>
    values.length <= 100 ? values : values.sublist(0, 100);

({double slope, double intercept})? _linearFit(
  List<double> xs,
  List<double> ys,
) {
  if (xs.length != ys.length || xs.length < 2) return null;
  final meanX = _mean(xs);
  final meanY = _mean(ys);
  if (meanX == null || meanY == null) return null;
  var numerator = 0.0;
  var denominator = 0.0;
  for (var i = 0; i < xs.length; i++) {
    final dx = xs[i] - meanX;
    numerator += dx * (ys[i] - meanY);
    denominator += dx * dx;
  }
  if (denominator <= 0) return null;
  final slope = numerator / denominator;
  return (slope: slope, intercept: meanY - slope * meanX);
}

double? _finite(double? value) =>
    value != null && value.isFinite ? value : null;
