/// Wire protocol codec for the JOY-IT / Juntek JDS6600.
///
/// Framing (from the official JOY-IT protocol document and the on1arf
/// reference implementation):
///
///   write:  `:w<reg>=<value>.` + LF  ->  `:ok` + CRLF
///   read:   `:r<reg>=0.`       + LF  ->  `:r<reg>=<data>.` + CRLF
///
/// Register numbers below 10 are zero-padded (`:r00=`, `:r01=`).
library;

import 'models.dart';

/// Pure register codec and value conversions.
class Jds6600Protocol {
  Jds6600Protocol._();

  // Register map (stage 1).
  static const int registerDeviceType = 0;
  static const int registerSerialNumber = 1;
  static const int registerOutputs = 20;
  static const int registerWaveform1 = 21;
  static const int registerWaveform2 = 22;
  static const int registerFrequency1 = 23;
  static const int registerFrequency2 = 24;
  static const int registerAmplitude1 = 25;
  static const int registerAmplitude2 = 26;
  static const int registerOffset1 = 27;
  static const int registerOffset2 = 28;
  static const int registerDuty1 = 29;
  static const int registerDuty2 = 30;
  static const int registerPhase = 31;
  static const int registerAction = 32;
  static const int registerMode = 33;

  /// The JDS6600 has one global phase register: CH2 relative to CH1.
  static const int firstChannel = 1;
  static const int secondChannel = 2;

  static String registerText(int register) =>
      register < 10 ? register.toString().padLeft(2, '0') : register.toString();

  /// Builds a read command.
  ///
  /// The device returns [count] consecutive `:r<reg>=...` lines; [count] is
  /// encoded as `count - 1` in the command (0 for a single register).
  static String readCommand(int register, {int count = 1}) {
    if (count < 1) {
      throw ArgumentError.value(count, 'count', 'Must be at least 1');
    }
    return ':r${registerText(register)}=${count - 1}.\n';
  }

  static String writeCommand(int register, String value) =>
      ':w${registerText(register)}=$value.\n';

  static String stopActionCommand() =>
      writeCommand(registerAction, '0,0,0,0');

  // ---------------------------------------------------------------------------
  // Channel register selection
  // ---------------------------------------------------------------------------

  static void _checkChannel(int channel) {
    if (channel != firstChannel && channel != secondChannel) {
      throw Jds6600RangeException('Invalid channel $channel (expected 1 or 2)');
    }
  }

  static int waveformRegister(int channel) {
    _checkChannel(channel);
    return channel == firstChannel ? registerWaveform1 : registerWaveform2;
  }

  static int frequencyRegister(int channel) {
    _checkChannel(channel);
    return channel == firstChannel ? registerFrequency1 : registerFrequency2;
  }

  static int amplitudeRegister(int channel) {
    _checkChannel(channel);
    return channel == firstChannel ? registerAmplitude1 : registerAmplitude2;
  }

  static int offsetRegister(int channel) {
    _checkChannel(channel);
    return channel == firstChannel ? registerOffset1 : registerOffset2;
  }

  static int dutyRegister(int channel) {
    _checkChannel(channel);
    return channel == firstChannel ? registerDuty1 : registerDuty2;
  }

  // ---------------------------------------------------------------------------
  // Response parsing
  // ---------------------------------------------------------------------------

  /// Parses `:r<reg>=<data>.` and returns the comma-separated integer payload.
  ///
  /// Accepts both padded (`:r00=`) and unpadded (`:r0=`) echoes.
  static List<int> parseRegisterResponse(int expectedRegister, String line) {
    final trimmed = line.trim();
    final match = RegExp(r'^:r0*(\d+)=(.*)$').firstMatch(trimmed);
    if (match == null) {
      throw Jds6600ProtocolException(
        'Unexpected response "$line" (expected a :r$expectedRegister= reply)',
      );
    }
    final actualRegister = int.tryParse(match.group(1)!);
    if (actualRegister != expectedRegister) {
      throw Jds6600ProtocolException(
        'Register echo mismatch: got ${match.group(1)}, '
        'expected $expectedRegister',
      );
    }

    var payload = match.group(2)!;
    final dot = payload.lastIndexOf('.');
    if (dot >= 0) payload = payload.substring(0, dot);
    payload = payload.trim();
    if (payload.isEmpty) return const <int>[];

    final values = <int>[];
    for (final part in payload.split(',')) {
      final value = int.tryParse(part.trim());
      if (value == null) {
        throw Jds6600ProtocolException(
          'Non-numeric value "${part.trim()}" in response "$line"',
        );
      }
      values.add(value);
    }
    return values;
  }

  /// Parses a single-value register reply.
  static int parseSingleValue(int expectedRegister, String line) {
    final values = parseRegisterResponse(expectedRegister, line);
    if (values.length != 1) {
      throw Jds6600ProtocolException(
        'Expected one value for register $expectedRegister, '
        'got ${values.length}',
      );
    }
    return values.first;
  }

  /// Parses a multi-register reply starting at [firstRegister].
  ///
  /// The device replies with one line per consecutive register, so the
  /// expected register is derived from the line index.
  static List<List<int>> parseRegisterSequence(
    int firstRegister,
    List<String> lines,
  ) {
    final result = <List<int>>[];
    for (var index = 0; index < lines.length; index++) {
      result.add(parseRegisterResponse(firstRegister + index, lines[index]));
    }
    return result;
  }

  static bool isAck(String line) => line.trim().toLowerCase() == ':ok';

