/// Domain models for the Bode Plot feature.
///
/// Pure Dart: no Flutter, no transport, no file I/O.
library;

import '../signal_generator/models.dart';

enum BodeSpacing { logarithmic, linear }

enum BodeStatus { idle, configuring, running, completed, cancelled, error }

enum BodePhaseSource { none, mead, waveform }

/// Measurement method used by the Bode Plot panel.
enum BodeMode {
  /// Sweep the generator frequency at a fixed amplitude.
  frequencySweep,

  /// Sweep the generator amplitude at a fixed frequency.
  amplitudeSweep,
}

/// Configuration for one Bode sweep.
class BodeConfig {
  const BodeConfig({
    this.mode = BodeMode.frequencySweep,
    this.startFrequencyHz = 100,
    this.stopFrequencyHz = 20000,
    this.sweepFrequencyHz = 1000,
    this.pointCount = 20,
    this.spacing = BodeSpacing.logarithmic,
    this.amplitudeSpacing = BodeSpacing.linear,
    this.amplitudeVpp = 1,
    this.startAmplitudeVpp = 0.1,
    this.stopAmplitudeVpp = 10,
    this.offsetV = 0,
    this.waveform = Jds6600Waveform.sine,
    this.settling = const Duration(milliseconds: 1500),
    this.measurePhase = false,
    this.vinChannel = 1,
    this.voutChannel = 2,
    this.generatorChannel = 1,
    this.turnOffOutputsAfterSweep = true,
    this.useCurrentGeneratorSettings = false,
    this.reportName = '',
  });

  /// Measurement method: frequency sweep or amplitude sweep.
  final BodeMode mode;

  final double startFrequencyHz;
  final double stopFrequencyHz;

  /// Fixed generator frequency used by an amplitude sweep.
  final double sweepFrequencyHz;

  final int pointCount;
  final BodeSpacing spacing;

  /// Spacing used for the amplitude sweep points.
  ///
  /// Kept separately from [spacing] so switching the measurement method does
  /// not silently change the frequency-sweep configuration.
  final BodeSpacing amplitudeSpacing;

  final double amplitudeVpp;

  /// First generator amplitude of an amplitude sweep, in Vpp.
  final double startAmplitudeVpp;

  /// Last generator amplitude of an amplitude sweep, in Vpp.
  final double stopAmplitudeVpp;

  final double offsetV;
  final Jds6600Waveform waveform;
  final Duration settling;
  final bool measurePhase;
  final int vinChannel;
  final int voutChannel;
  final int generatorChannel;

  /// Whether both generator outputs are switched off when the sweep ends.
  ///
  /// When false the selected output stays enabled at the last sweep frequency
  /// after completion, cancellation or failure.
  final bool turnOffOutputsAfterSweep;

  /// Whether the generator waveform, amplitude and offset stay unchanged.
  ///
  /// Only the frequency is stepped in that case. The current values are used
  /// for the scope scaling and restored after the sweep.
  final bool useCurrentGeneratorSettings;

  /// Optional free-text report name (max 150 characters).
  /// Shown in the configuration mask and included in the PDF report.
  final String reportName;

