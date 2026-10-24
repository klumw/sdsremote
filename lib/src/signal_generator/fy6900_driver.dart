/// Command-protocol driver for the FeelElec FY6900.
///
/// The FY6900 has no register map: every parameter is set and read with its
/// own `WM…`/`RM…` command. This driver maps those commands onto the same
/// [SiggenDriver] operations as the JDS6600, so the service and the SCPI
/// layer offer exactly the same commands and syntax for both generators.
///
/// Phase note: the shared SCPI interface exposes one phase value, which the
/// JDS6600 defines as CH2 relative to CH1. The FY6900 has per-channel phase
/// commands, so the shared value is mapped to the auxiliary-channel phase
/// (`WFP`/`RFP`).
library;

import '../core/logger.dart';
import 'fy6900_protocol.dart';
import 'fy6900_transport.dart';
import 'models.dart';
import 'siggen_driver.dart';

class Fy6900Driver implements SiggenDriver {
  Fy6900Driver(this._transport);

  final Fy6900Transport _transport;

  Jds6600DeviceInfo? _deviceInfo;

  @override
  bool get isOpen => _transport.isOpen;

  @override
  Future<void> open() => _transport.open();

  @override
  Future<void> close() => _transport.close();

  // ---------------------------------------------------------------------------
  // Device info and state
  // ---------------------------------------------------------------------------

  @override
  Future<Jds6600DeviceInfo> readDeviceInfo() async {
    final model = await _readRaw(Fy6900Protocol.readModelCommand);
    // The model reply identifies the device; the UID is only informative and
    // is treated as optional so firmware without UID support still works.
    String id;
    try {
      id = await _readRaw(Fy6900Protocol.readIdCommand);
    } on Jds6600TimeoutException {
      id = '0';
    }
    final info = Fy6900Protocol.parseDeviceInfo(model: model, id: id);
    _deviceInfo = info;
    return info;
  }

  @override
  Future<SiggenStateSnapshot> readState() async {
    final ch1 = await _readChannelState(Fy6900Protocol.firstChannel);
    final ch2 = await _readChannelState(Fy6900Protocol.secondChannel);
    final ch1On = await readOutput(Fy6900Protocol.firstChannel);
    final ch2On = await readOutput(Fy6900Protocol.secondChannel);
    return SiggenStateSnapshot(
      outputs: Jds6600OutputState(ch1: ch1On, ch2: ch2On),
      ch1: ch1,
      ch2: ch2,
      phaseDeg: ch2.phaseDeg,
      // The FY6900 has no action register.
      actionActive: false,
    );
  }

  Future<Jds6600ChannelState> _readChannelState(int channel) async {
    return Jds6600ChannelState(
      waveform: await readWaveform(channel),
      frequencyHz: await readFrequency(channel),
      amplitudeVpp: await readAmplitude(channel),
      offsetV: await readOffset(channel),
      dutyPercent: await readDuty(channel),
      phaseDeg: await readPhase(channel),
    );
  }

  // ---------------------------------------------------------------------------
  // Channel parameters
  // ---------------------------------------------------------------------------

  @override
  Future<void> setWaveform(int channel, Jds6600Waveform waveform) async {
    await _write(
      channel,
      Fy6900Parameter.waveform,
      Fy6900Protocol.encodeWaveform(channel, waveform),
    );
  }

  @override
  Future<Jds6600Waveform> readWaveform(int channel) async {
    final value = Fy6900Protocol.parseInteger(
      await _read(channel, Fy6900Parameter.waveform),
    );
    return Fy6900Protocol.decodeWaveform(channel, value);
  }

  @override
  Future<void> setFrequency(int channel, double hz) async {
    final info = _requireInfo();
    final waveform = await readWaveform(channel);
    if (!hz.isFinite || hz <= 0) {
      throw Jds6600RangeException(
        'Refusing to set a non-positive frequency: $hz Hz',
      );
    }
    Fy6900Protocol.validateFrequency(info, waveform, hz);

    // FY6900 firmware expects decimal Hz; older FY firmware expects
    // microhertz. Try the documented FY6900 form first and fall back once.
    final formats = <String>[
      Fy6900Protocol.encodeFrequency(hz),
      Fy6900Protocol.encodeFrequencyMicroHz(hz),
    ];
    var readback = double.nan;
    for (var attempt = 0; attempt < formats.length; attempt++) {
      try {
        await _write(channel, Fy6900Parameter.frequency, formats[attempt]);
        readback = await readFrequency(channel);
        if (readback > 0 &&
            (readback - hz).abs() <= Fy6900Protocol.frequencyToleranceHz(hz)) {
          return;
        }
      } on Jds6600TimeoutException {
        if (attempt == formats.length - 1) rethrow;
      }
      AppLogger(agentName: 'SigGen', toolName: 'setFrequency').warning(
        'FY6900 frequency readback mismatch on CH$channel: requested '
        '${hz.toStringAsFixed(6)} Hz, got ${readback.toStringAsFixed(6)} Hz '
        '(format ${attempt + 1}/${formats.length})',
      );
    }
    throw Jds6600ProtocolException(
      'Frequency write failed on CH$channel: requested '
      '${hz.toStringAsFixed(6)} Hz, '
      'readback ${readback.toStringAsFixed(6)} Hz',
    );
  }

