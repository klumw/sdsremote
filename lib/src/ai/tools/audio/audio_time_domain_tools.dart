/// Time-domain tools for the audio analysis agent.
///
/// Edge, delay, transient, dropout and stability measurements are computed
/// from the complete acquisition record, not from the decimated display data.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import 'audio_analysis_context.dart';
import 'audio_spectrum.dart';
import 'audio_time_domain.dart';
import 'audio_tool_support.dart';

/// Creates the time-domain tool group (D).
List<Tool<Map<String, dynamic>>> createAudioTimeDomainTools({
  AudioAnalysisContextProvider? context,
  String agentName = 'unknown',
}) {
  return [
    _measureRiseFallTime(context, agentName),
    _measurePhaseDifference(context, agentName),
    _measureDelay(context, agentName),
    _detectTransients(context, agentName),
    _detectDropout(context, agentName),
    _measureSignalStability(context, agentName),
  ];
}

Tool<Map<String, dynamic>> _measureRiseFallTime(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_rise_fall_time',
    agentName: agentName,
    description:
        'Measures 10–90 % rise and fall times of one acquired channel. '
        'Returns mean, median, minimum and maximum edge times, the edge '
        'counts and the low/high levels used for the thresholds. Requires '
        'at least one complete edge.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to measure. Omit it to use the first acquired channel.',
      ),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final requested = audioStringArg(args, 'channel');
      final channel = audioChannel(context, requested);
      if (channel == null) return audioChannelError(requested);

      final edges = measureAudioEdges(channel);
      final rise = _stats(edges.riseTimesSeconds);
      final fall = _stats(edges.fallTimesSeconds);
      return {
        'channel': channel.label,
        'riseTimeSeconds': rise.mean,
        'riseTimeMedianSeconds': rise.median,
        'riseTimeMinSeconds': rise.min,
        'riseTimeMaxSeconds': rise.max,
        'riseEdgeCount': edges.riseTimesSeconds.length,
        'fallTimeSeconds': fall.mean,
        'fallTimeMedianSeconds': fall.median,
        'fallTimeMinSeconds': fall.min,
        'fallTimeMaxSeconds': fall.max,
        'fallEdgeCount': edges.fallTimesSeconds.length,
        'lowLevelVolts': edges.lowLevelVolts,
        'highLevelVolts': edges.highLevelVolts,
        'lowThresholdVolts': edges.lowThresholdVolts,
        'highThresholdVolts': edges.highThresholdVolts,
        'method': 'time_domain_10_90_percent',
        'warnings': edges.warnings,
      };
    },
  );
}

Tool<Map<String, dynamic>> _measurePhaseDifference(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_phase_difference',
    agentName: agentName,
    description:
        'Measures the phase difference between two acquired channels at a '
        'given or detected fundamental frequency, and reports the normalized '
        'cross-correlation and relative delay for context. Positive delay '
        'means channelB is later than channelA. The channels must share a '
        'sample rate.',
    properties: {
      'channelA': audioChannelProperty('Reference channel (default ch1).'),
      'channelB': audioChannelProperty('Compared channel (default ch2).'),
      'frequencyHz': audioNumberProperty(
        'Frequency at which to measure phase. Omit it to use the detected '
        'fundamental.',
        minimum: 0.001,
      ),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final requestedA = audioStringArg(args, 'channelA') ?? 'ch1';
      final requestedB = audioStringArg(args, 'channelB') ?? 'ch2';
      final a = audioChannel(context, requestedA);
      final b = audioChannel(context, requestedB);
      if (a == null) return audioChannelError(requestedA);
      if (b == null) return audioChannelError(requestedB);
      if (a.sampleRateHz != b.sampleRateHz) {
        return {
          'error': 'The channels have different sample rates.',
          'channelA': a.label,
          'channelB': b.label,
        };
      }

      var frequency = audioNumberArg(args, 'frequencyHz');
      frequency ??= autocorrelationFundamentalHz(a);
      frequency ??= computeAudioSpectrum(a)?.metrics.fundamentalHz;
      final correlation = audioChannelCorrelation(a, b);
      return {
        'channelA': a.label,
        'channelB': b.label,
        'frequencyHz': frequency,
        'phaseDifferenceDeg': frequency == null
            ? null
            : phaseDifferenceAtFrequency(a, b, frequency),
        'correlation': correlation?.coefficient,
        'delaySamples': correlation?.lagSamples,
        'delaySeconds': correlation == null
            ? null
            : correlation.lagSamples / a.sampleRateHz,
        'delaySignConvention': 'positive means channelB is later than channelA',
        'method': 'windowed_dft_phase_and_cross_correlation',
        'warnings': frequency == null
            ? const ['no frequency available; only the delay was measured']
            : const <String>[],
      };
    },
  );
}

