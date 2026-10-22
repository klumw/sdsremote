/// Data model for the Data Logger feature.
///
/// Defines configuration, measurement points, and runtime state classes
/// used by the Data Logger service, plot, and dialog widgets.
library;

import 'dart:math' as math;

// =============================================================================
// Gain Calculation
// =============================================================================

/// Voltage gain in decibels between two voltage measurements.
///
/// Computes `20 * log10(signalVoltage / referenceVoltage)`, where
/// [signalVoltage] is the voltage on the signal channel (C1) and
/// [referenceVoltage] is the voltage on the reference channel (C2).
/// A positive result means the signal channel carries the larger voltage.
///
/// Both voltages must be the same measurement type and already scaled by
/// their respective probe attenuation factors, so that the ratio reflects
/// the actual voltages at the probe tips.
///
/// Returns null when either voltage is unavailable, or when either value is
/// zero or negative: the ratio is then undefined (`log10(0)` is negative
/// infinity) or meaningless, since an RMS voltage is never negative.
double? computeGainDb(double? signalVoltage, double? referenceVoltage) {
  if (signalVoltage == null || referenceVoltage == null) return null;
  if (signalVoltage <= 0 || referenceVoltage <= 0) return null;
  return 20.0 * (math.log(signalVoltage / referenceVoltage) / math.ln10);
}

/// Smallest RMS voltage, at the probe tip, that a Data Logger gain measurement
/// is computed from.
///
/// Below it the ratio between the two channels is dominated by the
/// instrument's noise floor and its 8 bit quantisation instead of the device
/// under test: the result would swing over tens of decibels from sample to
/// sample.
const double gainMinRmsVolts = 0.01;

/// Gain in dB for a Data Logger sample, or null when it cannot be measured.
///
/// Applies the measurement's noise floor on top of [computeGainDb]: as soon as
/// one of the two RMS voltages is below [gainMinRmsVolts], the sample carries
/// no gain value at all. Unlike [computeGainDb] - which is shared with the
/// `gain_db` calculation of the AI tools and therefore stays the plain ratio -
/// this is the Data Logger's own validity rule for what it records.
double? computeMeasuredGainDb(double? signalVoltage, double? referenceVoltage) {
  if (signalVoltage == null || referenceVoltage == null) return null;
  if (signalVoltage < gainMinRmsVolts || referenceVoltage < gainMinRmsVolts) {
    return null;
  }
  return computeGainDb(signalVoltage, referenceVoltage);
}

/// Formats a logged gain for display in the cursor popup: the value with its
/// unit, or `invalid` when the sample carries no gain.
String formatGainValue(double? gainDb) =>
    gainDb == null ? 'invalid' : '${gainDb.toStringAsFixed(2)} dB';

/// Extracts the measured number from a SCPI response.
///
/// The value follows the command echo after the last comma
/// (`C1:PAVA RMS,3.6E+00V`) or the last space (`C1:ATTN 10`); some firmware
/// answers with the bare value. A partial response that contains only the
/// command echo (`C1:PAVA RMS`) or an out-of-range marker (`C1:PAVA RMS,***`)
/// must not be parsed as the channel number, so it returns null.
double? parseScpiNumber(String rawResponse) {
  final trimmed = rawResponse.trim();
  if (trimmed.isEmpty) return null;

  double? lastNumber(String text) {
    final matches = RegExp(
      r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?',
    ).allMatches(text).toList();
    return matches.isEmpty ? null : double.tryParse(matches.last.group(0)!);
  }

  final comma = trimmed.lastIndexOf(',');
  if (comma >= 0) {
    final value = lastNumber(trimmed.substring(comma + 1));
    if (value != null) return value;
  }
  final space = trimmed.lastIndexOf(' ');
  if (space >= 0) {
    final value = lastNumber(trimmed.substring(space + 1));
    if (value != null) return value;
  }
  // Bare value responses only; require the number at the start so the
  // channel digit of a command echo cannot be mistaken for a measurement.
  final match = RegExp(r'^[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?').firstMatch(trimmed);
  return match == null ? null : double.tryParse(match.group(0)!);
}

