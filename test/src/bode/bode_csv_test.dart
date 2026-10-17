import 'package:flutter_test/flutter_test.dart';
import 'package:sdsremote/src/bode/bode_csv_writer.dart';
import 'package:sdsremote/src/bode/bode_models.dart';

void main() {
  test('writes header, columns and rows', () {
    const config = BodeConfig(measurePhase: true);
    final points = [
      const BodePoint(
        frequencyHz: 100,
        vinRms: 1,
        voutRms: 0.5,
        gainDb: -6.02,
        phaseDeg: -45,
        delaySeconds: 0.000125,
        phaseSource: BodePhaseSource.mead,
      ),
      const BodePoint(
        frequencyHz: 1000,
        valid: false,
        note: 'no signal, check wiring',
      ),
    ];
    final csv = buildBodeCsv(
      config: config,
      points: points,
      deviceName: 'SDS1202X-E',
      generatorIdentity: 'JOY-IT,JDS6600-LITE,1,N/A',
      savedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    );

    expect(csv, contains('# SDS-Remote Bode Plot'));
    expect(csv, contains('# Saved: 2026-01-02T03:04:05.000Z'));
    expect(csv, contains('# Scope: SDS1202X-E'));
    expect(csv, contains('# Generator: JOY-IT,JDS6600-LITE,1,N/A'));
    expect(
      csv,
      contains(
        'Frequency (Hz),Vin Rms (V),Vout Rms (V),Gain (dB),'
        'Phase (deg),Phase Source,Delay (s),Valid,Note',
      ),
    );
    expect(
      csv,
      contains(
        '100.000000,1.000000,0.500000,-6.020000,-45.000000,mead,'
        '0.000125000,1,',
      ),
    );
    expect(csv, contains('1000.000000'));
    expect(csv, contains('0,"no signal, check wiring"'));
  });

  test('omits phase columns when disabled', () {
    const config = BodeConfig(measurePhase: false);
    final csv = buildBodeCsv(
      config: config,
      points: const [
        BodePoint(
          frequencyHz: 100,
          vinRms: 1,
          voutRms: 1,
          gainDb: 0,
        ),
      ],
      deviceName: 'scope',
      generatorIdentity: 'gen',
    );

    expect(
      csv,
      contains(
        'Frequency (Hz),Vin Rms (V),Vout Rms (V),Gain (dB),Valid,Note',
      ),
    );
    expect(csv, isNot(contains('Phase (deg)')));
  });
}
