/// Data model for the Data Logger feature.
///
/// Defines configuration, measurement points, and runtime state classes
/// used by the Data Logger service, plot, and dialog widgets.

// =============================================================================
// Configuration
// =============================================================================

/// Configuration for a Data Logger session.
///
/// Stores the per-measurement selection (Vpp and/or Freq per channel),
/// sampling interval, total recording duration, and the probe attenuation
/// factors queried from the instrument.
class DataLoggerConfig {
  /// Whether CH1 peak-to-peak voltage is measured.
  final bool ch1VppEnabled;

  /// Whether CH1 frequency is measured.
  final bool ch1FreqEnabled;

  /// Whether CH2 peak-to-peak voltage is measured.
  final bool ch2VppEnabled;

  /// Whether CH2 frequency is measured.
  final bool ch2FreqEnabled;

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
  bool get ch1Enabled => ch1VppEnabled || ch1FreqEnabled;

  /// True if any measurement is enabled for CH2.
  bool get ch2Enabled => ch2VppEnabled || ch2FreqEnabled;

  const DataLoggerConfig({
    this.ch1VppEnabled = false,
    this.ch1FreqEnabled = false,
    this.ch2VppEnabled = false,
    this.ch2FreqEnabled = false,
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
    bool? ch1FreqEnabled,
    bool? ch2VppEnabled,
    bool? ch2FreqEnabled,
    int? intervalSeconds,
    int? durationMinutes,
    String? description,
    double? probeDividerCh1,
    double? probeDividerCh2,
  }) {
    return DataLoggerConfig(
      ch1VppEnabled: ch1VppEnabled ?? this.ch1VppEnabled,
      ch1FreqEnabled: ch1FreqEnabled ?? this.ch1FreqEnabled,
      ch2VppEnabled: ch2VppEnabled ?? this.ch2VppEnabled,
      ch2FreqEnabled: ch2FreqEnabled ?? this.ch2FreqEnabled,
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
          ch1FreqEnabled == other.ch1FreqEnabled &&
          ch2VppEnabled == other.ch2VppEnabled &&
          ch2FreqEnabled == other.ch2FreqEnabled &&
          intervalSeconds == other.intervalSeconds &&
          durationMinutes == other.durationMinutes &&
          description == other.description &&
          probeDividerCh1 == other.probeDividerCh1 &&
          probeDividerCh2 == other.probeDividerCh2;

  @override
  int get hashCode => Object.hash(
        ch1VppEnabled,
        ch1FreqEnabled,
        ch2VppEnabled,
        ch2FreqEnabled,
        intervalSeconds,
        durationMinutes,
        description,
        probeDividerCh1,
        probeDividerCh2,
      );

  @override
  String toString() =>
      'DataLoggerConfig('
      'ch1Vpp=$ch1VppEnabled, ch1Freq=$ch1FreqEnabled, '
      'ch2Vpp=$ch2VppEnabled, ch2Freq=$ch2FreqEnabled, '
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
/// [ch1Vpp] and [ch1Freq] are null if the respective measurement was disabled
/// in the config, or if the SCPI query failed.
/// [ch2Vpp] and [ch2Freq] are null if the respective measurement was disabled
/// in the config, or if the SCPI query failed.
/// All voltage values are already scaled by the probe divider factor.
class DataLoggerPoint {
  final DateTime timestamp;
  final double elapsedSeconds;
  final double? ch1Vpp;
  final double? ch1Freq;
  final double? ch2Vpp;
  final double? ch2Freq;

  const DataLoggerPoint({
    required this.timestamp,
    required this.elapsedSeconds,
    this.ch1Vpp,
    this.ch1Freq,
    this.ch2Vpp,
    this.ch2Freq,
  });

  @override
  String toString() =>
      'DataLoggerPoint(t=${elapsedSeconds.toStringAsFixed(1)}s, '
      'ch1Vpp=${ch1Vpp?.toStringAsFixed(4)}, '
      'ch1Freq=${ch1Freq?.toStringAsFixed(1)}, '
      'ch2Vpp=${ch2Vpp?.toStringAsFixed(4)}, '
      'ch2Freq=${ch2Freq?.toStringAsFixed(1)})';
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