  @override
  Future<double> readFrequency(int channel) async {
    return Fy6900Protocol.decodeFrequency(
      await _read(channel, Fy6900Parameter.frequency),
    );
  }

  @override
  Future<void> setAmplitude(int channel, double vpp) async {
    final info = _requireInfo();
    final frequency = await readFrequency(channel);
    Fy6900Protocol.validateAmplitude(info, frequency, vpp);
    await _write(
      channel,
      Fy6900Parameter.amplitude,
      Fy6900Protocol.encodeAmplitude(vpp),
    );
  }

  @override
  Future<double> readAmplitude(int channel) async {
    return Fy6900Protocol.decodeAmplitude(
      await _read(channel, Fy6900Parameter.amplitude),
    );
  }

  @override
  Future<void> setOffset(int channel, double volts) async {
    final info = _requireInfo();
    final frequency = await readFrequency(channel);
    Fy6900Protocol.validateOffsetAtFrequency(info, frequency, volts);
    await _write(
      channel,
      Fy6900Parameter.offset,
      Fy6900Protocol.encodeOffset(volts),
    );
  }

  @override
  Future<double> readOffset(int channel) async {
    return Fy6900Protocol.decodeOffset(
      await _read(channel, Fy6900Parameter.offset),
    );
  }

  @override
  Future<void> setDuty(int channel, double percent) async {
    Fy6900Protocol.validateDuty(percent);
    // Square (1) is fixed at 50 %; Rectangle (2) is the duty-adjustable
    // shape. Switch an existing square so the duty change takes effect on
    // both channels.
    final waveformIndex = Fy6900Protocol.parseInteger(
      await _read(channel, Fy6900Parameter.waveform),
    );
    if (waveformIndex == Fy6900Protocol.squareWaveformIndex) {
      await _write(
        channel,
        Fy6900Parameter.waveform,
        '${Fy6900Protocol.rectangleWaveformIndex}',
      );
    }
    await _write(
      channel,
      Fy6900Parameter.duty,
      Fy6900Protocol.encodeDuty(percent),
    );
  }

  @override
  Future<double> readDuty(int channel) async {
    return Fy6900Protocol.decodeDuty(
      await _read(channel, Fy6900Parameter.duty),
    );
  }

  @override
  Future<void> setPhase(int channel, double degrees) async {
    Fy6900Protocol.validatePhase(degrees);
    await _write(
      channel,
      Fy6900Parameter.phase,
      Fy6900Protocol.encodePhase(degrees),
    );
  }

  @override
  Future<double> readPhase(int channel) async {
    return Fy6900Protocol.decodePhase(
      await _read(channel, Fy6900Parameter.phase),
    );
  }

  @override
  Future<void> setOutput(int channel, bool enabled) async {
    await _write(
      channel,
      Fy6900Parameter.output,
      Fy6900Protocol.encodeOutput(enabled),
    );
  }

  @override
  Future<bool> readOutput(int channel) async {
    return Fy6900Protocol.decodeOutput(
      await _read(channel, Fy6900Parameter.output),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions and reset
  // ---------------------------------------------------------------------------

  @override
  Future<void> stopActions() async {
    // The FY6900 has no action register; sweeps are controlled explicitly.
  }

  @override
  Future<void> resetSafeState() async {
    for (final channel in const [
      Fy6900Protocol.firstChannel,
      Fy6900Protocol.secondChannel,
    ]) {
      await setOutput(channel, false);
    }
    for (final channel in const [
      Fy6900Protocol.firstChannel,
      Fy6900Protocol.secondChannel,
    ]) {
      await setWaveform(channel, Jds6600Waveform.sine);
      await setFrequency(channel, 1000);
      await setAmplitude(channel, 1);
      await setOffset(channel, 0);
      await setDuty(channel, 50);
      await _write(
        channel,
        Fy6900Parameter.phase,
        Fy6900Protocol.encodePhase(0),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Jds6600DeviceInfo _requireInfo() {
    final info = _deviceInfo;
    if (info == null) {
      throw const Jds6600ProtocolException(
        'Signal generator has not been identified',
      );
    }
    return info;
  }

  Future<String> _readRaw(String command) {
    return _transport.transact(
      command,
      accept: (line) => line.trim().isNotEmpty,
    );
  }

  Future<String> _read(int channel, Fy6900Parameter parameter) {
    return _readRaw(Fy6900Protocol.readCommand(channel, parameter));
  }

  Future<void> _write(
    int channel,
    Fy6900Parameter parameter,
    String value,
  ) async {
    final command = Fy6900Protocol.writeCommand(channel, parameter, value);
    final response = await _transport.transact(command);
    Fy6900Protocol.ensureAck(response, command);
  }
}
