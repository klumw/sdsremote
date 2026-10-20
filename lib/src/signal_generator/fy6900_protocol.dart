/// Command codec for the FeelElec FY6900.
///
/// Framing (FY6900 host-communication protocol, rev 1.8):
///
///   write:  `WM<code><value>` + LF   ->  LF (empty acknowledgement line)
///   read:   `RM<code>`         + LF   ->  `<value>` + LF
///
/// `WM`/`RM` address the main channel (CH1); `WF`/`RF` address the auxiliary
/// channel (CH2). Every command is a single ASCII line terminated by `0x0a`.
/// The FY6900 has no register map: each parameter has its own command.
///
/// Value formats follow the vendor protocol, cross-checked against the
/// open-source `fygen` and `pyfy6900` implementations:
///
///   waveform    plain index (channel-specific numbering)
///   frequency   Hz with six decimals, zero-padded to 15 characters
///   amplitude   volts with three decimals; readback in 0.1 mV units
///   offset      volts with three decimals; readback in 1 mV units, negative
///               values as unsigned 32-bit two's complement
///   duty        percent with one decimal; readback in 0.001 % units
///   phase       degrees with two decimals; readback in 0.001 degree units
///   output      `0` or `1`; readback is `0` or `255`
library;

import 'models.dart';

/// FY6900 parameter codes shared by the `WM`/`RM` command pairs.
enum Fy6900Parameter {
  waveform('W'),
  frequency('F'),
  amplitude('A'),
  offset('O'),
  duty('D'),
  phase('P'),
  output('N');

  const Fy6900Parameter(this.code);

  final String code;
}

/// Pure command codec and value conversions.
class Fy6900Protocol {
  Fy6900Protocol._();

  static const int firstChannel = 1;
  static const int secondChannel = 2;

  /// FY6900 waveform indices relevant to duty-cycle handling.
  ///
  /// Square (1) is the fixed 50 % shape; Rectangle (2) is the
  /// duty-adjustable shape documented in the manual.
  static const int squareWaveformIndex = 1;
  static const int rectangleWaveformIndex = 2;

  /// Minimum frequency the shared SCPI layer accepts (1 uHz on the device).
  static const double minFrequencyHz = 0.000001;

  /// FY6900 DC-offset range for frequencies up to 20 MHz.
  static const double minOffsetV = -12.0;
  static const double maxOffsetV = 12.0;

  /// Rectangular duty-cycle range specified by the FY6900 manual.
  static const double minDutyPercent = 0.1;
  static const double maxDutyPercent = 99.9;

  static const double minPhaseDegrees = 0.0;
  static const double maxPhaseDegrees = 360.0;

  /// Tolerance for frequency readback verification.
  ///
  /// The FY6900 firmware can report the frequency with a ~0.066 Hz rounding
  /// error (observed on hardware: 174.668135 Hz requested, 174.602599 Hz
  /// read back). Allow 0.1 Hz plus a 10 ppm relative margin so higher sweep
  /// points are not rejected by the same firmware behaviour. A zero readback
  /// is still treated as a failed write by the driver.
  static double frequencyToleranceHz(double hz) =>
      (hz.abs() * 1e-5).clamp(0.1, 1000.0).toDouble();

  // ---------------------------------------------------------------------------
  // Framing
  // ---------------------------------------------------------------------------

  static void _checkChannel(int channel) {
    if (channel != firstChannel && channel != secondChannel) {
      throw Jds6600RangeException('Invalid channel $channel (expected 1 or 2)');
    }
  }

  /// Write prefix: `WM` for CH1, `WF` for CH2.
  static String writePrefix(int channel) {
    _checkChannel(channel);
    return channel == firstChannel ? 'WM' : 'WF';
  }

  /// Read prefix: `RM` for CH1, `RF` for CH2.
  static String readPrefix(int channel) {
    _checkChannel(channel);
    return channel == firstChannel ? 'RM' : 'RF';
  }