  static void ensureAck(String line, String command) {
    if (!isAck(line)) {
      throw Jds6600ProtocolException(
        'Command "$command" was not acknowledged (reply: "$line")',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Device identity
  // ---------------------------------------------------------------------------

  static Jds6600DeviceInfo parseDeviceInfo({
    required int modelMHz,
    required int serialNumber,
  }) {
    return Jds6600DeviceInfo(
      modelMHz: modelMHz,
      serialNumber: serialNumber,
    );
  }

  /// Synthesised SCPI identity. The device has no firmware register, so the
  /// fourth field is deliberately `N/A`.
  static String identify(Jds6600DeviceInfo info) =>
      'JOY-IT,${info.modelName},${info.serialNumber},N/A';

  // ---------------------------------------------------------------------------
  // Value conversions
  // ---------------------------------------------------------------------------

  static String encodeOutputs(bool ch1, bool ch2) =>
      '${ch1 ? 1 : 0},${ch2 ? 1 : 0}';

  static Jds6600OutputState decodeOutputs(List<int> values) {
    if (values.length < 2) {
      throw Jds6600ProtocolException(
        'Output register must contain two values, got ${values.length}',
      );
    }
    return Jds6600OutputState(ch1: values[0] != 0, ch2: values[1] != 0);
  }

  /// Frequency is encoded as `X,Y`, where X uses 0.01 Hz units for Y=0.
  static String encodeFrequency(double hz) => '${(hz * 100).round()},0';

  /// Decodes `X,Y` into Hz.
  ///
  /// Y=0..2 only affects the display and X is always in 0.01 Hz units.
  /// Y=3 and Y=4 change the actual scale (mHz / uHz).
  static double decodeFrequency(List<int> values) {
    if (values.length < 2) {
      throw Jds6600ProtocolException(
        'Frequency register must contain two values, got ${values.length}',
      );
    }
    final x = values[0];
    switch (values[1]) {
      case 0:
      case 1:
      case 2:
        return x / 100.0;
      case 3:
        return x / 100000.0;
      case 4:
        return x / 100000000.0;
      default:
        throw Jds6600ProtocolException(
          'Unknown frequency multiplier ${values[1]}',
        );
    }
  }

  static String encodeAmplitude(double vpp) => '${(vpp * 1000).round()}';

  static double decodeAmplitude(List<int> values) {
    if (values.length != 1) {
      throw Jds6600ProtocolException(
        'Amplitude register must contain one value, got ${values.length}',
      );
    }
    return values.first / 1000.0;
  }

  /// Offset uses 0.01 V units with 1000 representing zero volts.
  static String encodeOffset(double volts) => '${(1000 + volts * 100).round()}';

  static double decodeOffset(List<int> values) {
    if (values.length != 1) {
      throw Jds6600ProtocolException(
        'Offset register must contain one value, got ${values.length}',
      );
    }
    return (values.first - 1000) / 100.0;
  }

  static String encodeDuty(double percent) => '${(percent * 10).round()}';

  static double decodeDuty(List<int> values) {
    if (values.length != 1) {
      throw Jds6600ProtocolException(
        'Duty register must contain one value, got ${values.length}',
      );
    }
    return values.first / 10.0;
  }

  static String encodePhase(double degrees) => '${(degrees * 10).round()}';

  static double decodePhase(List<int> values) {
    if (values.length != 1) {
      throw Jds6600ProtocolException(
        'Phase register must contain one value, got ${values.length}',
      );
    }
    return values.first / 10.0;
  }

  static String encodeWaveform(Jds6600Waveform waveform) =>
      '${waveform.registerValue}';

  static Jds6600Waveform decodeWaveform(List<int> values) {
    if (values.length != 1) {
      throw Jds6600ProtocolException(
        'Waveform register must contain one value, got ${values.length}',
      );
    }
    return Jds6600Waveform.fromRegister(values.first);
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
    if (!hz.isFinite || hz < Jds6600DeviceInfo.minFrequencyHz || hz > max) {
      throw Jds6600RangeException(
        'Frequency ${hz.toStringAsFixed(4)} Hz is outside '
        '${Jds6600DeviceInfo.minFrequencyHz}..${max / 1e6} MHz '
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
    if (!volts.isFinite ||
        volts < Jds6600DeviceInfo.minOffsetV ||
        volts > Jds6600DeviceInfo.maxOffsetV) {
      throw Jds6600RangeException(
        'Offset ${volts.toStringAsFixed(3)} V is outside '
        '${Jds6600DeviceInfo.minOffsetV}..${Jds6600DeviceInfo.maxOffsetV} V',
      );
    }
  }

  static void validateDuty(double percent) {
    if (!percent.isFinite ||
        percent < Jds6600DeviceInfo.minDutyPercent ||
        percent > Jds6600DeviceInfo.maxDutyPercent) {
      throw Jds6600RangeException(
        'Duty ${percent.toStringAsFixed(1)} % is outside '
        '${Jds6600DeviceInfo.minDutyPercent}..'
        '${Jds6600DeviceInfo.maxDutyPercent} %',
      );
    }
  }

  static void validatePhase(double degrees) {
    if (!degrees.isFinite ||
        degrees < Jds6600DeviceInfo.minPhaseDegrees ||
        degrees > Jds6600DeviceInfo.maxPhaseDegrees) {
      throw Jds6600RangeException(
        'Phase ${degrees.toStringAsFixed(1)} deg is outside '
        '${Jds6600DeviceInfo.minPhaseDegrees}..'
        '${Jds6600DeviceInfo.maxPhaseDegrees} deg',
      );
    }
  }
}
