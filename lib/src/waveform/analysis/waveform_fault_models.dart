/// Data models for the waveform fault analysis engine.
///
/// The analyzer works on the complete raw capture. Every status, measured
/// value and event is derived deterministically from the samples or from a
/// specification supplied by the caller; nothing is inferred by an LLM.
library;

import 'waveform_analysis_models.dart';

/// Fault categories understood by the fault analysis tool.
///
/// The identifiers are stable and are used in tool calls, result maps and the
/// agent system prompt.
enum WaveformFaultTest {
  amplitude('amplitude', 'Amplitude too high / too low'),
  signalLoss('signal_loss', 'Signal missing / signal dropout'),
  transients('transients', 'Transients / spikes'),
  clipping('clipping', 'Clipping / limiting'),
  frequencyError('frequency_error', 'Frequency error / frequency drift'),
  noise('noise', 'Increased noise'),
  ringing('ringing', 'Unexpected oscillations / ringing'),
  dutyCycle('duty_cycle', 'Duty cycle error'),
  glitches('glitches', 'Glitches / invalid pulses'),
  jitter('jitter', 'Period jitter / timing deviation'),
  dcOffset('dc_offset', 'DC offset error'),
  distortion('distortion', 'Waveform distortion'),
  spuriousFrequencies(
    'spurious_frequencies',
    'Unexpected frequency components',
  ),
  edgeTimes('edge_times', 'Rise / fall time error'),
  amplitudeStability('amplitude_stability', 'Unstable amplitude'),
  settling('settling', 'Incorrect settling behavior'),
  phaseDelay('phase_delay', 'Phase / propagation delay error'),
  crosstalk('crosstalk', 'Crosstalk between channels'),
  intermittent('intermittent', 'Intermittent faults'),
  measurementArtifacts(
    'measurement_artifacts',
    'Measurement errors / artifacts',
  );

  const WaveformFaultTest(this.id, this.label);

  /// Stable identifier used in tool calls and result maps.
  final String id;

  /// Human-readable name shown in the UI and quoted by the agent.
  final String label;

  /// Parses an [id], enum name or label (case-insensitive).
  static WaveformFaultTest? parse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final test in values) {
      if (test.id == normalized ||
          test.name.toLowerCase() == normalized ||
          test.label.toLowerCase() == normalized) {
        return test;
      }
    }
    return null;
  }
}

/// Outcome of a single fault test.
enum WaveformFaultStatus {
  /// The supplied specification was met, or no anomaly was detected.
  pass('pass'),

  /// The supplied specification was violated.
  fail('fail'),

  /// A clear anomaly was detected, but no specification was supplied.
  warning('warning'),

  /// Measurements are reported without a pass/fail verdict.
  informational('informational'),

  /// Required data or a required channel is missing.
  inconclusive('inconclusive'),

  /// The test does not apply to this signal.
  notApplicable('not_applicable');

  const WaveformFaultStatus(this.id);

  final String id;
}

/// Severity of a finding.
enum WaveformFaultSeverity {
  none('none'),
  low('low'),
  medium('medium'),
  high('high');

  const WaveformFaultSeverity(this.id);

  final String id;
}

/// One requested fault test with its optional specification.
class WaveformFaultRequest {
  const WaveformFaultRequest({
    required this.test,
    this.specification = const {},
  });

  final WaveformFaultTest test;

  /// Test-specific reference values and tolerances, for example
  /// `{'expectedVppVolts': 5.0, 'tolerancePercent': 2.0}`.
  final Map<String, dynamic> specification;

  double? number(String key) => _asDouble(specification[key]);

  int? integer(String key) => number(key)?.round();

