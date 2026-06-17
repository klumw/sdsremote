import 'data_logger_models.dart';

/// Builds the CSV content for data logger measurements.
///
/// Columns are included only for measurements enabled in [config] AND not
/// hidden via [hiddenLines] (the chip toggle buttons in the UI).
///
/// This is a pure function with no Flutter or I/O dependency.
String buildDataLoggerCsv({
  required DataLoggerConfig config,
  required List<DataLoggerPoint> points,
  required Set<String> hiddenLines,
  required String deviceName,
}) {
  final csvBuffer = StringBuffer();

  // ---- Header comments ----
  csvBuffer.writeln('# SDS-Remote Data Logger Data');
  csvBuffer.writeln('# Saved: ${DateTime.now().toIso8601String()}');
  csvBuffer.writeln('# Device: $deviceName');
  csvBuffer.writeln('# Duration: ${config.durationMinutes} min');
  csvBuffer.writeln('# Interval: ${config.intervalSeconds} s');
  if (config.description.isNotEmpty) {
    csvBuffer.writeln('# Description: ${config.description}');
  }
  csvBuffer.writeln('#');

  // Determine which columns to include based on config AND chip visibility.
  final columns = <String>['Time (s)'];
  final getters = <String, double? Function(DataLoggerPoint)>{};

  void addCol(String name, double? Function(DataLoggerPoint) getter, bool enabled, String key) {
    if (enabled && !hiddenLines.contains(key)) {
      columns.add(name);
      getters[name] = getter;
    }
  }

  addCol('CH1 Vpp (V)', (p) => p.ch1Vpp, config.ch1VppEnabled, 'ch1_vpp');
  addCol('CH1 Mean (V)', (p) => p.ch1Mean, config.ch1MeanEnabled, 'ch1_mean');
  addCol('CH1 Rms (V)', (p) => p.ch1Rms, config.ch1RmsEnabled, 'ch1_rms');
  addCol('CH1 Duty (%)', (p) => p.ch1Duty, config.ch1DutyEnabled, 'ch1_duty');
  addCol('CH1 Freq (Hz)', (p) => p.ch1Freq, config.ch1FreqEnabled, 'ch1_freq');
  addCol('CH2 Vpp (V)', (p) => p.ch2Vpp, config.ch2VppEnabled, 'ch2_vpp');
  addCol('CH2 Mean (V)', (p) => p.ch2Mean, config.ch2MeanEnabled, 'ch2_mean');
  addCol('CH2 Rms (V)', (p) => p.ch2Rms, config.ch2RmsEnabled, 'ch2_rms');
  addCol('CH2 Duty (%)', (p) => p.ch2Duty, config.ch2DutyEnabled, 'ch2_duty');
  addCol('CH2 Freq (Hz)', (p) => p.ch2Freq, config.ch2FreqEnabled, 'ch2_freq');

  // CSV header row
  csvBuffer.writeln(columns.join(','));

  // Data rows
  for (final point in points) {
    final row = <String>[point.elapsedSeconds.toStringAsFixed(1)];
    for (final col in columns.skip(1)) {
      final getter = getters[col];
      if (getter == null) continue;
      final value = getter(point);
      row.add(value == null ? '' : value.toStringAsFixed(6));
    }
    csvBuffer.writeln(row.join(','));
  }

  return csvBuffer.toString();
}