// =============================================================================
// Configuration
// =============================================================================

/// Configuration for a Data Logger session.
///
/// Stores the per-measurement selection (Vpp, Mean, Rms, Duty, and/or Freq
/// per channel), whether the cross-channel voltage gain in dB is measured,
/// sampling interval, total recording duration, and the probe attenuation
/// factors queried from the instrument.
class DataLoggerConfig {
  /// Whether CH1 peak-to-peak voltage is measured.
  final bool ch1VppEnabled;

  /// Whether CH1 mean voltage is measured.
  final bool ch1MeanEnabled;

  /// Whether CH1 RMS voltage is measured.
  final bool ch1RmsEnabled;

  /// Whether CH1 duty cycle is measured.
  final bool ch1DutyEnabled;

  /// Whether CH1 frequency is measured.
  final bool ch1FreqEnabled;

  /// Whether CH2 peak-to-peak voltage is measured.
  final bool ch2VppEnabled;

  /// Whether CH2 mean voltage is measured.
  final bool ch2MeanEnabled;

  /// Whether CH2 RMS voltage is measured.
  final bool ch2RmsEnabled;

  /// Whether CH2 duty cycle is measured.
  final bool ch2DutyEnabled;

  /// Whether CH2 frequency is measured.
  final bool ch2FreqEnabled;

  /// Whether CH3 peak-to-peak voltage is measured.
  final bool ch3VppEnabled;

  /// Whether CH3 mean voltage is measured.
  final bool ch3MeanEnabled;

  /// Whether CH3 RMS voltage is measured.
  final bool ch3RmsEnabled;

  /// Whether CH3 duty cycle is measured.
  final bool ch3DutyEnabled;

  /// Whether CH3 frequency is measured.
  final bool ch3FreqEnabled;

  /// Whether CH4 peak-to-peak voltage is measured.
  final bool ch4VppEnabled;

  /// Whether CH4 mean voltage is measured.
  final bool ch4MeanEnabled;

  /// Whether CH4 RMS voltage is measured.
  final bool ch4RmsEnabled;

  /// Whether CH4 duty cycle is measured.
  final bool ch4DutyEnabled;

  /// Whether CH4 frequency is measured.
  final bool ch4FreqEnabled;

  /// Whether the voltage gain between CH1 (signal) and CH2 (reference) is
  /// measured in decibels. Unlike the per-channel measurements above, this is
  /// a derived cross-channel measurement: it queries the RMS voltage on both
  /// channels and records `20 * log10(C1 / C2)`.
  final bool gainDbEnabled;

  final int intervalSeconds;
  final int durationMinutes;

  /// Optional free-text description (max 150 characters).
  /// Shown on top of the logger chart and included in the PDF report.
  final String description;

  /// Probe attenuation factor for CH1, queried via C1:ATTN?.
  /// Defaults to 1.0 if not yet queried.
  final double probeDividerCh1;

  /// Probe attenuation factor for CH2, queried via C2:ATTN?.
  /// Defaults to 1.0 if not yet queried.
  final double probeDividerCh2;

  /// Probe attenuation factor for CH3, queried via C3:ATTN?.
  /// Defaults to 1.0 if not yet queried.
  final double probeDividerCh3;

  /// Probe attenuation factor for CH4, queried via C4:ATTN?.
  /// Defaults to 1.0 if not yet queried.
  final double probeDividerCh4;

  /// True if any measurement is enabled for CH1.
  ///
  /// Gain (dB) is included because it queries the RMS voltage on both
  /// channels, so CH1 must be considered active whenever gain is selected
  /// (this also ensures the CH1 probe attenuation is queried).
  bool get ch1Enabled =>
      ch1VppEnabled ||
      ch1MeanEnabled ||
      ch1RmsEnabled ||
      ch1DutyEnabled ||
      ch1FreqEnabled ||
      gainDbEnabled;

