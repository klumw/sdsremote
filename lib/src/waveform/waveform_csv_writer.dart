import '../waveform_models.dart';

/// Builds the CSV content for saved waveform data.
///
/// This is a pure function with no Flutter or I/O dependency — it only
/// produces the string that will later be written to disk.
String buildWaveformCsv({
  required WaveformData? ch1,
  required WaveformData? ch2,
  required DeviceParams params,
  required String deviceName,
  required CursorState cursorState,
}) {
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
  csvBuffer.writeln('# Cursors X Enabled: ${cursorState.cursorsXEnabled}');
  csvBuffer.writeln('# Cursors Y Enabled: ${cursorState.cursorsYEnabled}');
  csvBuffer.writeln('#');
  csvBuffer.writeln('Time (s),CH1 (V),CH2 (V)');

  // Determine the maximum number of points across both channels.
  final int maxPoints = [
    if (ch1 != null) ch1.points.length,
    if (ch2 != null) ch2.points.length,
  ].fold(0, (a, b) => a > b ? a : b);

  // CSV time starts at 0 and increments by 1/sampleRate for each sample.
  final csvDt = 1.0 / params.sampleRate;
  for (int i = 0; i < maxPoints; i++) {
    final time = i * csvDt;
    final ch1V = ch1 != null && i < ch1.points.length
        ? ch1.points[i].$2.toStringAsFixed(6)
        : '';
    final ch2V = ch2 != null && i < ch2.points.length
        ? ch2.points[i].$2.toStringAsFixed(6)
        : '';
    csvBuffer.writeln('$time,$ch1V,$ch2V');
  }

  return csvBuffer.toString();
}
