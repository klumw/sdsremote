/// Domain models for the JOY-IT / Juntek JDS6600 signal generator.
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

/// Device identity and model limits.
class Jds6600DeviceInfo {
  const Jds6600DeviceInfo({
    required this.modelMHz,
    required this.serialNumber,
  });

  /// MHz class reported by register 0 (15 for the Lite, 60 for the standard).
  final int modelMHz;

  /// Serial number reported by register 1.
  final int serialNumber;

  bool get isLite => modelMHz <= 15;

  String get modelName => isLite ? 'JDS6600-LITE' : 'JDS6600';

  /// Maximum frequency for a waveform, derived from the documented model
  /// limits. For unknown models the conservative Lite limits are used.
  double maxFrequencyHz(Jds6600Waveform waveform) {
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
  /// The Lite data sheet specifies 0-20 Vpp below 10 MHz and 0-10 Vpp above.
  /// The same conservative limits are applied to the standard model until
  /// measured otherwise.
  double maxAmplitudeVpp(double frequencyHz) =>
      frequencyHz < 10e6 ? 20.0 : 10.0;

  static const double minFrequencyHz = 0.01;
  static const double minOffsetV = -9.99;
  static const double maxOffsetV = 9.99;
  static const double minDutyPercent = 0.0;
  static const double maxDutyPercent = 100.0;
  static const double minPhaseDegrees = 0.0;
  static const double maxPhaseDegrees = 360.0;
}

/// State of one generator channel as cached by the service.
class Jds6600ChannelState {
  const Jds6600ChannelState({
    this.waveform = Jds6600Waveform.sine,
    this.frequencyHz = 1000.0,
    this.amplitudeVpp = 1.0,
    this.offsetV = 0.0,
    this.dutyPercent = 50.0,
  });

  final Jds6600Waveform waveform;
  final double frequencyHz;
  final double amplitudeVpp;
  final double offsetV;
  final double dutyPercent;

  Jds6600ChannelState copyWith({
    Jds6600Waveform? waveform,
    double? frequencyHz,
    double? amplitudeVpp,
    double? offsetV,
    double? dutyPercent,
  }) {
    return Jds6600ChannelState(
      waveform: waveform ?? this.waveform,
      frequencyHz: frequencyHz ?? this.frequencyHz,
      amplitudeVpp: amplitudeVpp ?? this.amplitudeVpp,
      offsetV: offsetV ?? this.offsetV,
      dutyPercent: dutyPercent ?? this.dutyPercent,
    );
  }

  @override
  String toString() =>
      'Jds6600ChannelState(waveform: $waveform, frequencyHz: $frequencyHz, '
      'amplitudeVpp: $amplitudeVpp, offsetV: $offsetV, '
      'dutyPercent: $dutyPercent)';
}

/// Output-enable state of both channels.
class Jds6600OutputState {
  const Jds6600OutputState({this.ch1 = false, this.ch2 = false});

  final bool ch1;
  final bool ch2;

  Jds6600OutputState copyWith({bool? ch1, bool? ch2}) {
    return Jds6600OutputState(
      ch1: ch1 ?? this.ch1,
      ch2: ch2 ?? this.ch2,
    );
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
  String toString() =>
      cause == null ? message : '$message (cause: $cause)';
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