Tool<Map<String, dynamic>> _measureDelay(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_delay',
    agentName: agentName,
    description:
        'Measures the relative delay between two acquired channels with '
        'normalized cross-correlation. Positive delay means channelB is later '
        'than channelA. The search is limited to maxDelaySeconds; a result at '
        'the limit is flagged because the true delay may be longer. For '
        'periodic signals the delay is ambiguous modulo one period; use '
        'measure_phase_difference for the phase at a known frequency.',
    properties: {
      'channelA': audioChannelProperty('Reference channel (default ch1).'),
      'channelB': audioChannelProperty('Compared channel (default ch2).'),
      'maxDelaySeconds': audioNumberProperty(
        'Maximum delay searched, in seconds.',
        minimum: 0.000001,
        maximum: 1,
      ),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final requestedA = audioStringArg(args, 'channelA') ?? 'ch1';
      final requestedB = audioStringArg(args, 'channelB') ?? 'ch2';
      final a = audioChannel(context, requestedA);
      final b = audioChannel(context, requestedB);
      if (a == null) return audioChannelError(requestedA);
      if (b == null) return audioChannelError(requestedB);
      if (a.sampleRateHz != b.sampleRateHz) {
        return {
          'error': 'The channels have different sample rates.',
          'channelA': a.label,
          'channelB': b.label,
        };
      }
      final maxDelay = audioDoubleOr(
        args,
        'maxDelaySeconds',
        0.02,
      ).clamp(0.000001, 1.0).toDouble();
      final correlation = audioChannelCorrelation(
        a,
        b,
        maxSamples: 8192,
        maxDelaySeconds: maxDelay,
      );
      if (correlation == null) {
        return {
          'error': 'The channels are too short or have incompatible rates.',
        };
      }
      final warnings = <String>[];
      final maxLag = (maxDelay * a.sampleRateHz).round();
      if (correlation.lagSamples.abs() >= maxLag - 1) {
        warnings.add(
          'the correlation peak is at the search limit; the real delay may be '
          'longer than maxDelaySeconds',
        );
      }
      return {
        'channelA': a.label,
        'channelB': b.label,
        'delaySamples': correlation.lagSamples,
        'delaySeconds': correlation.lagSamples / a.sampleRateHz,
        'correlation': correlation.coefficient,
        'maxDelaySeconds': maxDelay,
        'sampleRateHz': a.sampleRateHz,
        'delaySignConvention': 'positive means channelB is later than channelA',
        'method': 'normalized_cross_correlation',
        'warnings': warnings,
      };
    },
  );
}

Tool<Map<String, dynamic>> _detectTransients(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'detect_transients',
    agentName: agentName,
    description:
        'Detects short transients or spikes whose window RMS exceeds '
        'thresholdFactor times the median window RMS. Returns event count, '
        'start/end times, peak amplitude and the ratio to the median. '
        'The detector is a windowed-RMS heuristic, not an edge-triggered '
        'oscilloscope trigger.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to analyse. Omit it to use the first acquired channel.',
      ),
      'thresholdFactor': audioNumberProperty(
        'Window RMS multiple above the median that counts as a transient.',
        minimum: 1.1,
        maximum: 100,
      ),
      'maxDurationMs': audioNumberProperty(
        'Longest event duration counted as a transient, in milliseconds.',
        minimum: 0.01,
        maximum: 1000,
      ),
      'windowMs': audioNumberProperty(
        'RMS analysis window, in milliseconds.',
        minimum: 0.01,
        maximum: 100,
      ),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final requested = audioStringArg(args, 'channel');
      final channel = audioChannel(context, requested);
      if (channel == null) return audioChannelError(requested);

      final result = detectAudioTransients(
        channel,
        thresholdFactor: audioDoubleOr(args, 'thresholdFactor', 4),
        maxDurationSeconds: audioDoubleOr(args, 'maxDurationMs', 10) / 1000,
        windowSeconds: audioDoubleOr(args, 'windowMs', 1) / 1000,
      );
      return {
        'channel': channel.label,
        'transientDetected': result.events.isNotEmpty,
        'eventCount': result.events.length,
        'events': [
          for (final event in result.events)
            {
              'startSeconds': event.startSeconds,
              'endSeconds': event.endSeconds,
              'peakVolts': event.peakVolts,
              'rmsVolts': event.rmsVolts,
              'ratioToMedian': event.ratioToMedian,
            },
        ],
        'medianRmsVolts': result.medianRmsVolts,
        'thresholdVolts': result.thresholdVolts,
        'windowSeconds': result.windowSeconds,
        'method': 'windowed_rms_transient_search',
        'warnings': result.warnings,
      };
    },
  );
}

