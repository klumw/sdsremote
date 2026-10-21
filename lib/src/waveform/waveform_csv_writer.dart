import 'waveform_models.dart';

/// Builds the CSV content for saved waveform data.
///
/// This is a pure function with no Flutter or I/O dependency — it only
/// produces the string that will later be written to disk.
String buildWaveformCsv({
  required WaveformData? ch1,
  required WaveformData? ch2,
  WaveformData? ch3,
  WaveformData? ch4,
  required DeviceParams params,
  required String deviceName,
  required CursorState cursorState,
  int channelCount = 2,
}) {
  final bool fourChannels = channelCount >= 4;
  final csvBuffer = StringBuffer();
  csvBuffer.writeln('# SDS-Remote Waveform Data');
  csvBuffer.writeln('# Saved: ${DateTime.now().toIso8601String()}');
  csvBuffer.writeln('# Device: $deviceName');
  csvBuffer.writeln('# Timebase: ${params.timebase} s/div');
  csvBuffer.writeln('# Trigger Delay: ${params.trdl} s');
  csvBuffer.writeln('# Sample Rate: ${params.sampleRate} Sa/s');
  if (params.vdivCh1 != null) {
    csvBuffer.writeln('# CH1 V/div: ${params.vdivCh1} V');
    csvBuffer.writeln('# CH1 Offset: ${params.voffsetCh1} V');
  }
  if (params.vdivCh2 != null) {
    csvBuffer.writeln('# CH2 V/div: ${params.vdivCh2} V');
    csvBuffer.writeln('# CH2 Offset: ${params.voffsetCh2} V');
  }
  if (params.vdivCh3 != null) {
    csvBuffer.writeln('# CH3 V/div: ${params.vdivCh3} V');
    csvBuffer.writeln('# CH3 Offset: ${params.voffsetCh3} V');
  }
  if (params.vdivCh4 != null) {
    csvBuffer.writeln('# CH4 V/div: ${params.vdivCh4} V');
    csvBuffer.writeln('# CH4 Offset: ${params.voffsetCh4} V');
  }
  csvBuffer.writeln('# Cursors X Enabled: ${cursorState.cursorsXEnabled}');
  csvBuffer.writeln('# Cursors Y Enabled: ${cursorState.cursorsYEnabled}');
  csvBuffer.writeln('#');
  csvBuffer.writeln(
    fourChannels
        ? 'Time (s),CH1 (V),CH2 (V),CH3 (V),CH4 (V)'
        : 'Time (s),CH1 (V),CH2 (V)',
  );

  // Determine the maximum number of points across all acquired channels.
  final int maxPoints = [
    if (ch1 != null) ch1.points.length,
    if (ch2 != null) ch2.points.length,
    if (ch3 != null) ch3.points.length,
    if (ch4 != null) ch4.points.length,
  ].fold(0, (a, b) => a > b ? a : b);

  String voltageAt(WaveformData? data, int index) =>
      data != null && index < data.points.length
      ? data.points[index].$2.toStringAsFixed(6)
      : '';

  // CSV time starts at 0 and increments by 1/sampleRate for each sample.
  final csvDt = 1.0 / params.sampleRate;
  for (int i = 0; i < maxPoints; i++) {
    final time = i * csvDt;
    final row = StringBuffer('$time,${voltageAt(ch1, i)},${voltageAt(ch2, i)}');
    if (fourChannels) {
      row.write(',${voltageAt(ch3, i)},${voltageAt(ch4, i)}');
    }
    csvBuffer.writeln(row);
  }

  return csvBuffer.toString();
}