  BodeConfig copyWith({
    BodeMode? mode,
    double? startFrequencyHz,
    double? stopFrequencyHz,
    double? sweepFrequencyHz,
    int? pointCount,
    BodeSpacing? spacing,
    BodeSpacing? amplitudeSpacing,
    double? amplitudeVpp,
    double? startAmplitudeVpp,
    double? stopAmplitudeVpp,
    double? offsetV,
    Jds6600Waveform? waveform,
    Duration? settling,
    bool? measurePhase,
    int? vinChannel,
    int? voutChannel,
    int? generatorChannel,
    bool? turnOffOutputsAfterSweep,
    bool? useCurrentGeneratorSettings,
    String? reportName,
  }) {
    return BodeConfig(
      mode: mode ?? this.mode,
      startFrequencyHz: startFrequencyHz ?? this.startFrequencyHz,
      stopFrequencyHz: stopFrequencyHz ?? this.stopFrequencyHz,
      sweepFrequencyHz: sweepFrequencyHz ?? this.sweepFrequencyHz,
      pointCount: pointCount ?? this.pointCount,
      spacing: spacing ?? this.spacing,
      amplitudeSpacing: amplitudeSpacing ?? this.amplitudeSpacing,
      amplitudeVpp: amplitudeVpp ?? this.amplitudeVpp,
      startAmplitudeVpp: startAmplitudeVpp ?? this.startAmplitudeVpp,
      stopAmplitudeVpp: stopAmplitudeVpp ?? this.stopAmplitudeVpp,
      offsetV: offsetV ?? this.offsetV,
      waveform: waveform ?? this.waveform,
      settling: settling ?? this.settling,
      measurePhase: measurePhase ?? this.measurePhase,
      vinChannel: vinChannel ?? this.vinChannel,
      voutChannel: voutChannel ?? this.voutChannel,
      generatorChannel: generatorChannel ?? this.generatorChannel,
      turnOffOutputsAfterSweep:
          turnOffOutputsAfterSweep ?? this.turnOffOutputsAfterSweep,
      useCurrentGeneratorSettings:
          useCurrentGeneratorSettings ?? this.useCurrentGeneratorSettings,
      reportName: reportName ?? this.reportName,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BodeConfig &&
        other.mode == mode &&
        other.startFrequencyHz == startFrequencyHz &&
        other.stopFrequencyHz == stopFrequencyHz &&
        other.sweepFrequencyHz == sweepFrequencyHz &&
        other.pointCount == pointCount &&
        other.spacing == spacing &&
        other.amplitudeSpacing == amplitudeSpacing &&
        other.amplitudeVpp == amplitudeVpp &&
        other.startAmplitudeVpp == startAmplitudeVpp &&
        other.stopAmplitudeVpp == stopAmplitudeVpp &&
        other.offsetV == offsetV &&
        other.waveform == waveform &&
        other.settling == settling &&
        other.measurePhase == measurePhase &&
        other.vinChannel == vinChannel &&
        other.voutChannel == voutChannel &&
        other.generatorChannel == generatorChannel &&
        other.turnOffOutputsAfterSweep == turnOffOutputsAfterSweep &&
        other.useCurrentGeneratorSettings == useCurrentGeneratorSettings &&
        other.reportName == reportName;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    startFrequencyHz,
    stopFrequencyHz,
    sweepFrequencyHz,
    pointCount,
    spacing,
    amplitudeSpacing,
    amplitudeVpp,
    startAmplitudeVpp,
    stopAmplitudeVpp,
    offsetV,
    waveform,
    settling,
    measurePhase,
    vinChannel,
    voutChannel,
    generatorChannel,
    turnOffOutputsAfterSweep,
    useCurrentGeneratorSettings,
    reportName,
  );
}

/// One measured sweep point.
class BodePoint {
  const BodePoint({
    required this.frequencyHz,
    this.amplitudeVpp,
    this.vinRms,
    this.voutRms,
    this.vinVpp,
    this.voutVpp,
    this.gainDb,
    this.phaseDeg,
    this.delaySeconds,
    this.phaseSource = BodePhaseSource.none,
    this.valid = true,
    this.note,
  });

  final double frequencyHz;

  /// Generator amplitude setpoint in Vpp; set for amplitude-sweep points.
  final double? amplitudeVpp;

  final double? vinRms;
  final double? voutRms;
  final double? vinVpp;
  final double? voutVpp;
  final double? gainDb;
  final double? phaseDeg;
  final double? delaySeconds;
  final BodePhaseSource phaseSource;
  final bool valid;
  final String? note;

  /// Measured output form factor `Vout Vpp / Vout Vrms`.
  ///
  /// A clean sine gives `2 * sqrt(2) ≈ 2.83`; lower values indicate clipping,
  /// distortion or an asymmetric waveform.
  double? get voutVppRmsRatio {
    final vpp = voutVpp;
    final rms = voutRms;
    if (vpp == null || rms == null) return null;
    if (!vpp.isFinite || !rms.isFinite || rms <= 0) return null;
    return vpp / rms;
  }

  BodePoint copyWith({
    double? frequencyHz,
    double? amplitudeVpp,
    double? vinRms,
    double? voutRms,
    double? vinVpp,
    double? voutVpp,
    double? gainDb,
    double? phaseDeg,
    double? delaySeconds,
    BodePhaseSource? phaseSource,
    bool? valid,
    String? note,
  }) {
    return BodePoint(
      frequencyHz: frequencyHz ?? this.frequencyHz,
      amplitudeVpp: amplitudeVpp ?? this.amplitudeVpp,
      vinRms: vinRms ?? this.vinRms,
      voutRms: voutRms ?? this.voutRms,
      vinVpp: vinVpp ?? this.vinVpp,
      voutVpp: voutVpp ?? this.voutVpp,
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
        other.amplitudeVpp == amplitudeVpp &&
        other.vinRms == vinRms &&
        other.voutRms == voutRms &&
        other.vinVpp == vinVpp &&
        other.voutVpp == voutVpp &&
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
    amplitudeVpp,
    vinRms,
    voutRms,
    vinVpp,
    voutVpp,
    gainDb,
    phaseDeg,
    delaySeconds,
    phaseSource,
    valid,
    note,
  );
}
