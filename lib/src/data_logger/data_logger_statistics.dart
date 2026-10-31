/// Per-parameter statistics for Data Logger recordings.
///
/// The module is Flutter-free and performs no I/O. It defines the stable
/// parameter registry shared by the statistics strip, the PDF report and the
/// alarm configuration, plus the statistics themselves (min/max/mean/median/
/// standard deviation, linear trend and percentage drift).
library;

import 'dart:math' as math;

import 'data_logger_models.dart';

/// Physical axis a Data Logger parameter belongs to.
///
/// Voltage parameters share one axis in the plot; frequency, duty cycle and
/// gain each have their own axis.
enum DataLoggerAxis { voltage, frequency, duty, gain }

/// Description of one measurable Data Logger parameter.
class DataLoggerParameter {
  /// Stable id, matching the legend keys and alarm-rule keys.
  final String id;

  /// Human-readable label, e.g. `CH1 Vpp`.
  final String label;

  /// Unit symbol, e.g. `V`, `Hz`, `%`, `dB`.
  final String unit;

  final DataLoggerAxis axis;

  /// Channel identifier (`ch1` … `ch4`, `gain`).
  final String channel;

  final double? Function(DataLoggerPoint) valueOf;
  final bool Function(DataLoggerConfig) isEnabled;

  const DataLoggerParameter({
    required this.id,
    required this.label,
    required this.unit,
    required this.axis,
    required this.channel,
    required this.valueOf,
    required this.isEnabled,
  });
}