  static String readCommand(int channel, Fy6900Parameter parameter) =>
      '${readPrefix(channel)}${parameter.code}\n';

  static String writeCommand(
    int channel,
    Fy6900Parameter parameter,
    String value,
  ) => '${writePrefix(channel)}${parameter.code}$value\n';

  /// Reads the model string (`UMO`).
  static const String readModelCommand = 'UMO\n';

  /// Reads the instrument ID (`UID`).
  static const String readIdCommand = 'UID\n';

  /// The FY6900 acknowledges a write with a bare line feed; some firmware
  /// variants answer `ok` instead.
  static bool isAck(String line) {
    final trimmed = line.trim().toLowerCase();
    return trimmed.isEmpty || trimmed == 'ok';
  }

  static void ensureAck(String line, String command) {
    if (!isAck(line)) {
      throw Jds6600ProtocolException(
        'Command "$command" was not acknowledged (reply: "$line")',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Response parsing
  // ---------------------------------------------------------------------------

  static String parseValue(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      throw const Jds6600ProtocolException('Empty response from device');
    }
    return trimmed;
  }

  static int parseInteger(String line) {
    final text = parseValue(line);
    final value = int.tryParse(text);
    if (value == null) {
      throw Jds6600ProtocolException('Expected an integer, got "$text"');
    }
    return value;
  }

  static double parseNumber(String line) {
    final text = parseValue(line);
    final value = double.tryParse(text);
    if (value == null) {
      throw Jds6600ProtocolException('Expected a number, got "$text"');
    }
    return value;
  }

  // ---------------------------------------------------------------------------
  // Device identity
  // ---------------------------------------------------------------------------

  static final RegExp _modelPattern = RegExp(
    // Accepts FY6900-30M, FY6900-60M and the shortened FY6900-60.
    r'FY6900[- _]?(\d+)\s*M?',
    caseSensitive: false,
  );

  /// Builds device information from the `UMO` and `UID` replies.
  ///
  /// The model suffix is the sine-wave upper limit in MHz (for example
  /// `FY6900-60M`). If the reply omits it, the conservative 20 MHz class is
  /// assumed so out-of-range commands are not sent to a smaller model.
  static Jds6600DeviceInfo parseDeviceInfo({
    required String model,
    required String id,
  }) {
    final modelText = parseValue(model);
    final match = _modelPattern.firstMatch(modelText);
    final modelMHz = match == null ? 0 : int.parse(match.group(1)!);
    final serialNumber = int.tryParse(parseValue(id)) ?? 0;
    return Jds6600DeviceInfo(
      modelMHz: modelMHz > 0 ? modelMHz : 20,
      serialNumber: serialNumber,
      family: SiggenFamily.fy6900,
      modelNameOverride: modelText,
    );
  }

  // ---------------------------------------------------------------------------
  // Value conversions
  // ---------------------------------------------------------------------------

  /// FY6900 firmware expects Hz with six decimals, zero-padded to 15
  /// characters (for example `00010000.000000` for 10 kHz).
  static String encodeFrequency(double hz) =>
      hz.toStringAsFixed(6).padLeft(15, '0');

  /// Legacy FY firmware expects a 14-digit integer in microhertz.
  static String encodeFrequencyMicroHz(double hz) =>
      (hz * 1e6).round().toString().padLeft(14, '0');

  static double decodeFrequency(String line) => parseNumber(line);

  static String encodeAmplitude(double vpp) => vpp.toStringAsFixed(3);

  /// Readback is in 0.1 mV units.
  static double decodeAmplitude(String line) => parseInteger(line) / 10000.0;

  static String encodeOffset(double volts) => volts.toStringAsFixed(3);

  /// Readback is in 1 mV units. Negative offsets are reported as unsigned
  /// 32-bit two's-complement values on some firmware versions.
  static double decodeOffset(String line) {
    var raw = parseInteger(line);
    if (raw > 0x7FFFFFFF) raw -= 0x100000000;
    return raw / 1000.0;
  }

  static String encodeDuty(double percent) => percent.toStringAsFixed(1);

  /// Readback is in 0.001 % units.
  static double decodeDuty(String line) => parseInteger(line) / 1000.0;

  static String encodePhase(double degrees) {
    var normalized = degrees % 360;
    if (normalized < 0) normalized += 360;
    return normalized.toStringAsFixed(2);
  }

  /// Readback is in 0.001 degree units.
  static double decodePhase(String line) => parseInteger(line) / 1000.0;

  static String encodeOutput(bool enabled) => enabled ? '1' : '0';

  static bool decodeOutput(String line) => parseInteger(line) != 0;

  // ---------------------------------------------------------------------------
  // Waveform mapping
  // ---------------------------------------------------------------------------

  /// Maps the shared waveform enum to the FY6900 index for [channel].
  ///
  /// The main and auxiliary channels use different numbering (CH2 omits the
  /// adjustable-pulse entry). Waveforms without an exact FY6900 counterpart
  /// map to the closest available shape.
  static int waveformIndex(int channel, Jds6600Waveform waveform) {
    _checkChannel(channel);
    if (channel == secondChannel) {
      return switch (waveform) {
        Jds6600Waveform.sine => 0,
        // Rectangle is the duty-adjustable square on the FY6900.
        Jds6600Waveform.square => rectangleWaveformIndex,
        // CH2 has no adjustable pulse; a duty-adjustable rectangle is the
        // closest shape.
        Jds6600Waveform.pulse => rectangleWaveformIndex,
        Jds6600Waveform.triangle => 6,
        Jds6600Waveform.partialSine => 0,
        Jds6600Waveform.cmos => 4,
        Jds6600Waveform.dc => 5,
        Jds6600Waveform.halfWave => 22,
        Jds6600Waveform.fullWave => 20,
        Jds6600Waveform.positiveLadder => 10,
        Jds6600Waveform.negativeLadder => 11,
        Jds6600Waveform.noise => 26,
        Jds6600Waveform.expRise => 12,
        Jds6600Waveform.expDecay => 13,
        Jds6600Waveform.multiTone => 25,
        Jds6600Waveform.sinc => 29,
        Jds6600Waveform.lorenz => 24,
        Jds6600Waveform.arbitrary => throw const Jds6600RangeException(
          'Arbitrary waveform selection is not supported in stage 1',
        ),
      };
    }
    return switch (waveform) {
      Jds6600Waveform.sine => 0,
      // Rectangle is the duty-adjustable square on the FY6900.
      Jds6600Waveform.square => rectangleWaveformIndex,
      Jds6600Waveform.pulse => 5,
      Jds6600Waveform.triangle => 7,
      Jds6600Waveform.partialSine => 0,
      Jds6600Waveform.cmos => 4,
      Jds6600Waveform.dc => 6,
      Jds6600Waveform.halfWave => 23,
      Jds6600Waveform.fullWave => 21,
      Jds6600Waveform.positiveLadder => 11,
      Jds6600Waveform.negativeLadder => 12,
      Jds6600Waveform.noise => 27,
      Jds6600Waveform.expRise => 13,
      Jds6600Waveform.expDecay => 14,
      Jds6600Waveform.multiTone => 26,
      Jds6600Waveform.sinc => 30,
      Jds6600Waveform.lorenz => 25,
      Jds6600Waveform.arbitrary => throw const Jds6600RangeException(
        'Arbitrary waveform selection is not supported in stage 1',
      ),
    };
  }

  static String encodeWaveform(int channel, Jds6600Waveform waveform) =>
      '${waveformIndex(channel, waveform)}';

  /// Main-channel indices 0..36; indices 37..99 select arbitrary slots 1..64.
  static const List<Jds6600Waveform> _mainWaveforms = [
    Jds6600Waveform.sine, // 0
    Jds6600Waveform.square, // 1
    Jds6600Waveform.square, // 2 rectangle
    Jds6600Waveform.triangle, // 3 trapezoid
    Jds6600Waveform.cmos, // 4
    Jds6600Waveform.pulse, // 5 adjustable pulse
    Jds6600Waveform.dc, // 6
    Jds6600Waveform.triangle, // 7
    Jds6600Waveform.triangle, // 8 ramp
    Jds6600Waveform.triangle, // 9 negative ramp
    Jds6600Waveform.positiveLadder, // 10 stair triangle
    Jds6600Waveform.positiveLadder, // 11 stairstep
    Jds6600Waveform.negativeLadder, // 12 negative stair
    Jds6600Waveform.expRise, // 13 positive exponential
    Jds6600Waveform.expDecay, // 14 negative exponential
    Jds6600Waveform.expDecay, // 15 positive falling exponential
    Jds6600Waveform.expDecay, // 16 negative falling exponential
    Jds6600Waveform.expRise, // 17 positive logarithm
    Jds6600Waveform.expDecay, // 18 negative logarithm
    Jds6600Waveform.expDecay, // 19 positive falling logarithm
    Jds6600Waveform.expDecay, // 20 negative falling logarithm
    Jds6600Waveform.fullWave, // 21 positive full wave
    Jds6600Waveform.fullWave, // 22 negative full wave
    Jds6600Waveform.halfWave, // 23 positive half wave
    Jds6600Waveform.halfWave, // 24 negative half wave
    Jds6600Waveform.lorenz, // 25 Lorentz pulse
    Jds6600Waveform.multiTone, // 26 multitone
    Jds6600Waveform.noise, // 27 random noise
    Jds6600Waveform.partialSine, // 28 ECG
    Jds6600Waveform.triangle, // 29 trapezoidal pulse
    Jds6600Waveform.sinc, // 30 sinc pulse
    Jds6600Waveform.pulse, // 31 impulse
    Jds6600Waveform.noise, // 32 AWGN
    Jds6600Waveform.partialSine, // 33 AM
    Jds6600Waveform.partialSine, // 34 FM
    Jds6600Waveform.partialSine, // 35 chirp
    Jds6600Waveform.pulse, // 36 impulse
  ];

  /// Auxiliary-channel indices 0..35; indices 36..98 select arbitrary slots.
  static const List<Jds6600Waveform> _auxWaveforms = [
    Jds6600Waveform.sine, // 0
    Jds6600Waveform.square, // 1
    Jds6600Waveform.square, // 2 rectangle
    Jds6600Waveform.triangle, // 3 trapezoid
    Jds6600Waveform.cmos, // 4
    Jds6600Waveform.dc, // 5
    Jds6600Waveform.triangle, // 6
    Jds6600Waveform.triangle, // 7 ramp
    Jds6600Waveform.triangle, // 8 negative ramp
    Jds6600Waveform.positiveLadder, // 9 stair triangle
    Jds6600Waveform.positiveLadder, // 10 stairstep
    Jds6600Waveform.negativeLadder, // 11 negative stair
    Jds6600Waveform.expRise, // 12 positive exponential
    Jds6600Waveform.expDecay, // 13 negative exponential
    Jds6600Waveform.expDecay, // 14 positive falling exponential
    Jds6600Waveform.expDecay, // 15 negative falling exponential
    Jds6600Waveform.expRise, // 16 positive logarithm
    Jds6600Waveform.expDecay, // 17 negative logarithm
    Jds6600Waveform.expDecay, // 18 positive falling logarithm
    Jds6600Waveform.expDecay, // 19 negative falling logarithm
    Jds6600Waveform.fullWave, // 20 positive full wave
    Jds6600Waveform.fullWave, // 21 negative full wave
    Jds6600Waveform.halfWave, // 22 positive half wave
    Jds6600Waveform.halfWave, // 23 negative half wave
    Jds6600Waveform.lorenz, // 24 Lorentz pulse
    Jds6600Waveform.multiTone, // 25 multit
    Jds6600Waveform.noise, // 26 random noise
    Jds6600Waveform.partialSine, // 27 ECG
    Jds6600Waveform.triangle, // 28 trapezoidal pulse
    Jds6600Waveform.sinc, // 29 sinc pulse
    Jds6600Waveform.pulse, // 30 impulse
    Jds6600Waveform.noise, // 31 AWGN
    Jds6600Waveform.partialSine, // 32 AM
    Jds6600Waveform.partialSine, // 33 FM
    Jds6600Waveform.partialSine, // 34 chirp
    Jds6600Waveform.pulse, // 35 impulse
  ];

  static Jds6600Waveform decodeWaveform(int channel, int index) {
    _checkChannel(channel);
    if (index < 0) {
      throw Jds6600ProtocolException(
        'Invalid waveform index $index on CH$channel',
      );
    }
    final table = channel == firstChannel ? _mainWaveforms : _auxWaveforms;
    if (index < table.length) return table[index];
    return Jds6600Waveform.arbitrary;
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  static void validateFrequency(
    Jds6600DeviceInfo info,
    Jds6600Waveform waveform,
    double hz,
  ) {
    final max = info.maxFrequencyHz(waveform);
    if (!hz.isFinite || hz < minFrequencyHz || hz > max) {
      throw Jds6600RangeException(
        'Frequency ${hz.toStringAsFixed(6)} Hz is outside '
        '$minFrequencyHz..${max / 1e6} MHz '
        'for ${waveform.displayName}',
      );
    }
  }

  static void validateAmplitude(
    Jds6600DeviceInfo info,
    double frequencyHz,
    double vpp,
  ) {
    final max = info.maxAmplitudeVpp(frequencyHz);
    if (!vpp.isFinite || vpp < 0 || vpp > max) {
      throw Jds6600RangeException(
        'Amplitude ${vpp.toStringAsFixed(3)} Vpp is outside 0..$max Vpp '
        'at ${frequencyHz / 1e6} MHz',
      );
    }
  }

  static void validateOffset(double volts) {
    if (!volts.isFinite || volts < minOffsetV || volts > maxOffsetV) {
      throw Jds6600RangeException(
        'Offset ${volts.toStringAsFixed(3)} V is outside '
        '$minOffsetV..$maxOffsetV V',
      );
    }
  }

  /// Validates the offset against the frequency-dependent FY6900 range
  /// (±12 V up to 20 MHz, ±2.5 V above).
  static void validateOffsetAtFrequency(
    Jds6600DeviceInfo info,
    double frequencyHz,
    double volts,
  ) {
    final max = info.maxOffsetVAt(frequencyHz);
    if (!volts.isFinite || volts < -max || volts > max) {
      throw Jds6600RangeException(
        'Offset ${volts.toStringAsFixed(3)} V is outside '
        '${(-max).toStringAsFixed(2)}..${max.toStringAsFixed(2)} V '
        'at ${frequencyHz / 1e6} MHz',
      );
    }
  }

  static void validateDuty(double percent) {
    if (!percent.isFinite ||
        percent < minDutyPercent ||
        percent > maxDutyPercent) {
      throw Jds6600RangeException(
        'Duty ${percent.toStringAsFixed(1)} % is outside '
        '$minDutyPercent..$maxDutyPercent %',
      );
    }
  }

  static void validatePhase(double degrees) {
    if (!degrees.isFinite ||
        degrees < minPhaseDegrees ||
        degrees > maxPhaseDegrees) {
      throw Jds6600RangeException(
        'Phase ${degrees.toStringAsFixed(1)} deg is outside '
        '$minPhaseDegrees..$maxPhaseDegrees deg',
      );
    }
  }
}
