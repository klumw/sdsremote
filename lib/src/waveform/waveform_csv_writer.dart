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
  csvBuffer.writeln('# Format Version: 2');
  csvBuffer.writeln('# Time axis: sample time');
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

  // The points already carry their real timestamps and the display path
  // decimates them 2:1, so deriving the time step from `1 / sampleRate`
  // would halve the exported time axis. Use the actual timestamps of the
  // first acquired channel and normalise its first point to 0; the reference
  // loader aligns relative to the live waveform anyway.
  final timeSource = ch1 ?? ch2 ?? ch3 ?? ch4;
  final timePoints = timeSource?.points ?? const <(double, double)>[];
  final double t0 = timePoints.isEmpty ? 0.0 : timePoints.first.$1;
  final double fallbackDt = params.sampleRate > 0 ? 1 / params.sampleRate : 0.0;

  double timeAt(int index) {
    if (index < timePoints.length) {
      return timePoints[index].$1 - t0;
    }
    if (timePoints.isEmpty) return index * fallbackDt;
    final lastTime = timePoints.last.$1 - t0;
    final previousTime = timePoints.length > 1
        ? timePoints[timePoints.length - 2].$1 - t0
        : lastTime;
    final lastStep = lastTime - previousTime;
    final step = lastStep > 0 ? lastStep : fallbackDt;
    return lastTime + (index - timePoints.length + 1) * step;
  }

  for (int i = 0; i < maxPoints; i++) {
    final time = timeAt(i);
    final row = StringBuffer('$time,${voltageAt(ch1, i)},${voltageAt(ch2, i)}');
    if (fourChannels) {
      row.write(',${voltageAt(ch3, i)},${voltageAt(ch4, i)}');
    }
    csvBuffer.writeln(row);
  }

  return csvBuffer.toString();
}