Tool<Map<String, dynamic>> _detectDropout(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'detect_dropout',
    agentName: agentName,
    description:
        'Detects signal dropouts whose window RMS falls below '
        'thresholdFactor times the median window RMS for at least '
        'minDurationMs. Returns event count, start/end times, RMS and the '
        'ratio to the median. A silent record returns a warning instead of '
        'an invented event.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to analyse. Omit it to use the first acquired channel.',
      ),
      'thresholdFactor': audioNumberProperty(
        'Window RMS fraction of the median that counts as a dropout.',
        minimum: 0.001,
        maximum: 0.999,
      ),
      'minDurationMs': audioNumberProperty(
        'Shortest dropout duration reported, in milliseconds.',
        minimum: 0.01,
        maximum: 10000,
      ),
      'windowMs': audioNumberProperty(
        'RMS analysis window, in milliseconds.',
        minimum: 0.01,
        maximum: 100,
      ),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final requested = audioStringArg(args, 'channel');
      final channel = audioChannel(context, requested);
      if (channel == null) return audioChannelError(requested);

      final result = detectAudioDropouts(
        channel,
        thresholdFactor: audioDoubleOr(args, 'thresholdFactor', 0.1),
        minDurationSeconds: audioDoubleOr(args, 'minDurationMs', 1) / 1000,
        windowSeconds: audioDoubleOr(args, 'windowMs', 1) / 1000,
      );
      return {
        'channel': channel.label,
        'dropoutDetected': result.events.isNotEmpty,
        'eventCount': result.events.length,
        'events': [
          for (final event in result.events)
            {
              'startSeconds': event.startSeconds,
              'endSeconds': event.endSeconds,
              'peakVolts': event.peakVolts,
              'rmsVolts': event.rmsVolts,
              'ratioToMedian': event.ratioToMedian,
            },
        ],
        'medianRmsVolts': result.medianRmsVolts,
        'thresholdVolts': result.thresholdVolts,
        'windowSeconds': result.windowSeconds,
        'method': 'windowed_rms_dropout_search',
        'warnings': result.warnings,
      };
    },
  );
}

Tool<Map<String, dynamic>> _measureSignalStability(
  AudioAnalysisContextProvider? contextProvider,
  String agentName,
) {
  return createAudioTool(
    name: 'measure_signal_stability',
    agentName: agentName,
    description:
        'Measures period-to-period and window-to-window stability of a '
        'periodic signal: frequency variation and ppm stability, period '
        'jitter, duty-cycle variation, per-period amplitude variation and '
        'RMS variation. Needs at least two complete periods; otherwise it '
        'returns a warning instead of a fabricated value.',
    properties: {
      'channel': audioChannelProperty(
        'Channel to measure. Omit it to use the first acquired channel.',
      ),
    },
    handler: (args) async {
      final context = audioContext(contextProvider);
      if (context == null) return audioContextError();
      final requested = audioStringArg(args, 'channel');
      final channel = audioChannel(context, requested);
      if (channel == null) return audioChannelError(requested);

      final stability = measureAudioStability(channel);
      return {
        'channel': channel.label,
        'periodCount': stability.periodCount,
        'meanFrequencyHz': stability.meanFrequencyHz,
        'frequencyStdDevHz': stability.frequencyStdDevHz,
        'frequencyVariationPercent': stability.frequencyVariationPercent,
        'frequencyStabilityPpm': stability.frequencyStabilityPpm,
        'periodJitterSeconds': stability.periodJitterSeconds,
        'periodJitterPercent': stability.periodJitterPercent,
        'meanDutyPercent': stability.meanDutyPercent,
        'dutyStdDevPercent': stability.dutyStdDevPercent,
        'dutyVariationPercent': stability.dutyVariationPercent,
        'meanVppVolts': stability.meanVppVolts,
        'vppStdDevVolts': stability.vppStdDevVolts,
        'amplitudeVariationPercent': stability.amplitudeVariationPercent,
        'rmsVariationPercent': stability.rmsVariationPercent,
        'method': 'schmitt_trigger_period_and_window_statistics',
        'warnings': stability.warnings,
      };
    },
  );
}

class _ListStats {
  const _ListStats({this.mean, this.median, this.min, this.max});

  final double? mean;
  final double? median;
  final double? min;
  final double? max;
}

_ListStats _stats(List<double> values) {
  if (values.isEmpty) return const _ListStats();
  final sorted = List<double>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  final median = sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
  var sum = 0.0;
  for (final value in values) {
    sum += value;
  }
  return _ListStats(
    mean: sum / values.length,
    median: median,
    min: sorted.first,
    max: sorted.last,
  );
}
