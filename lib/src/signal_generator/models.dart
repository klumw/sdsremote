/// Domain models shared by the supported signal generators
/// (JOY-IT / Juntek JDS6600 and FeelElec FY6900).
///
/// This layer is deliberately free of Flutter and transport imports so it can
/// be unit-tested without a device.
library;

/// Families used to derive frequency limits from the device manual.
enum Jds6600WaveformFamily { sine, square, triangle, pulse, other, arbitrary }

/// Predefined JDS6600 waveforms and their register/SCPI representations.
///
/// Register values 101-160 select arbitrary-waveform slots. Stage 1 exposes
/// only the predefined waveforms and treats an arb slot as [arbitrary]; the
/// actual waveform data upload is a later stage.
enum Jds6600Waveform {
  sine(0, 'SIN', 'Sine', Jds6600WaveformFamily.sine),
  square(1, 'SQU', 'Square', Jds6600WaveformFamily.square),
  pulse(2, 'PULS', 'Pulse', Jds6600WaveformFamily.pulse),
  triangle(3, 'TRI', 'Triangle', Jds6600WaveformFamily.triangle),
  partialSine(4, 'PSIN', 'Partial sine', Jds6600WaveformFamily.other),
  cmos(5, 'CMOS', 'CMOS', Jds6600WaveformFamily.other),
  dc(6, 'DC', 'DC', Jds6600WaveformFamily.other),
  halfWave(7, 'HALF', 'Half wave', Jds6600WaveformFamily.other),
  fullWave(8, 'FULL', 'Full wave', Jds6600WaveformFamily.other),
  positiveLadder(9, 'POSL', 'Pos. ladder', Jds6600WaveformFamily.other),
  negativeLadder(10, 'NEGL', 'Neg. ladder', Jds6600WaveformFamily.other),
  noise(11, 'NOIS', 'Noise', Jds6600WaveformFamily.other),
  expRise(12, 'ERIS', 'Exp. rise', Jds6600WaveformFamily.other),
  expDecay(13, 'EDEC', 'Exp. decay', Jds6600WaveformFamily.other),
  multiTone(14, 'MTON', 'Multi tone', Jds6600WaveformFamily.other),
  sinc(15, 'SINC', 'Sinc', Jds6600WaveformFamily.other),
  lorenz(16, 'LOR', 'Lorenz', Jds6600WaveformFamily.other),
  arbitrary(101, 'ARB', 'Arbitrary', Jds6600WaveformFamily.arbitrary);

  const Jds6600Waveform(
    this.registerValue,
    this.scpiMnemonic,
    this.displayName,
    this.family,
  );

  final int registerValue;
  final String scpiMnemonic;
  final String displayName;
  final Jds6600WaveformFamily family;

  /// Resolves a register value read from the device.
  ///
  /// Register values 101-160 map to [arbitrary]; the caller keeps the concrete
  /// slot separately if it needs to display it.
  static Jds6600Waveform fromRegister(int value) {
    for (final waveform in values) {
      if (waveform.registerValue == value) return waveform;
    }
    if (value >= 101 && value <= 160) return arbitrary;
    throw ArgumentError.value(value, 'value', 'Unknown waveform register');
  }

  /// Resolves a SCPI waveform mnemonic, case-insensitively.
  static Jds6600Waveform? fromScpi(String value) {
    final normalized = value.trim().toUpperCase();
    for (final waveform in values) {
      if (waveform.scpiMnemonic == normalized) return waveform;
    }
    // Common SCPI spellings that are not identical to the device mnemonic.
    switch (normalized) {
      case 'SINE':
        return sine;
      case 'SQUARE':
        return square;
      case 'PULSE':
        return pulse;
      case 'TRIANGLE':
        return triangle;
      case 'NOISE':
        return noise;
    }
    return null;
  }
}

/// Device family used to pick model limits and identity formatting.
enum SiggenFamily { jds6600, fy6900 }

/// Device identity and model limits.
///
/// The class predates multi-device support and keeps its name so the existing
/// Bode and signal-generator UI keep compiling; [family] decides which limit
/// table and `*IDN?` identity apply.
class Jds6600DeviceInfo {
  const Jds6600DeviceInfo({
    required this.modelMHz,
    required this.serialNumber,
    this.family = SiggenFamily.jds6600,
    this.modelNameOverride,
  });

  /// MHz class reported by register 0 (JDS6600) or the `UMO` reply (FY6900).
  final int modelMHz;

  /// Serial number reported by register 1 / the `UID` reply.
  final int serialNumber;

  final SiggenFamily family;