/// All Data Logger parameters in display order.
final List<DataLoggerParameter> dataLoggerParameters = [
  DataLoggerParameter(
    id: 'ch1_vpp',
    label: 'CH1 Vpp',
    unit: 'V',
    axis: DataLoggerAxis.voltage,
    channel: 'ch1',
    valueOf: (point) => point.ch1Vpp,
    isEnabled: (config) => config.ch1VppEnabled,
  ),
  DataLoggerParameter(
    id: 'ch1_mean',
    label: 'CH1 Mean',
    unit: 'V',
    axis: DataLoggerAxis.voltage,
    channel: 'ch1',
    valueOf: (point) => point.ch1Mean,
    isEnabled: (config) => config.ch1MeanEnabled,
  ),
  DataLoggerParameter(
    id: 'ch1_rms',
    label: 'CH1 Rms',
    unit: 'V',
    axis: DataLoggerAxis.voltage,
    channel: 'ch1',
    valueOf: (point) => point.ch1Rms,
    isEnabled: (config) => config.ch1RmsEnabled,
  ),
  DataLoggerParameter(
    id: 'ch1_duty',
    label: 'CH1 Duty',
    unit: '%',
    axis: DataLoggerAxis.duty,
    channel: 'ch1',
    valueOf: (point) => point.ch1Duty,
    isEnabled: (config) => config.ch1DutyEnabled,
  ),
  DataLoggerParameter(
    id: 'ch1_freq',
    label: 'CH1 Freq',
    unit: 'Hz',
    axis: DataLoggerAxis.frequency,
    channel: 'ch1',
    valueOf: (point) => point.ch1Freq,
    isEnabled: (config) => config.ch1FreqEnabled,
  ),
  DataLoggerParameter(
    id: 'ch2_vpp',
    label: 'CH2 Vpp',
    unit: 'V',
    axis: DataLoggerAxis.voltage,
    channel: 'ch2',
    valueOf: (point) => point.ch2Vpp,
    isEnabled: (config) => config.ch2VppEnabled,
  ),
  DataLoggerParameter(
    id: 'ch2_mean',
    label: 'CH2 Mean',
    unit: 'V',
    axis: DataLoggerAxis.voltage,
    channel: 'ch2',
    valueOf: (point) => point.ch2Mean,
    isEnabled: (config) => config.ch2MeanEnabled,
  ),
  DataLoggerParameter(
    id: 'ch2_rms',
    label: 'CH2 Rms',
    unit: 'V',
    axis: DataLoggerAxis.voltage,
    channel: 'ch2',
    valueOf: (point) => point.ch2Rms,
    isEnabled: (config) => config.ch2RmsEnabled,
  ),
  DataLoggerParameter(
    id: 'ch2_duty',
    label: 'CH2 Duty',
    unit: '%',
    axis: DataLoggerAxis.duty,
    channel: 'ch2',
    valueOf: (point) => point.ch2Duty,
    isEnabled: (config) => config.ch2DutyEnabled,
  ),
  DataLoggerParameter(
    id: 'ch2_freq',
    label: 'CH2 Freq',
    unit: 'Hz',
    axis: DataLoggerAxis.frequency,
    channel: 'ch2',
    valueOf: (point) => point.ch2Freq,
    isEnabled: (config) => config.ch2FreqEnabled,
  ),
  DataLoggerParameter(
    id: 'ch3_vpp',
    label: 'CH3 Vpp',
    unit: 'V',
    axis: DataLoggerAxis.voltage,
    channel: 'ch3',
    valueOf: (point) => point.ch3Vpp,
    isEnabled: (config) => config.ch3VppEnabled,
  ),
  DataLoggerParameter(
    id: 'ch3_mean',
    label: 'CH3 Mean',
    unit: 'V',
    axis: DataLoggerAxis.voltage,
    channel: 'ch3',
    valueOf: (point) => point.ch3Mean,
    isEnabled: (config) => config.ch3MeanEnabled,
  ),
  DataLoggerParameter(
    id: 'ch3_rms',
    label: 'CH3 Rms',
    unit: 'V',
    axis: DataLoggerAxis.voltage,
    channel: 'ch3',
    valueOf: (point) => point.ch3Rms,
    isEnabled: (config) => config.ch3RmsEnabled,
  ),
  DataLoggerParameter(
    id: 'ch3_duty',
    label: 'CH3 Duty',
    unit: '%',
    axis: DataLoggerAxis.duty,
    channel: 'ch3',
    valueOf: (point) => point.ch3Duty,
    isEnabled: (config) => config.ch3DutyEnabled,
  ),
  DataLoggerParameter(
    id: 'ch3_freq',
    label: 'CH3 Freq',
    unit: 'Hz',
    axis: DataLoggerAxis.frequency,
    channel: 'ch3',
    valueOf: (point) => point.ch3Freq,
    isEnabled: (config) => config.ch3FreqEnabled,
  ),
  DataLoggerParameter(
    id: 'ch4_vpp',
    label: 'CH4 Vpp',
    unit: 'V',
    axis: DataLoggerAxis.voltage,
    channel: 'ch4',
    valueOf: (point) => point.ch4Vpp,
    isEnabled: (config) => config.ch4VppEnabled,
  ),
  DataLoggerParameter(
    id: 'ch4_mean',
    label: 'CH4 Mean',
    unit: 'V',
    axis: DataLoggerAxis.voltage,
    channel: 'ch4',
    valueOf: (point) => point.ch4Mean,
    isEnabled: (config) => config.ch4MeanEnabled,
  ),
  DataLoggerParameter(
    id: 'ch4_rms',
    label: 'CH4 Rms',
    unit: 'V',
    axis: DataLoggerAxis.voltage,
    channel: 'ch4',
    valueOf: (point) => point.ch4Rms,
    isEnabled: (config) => config.ch4RmsEnabled,
  ),
  DataLoggerParameter(
    id: 'ch4_duty',
    label: 'CH4 Duty',
    unit: '%',
    axis: DataLoggerAxis.duty,
    channel: 'ch4',
    valueOf: (point) => point.ch4Duty,
    isEnabled: (config) => config.ch4DutyEnabled,
  ),
  DataLoggerParameter(
    id: 'ch4_freq',
    label: 'CH4 Freq',
    unit: 'Hz',
    axis: DataLoggerAxis.frequency,
    channel: 'ch4',
    valueOf: (point) => point.ch4Freq,
    isEnabled: (config) => config.ch4FreqEnabled,
  ),
  DataLoggerParameter(
    id: 'gain_db',
    label: 'Gain',
    unit: 'dB',
    axis: DataLoggerAxis.gain,
    channel: 'gain',
    valueOf: (point) => point.gainDb,
    isEnabled: (config) => config.gainDbEnabled,
  ),
];