  bool? boolean(String key) {
    final value = specification[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == 'yes') return true;
      if (normalized == 'false' || normalized == 'no') return false;
    }
    return null;
  }

  String? string(String key) {
    final value = specification[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}

/// Input data of one fault analysis run.
///
/// The trace contains the complete raw capture (no classification
/// decimation). [secondTrace] is required for phase and crosstalk tests.
class WaveformFaultContext {
  const WaveformFaultContext({
    required this.trace,
    required this.channel,
    this.secondTrace,
    this.secondChannel,
    this.sampleRateHz,
    this.verticalScaleVoltsPerDiv,
    this.verticalOffsetVolts,
    this.timebaseSecondsPerDiv,
    this.adcBits = 8,
    this.probeAttenuation = 1.0,
    this.probeAttenuationAssumed = true,
    this.triggerLevelVolts,
    this.triggerPosition = 0,
    this.triggerDelaySeconds,
    this.leadingSamplesExcluded = 0,
  });

  final WaveformTrace trace;
  final String channel;
  final WaveformTrace? secondTrace;
  final String? secondChannel;

  /// Effective sample rate of the transferred record in samples per second.
  final double? sampleRateHz;

  final double? verticalScaleVoltsPerDiv;
  final double? verticalOffsetVolts;
  final double? timebaseSecondsPerDiv;

  /// ADC resolution of the acquisition; the SDS1000X-E series uses 8 bits.
  final int adcBits;

  /// Probe attenuation factor applied to the displayed voltage values.
  final double probeAttenuation;

  /// Whether [probeAttenuation] was assumed (1:1) instead of supplied.
  final bool probeAttenuationAssumed;

  final double? triggerLevelVolts;

  /// Sample index of the trigger inside the transferred record.
  final int triggerPosition;

  final double? triggerDelaySeconds;

  /// Number of leading samples excluded as a known acquisition artifact.
  final int leadingSamplesExcluded;

  double? get durationSeconds => trace.durationSeconds;

  double? get sampleIntervalSeconds => trace.sampleIntervalSeconds;
}

/// Result of one fault test.
class WaveformFaultFinding {
  const WaveformFaultFinding({
    required this.test,
    required this.status,
    required this.severity,
    required this.summary,
    this.measured = const {},
    this.expected,
    this.deviation,
    this.events = const [],
    this.missingInputs = const [],
    this.limitations = const [],
  });

  final WaveformFaultTest test;
  final WaveformFaultStatus status;
  final WaveformFaultSeverity severity;

  /// Deterministic one-sentence explanation of the result.
  final String summary;

  /// Measured values with their units, for example
  /// `{'vppVolts': 6.4, 'vmaxVolts': 3.2}`.
  final Map<String, dynamic> measured;

  /// Supplied reference values and tolerances that were checked.
  final Map<String, dynamic>? expected;

  /// Absolute and relative deviations from [expected].
  final Map<String, dynamic>? deviation;

  /// Affected events, capped by the analyzer (first occurrences first).
  final List<Map<String, dynamic>> events;

  /// Reference or setup values the test needs but did not receive.
  final List<String> missingInputs;

  /// Measurement limitations that affect the interpretation.
  final List<String> limitations;

  Map<String, dynamic> toMap() => {
    'test': test.id,
    'label': test.label,
    'status': status.id,
    'severity': severity.id,
    'summary': summary,
    'measured': measured,
    if (expected != null) 'expected': expected,
    if (deviation != null) 'deviation': deviation,
    if (events.isNotEmpty) 'events': events,
    if (missingInputs.isNotEmpty) 'missingInputs': missingInputs,
    if (limitations.isNotEmpty) 'limitations': limitations,
  };
}

/// Complete result of a fault analysis run.
class WaveformFaultReport {
  const WaveformFaultReport({
    required this.channel,
    required this.sampleCount,
    required this.durationSeconds,
    required this.overallStatus,
    required this.findings,
    required this.context,
    this.sampleRateHz,
    this.fundamentalFrequencyHz,
    this.limitations = const [],
  });

  final String channel;
  final int sampleCount;
  final double durationSeconds;
  final double? sampleRateHz;
  final double? fundamentalFrequencyHz;

  /// One of `pass`, `fail`, `warning`, `informational` or `incomplete`.
  final String overallStatus;

  final List<WaveformFaultFinding> findings;

  /// Acquisition context used by the analyzer.
  final Map<String, dynamic> context;

  /// Measurement limitations that apply to the complete run.
  final List<String> limitations;

  Map<String, dynamic> toMap() => {
    'channel': channel,
    'sampleCount': sampleCount,
    'durationSeconds': durationSeconds,
    if (sampleRateHz != null) 'sampleRateHz': sampleRateHz,
    if (fundamentalFrequencyHz != null)
      'fundamentalFrequencyHz': fundamentalFrequencyHz,
    'overallStatus': overallStatus,
    'findingCount': findings.length,
    'findings': [for (final finding in findings) finding.toMap()],
    'context': context,
    if (limitations.isNotEmpty) 'limitations': limitations,
  };
}

double? _asDouble(Object? value) {
  if (value is num) {
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }
  if (value is String) {
    final result = double.tryParse(value.trim());
    return result != null && result.isFinite ? result : null;
  }
  return null;
}
