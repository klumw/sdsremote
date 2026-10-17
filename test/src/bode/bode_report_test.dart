import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/bode/bode_models.dart';
import 'package:sdsremote/src/bode/bode_report.dart';

/// A valid 1x1 transparent PNG, used as the captured plot image.
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhf'
  'DwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

void main() {
  const config = BodeConfig(
    startFrequencyHz: 100,
    stopFrequencyHz: 20000,
    pointCount: 3,
    amplitudeVpp: 1,
    reportName: 'RC low-pass',
  );
  const points = [
    BodePoint(
      frequencyHz: 100,
      vinRms: 1,
      voutRms: 0.99,
      gainDb: -0.09,
      phaseDeg: -5.7,
      phaseSource: BodePhaseSource.mead,
    ),
    BodePoint(
      frequencyHz: 1000,
      vinRms: 1,
      voutRms: 0.707,
      gainDb: -3.01,
      phaseDeg: -45,
      phaseSource: BodePhaseSource.mead,
    ),
    BodePoint(frequencyHz: 20000, valid: false, note: 'no signal'),
  ];

  test('generatePdf returns a PDF document', () async {
    final bytes = await BodeReport.generatePdf(
      config: config,
      points: points,
      chartImageBytes: _tinyPng,
      deviceName: 'SDS1202X-E',
      generatorIdentity: 'JOY-IT,JDS6600-LITE,1,N/A',
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('report name is optional', () async {
    final bytes = await BodeReport.generatePdf(
      config: const BodeConfig(reportName: ''),
      points: const [],
      chartImageBytes: _tinyPng,
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('copyWith preserves the report name', () {
    final copied = config.copyWith(pointCount: 5);
    expect(copied.reportName, 'RC low-pass');
    expect(copied.pointCount, 5);
  });
}