  /// True if any measurement is enabled for CH2.
  ///
  /// Gain (dB) is included because it queries the RMS voltage on both
  /// channels, so CH2 must be considered active whenever gain is selected
  /// (this also ensures the CH2 probe attenuation is queried).
  bool get ch2Enabled =>
      ch2VppEnabled ||
      ch2MeanEnabled ||
      ch2RmsEnabled ||
      ch2DutyEnabled ||
      ch2FreqEnabled ||
      gainDbEnabled;

  /// True if any measurement is enabled for CH3.
  bool get ch3Enabled =>
      ch3VppEnabled ||
      ch3MeanEnabled ||
      ch3RmsEnabled ||
      ch3DutyEnabled ||
      ch3FreqEnabled;

  /// True if any measurement is enabled for CH4.
  bool get ch4Enabled =>
      ch4VppEnabled ||
      ch4MeanEnabled ||
      ch4RmsEnabled ||
      ch4DutyEnabled ||
      ch4FreqEnabled;

  const DataLoggerConfig({
    this.ch1VppEnabled = false,
    this.ch1MeanEnabled = false,
    this.ch1RmsEnabled = false,
    this.ch1DutyEnabled = false,
    this.ch1FreqEnabled = false,
    this.ch2VppEnabled = false,
    this.ch2MeanEnabled = false,
    this.ch2RmsEnabled = false,
    this.ch2DutyEnabled = false,
    this.ch2FreqEnabled = false,
    this.ch3VppEnabled = false,
    this.ch3MeanEnabled = false,
    this.ch3RmsEnabled = false,
    this.ch3DutyEnabled = false,
    this.ch3FreqEnabled = false,
    this.ch4VppEnabled = false,
    this.ch4MeanEnabled = false,
    this.ch4RmsEnabled = false,
    this.ch4DutyEnabled = false,
    this.ch4FreqEnabled = false,
    this.gainDbEnabled = false,
    this.intervalSeconds = 10,
    this.durationMinutes = 1,
    this.description = '',
    this.probeDividerCh1 = 1.0,
    this.probeDividerCh2 = 1.0,
    this.probeDividerCh3 = 1.0,
    this.probeDividerCh4 = 1.0,
  });

  /// Total number of data points expected for this configuration.
  /// Includes both t=0 and t=duration endpoints (e.g., 60s/10s = 7 points:
  /// 0, 10, 20, 30, 40, 50, 60).
  int get totalPoints => (durationMinutes * 60) ~/ intervalSeconds + 1;

