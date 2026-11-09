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
  final amplitudeSweep = config.mode == BodeMode.amplitudeSweep;

  buffer.writeln('# SDS-Remote Bode Plot');
  buffer.writeln('# Mode: ${amplitudeSweep ? 'amplitude' : 'frequency'} sweep');
  buffer.writeln('# Saved: $timestamp');
  buffer.writeln('# Scope: $deviceName');
  buffer.writeln('# Generator: $generatorIdentity');
  if (amplitudeSweep) {
    buffer.writeln('# Frequency (Hz): ${config.sweepFrequencyHz}');
    buffer.writeln('# Start amplitude (Vpp): ${config.startAmplitudeVpp}');
    buffer.writeln('# Stop amplitude (Vpp): ${config.stopAmplitudeVpp}');
    buffer.writeln('# Spacing: ${config.amplitudeSpacing.name}');
    buffer.writeln('# Offset (V): ${config.offsetV}');
  } else {
    buffer.writeln('# Start (Hz): ${config.startFrequencyHz}');
    buffer.writeln('# Stop (Hz): ${config.stopFrequencyHz}');
    buffer.writeln('# Spacing: ${config.spacing.name}');
    buffer.writeln('# Amplitude (Vpp): ${config.amplitudeVpp}');
    buffer.writeln('# Offset (V): ${config.offsetV}');
  }
  buffer.writeln('# Points: ${config.pointCount}');
  buffer.writeln('# Waveform: ${config.waveform.scpiMnemonic}');
  buffer.writeln('# Vin channel: CH${config.vinChannel}');
  buffer.writeln('# Vout channel: CH${config.voutChannel}');
  buffer.writeln('# Generator channel: CH${config.generatorChannel}');
  buffer.writeln(
    '# Generator outputs: '
    '${config.turnOffOutputsAfterSweep ? 'off' : 'on'}',
  );

  final columns = <String>[
    if (amplitudeSweep) ...['Amplitude (Vpp)', 'Vin Vpp (V)', 'Vout Vpp (V)'],
    if (amplitudeSweep) ...['Vin Rms (V)', 'Vout Rms (V)', 'Gain (dB)'],
    if (amplitudeSweep) 'Vpp/Vrms',
    if (!amplitudeSweep) ...['Frequency (Hz)', 'Vin Rms (V)', 'Vout Rms (V)'],
    if (!amplitudeSweep) 'Gain (dB)',
  ];
  if (!amplitudeSweep && config.measurePhase) {
    columns.addAll(['Phase (deg)', 'Phase Source', 'Delay (s)']);
  }
  columns.addAll(['Valid', 'Note']);
  buffer.writeln(columns.join(','));

  for (final point in points) {
    final row = <String>[
      if (amplitudeSweep) ...[
        _number(point.amplitudeVpp, 6),
        _number(point.vinVpp, 6),
        _number(point.voutVpp, 6),
        _number(point.vinRms, 6),
        _number(point.voutRms, 6),
        _number(point.gainDb, 6),
        _number(point.voutVppRmsRatio, 6),
      ],
      if (!amplitudeSweep) ...[
        _number(point.frequencyHz, 6),
        _number(point.vinRms, 6),
        _number(point.voutRms, 6),
        _number(point.gainDb, 6),
      ],
    ];
    if (!amplitudeSweep && config.measurePhase) {
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