  /// Exact model string reported by the device, when available.
  final String? modelNameOverride;

  bool get isLite => family == SiggenFamily.jds6600 && modelMHz <= 15;

  String get modelName {
    final override = modelNameOverride;
    if (override != null && override.isNotEmpty) return override;
    if (family == SiggenFamily.fy6900) {
      return modelMHz > 0 ? 'FY6900-${modelMHz}M' : 'FY6900';
    }
    return isLite ? 'JDS6600-LITE' : 'JDS6600';
  }

  /// SCPI identity returned by `*IDN?`.
  String get scpiIdentity {
    final manufacturer = family == SiggenFamily.fy6900 ? 'FeelElec' : 'JOY-IT';
    return '$manufacturer,$modelName,$serialNumber,N/A';
  }

  /// Maximum frequency for a waveform, derived from the documented model
  /// limits. For unknown models the conservative Lite limits are used.
  double maxFrequencyHz(Jds6600Waveform waveform) {
    if (family == SiggenFamily.fy6900) {
      switch (waveform.family) {
        case Jds6600WaveformFamily.sine:
          return modelMHz > 0 ? modelMHz * 1e6 : 20e6;
        case Jds6600WaveformFamily.square:
          // FY6900-20M is specified to 15 MHz; the larger models to 25 MHz.
          return modelMHz >= 30 ? 25e6 : 15e6;
        case Jds6600WaveformFamily.triangle:
        case Jds6600WaveformFamily.pulse:
        case Jds6600WaveformFamily.other:
        case Jds6600WaveformFamily.arbitrary:
          return 10e6;
      }
    }
    final modelMax = modelMHz > 0 ? modelMHz * 1e6 : 15e6;
    switch (waveform.family) {
      case Jds6600WaveformFamily.sine:
        return modelMax;
      case Jds6600WaveformFamily.square:
      case Jds6600WaveformFamily.triangle:
        // Both the 15 MHz Lite and the 60 MHz standard model are specified
        // to 15 MHz for square/triangle.
        return 15e6;
      case Jds6600WaveformFamily.pulse:
      case Jds6600WaveformFamily.other:
      case Jds6600WaveformFamily.arbitrary:
        return 6e6;
    }
  }

  /// Amplitude limit in Vpp for the given frequency.
  ///
  /// The JDS6600 Lite data sheet specifies 0-20 Vpp below 10 MHz and
  /// 0-10 Vpp above. The FY6900 specifies 24/20/10/5 Vpp for the frequency
  /// bands up to 5/10/20 MHz and above.
  double maxAmplitudeVpp(double frequencyHz) {
    if (family == SiggenFamily.fy6900) {
      if (frequencyHz <= 5e6) return 24.0;
      if (frequencyHz <= 10e6) return 20.0;
      if (frequencyHz <= 20e6) return 10.0;
      return 5.0;
    }
    return frequencyHz < 10e6 ? 20.0 : 10.0;
  }

  /// Input limits for this device family.
  SiggenLimits get limits => SiggenLimits.forFamily(family);

  /// Maximum DC offset at the given output frequency.
  ///
  /// The FY6900 allows ±12 V up to 20 MHz and ±2.5 V above. The JDS6600 uses
  /// its fixed ±9.99 V range.
  double maxOffsetVAt(double frequencyHz) {
    if (family == SiggenFamily.fy6900) {
      return frequencyHz > 20e6 ? 2.5 : 12.0;
    }
    return maxOffsetV;
  }

  double minOffsetVAt(double frequencyHz) => -maxOffsetVAt(frequencyHz);

  static const double minFrequencyHz = 0.01;
  static const double minOffsetV = -9.99;
  static const double maxOffsetV = 9.99;
  static const double minDutyPercent = 0.0;
  static const double maxDutyPercent = 100.0;
  static const double minPhaseDegrees = 0.0;
  static const double maxPhaseDegrees = 360.0;
}

/// Input limits derived from the detected device family.
///
/// Frequency and amplitude limits additionally depend on the waveform and the
/// frequency band; those are provided by [Jds6600DeviceInfo.maxFrequencyHz]
/// and [Jds6600DeviceInfo.maxAmplitudeVpp].
class SiggenLimits {
  const SiggenLimits({
    required this.minFrequencyHz,
    required this.minOffsetV,
    required this.maxOffsetV,
    required this.minDutyPercent,
    required this.maxDutyPercent,
    required this.minPhaseDegrees,
    required this.maxPhaseDegrees,
  });

