/// Data model for the Data Logger feature.
///
/// Defines configuration, measurement points, and runtime state classes
/// used by the Data Logger service, plot, and dialog widgets.

// =============================================================================
// Configuration
// =============================================================================

/// Configuration for a Data Logger session.
///
/// Stores the channel selection, sampling interval, total recording duration,
/// and probe divider factor (attenuation).
class DataLoggerConfig {
  final bool ch1Enabled;
  final bool ch2Enabled;
  final int intervalSeconds;
  final int durationMinutes;
  final double probeDivider;

  const DataLoggerConfig({
    this.ch1Enabled = true,
    this.ch2Enabled = false,
    this.intervalSeconds = 10,
    this.durationMinutes = 1,
    this.probeDivider = 1.0,
  });

  /// Total number of data points expected for this configuration.
  int get totalPoints => (durationMinutes * 60) ~/ intervalSeconds;

  DataLoggerConfig copyWith({
    bool? ch1Enabled,
    bool? ch2Enabled,
    int? intervalSeconds,
    int? durationMinutes,
    double? probeDivider,
  }) {
    return DataLoggerConfig(
      ch1Enabled: ch1Enabled ?? this.ch1Enabled,
      ch2Enabled: ch2Enabled ?? this.ch2Enabled,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      probeDivider: probeDivider ?? this.probeDivider,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataLoggerConfig &&
          ch1Enabled == other.ch1Enabled &&
          ch2Enabled == other.ch2Enabled &&
          intervalSeconds == other.intervalSeconds &&
          durationMinutes == other.durationMinutes &&
          probeDivider == other.probeDivider;

  @override
  int get hashCode => Object.hash(ch1Enabled, ch2Enabled, intervalSeconds, durationMinutes, probeDivider);

  @override
  String toString() =>
      'DataLoggerConfig(ch1=$ch1Enabled, ch2=$ch2Enabled, '
      'interval=${intervalSeconds}s, duration=${durationMinutes}min, '
      'probe=${probeDivider}x)';
}

// =============================================================================
// Measurement Point
// =============================================================================

/// A single measurement data point collected at a given timestamp.
///
/// [ch1Vpp] and [ch1Freq] are null if CH1 is not enabled.
/// [ch2Vpp] and [ch2Freq] are null if CH2 is not enabled.
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
