/// Pure CSV export for Bode Plot results.
library;

import 'bode_models.dart';

String buildBodeCsv({
  required BodeConfig config,
  required List<BodePoint> points,
  required String deviceName,
  required String generatorIdentity,
  DateTime? savedAt,
}) {
  final buffer = StringBuffer();
  final timestamp = (savedAt ?? DateTime.now()).toIso8601String();

  buffer.writeln('# SDS-Remote Bode Plot');
  buffer.writeln('# Saved: $timestamp');
  buffer.writeln('# Scope: $deviceName');
  buffer.writeln('# Generator: $generatorIdentity');
  buffer.writeln('# Start (Hz): ${config.startFrequencyHz}');
  buffer.writeln('# Stop (Hz): ${config.stopFrequencyHz}');
  buffer.writeln('# Points: ${config.pointCount}');
  buffer.writeln('# Spacing: ${config.spacing.name}');
  buffer.writeln('# Amplitude (Vpp): ${config.amplitudeVpp}');
  buffer.writeln('# Offset (V): ${config.offsetV}');
  buffer.writeln('# Waveform: ${config.waveform.scpiMnemonic}');
  buffer.writeln('# Vin channel: CH${config.vinChannel}');
  buffer.writeln('# Vout channel: CH${config.voutChannel}');
  buffer.writeln('# Generator channel: CH${config.generatorChannel}');
  buffer.writeln('# Generator outputs: off');

  final columns = <String>[
    'Frequency (Hz)',
    'Vin Rms (V)',
    'Vout Rms (V)',
    'Gain (dB)',
  ];
  if (config.measurePhase) {
    columns.addAll(['Phase (deg)', 'Phase Source', 'Delay (s)']);
  }
  columns.addAll(['Valid', 'Note']);
  buffer.writeln(columns.join(','));

  for (final point in points) {
    final row = <String>[
      _number(point.frequencyHz, 6),
      _number(point.vinRms, 6),
      _number(point.voutRms, 6),
      _number(point.gainDb, 6),
    ];
    if (config.measurePhase) {
      row.addAll([
        _number(point.phaseDeg, 6),
        point.phaseSource.name,
        _number(point.delaySeconds, 9),
      ]);
    }
    row.addAll([point.valid ? '1' : '0', _cell(point.note ?? '')]);
    buffer.writeln(row.join(','));
  }

  return buffer.toString();
}

String _number(double? value, int decimals) {
  if (value == null || !value.isFinite) return '';
  return value.toStringAsFixed(decimals);
}

String _cell(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
