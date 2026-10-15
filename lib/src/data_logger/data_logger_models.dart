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
    this.gainDbEnabled = false,
    this.intervalSeconds = 10,
    this.durationMinutes = 1,
    this.description = '',
    this.probeDividerCh1 = 1.0,
    this.probeDividerCh2 = 1.0,
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
    bool? gainDbEnabled,
    int? intervalSeconds,
    int? durationMinutes,
    String? description,
    double? probeDividerCh1,
    double? probeDividerCh2,
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
      gainDbEnabled: gainDbEnabled ?? this.gainDbEnabled,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      description: description ?? this.description,
      probeDividerCh1: probeDividerCh1 ?? this.probeDividerCh1,
      probeDividerCh2: probeDividerCh2 ?? this.probeDividerCh2,
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
          gainDbEnabled == other.gainDbEnabled &&
          intervalSeconds == other.intervalSeconds &&
          durationMinutes == other.durationMinutes &&
          description == other.description &&
          probeDividerCh1 == other.probeDividerCh1 &&
          probeDividerCh2 == other.probeDividerCh2;

  @override
  int get hashCode => Object.hash(
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
    gainDbEnabled,
    intervalSeconds,
    durationMinutes,
    description,
    probeDividerCh1,
    probeDividerCh2,
  );

  @override
  String toString() =>
      'DataLoggerConfig('
      'ch1Vpp=$ch1VppEnabled, ch1Mean=$ch1MeanEnabled, ch1Rms=$ch1RmsEnabled, ch1Duty=$ch1DutyEnabled, ch1Freq=$ch1FreqEnabled, '
      'ch2Vpp=$ch2VppEnabled, ch2Mean=$ch2MeanEnabled, ch2Rms=$ch2RmsEnabled, ch2Duty=$ch2DutyEnabled, ch2Freq=$ch2FreqEnabled, '
      'gainDb=$gainDbEnabled, '
      'interval=${intervalSeconds}s, duration=${durationMinutes}min'
      '${description.isEmpty ? '' : ', description=$description'}'
      ', probeDividerCh1=${probeDividerCh1}x, probeDividerCh2=${probeDividerCh2}x'
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
/// RMS query failed, or if the reference voltage was unusable (see
/// [computeGainDb]).
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