  final double minFrequencyHz;
  final double minOffsetV;
  final double maxOffsetV;
  final double minDutyPercent;
  final double maxDutyPercent;
  final double minPhaseDegrees;
  final double maxPhaseDegrees;

  static const SiggenLimits jds6600 = SiggenLimits(
    minFrequencyHz: Jds6600DeviceInfo.minFrequencyHz,
    minOffsetV: Jds6600DeviceInfo.minOffsetV,
    maxOffsetV: Jds6600DeviceInfo.maxOffsetV,
    minDutyPercent: Jds6600DeviceInfo.minDutyPercent,
    maxDutyPercent: Jds6600DeviceInfo.maxDutyPercent,
    minPhaseDegrees: Jds6600DeviceInfo.minPhaseDegrees,
    maxPhaseDegrees: Jds6600DeviceInfo.maxPhaseDegrees,
  );

  /// FY6900 values from the vendor manual: 1 uHz resolution, ±12 V offset
  /// (up to 20 MHz), 0.1-99.9 % duty and 0-359.99 degrees phase.
  static const SiggenLimits fy6900 = SiggenLimits(
    minFrequencyHz: 0.000001,
    minOffsetV: -12.0,
    maxOffsetV: 12.0,
    minDutyPercent: 0.1,
    maxDutyPercent: 99.9,
    minPhaseDegrees: 0.0,
    maxPhaseDegrees: 360.0,
  );

  static SiggenLimits forFamily(SiggenFamily family) =>
      family == SiggenFamily.fy6900 ? fy6900 : jds6600;
}

/// State of one generator channel as cached by the service.
class Jds6600ChannelState {
  const Jds6600ChannelState({
    this.waveform = Jds6600Waveform.sine,
    this.frequencyHz = 1000.0,
    this.amplitudeVpp = 1.0,
    this.offsetV = 0.0,
    this.dutyPercent = 50.0,
    this.phaseDeg = 0.0,
  });

  final Jds6600Waveform waveform;
  final double frequencyHz;
  final double amplitudeVpp;
  final double offsetV;
  final double dutyPercent;

  /// Channel phase in degrees. The JDS6600 reports the same global
  /// CH2-vs-CH1 value for both channels; the FY6900 has per-channel phase.
  final double phaseDeg;

  Jds6600ChannelState copyWith({
    Jds6600Waveform? waveform,
    double? frequencyHz,
    double? amplitudeVpp,
    double? offsetV,
    double? dutyPercent,
    double? phaseDeg,
  }) {
    return Jds6600ChannelState(
      waveform: waveform ?? this.waveform,
      frequencyHz: frequencyHz ?? this.frequencyHz,
      amplitudeVpp: amplitudeVpp ?? this.amplitudeVpp,
      offsetV: offsetV ?? this.offsetV,
      dutyPercent: dutyPercent ?? this.dutyPercent,
      phaseDeg: phaseDeg ?? this.phaseDeg,
    );
  }

  @override
  String toString() =>
      'Jds6600ChannelState(waveform: $waveform, frequencyHz: $frequencyHz, '
      'amplitudeVpp: $amplitudeVpp, offsetV: $offsetV, '
      'dutyPercent: $dutyPercent, phaseDeg: $phaseDeg)';
}

/// Output-enable state of both channels.
class Jds6600OutputState {
  const Jds6600OutputState({this.ch1 = false, this.ch2 = false});

  final bool ch1;
  final bool ch2;

  Jds6600OutputState copyWith({bool? ch1, bool? ch2}) {
    return Jds6600OutputState(ch1: ch1 ?? this.ch1, ch2: ch2 ?? this.ch2);
  }

  @override
  String toString() => 'Jds6600OutputState(ch1: $ch1, ch2: $ch2)';
}

/// A queued SCPI error.
class ScpiError {
  const ScpiError(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => '$code,"$message"';
}

/// Base type for all generator errors.
class Jds6600Exception implements Exception {
  const Jds6600Exception(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message (cause: $cause)';
}

class Jds6600OpenException extends Jds6600Exception {
  const Jds6600OpenException(super.message, [super.cause]);
}

class Jds6600TimeoutException extends Jds6600Exception {
  const Jds6600TimeoutException(super.message, [super.cause]);
}

class Jds6600ProtocolException extends Jds6600Exception {
  const Jds6600ProtocolException(super.message, [super.cause]);
}

class Jds6600DisconnectedException extends Jds6600Exception {
  const Jds6600DisconnectedException(super.message, [super.cause]);
}

class Jds6600RangeException extends Jds6600Exception {
  const Jds6600RangeException(super.message, [super.cause]);
}
