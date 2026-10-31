/// Waveform export formats: LTspice PWL, WAV, VCD and clipboard TSV.
///
/// The module is Flutter-free and performs no I/O. All builders take the
/// displayed `(time, voltage)` points and return the file content as text or
/// bytes; the UI layer writes the files.
library;

import 'dart:typed_data';

import 'waveform_measurements.dart';

/// Supported waveform export targets.
enum WaveformExportFormat { ltspicePwl, wav, vcd, clipboard }

/// Builds an LTspice PWL source.
///
/// Each line contains `time value`; with [wrap] the pairs are emitted as one
/// `PWL(...)` expression suitable for pasting into a voltage source. Invalid
/// points are skipped and the points are sorted by time.
String buildLtspicePwl(List<(double, double)> points, {bool wrap = false}) {
  final sorted = _validSorted(points);
  if (sorted.isEmpty) return '';

  final entries = [
    for (final (time, voltage) in sorted)
      '${_fmtNumber(time)} ${_fmtNumber(voltage)}',
  ];
  return wrap ? 'PWL(${entries.join(' ')})' : entries.join('\n');
}

/// Builds a 16-bit PCM mono WAV file.
///
/// The points are resampled linearly onto a uniform grid at [sampleRate] and
/// normalised to full scale (the largest absolute voltage maps to 32767).
/// Fewer than two points or a non-positive sample rate produce a valid WAV
/// with an empty data chunk.
Uint8List buildWav(
  List<(double, double)> points, {
  required double sampleRate,
}) {
  final sorted = _validSorted(points);
  if (sorted.length < 2 || !sampleRate.isFinite || sampleRate <= 0) {
    return _wavBytes(const [], sampleRate: 44100);
  }

  final double start = sorted.first.$1;
  final double duration = sorted.last.$1 - start;
  var count = (duration * sampleRate).round() + 1;
  if (count < 2) count = 2;
  // Guard against absurd allocations from a bad sample rate.
  const int maxSamples = 10000000;
  if (count > maxSamples) count = maxSamples;

  final voltages = <double>[];
  var maxAbs = 0.0;
  var index = 0;
  for (var i = 0; i < count; i++) {
    final t = start + i / sampleRate;
    // Advance to the segment that brackets t.
    while (index + 1 < sorted.length && sorted[index + 1].$1 < t) {
      index++;
    }
    final (t0, v0) = sorted[index];
    if (index + 1 >= sorted.length || t <= t0) {
      voltages.add(v0);
      if (v0.abs() > maxAbs) maxAbs = v0.abs();
      continue;
    }
    final (t1, v1) = sorted[index + 1];
    final span = t1 - t0;
    final value = span > 0 ? v0 + (v1 - v0) * (t - t0) / span : v0;
    voltages.add(value);
    if (value.abs() > maxAbs) maxAbs = value.abs();
  }

  final scale = maxAbs > 0 ? 32767.0 / maxAbs : 0.0;
  final samples = [
    for (final voltage in voltages)
      (voltage * scale).round().clamp(-32768, 32767),
  ];
  return _wavBytes(samples, sampleRate: sampleRate);
}

/// Builds a Value Change Dump for digital versions of [channels].
///
/// A channel is high when its voltage is greater than or equal to
/// [thresholdVolts]. Timestamps use a 1 ns timescale and are normalised so
/// the earliest sample is at t=0. Invalid and empty channels are skipped.
String buildVcd(
  Map<String, List<(double, double)>> channels, {
  required double thresholdVolts,
}) {
  final valid = <String, List<(double, double)>>{};
  for (final entry in channels.entries) {
    final points = _validSorted(entry.value);
    if (points.isNotEmpty) valid[entry.key] = points;
  }
  if (valid.isEmpty) return '';

  var startTime = double.infinity;
  for (final points in valid.values) {
    if (points.first.$1 < startTime) startTime = points.first.$1;
  }

  final buffer = StringBuffer()
    ..writeln(r'$version SDS-Remote waveform export $end')
    ..writeln(r'$timescale 1ns $end')
    ..writeln(r'$scope module waveform $end');

  final ids = <String, String>{};
  var idCode = 33; // '!'
  for (final name in valid.keys) {
    ids[name] = String.fromCharCode(idCode++);
  }
  for (final name in valid.keys) {
    buffer.writeln('\$var wire 1 ${ids[name]!} ${name.toUpperCase()} \$end');
  }
  buffer
    ..writeln(r'$upscope $end')
    ..writeln(r'$enddefinitions $end');

  // Collect state changes per timestamp.
  final changes = <int, List<(String, int)>>{};
  for (final entry in valid.entries) {
    final id = ids[entry.key]!;
    int? previous;
    for (final (time, voltage) in entry.value) {
      final state = voltage >= thresholdVolts ? 1 : 0;
      if (state == previous) continue;
      final stamp = ((time - startTime) * 1e9).round();
      (changes[stamp] ??= []).add((id, state));
      previous = state;
    }
  }

  final stamps = changes.keys.toList()..sort();
  for (final stamp in stamps) {
    buffer.writeln('#$stamp');
    for (final (id, state) in changes[stamp]!) {
      buffer.writeln('$state$id');
    }
  }
  return buffer.toString();
}

/// Builds a tab-separated table of the automatic measurements.
///
/// Missing values are empty cells so the text pastes cleanly into a
/// spreadsheet.
String buildClipboardText(Map<String, WaveformMeasurements> measurements) {
  final buffer = StringBuffer()
    ..writeln(
      'Channel\tVpp (V)\tRMS (V)\tFrequency (Hz)\tDuty (%)\t'
      'Rise (s)\tFall (s)\tOvershoot (%)',
    );
  for (final channel in const ['ch1', 'ch2', 'ch3', 'ch4']) {
    final measurement = measurements[channel];
    if (measurement == null) continue;
    buffer.writeln(
      [
        channel.toUpperCase(),
        _fmtCell(measurement.vPp),
        _fmtCell(measurement.vRms),
        _fmtCell(measurement.frequencyHz),
        _fmtCell(measurement.dutyPercent),
        _fmtCell(measurement.riseTimeSeconds),
        _fmtCell(measurement.fallTimeSeconds),
        _fmtCell(measurement.overshootPercent),
      ].join('\t'),
    );
  }
  return buffer.toString();
}

/// Sorted, finite points with a strictly increasing time axis.
List<(double, double)> _validSorted(List<(double, double)> points) {
  final valid = [
    for (final point in points)
      if (point.$1.isFinite && point.$2.isFinite) point,
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return valid;
}

String _fmtNumber(double value) {
  var text = value.toStringAsFixed(9);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text == '-0' ? '0' : text;
}

String _fmtCell(double? value) =>
    value == null || !value.isFinite ? '' : value.toStringAsFixed(6);

Uint8List _wavBytes(List<int> samples, {required double sampleRate}) {
  final dataSize = samples.length * 2;
  final totalSize = 44 + dataSize;
  final data = ByteData(totalSize);

  void writeAscii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      data.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  data.setUint32(4, 36 + dataSize, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little); // fmt chunk size
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  final rate = sampleRate.isFinite && sampleRate > 0
      ? sampleRate.round()
      : 44100;
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little); // byte rate
  data.setUint16(32, 2, Endian.little); // block align
  data.setUint16(34, 16, Endian.little); // bits per sample
  writeAscii(36, 'data');
  data.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}
