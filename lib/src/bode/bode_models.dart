/// Domain models for the Bode Plot feature.
///
/// Pure Dart: no Flutter, no transport, no file I/O.
library;

import '../signal_generator/models.dart';

enum BodeSpacing { logarithmic, linear }

enum BodeStatus { idle, configuring, running, completed, cancelled, error }

enum BodePhaseSource { none, mead, waveform }

/// Configuration for one Bode sweep.
class BodeConfig {
  const BodeConfig({
    this.startFrequencyHz = 100,
    this.stopFrequencyHz = 20000,
    this.pointCount = 20,
    this.spacing = BodeSpacing.logarithmic,
    this.amplitudeVpp = 1,
    this.offsetV = 0,
    this.waveform = Jds6600Waveform.sine,
    this.settling = const Duration(milliseconds: 500),
    this.measurePhase = true,
    this.vinChannel = 1,
    this.voutChannel = 2,
    this.generatorChannel = 1,
  });

  final double startFrequencyHz;
  final double stopFrequencyHz;
  final int pointCount;
  final BodeSpacing spacing;
  final double amplitudeVpp;
  final double offsetV;
  final Jds6600Waveform waveform;
  final Duration settling;
  final bool measurePhase;
  final int vinChannel;
  final int voutChannel;
  final int generatorChannel;

  BodeConfig copyWith({
    double? startFrequencyHz,
    double? stopFrequencyHz,
    int? pointCount,
    BodeSpacing? spacing,
    double? amplitudeVpp,
    double? offsetV,
    Jds6600Waveform? waveform,
    Duration? settling,
    bool? measurePhase,
    int? vinChannel,
    int? voutChannel,
    int? generatorChannel,
  }) {
    return BodeConfig(
      startFrequencyHz: startFrequencyHz ?? this.startFrequencyHz,
      stopFrequencyHz: stopFrequencyHz ?? this.stopFrequencyHz,
      pointCount: pointCount ?? this.pointCount,
      spacing: spacing ?? this.spacing,
      amplitudeVpp: amplitudeVpp ?? this.amplitudeVpp,
      offsetV: offsetV ?? this.offsetV,
      waveform: waveform ?? this.waveform,
      settling: settling ?? this.settling,
      measurePhase: measurePhase ?? this.measurePhase,
      vinChannel: vinChannel ?? this.vinChannel,
      voutChannel: voutChannel ?? this.voutChannel,
      generatorChannel: generatorChannel ?? this.generatorChannel,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BodeConfig &&
        other.startFrequencyHz == startFrequencyHz &&
        other.stopFrequencyHz == stopFrequencyHz &&
        other.pointCount == pointCount &&
        other.spacing == spacing &&
        other.amplitudeVpp == amplitudeVpp &&
        other.offsetV == offsetV &&
        other.waveform == waveform &&
        other.settling == settling &&
        other.measurePhase == measurePhase &&
        other.vinChannel == vinChannel &&
        other.voutChannel == voutChannel &&
        other.generatorChannel == generatorChannel;
  }

  @override
  int get hashCode => Object.hash(
        startFrequencyHz,
        stopFrequencyHz,
        pointCount,
        spacing,
        amplitudeVpp,
        offsetV,
        waveform,
        settling,
        measurePhase,
        vinChannel,
        voutChannel,
        generatorChannel,
      );
}

/// One measured frequency point.
class BodePoint {
  const BodePoint({
    required this.frequencyHz,
    this.vinRms,
    this.voutRms,
    this.gainDb,
    this.phaseDeg,
    this.delaySeconds,
    this.phaseSource = BodePhaseSource.none,
    this.valid = true,
    this.note,
  });

  final double frequencyHz;
  final double? vinRms;
  final double? voutRms;
  final double? gainDb;
  final double? phaseDeg;
  final double? delaySeconds;
  final BodePhaseSource phaseSource;
  final bool valid;
  final String? note;

  BodePoint copyWith({
    double? frequencyHz,
    double? vinRms,
    double? voutRms,
    double? gainDb,
    double? phaseDeg,
    double? delaySeconds,
    BodePhaseSource? phaseSource,
    bool? valid,
    String? note,
  }) {
    return BodePoint(
      frequencyHz: frequencyHz ?? this.frequencyHz,
      vinRms: vinRms ?? this.vinRms,
      voutRms: voutRms ?? this.voutRms,
      gainDb: gainDb ?? this.gainDb,
      phaseDeg: phaseDeg ?? this.phaseDeg,
      delaySeconds: delaySeconds ?? this.delaySeconds,
      phaseSource: phaseSource ?? this.phaseSource,
      valid: valid ?? this.valid,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BodePoint &&
        other.frequencyHz == frequencyHz &&
        other.vinRms == vinRms &&
        other.voutRms == voutRms &&
        other.gainDb == gainDb &&
        other.phaseDeg == phaseDeg &&
        other.delaySeconds == delaySeconds &&
        other.phaseSource == phaseSource &&
        other.valid == valid &&
        other.note == note;
  }

  @override
  int get hashCode => Object.hash(
        frequencyHz,
        vinRms,
        voutRms,
        gainDb,
        phaseDeg,
        delaySeconds,
        phaseSource,
        valid,
        note,
      );
}
