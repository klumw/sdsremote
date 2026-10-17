/// Signal-generator facade: connection lifecycle, cached state, command queue,
/// readback and polling.
///
/// The service is deliberately independent of Flutter widgets and of the
/// Siglent instrument path. It owns one serial transport at a time and
/// serialises every transaction through a single operation queue.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/logger.dart';
import 'jds6600_protocol.dart';
import 'jds6600_transport.dart';
import 'models.dart';
import 'siggen_scpi.dart';

typedef Jds6600TransportFactory = Jds6600Transport Function(String port);

class SignalGeneratorService extends ChangeNotifier
    implements SiggenScpiTarget {
  SignalGeneratorService({
    required Jds6600TransportFactory transportFactory,
    this.pollInterval = const Duration(seconds: 1),
  }) : _transportFactory = transportFactory {
    _scpi = SiggenScpiInterpreter(this);
  }

  final Jds6600TransportFactory _transportFactory;
  final Duration pollInterval;
  late final SiggenScpiInterpreter _scpi;

  Jds6600Transport? _transport;
  String? _port;
  Jds6600DeviceInfo? _deviceInfo;
  Jds6600ChannelState _ch1 = const Jds6600ChannelState();
  Jds6600ChannelState _ch2 = const Jds6600ChannelState();
  Jds6600OutputState _outputs = const Jds6600OutputState();
  double _phaseDeg = 0;
  bool _actionActive = false;
  DateTime? _lastRefresh;
  String? _lastError;
  bool _busy = false;
  bool _disposed = false;
  bool _panelActive = false;
  Timer? _pollTimer;
  int _pollFailures = 0;
  final Queue<ScpiError> _errors = Queue<ScpiError>();
  Future<void> _tail = Future<void>.value();

  static const int _maxQueuedErrors = 16;

  // ---------------------------------------------------------------------------
  // Read-only state
  // ---------------------------------------------------------------------------

  bool get isConnected => _transport?.isOpen ?? false;

  String? get port => _port;

  @override
  Jds6600DeviceInfo? get deviceInfo => _deviceInfo;

  Jds6600ChannelState get ch1 => _ch1;

  Jds6600ChannelState get ch2 => _ch2;

  Jds6600ChannelState channel(int channel) => channel == 1 ? _ch1 : _ch2;

  Jds6600OutputState get outputs => _outputs;

  double get phaseDeg => _phaseDeg;

  bool get actionActive => _actionActive;

  DateTime? get lastRefresh => _lastRefresh;

  String? get lastError => _lastError;

  bool get busy => _busy;

  // ---------------------------------------------------------------------------
  // Connection lifecycle
  // ---------------------------------------------------------------------------

  Future<void> connect(String portName) => _guard(() async {
    await _enqueue(() => _connectInternal(portName));
  });

  Future<void> _connectInternal(String portName) async {
    if (isConnected && _port == portName) return;
    await _disconnectInternal();

    final transport = _transportFactory(portName);
    try {
      await transport.open();
      _transport = transport;
      _port = portName;
      await _readDeviceInfoInternal();
      await _readStateInternal();
      _lastError = null;
      _pollFailures = 0;
      _startPollingIfNeeded();
      _notify();
    } catch (e) {
      _transport = null;
      _port = null;
      try {
        await transport.close();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> disconnect() => _guard(() async {
    await _enqueue(_disconnectInternal);
  });

  Future<void> _disconnectInternal() async {
    _stopPolling();
    final transport = _transport;
    _transport = null;
    _port = null;
    _deviceInfo = null;
    _actionActive = false;
    _lastError = null;
    _notify();
    if (transport != null) {
      try {
        await transport.close();
      } catch (e) {
        AppLogger(
          agentName: 'SigGen',
          toolName: 'disconnect',
        ).log('Error closing serial port: $e');
      }
    }
  }

  /// Tests a port without disturbing a connection to a different port.
  Future<String> testConnection(String portName) async {
    if (isConnected && _port == portName) {
      try {
        await _enqueue(_readDeviceInfoInternal);
        final info = _deviceInfo;
        if (info == null) return 'FAILURE: no device information';
        return 'SUCCESS: ${info.modelName}, serial ${info.serialNumber}';
      } catch (e) {
        return 'FAILURE: $e';
      }
    }

    final transport = _transportFactory(portName);
    try {
      await transport.open();
      final info = await _readDeviceInfoFrom(transport);
      return 'SUCCESS: ${info.modelName}, serial ${info.serialNumber}';
    } catch (e) {
      return 'FAILURE: $e';
    } finally {
      try {
        await transport.close();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Typed setters
  // ---------------------------------------------------------------------------

  @override
  Future<void> setWaveform(int channel, Jds6600Waveform waveform) =>
      _guard(() async {
        await _enqueue(() => _setWaveformInternal(channel, waveform));
      });

  Future<void> _setWaveformInternal(
    int channel,
    Jds6600Waveform waveform,
  ) async {
    if (waveform == Jds6600Waveform.arbitrary) {
      throw const Jds6600RangeException(
        'Arbitrary waveform selection is not supported in stage 1',
      );
    }
    await _writeRegister(
      Jds6600Protocol.waveformRegister(channel),
      Jds6600Protocol.encodeWaveform(waveform),
    );
    _updateChannel(
      channel,
      channel == 1
          ? _ch1.copyWith(waveform: waveform)
          : _ch2.copyWith(waveform: waveform),
    );
  }

  @override
  Future<void> setFrequency(int channel, double hz) => _guard(() async {
    await _enqueue(() => _setFrequencyInternal(channel, hz));
  });

  Future<void> _setFrequencyInternal(int channel, double hz) async {
    final info = _requireInfo();
    final state = channel == 1 ? _ch1 : _ch2;
    if (!hz.isFinite || hz <= 0) {
      throw Jds6600RangeException(
        'Refusing to set a non-positive frequency: $hz Hz',
      );
    }
    Jds6600Protocol.validateFrequency(info, state.waveform, hz);

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
      if ((readback - hz).abs() <= 0.05) {
        _updateChannel(channel, state.copyWith(frequencyHz: hz));
        return;
      }
      AppLogger(agentName: 'SigGen', toolName: 'setFrequency').log(
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
  Future<void> setAmplitude(int channel, double vpp) => _guard(() async {
    await _enqueue(() => _setAmplitudeInternal(channel, vpp));
  });

  Future<void> _setAmplitudeInternal(int channel, double vpp) async {
    final info = _requireInfo();
    final state = channel == 1 ? _ch1 : _ch2;
    Jds6600Protocol.validateAmplitude(info, state.frequencyHz, vpp);
    await _writeRegister(
      Jds6600Protocol.amplitudeRegister(channel),
      Jds6600Protocol.encodeAmplitude(vpp),
    );
    _updateChannel(channel, state.copyWith(amplitudeVpp: vpp));
  }

  @override
  Future<void> setOffset(int channel, double volts) => _guard(() async {
    await _enqueue(() => _setOffsetInternal(channel, volts));
  });

  Future<void> _setOffsetInternal(int channel, double volts) async {
    Jds6600Protocol.validateOffset(volts);
    final state = channel == 1 ? _ch1 : _ch2;
    await _writeRegister(
      Jds6600Protocol.offsetRegister(channel),
      Jds6600Protocol.encodeOffset(volts),
    );
    _updateChannel(channel, state.copyWith(offsetV: volts));
  }

  @override
  Future<void> setDuty(int channel, double percent) => _guard(() async {
    await _enqueue(() => _setDutyInternal(channel, percent));
  });

  Future<void> _setDutyInternal(int channel, double percent) async {
    Jds6600Protocol.validateDuty(percent);
    final state = channel == 1 ? _ch1 : _ch2;
    await _writeRegister(
      Jds6600Protocol.dutyRegister(channel),
      Jds6600Protocol.encodeDuty(percent),
    );
    _updateChannel(channel, state.copyWith(dutyPercent: percent));
  }

  @override
  Future<void> setPhase(double degrees) => _guard(() async {
    await _enqueue(() => _setPhaseInternal(degrees));
  });

  Future<void> _setPhaseInternal(double degrees) async {
    Jds6600Protocol.validatePhase(degrees);
    await _writeRegister(
      Jds6600Protocol.registerPhase,
      Jds6600Protocol.encodePhase(degrees),
    );
    _phaseDeg = degrees;
    _notify();
  }

  @override
  Future<void> setOutput(int channel, bool enabled) => _guard(() async {
    await _enqueue(() => _setOutputInternal(channel, enabled));
  });

  Future<void> _setOutputInternal(int channel, bool enabled) async {
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
    _outputs = next;
    _notify();
  }

  // ---------------------------------------------------------------------------
  // Typed readers (used by the SCPI layer)
  // ---------------------------------------------------------------------------

  @override
  Future<Jds6600Waveform> readWaveform(int channel) => _enqueue(() async {
    final values = await _readRegisterValues(
      Jds6600Protocol.waveformRegister(channel),
    );
    return Jds6600Protocol.decodeWaveform(values);
  });

  @override
  Future<double> readFrequency(int channel) => _enqueue(() async {
    final values = await _readRegisterValues(
      Jds6600Protocol.frequencyRegister(channel),
    );
    return Jds6600Protocol.decodeFrequency(values);
  });

  @override
  Future<double> readAmplitude(int channel) => _enqueue(() async {
    final values = await _readRegisterValues(
      Jds6600Protocol.amplitudeRegister(channel),
    );
    return Jds6600Protocol.decodeAmplitude(values);
  });

  @override
  Future<double> readOffset(int channel) => _enqueue(() async {
    final values = await _readRegisterValues(
      Jds6600Protocol.offsetRegister(channel),
    );
    return Jds6600Protocol.decodeOffset(values);
  });

  @override
  Future<double> readDuty(int channel) => _enqueue(() async {
    final values = await _readRegisterValues(
      Jds6600Protocol.dutyRegister(channel),
    );
    return Jds6600Protocol.decodeDuty(values);
  });

  @override
  Future<double> readPhase() => _enqueue(() async {
    final values = await _readRegisterValues(Jds6600Protocol.registerPhase);
    return Jds6600Protocol.decodePhase(values);
  });

  @override
  Future<bool> readOutput(int channel) => _enqueue(() async {
    final values = await _readRegisterValues(Jds6600Protocol.registerOutputs);
    final outputs = Jds6600Protocol.decodeOutputs(values);
    return channel == 1 ? outputs.ch1 : outputs.ch2;
  });

  // ---------------------------------------------------------------------------
  // Readback / reset
  // ---------------------------------------------------------------------------

  @override
  Future<void> refreshDeviceInfo() => _enqueue(_readDeviceInfoInternal);

  Future<void> _readDeviceInfoInternal() async {
    final transport = _requireTransport();
    final info = await _readDeviceInfoFrom(transport);
    _deviceInfo = info;
    _notify();
  }

  Future<Jds6600DeviceInfo> _readDeviceInfoFrom(
    Jds6600Transport transport,
  ) async {
    final command = Jds6600Protocol.readCommand(0, count: 2);
    try {
      final lines = await transport.transactMany(
        command,
        count: 2,
        accept: (line) => line.startsWith(':r'),
      );
      final values = Jds6600Protocol.parseRegisterSequence(0, lines);
      return Jds6600DeviceInfo(
        modelMHz: values[0].first,
        serialNumber: values[1].first,
      );
    } on Jds6600ProtocolException catch (_) {
      // Some firmware variants reject multi-register reads; fall back.
      final modelLine = await transport.transact(
        Jds6600Protocol.readCommand(0),
        accept: (line) => line.startsWith(':r'),
      );
      final serialLine = await transport.transact(
        Jds6600Protocol.readCommand(1),
        accept: (line) => line.startsWith(':r'),
      );
      return Jds6600DeviceInfo(
        modelMHz: Jds6600Protocol.parseSingleValue(0, modelLine),
        serialNumber: Jds6600Protocol.parseSingleValue(1, serialLine),
      );
    } on Jds6600TimeoutException catch (_) {
      // A multi-register read may time out on clones that only support
      // single-register reads; fall back as well.
      final modelLine = await transport.transact(
        Jds6600Protocol.readCommand(0),
        accept: (line) => line.startsWith(':r'),
      );
      final serialLine = await transport.transact(
        Jds6600Protocol.readCommand(1),
        accept: (line) => line.startsWith(':r'),
      );
      return Jds6600DeviceInfo(
        modelMHz: Jds6600Protocol.parseSingleValue(0, modelLine),
        serialNumber: Jds6600Protocol.parseSingleValue(1, serialLine),
      );
    }
  }

  Future<void> refreshAll() => _enqueue(_readStateInternal);

  Future<void> _readStateInternal() async {
    final transport = _requireTransport();
    List<List<int>> values;
    try {
      final command = Jds6600Protocol.readCommand(20, count: 13);
      final lines = await transport.transactMany(
        command,
        count: 13,
        accept: (line) => line.startsWith(':r'),
      );
      values = Jds6600Protocol.parseRegisterSequence(20, lines);
    } catch (e) {
      AppLogger(
        agentName: 'SigGen',
        toolName: 'readState',
      ).log('Multi-register read failed, falling back: $e');
      values = await _readStateIndividually(transport);
    }
    _applyRegisterValues(values);
  }

  Future<List<List<int>>> _readStateIndividually(
    Jds6600Transport transport,
  ) async {
    final values = <List<int>>[];
    for (var register = 20; register <= 32; register++) {
      final line = await transport.transact(
        Jds6600Protocol.readCommand(register),
        accept: (response) => response.startsWith(':r'),
      );
      values.add(Jds6600Protocol.parseRegisterResponse(register, line));
    }
    return values;
  }

  void _applyRegisterValues(List<List<int>> values) {
    if (values.length < 13) {
      throw Jds6600ProtocolException(
        'Expected 13 register lines, got ${values.length}',
      );
    }
    _outputs = Jds6600Protocol.decodeOutputs(values[0]);
    _ch1 = Jds6600ChannelState(
      waveform: Jds6600Protocol.decodeWaveform(values[1]),
      frequencyHz: Jds6600Protocol.decodeFrequency(values[3]),
      amplitudeVpp: Jds6600Protocol.decodeAmplitude(values[5]),
      offsetV: Jds6600Protocol.decodeOffset(values[7]),
      dutyPercent: Jds6600Protocol.decodeDuty(values[9]),
    );
    _ch2 = Jds6600ChannelState(
      waveform: Jds6600Protocol.decodeWaveform(values[2]),
      frequencyHz: Jds6600Protocol.decodeFrequency(values[4]),
      amplitudeVpp: Jds6600Protocol.decodeAmplitude(values[6]),
      offsetV: Jds6600Protocol.decodeOffset(values[8]),
      dutyPercent: Jds6600Protocol.decodeDuty(values[10]),
    );
    _phaseDeg = Jds6600Protocol.decodePhase(values[11]);
    _actionActive = values[12].any((value) => value != 0);
    _lastRefresh = DateTime.now();
    _notify();
  }

  Future<void> stopActions() => _guard(() async {
    await _enqueue(() async {
      await _writeRegister(Jds6600Protocol.registerAction, '0,0,0,0');
      _actionActive = false;
      _notify();
    });
  });

  @override
  Future<void> resetSafeState() => _guard(() async {
    await _enqueue(_resetSafeStateInternal);
  });

  Future<void> _resetSafeStateInternal() async {
    _requireTransport();
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

    _ch1 = const Jds6600ChannelState();
    _ch2 = const Jds6600ChannelState();
    _outputs = const Jds6600OutputState();
    _phaseDeg = 0;
    _actionActive = false;
    _lastRefresh = DateTime.now();
    _notify();
  }

  // ---------------------------------------------------------------------------
  // SCPI
  // ---------------------------------------------------------------------------

  Future<String?> executeScpi(String line) => _scpi.execute(line);

  @override
  void pushError(ScpiError error) {
    if (_errors.length >= _maxQueuedErrors) {
      _errors.removeLast();
      _errors.addLast(const ScpiError(-350, 'Queue overflow'));
      return;
    }
    _errors.addLast(error);
  }

  @override
  ScpiError? popError() => _errors.isEmpty ? null : _errors.removeFirst();

  @override
  void clearErrors() => _errors.clear();

  @override
  int get errorCount => _errors.length;

  // ---------------------------------------------------------------------------
  // Polling
  // ---------------------------------------------------------------------------

  void setPanelActive(bool active) {
    if (_panelActive == active) return;
    _panelActive = active;
    if (active) {
      _startPollingIfNeeded();
    } else {
      _stopPolling();
    }
  }

  void _startPollingIfNeeded() {
    _stopPolling();
    if (!_panelActive || !isConnected || pollInterval <= Duration.zero) return;
    _pollTimer = Timer(pollInterval, _pollTick);
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollTick() async {
    _pollTimer = null;
    if (!_panelActive || !isConnected) return;
    if (!_busy) {
      try {
        await refreshAll();
        _pollFailures = 0;
      } catch (e) {
        _pollFailures++;
        _lastError = e.toString();
        AppLogger(
          agentName: 'SigGen',
          toolName: 'poll',
        ).log('Poll failed ($_pollFailures): $e');
        if (_pollFailures >= 3) {
          await _guard(() async {
            await _enqueue(_disconnectInternal);
          });
          _lastError = 'Signal generator disconnected: $e';
          _notify();
          return;
        }
        _notify();
      }
    }
    if (_panelActive && isConnected) {
      _pollTimer = Timer(pollInterval, _pollTick);
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Jds6600Transport _requireTransport() {
    final transport = _transport;
    if (transport == null || !transport.isOpen) {
      throw const Jds6600DisconnectedException(
        'Signal generator is not connected',
      );
    }
    return transport;
  }

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
    final transport = _requireTransport();
    final line = await transport.transact(
      Jds6600Protocol.readCommand(register),
      accept: (response) => response.startsWith(':r'),
    );
    return Jds6600Protocol.parseRegisterResponse(register, line);
  }

  Future<void> _writeRegister(int register, String value) async {
    final transport = _requireTransport();
    final command = Jds6600Protocol.writeCommand(register, value);
    final response = await transport.transact(command);
    Jds6600Protocol.ensureAck(response, command);
  }

  void _updateChannel(int channel, Jds6600ChannelState state) {
    if (channel == 1) {
      _ch1 = state;
    } else {
      _ch2 = state;
    }
    _lastRefresh = DateTime.now();
    _notify();
  }

  Future<void> _guard(Future<void> Function() operation) async {
    try {
      await operation();
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      _notify();
      rethrow;
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    if (_disposed) {
      return Future<T>.error(StateError('Signal generator service disposed'));
    }
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      if (_disposed) {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('Signal generator service disposed'),
          );
        }
        return;
      }
      _setBusy(true);
      try {
        if (!completer.isCompleted) {
          completer.complete(await operation());
        }
      } catch (e, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(e, stackTrace);
        }
      } finally {
        _setBusy(false);
      }
    });
    return completer.future;
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    _disposed = true;
    _stopPolling();
    final transport = _transport;
    _transport = null;
    _port = null;
    if (transport != null) {
      try {
        await transport.close().timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    final transport = _transport;
    _transport = null;
    if (transport != null) {
      unawaited(transport.close());
    }
    super.dispose();
  }
}