/// Looks up a parameter by [id], or returns `null` for an unknown id.
DataLoggerParameter? dataLoggerParameterById(String id) {
  for (final parameter in dataLoggerParameters) {
    if (parameter.id == id) return parameter;
  }
  return null;
}

/// Display label for a parameter id (falls back to the id itself).
String dataLoggerParameterLabel(String id) =>
    dataLoggerParameterById(id)?.label ?? id;

/// Statistics of one parameter over all valid samples of a recording.
class ParameterStatistics {
  final String parameterId;
  final String unit;

  /// Number of valid samples that contributed to the statistics.
  final int count;

  final double? min;
  final double? max;
  final double? mean;
  final double? median;

  /// Sample standard deviation (`n − 1`); `null` for fewer than two samples.
  final double? standardDeviation;

  /// Slope of a least-squares line through `(elapsed minutes, value)`.
  final double? trendPerMinute;

  /// Change from the first to the last valid value, relative to the absolute
  /// first value, in percent. `null` when the first value is zero.
  final double? driftPercent;

  final double? firstValue;
  final double? lastValue;

  const ParameterStatistics({
    required this.parameterId,
    required this.unit,
    required this.count,
    this.min,
    this.max,
    this.mean,
    this.median,
    this.standardDeviation,
    this.trendPerMinute,
    this.driftPercent,
    this.firstValue,
    this.lastValue,
  });
}

/// Computes the statistics of every enabled parameter with valid samples.
Map<String, ParameterStatistics> computeDataLoggerStatistics({
  required DataLoggerConfig config,
  required List<DataLoggerPoint> points,
}) {
  final result = <String, ParameterStatistics>{};

  for (final parameter in dataLoggerParameters) {
    if (!parameter.isEnabled(config)) continue;

    final samples = <(double, double)>[];
    for (final point in points) {
      final value = parameter.valueOf(point);
      if (value == null || !value.isFinite) continue;
      samples.add((point.elapsedSeconds, value));
    }
    if (samples.isEmpty) continue;

    samples.sort((a, b) => a.$1.compareTo(b.$1));
    result[parameter.id] = _computeStatistics(parameter, samples);
  }

  return result;
}

ParameterStatistics _computeStatistics(
  DataLoggerParameter parameter,
  List<(double, double)> samples,
) {
  final count = samples.length;
  final values = [for (final sample in samples) sample.$2];

  var min = values.first;
  var max = values.first;
  var sum = 0.0;
  for (final value in values) {
    if (value < min) min = value;
    if (value > max) max = value;
    sum += value;
  }
  final mean = sum / count;

  final sorted = [...values]..sort();
  final middle = count ~/ 2;
  final median = count.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;

  double? standardDeviation;
  if (count > 1) {
    var sumSquares = 0.0;
    for (final value in values) {
      final deviation = value - mean;
      sumSquares += deviation * deviation;
    }
    standardDeviation = math.sqrt(sumSquares / (count - 1));
  }

  // Least-squares slope against elapsed time in minutes.
  double? trendPerMinute;
  if (count > 1) {
    final times = [for (final sample in samples) sample.$1 / 60.0];
    final timeMean = times.reduce((a, b) => a + b) / count;
    var numerator = 0.0;
    var denominator = 0.0;
    for (var i = 0; i < count; i++) {
      final dx = times[i] - timeMean;
      numerator += dx * (values[i] - mean);
      denominator += dx * dx;
    }
    if (denominator > 0) {
      trendPerMinute = numerator / denominator;
    }
  }

  final firstValue = samples.first.$2;
  final lastValue = samples.last.$2;
  final driftPercent = firstValue == 0
      ? null
      : (lastValue - firstValue) / firstValue.abs() * 100;

  return ParameterStatistics(
    parameterId: parameter.id,
    unit: parameter.unit,
    count: count,
    min: min,
    max: max,
    mean: mean,
    median: median,
    standardDeviation: standardDeviation,
    trendPerMinute: trendPerMinute,
    driftPercent: driftPercent,
    firstValue: firstValue,
    lastValue: lastValue,
  );
}