  DataLoggerConfig copyWith({
    bool? ch1VppEnabled,
    bool? ch1MeanEnabled,
    bool? ch1RmsEnabled,
    bool? ch1DutyEnabled,
    bool? ch1FreqEnabled,
    bool? ch2VppEnabled,
    bool? ch2MeanEnabled,
    bool? ch2RmsEnabled,
    bool? ch2DutyEnabled,
    bool? ch2FreqEnabled,
    bool? ch3VppEnabled,
    bool? ch3MeanEnabled,
    bool? ch3RmsEnabled,
    bool? ch3DutyEnabled,
    bool? ch3FreqEnabled,
    bool? ch4VppEnabled,
    bool? ch4MeanEnabled,
    bool? ch4RmsEnabled,
    bool? ch4DutyEnabled,
    bool? ch4FreqEnabled,
    bool? gainDbEnabled,
    int? intervalSeconds,
    int? durationMinutes,
    String? description,
    double? probeDividerCh1,
    double? probeDividerCh2,
    double? probeDividerCh3,
    double? probeDividerCh4,
  }) {
    return DataLoggerConfig(
      ch1VppEnabled: ch1VppEnabled ?? this.ch1VppEnabled,
      ch1MeanEnabled: ch1MeanEnabled ?? this.ch1MeanEnabled,
      ch1RmsEnabled: ch1RmsEnabled ?? this.ch1RmsEnabled,
      ch1DutyEnabled: ch1DutyEnabled ?? this.ch1DutyEnabled,
      ch1FreqEnabled: ch1FreqEnabled ?? this.ch1FreqEnabled,
      ch2VppEnabled: ch2VppEnabled ?? this.ch2VppEnabled,
      ch2MeanEnabled: ch2MeanEnabled ?? this.ch2MeanEnabled,
      ch2RmsEnabled: ch2RmsEnabled ?? this.ch2RmsEnabled,
      ch2DutyEnabled: ch2DutyEnabled ?? this.ch2DutyEnabled,
      ch2FreqEnabled: ch2FreqEnabled ?? this.ch2FreqEnabled,
      ch3VppEnabled: ch3VppEnabled ?? this.ch3VppEnabled,
      ch3MeanEnabled: ch3MeanEnabled ?? this.ch3MeanEnabled,
      ch3RmsEnabled: ch3RmsEnabled ?? this.ch3RmsEnabled,
      ch3DutyEnabled: ch3DutyEnabled ?? this.ch3DutyEnabled,
      ch3FreqEnabled: ch3FreqEnabled ?? this.ch3FreqEnabled,
      ch4VppEnabled: ch4VppEnabled ?? this.ch4VppEnabled,
      ch4MeanEnabled: ch4MeanEnabled ?? this.ch4MeanEnabled,
      ch4RmsEnabled: ch4RmsEnabled ?? this.ch4RmsEnabled,
      ch4DutyEnabled: ch4DutyEnabled ?? this.ch4DutyEnabled,
      ch4FreqEnabled: ch4FreqEnabled ?? this.ch4FreqEnabled,
      gainDbEnabled: gainDbEnabled ?? this.gainDbEnabled,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      description: description ?? this.description,
      probeDividerCh1: probeDividerCh1 ?? this.probeDividerCh1,
      probeDividerCh2: probeDividerCh2 ?? this.probeDividerCh2,
      probeDividerCh3: probeDividerCh3 ?? this.probeDividerCh3,
      probeDividerCh4: probeDividerCh4 ?? this.probeDividerCh4,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataLoggerConfig &&
          ch1VppEnabled == other.ch1VppEnabled &&
          ch1MeanEnabled == other.ch1MeanEnabled &&
          ch1RmsEnabled == other.ch1RmsEnabled &&
          ch1DutyEnabled == other.ch1DutyEnabled &&
          ch1FreqEnabled == other.ch1FreqEnabled &&
          ch2VppEnabled == other.ch2VppEnabled &&
          ch2MeanEnabled == other.ch2MeanEnabled &&
          ch2RmsEnabled == other.ch2RmsEnabled &&
          ch2DutyEnabled == other.ch2DutyEnabled &&
          ch2FreqEnabled == other.ch2FreqEnabled &&
          ch3VppEnabled == other.ch3VppEnabled &&
          ch3MeanEnabled == other.ch3MeanEnabled &&
          ch3RmsEnabled == other.ch3RmsEnabled &&
          ch3DutyEnabled == other.ch3DutyEnabled &&
          ch3FreqEnabled == other.ch3FreqEnabled &&
          ch4VppEnabled == other.ch4VppEnabled &&
          ch4MeanEnabled == other.ch4MeanEnabled &&
          ch4RmsEnabled == other.ch4RmsEnabled &&
          ch4DutyEnabled == other.ch4DutyEnabled &&
          ch4FreqEnabled == other.ch4FreqEnabled &&
          gainDbEnabled == other.gainDbEnabled &&
          intervalSeconds == other.intervalSeconds &&
          durationMinutes == other.durationMinutes &&
          description == other.description &&
          probeDividerCh1 == other.probeDividerCh1 &&
          probeDividerCh2 == other.probeDividerCh2 &&
          probeDividerCh3 == other.probeDividerCh3 &&
          probeDividerCh4 == other.probeDividerCh4;

  @override
  int get hashCode => Object.hashAll([
    ch1VppEnabled,
    ch1MeanEnabled,
    ch1RmsEnabled,
    ch1DutyEnabled,
    ch1FreqEnabled,
    ch2VppEnabled,
    ch2MeanEnabled,
    ch2RmsEnabled,
    ch2DutyEnabled,
    ch2FreqEnabled,
    ch3VppEnabled,
    ch3MeanEnabled,
    ch3RmsEnabled,
    ch3DutyEnabled,
    ch3FreqEnabled,
    ch4VppEnabled,
    ch4MeanEnabled,
    ch4RmsEnabled,
    ch4DutyEnabled,
    ch4FreqEnabled,
    gainDbEnabled,
    intervalSeconds,
    durationMinutes,
    description,
    probeDividerCh1,
    probeDividerCh2,
    probeDividerCh3,
    probeDividerCh4,
  ]);

  @override
  String toString() =>
      'DataLoggerConfig('
      'ch1Vpp=$ch1VppEnabled, ch1Mean=$ch1MeanEnabled, ch1Rms=$ch1RmsEnabled, ch1Duty=$ch1DutyEnabled, ch1Freq=$ch1FreqEnabled, '
      'ch2Vpp=$ch2VppEnabled, ch2Mean=$ch2MeanEnabled, ch2Rms=$ch2RmsEnabled, ch2Duty=$ch2DutyEnabled, ch2Freq=$ch2FreqEnabled, '
      'ch3Vpp=$ch3VppEnabled, ch3Mean=$ch3MeanEnabled, ch3Rms=$ch3RmsEnabled, ch3Duty=$ch3DutyEnabled, ch3Freq=$ch3FreqEnabled, '
      'ch4Vpp=$ch4VppEnabled, ch4Mean=$ch4MeanEnabled, ch4Rms=$ch4RmsEnabled, ch4Duty=$ch4DutyEnabled, ch4Freq=$ch4FreqEnabled, '
      'gainDb=$gainDbEnabled, '
      'interval=${intervalSeconds}s, duration=${durationMinutes}min'
      '${description.isEmpty ? '' : ', description=$description'}'
      ', probeDividerCh1=${probeDividerCh1}x, probeDividerCh2=${probeDividerCh2}x'
      ', probeDividerCh3=${probeDividerCh3}x, probeDividerCh4=${probeDividerCh4}x'
      ')';
}

// =============================================================================
// Measurement Point
// =============================================================================

/// A single measurement data point collected at a given timestamp.
///
/// [ch1Vpp], [ch1Mean], [ch1Rms], and [ch1Freq] are null if the respective
/// measurement was disabled in the config, or if the SCPI query failed.
/// [ch2Vpp], [ch2Mean], [ch2Rms], and [ch2Freq] are null if the respective
/// measurement was disabled in the config, or if the SCPI query failed.
/// [gainDb] is null if gain measurement was disabled, if either channel's
/// RMS query failed, or if one of the two RMS voltages is below
/// [gainMinRmsVolts] (see [computeMeasuredGainDb]).
/// All voltage values are already scaled by the probe divider factor.
class DataLoggerPoint {
  final DateTime timestamp;
  final double elapsedSeconds;
  final double? ch1Vpp;
  final double? ch1Mean;
  final double? ch1Rms;
  final double? ch1Duty;
  final double? ch1Freq;
  final double? ch2Vpp;
  final double? ch2Mean;
  final double? ch2Rms;
  final double? ch2Duty;
  final double? ch2Freq;
  final double? ch3Vpp;
  final double? ch3Mean;
  final double? ch3Rms;
  final double? ch3Duty;
  final double? ch3Freq;
  final double? ch4Vpp;
  final double? ch4Mean;
  final double? ch4Rms;
  final double? ch4Duty;
  final double? ch4Freq;
  final double? gainDb;

  const DataLoggerPoint({
    required this.timestamp,
    required this.elapsedSeconds,
    this.ch1Vpp,
    this.ch1Mean,
    this.ch1Rms,
    this.ch1Duty,
    this.ch1Freq,
    this.ch2Vpp,
    this.ch2Mean,
    this.ch2Rms,
    this.ch2Duty,
    this.ch2Freq,
    this.ch3Vpp,
    this.ch3Mean,
    this.ch3Rms,
    this.ch3Duty,
    this.ch3Freq,
    this.ch4Vpp,
    this.ch4Mean,
    this.ch4Rms,
    this.ch4Duty,
    this.ch4Freq,
    this.gainDb,
  });

  @override
  String toString() =>
      'DataLoggerPoint(t=${elapsedSeconds.toStringAsFixed(1)}s, '
      'ch1Vpp=${ch1Vpp?.toStringAsFixed(4)}, '
      'ch1Mean=${ch1Mean?.toStringAsFixed(4)}, '
      'ch1Rms=${ch1Rms?.toStringAsFixed(4)}, '
      'ch1Duty=${ch1Duty?.toStringAsFixed(1)}, '
      'ch1Freq=${ch1Freq?.toStringAsFixed(1)}, '
      'ch2Vpp=${ch2Vpp?.toStringAsFixed(4)}, '
      'ch2Mean=${ch2Mean?.toStringAsFixed(4)}, '
      'ch2Rms=${ch2Rms?.toStringAsFixed(4)}, '
      'ch2Duty=${ch2Duty?.toStringAsFixed(1)}, '
      'ch2Freq=${ch2Freq?.toStringAsFixed(1)}, '
      'ch3Vpp=${ch3Vpp?.toStringAsFixed(4)}, '
      'ch3Mean=${ch3Mean?.toStringAsFixed(4)}, '
      'ch3Rms=${ch3Rms?.toStringAsFixed(4)}, '
      'ch3Duty=${ch3Duty?.toStringAsFixed(1)}, '
      'ch3Freq=${ch3Freq?.toStringAsFixed(1)}, '
      'ch4Vpp=${ch4Vpp?.toStringAsFixed(4)}, '
      'ch4Mean=${ch4Mean?.toStringAsFixed(4)}, '
      'ch4Rms=${ch4Rms?.toStringAsFixed(4)}, '
      'ch4Duty=${ch4Duty?.toStringAsFixed(1)}, '
      'ch4Freq=${ch4Freq?.toStringAsFixed(1)}, '
      'gainDb=${gainDb?.toStringAsFixed(2)})';
}

// =============================================================================
// Runtime State
// =============================================================================

/// Runtime status of the data logger.
enum DataLoggerStatus {
  /// No recording active; panel may be closed or initial state.
  idle,

  /// Configuration dialog is being shown.
  configuring,

  /// Logger is actively sampling and recording data.
  running,

  /// Logger has finished (either stopped manually or duration elapsed).
  stopped,
}

/// Full runtime state of the Data Logger.
///
/// Combines the current [status], the active [config], and
/// the list of collected [points].
class DataLoggerState {
  final DataLoggerStatus status;
  final DataLoggerConfig? config;
  final List<DataLoggerPoint> points;

  const DataLoggerState({
    this.status = DataLoggerStatus.idle,
    this.config,
    this.points = const [],
  });

  DataLoggerState copyWith({
    DataLoggerStatus? status,
    DataLoggerConfig? config,
    List<DataLoggerPoint>? points,
    bool clearConfig = false,
    bool clearPoints = false,
  }) {
    return DataLoggerState(
      status: status ?? this.status,
      config: clearConfig ? null : (config ?? this.config),
      points: clearPoints ? [] : (points ?? this.points),
    );
  }
}
