/// Register-protocol driver for the JOY-IT / Juntek JDS6600.
///
/// The service used to talk to the register protocol directly. It now lives
/// here so other generator families can implement the same [SiggenDriver]
/// seam while sharing the SCPI layer and state cache.
library;

import '../core/logger.dart';
import 'jds6600_protocol.dart';
import 'jds6600_transport.dart';
import 'models.dart';
import 'siggen_driver.dart';

class Jds6600Driver implements SiggenDriver {
  Jds6600Driver(this._transport);

  final Jds6600Transport _transport;

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
    Jds6600DeviceInfo info;
    try {
      final command = Jds6600Protocol.readCommand(0, count: 2);
      final lines = await _transport.transactMany(
        command,
        count: 2,
        accept: _isRegisterLine,
      );
      final values = Jds6600Protocol.parseRegisterSequence(0, lines);
      info = Jds6600DeviceInfo(
        modelMHz: values[0].first,
        serialNumber: values[1].first,
      );
    } on Jds6600ProtocolException catch (_) {
      // Some firmware variants reject multi-register reads; fall back.
      info = await _readDeviceInfoIndividually();
    } on Jds6600TimeoutException catch (_) {
      // A multi-register read may time out on clones that only support
      // single-register reads; fall back as well.
      info = await _readDeviceInfoIndividually();
    }
    _deviceInfo = info;
    return info;
  }

  Future<Jds6600DeviceInfo> _readDeviceInfoIndividually() async {
    final modelLine = await _transport.transact(
      Jds6600Protocol.readCommand(0),
      accept: _isRegisterLine,
    );
    final serialLine = await _transport.transact(
      Jds6600Protocol.readCommand(1),
      accept: _isRegisterLine,
    );
    return Jds6600DeviceInfo(
      modelMHz: Jds6600Protocol.parseSingleValue(0, modelLine),
      serialNumber: Jds6600Protocol.parseSingleValue(1, serialLine),
    );
  }

  @override
  Future<SiggenStateSnapshot> readState() async {
    List<List<int>> values;
    try {
      final command = Jds6600Protocol.readCommand(20, count: 13);
      final lines = await _transport.transactMany(
        command,
        count: 13,
        accept: _isRegisterLine,
      );
      values = Jds6600Protocol.parseRegisterSequence(20, lines);
    } catch (e) {
      AppLogger(
        agentName: 'SigGen',
        toolName: 'readState',
      ).warning('Multi-register read failed, falling back: $e');
      values = await _readStateIndividually();
    }
    return _decodeState(values);
  }

  Future<List<List<int>>> _readStateIndividually() async {
    final values = <List<int>>[];
    for (var register = 20; register <= 32; register++) {
      final line = await _transport.transact(
        Jds6600Protocol.readCommand(register),
        accept: _isRegisterLine,
      );
      values.add(Jds6600Protocol.parseRegisterResponse(register, line));
    }
    return values;
  }

  SiggenStateSnapshot _decodeState(List<List<int>> values) {
    if (values.length < 13) {
      throw Jds6600ProtocolException(
        'Expected 13 register lines, got ${values.length}',
      );
    }
    final phase = Jds6600Protocol.decodePhase(values[11]);
    return SiggenStateSnapshot(
      outputs: Jds6600Protocol.decodeOutputs(values[0]),
      ch1: Jds6600ChannelState(
        waveform: Jds6600Protocol.decodeWaveform(values[1]),
        frequencyHz: Jds6600Protocol.decodeFrequency(values[3]),
        amplitudeVpp: Jds6600Protocol.decodeAmplitude(values[5]),
        offsetV: Jds6600Protocol.decodeOffset(values[7]),
        dutyPercent: Jds6600Protocol.decodeDuty(values[9]),
        phaseDeg: phase,
      ),
      ch2: Jds6600ChannelState(
        waveform: Jds6600Protocol.decodeWaveform(values[2]),
        frequencyHz: Jds6600Protocol.decodeFrequency(values[4]),
        amplitudeVpp: Jds6600Protocol.decodeAmplitude(values[6]),
        offsetV: Jds6600Protocol.decodeOffset(values[8]),
        dutyPercent: Jds6600Protocol.decodeDuty(values[10]),
        phaseDeg: phase,
      ),
      phaseDeg: phase,
      actionActive: values[12].any((value) => value != 0),
    );
  }

  // ---------------------------------------------------------------------------
  // Channel parameters
  // ---------------------------------------------------------------------------

  @override
  Future<void> setWaveform(int channel, Jds6600Waveform waveform) async {
    if (waveform == Jds6600Waveform.arbitrary) {
      throw const Jds6600RangeException(
        'Arbitrary waveform selection is not supported in stage 1',
      );
    }
    await _writeRegister(
      Jds6600Protocol.waveformRegister(channel),
      Jds6600Protocol.encodeWaveform(waveform),
    );
  }

  @override
  Future<Jds6600Waveform> readWaveform(int channel) async {
    final values = await _readRegisterValues(
      Jds6600Protocol.waveformRegister(channel),
    );
    return Jds6600Protocol.decodeWaveform(values);
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
    Jds6600Protocol.validateFrequency(info, waveform, hz);

    // Verify the readback. A partial serial write can leave the device at
    // 0 Hz; rewriting once recovers it instead of continuing a sweep at 0 Hz.
    final command = Jds6600Protocol.encodeFrequency(hz);
    late double readback;
    for (var attempt = 1; attempt <= 2; attempt++) {
      await _writeRegister(Jds6600Protocol.frequencyRegister(channel), command);
      final values = await _readRegisterValues(
        Jds6600Protocol.frequencyRegister(channel),
      );
      readback = Jds6600Protocol.decodeFrequency(values);
      if ((readback - hz).abs() <= 0.05) return;
      AppLogger(agentName: 'SigGen', toolName: 'setFrequency').warning(
        'Frequency readback mismatch on CH$channel: requested $hz Hz, '
        'got $readback Hz (attempt $attempt/2)',
      );
    }
    throw Jds6600ProtocolException(
      'Frequency write failed on CH$channel: requested $hz Hz, '
      'readback $readback Hz',
    );
  }

  @override
  Future<double> readFrequency(int channel) async {
    final values = await _readRegisterValues(
      Jds6600Protocol.frequencyRegister(channel),
    );
    return Jds6600Protocol.decodeFrequency(values);
  }

  @override
  Future<void> setAmplitude(int channel, double vpp) async {
    final info = _requireInfo();
    final frequency = await readFrequency(channel);
    Jds6600Protocol.validateAmplitude(info, frequency, vpp);
    await _writeRegister(
      Jds6600Protocol.amplitudeRegister(channel),
      Jds6600Protocol.encodeAmplitude(vpp),
    );
  }

  @override
  Future<double> readAmplitude(int channel) async {
    final values = await _readRegisterValues(
      Jds6600Protocol.amplitudeRegister(channel),
    );
    return Jds6600Protocol.decodeAmplitude(values);
  }

  @override
  Future<void> setOffset(int channel, double volts) async {
    Jds6600Protocol.validateOffset(volts);
    await _writeRegister(
      Jds6600Protocol.offsetRegister(channel),
      Jds6600Protocol.encodeOffset(volts),
    );
  }

  @override
  Future<double> readOffset(int channel) async {
    final values = await _readRegisterValues(
      Jds6600Protocol.offsetRegister(channel),
    );
    return Jds6600Protocol.decodeOffset(values);
  }

  @override
  Future<void> setDuty(int channel, double percent) async {
    Jds6600Protocol.validateDuty(percent);
    await _writeRegister(
      Jds6600Protocol.dutyRegister(channel),
      Jds6600Protocol.encodeDuty(percent),
    );
  }

  @override
  Future<double> readDuty(int channel) async {
    final values = await _readRegisterValues(
      Jds6600Protocol.dutyRegister(channel),
    );
    return Jds6600Protocol.decodeDuty(values);
  }

  /// The JDS6600 has one global phase register (CH2 relative to CH1), so the
  /// channel argument does not change the register that is addressed.
  @override
  Future<void> setPhase(int channel, double degrees) async {
    Jds6600Protocol.validatePhase(degrees);
    await _writeRegister(
      Jds6600Protocol.registerPhase,
      Jds6600Protocol.encodePhase(degrees),
    );
  }

  @override
  Future<double> readPhase(int channel) async {
    final values = await _readRegisterValues(Jds6600Protocol.registerPhase);
    return Jds6600Protocol.decodePhase(values);
  }

  @override
  Future<void> setOutput(int channel, bool enabled) async {
    // Read-modify-write: register 20 always sets both channels.
    final values = await _readRegisterValues(Jds6600Protocol.registerOutputs);
    final current = Jds6600Protocol.decodeOutputs(values);
    final next = channel == 1
        ? current.copyWith(ch1: enabled)
        : current.copyWith(ch2: enabled);
    await _writeRegister(
      Jds6600Protocol.registerOutputs,
      Jds6600Protocol.encodeOutputs(next.ch1, next.ch2),
    );
  }

  @override
  Future<bool> readOutput(int channel) async {
    final values = await _readRegisterValues(Jds6600Protocol.registerOutputs);
    final outputs = Jds6600Protocol.decodeOutputs(values);
    return channel == 1 ? outputs.ch1 : outputs.ch2;
  }

  // ---------------------------------------------------------------------------
  // Actions and reset
  // ---------------------------------------------------------------------------

  @override
  Future<void> stopActions() async {
    await _writeRegister(Jds6600Protocol.registerAction, '0,0,0,0');
  }

  @override
  Future<void> resetSafeState() async {
    await _writeRegister(Jds6600Protocol.registerAction, '0,0,0,0');
    await _writeRegister(
      Jds6600Protocol.registerOutputs,
      Jds6600Protocol.encodeOutputs(false, false),
    );
    for (final channel in const [1, 2]) {
      await _writeRegister(
        Jds6600Protocol.waveformRegister(channel),
        Jds6600Protocol.encodeWaveform(Jds6600Waveform.sine),
      );
      await _writeRegister(
        Jds6600Protocol.frequencyRegister(channel),
        Jds6600Protocol.encodeFrequency(1000),
      );
      await _writeRegister(
        Jds6600Protocol.amplitudeRegister(channel),
        Jds6600Protocol.encodeAmplitude(1),
      );
      await _writeRegister(
        Jds6600Protocol.offsetRegister(channel),
        Jds6600Protocol.encodeOffset(0),
      );
      await _writeRegister(
        Jds6600Protocol.dutyRegister(channel),
        Jds6600Protocol.encodeDuty(50),
      );
    }
    await _writeRegister(
      Jds6600Protocol.registerPhase,
      Jds6600Protocol.encodePhase(0),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static bool _isRegisterLine(String line) => line.startsWith(':r');

  Jds6600DeviceInfo _requireInfo() {
    final info = _deviceInfo;
    if (info == null) {
      throw const Jds6600ProtocolException(
        'Signal generator has not been identified',
      );
    }
    return info;
  }

  Future<List<int>> _readRegisterValues(int register) async {
    final line = await _transport.transact(
      Jds6600Protocol.readCommand(register),
      accept: _isRegisterLine,
    );
    return Jds6600Protocol.parseRegisterResponse(register, line);
  }

  Future<void> _writeRegister(int register, String value) async {
    final command = Jds6600Protocol.writeCommand(register, value);
    final response = await _transport.transact(command);
    Jds6600Protocol.ensureAck(response, command);
  }
}
