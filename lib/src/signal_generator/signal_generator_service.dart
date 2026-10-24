/// Signal-generator facade: connection lifecycle, cached state, command queue,
/// readback and polling.
///
/// The service is deliberately independent of Flutter widgets and of the
/// Siglent instrument path. It owns one [SiggenDriver] at a time and
/// serialises every transaction through a single operation queue. All
/// device-specific framing and value encoding lives behind the driver seam.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/logger.dart';
import 'jds6600_driver.dart';
import 'jds6600_transport.dart';
import 'models.dart';
import 'siggen_driver.dart';
import 'siggen_scpi.dart';

typedef Jds6600TransportFactory = Jds6600Transport Function(String port);

class SignalGeneratorService extends ChangeNotifier
    implements SiggenScpiTarget {
  /// Builds a service around a concrete generator driver.
  SignalGeneratorService({
    Jds6600TransportFactory? transportFactory,
    SiggenDriverFactory? driverFactory,
    this.pollInterval = const Duration(seconds: 1),
  }) : assert(
         (transportFactory == null) != (driverFactory == null),
         'Provide exactly one of transportFactory or driverFactory',
       ),
       _driverFactory =
           driverFactory ?? ((port) => Jds6600Driver(transportFactory!(port))) {
    _scpi = SiggenScpiInterpreter(this);
  }

  final SiggenDriverFactory _driverFactory;
  final Duration pollInterval;
  late final SiggenScpiInterpreter _scpi;

  SiggenDriver? _driver;
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

  bool get isConnected => _driver?.isOpen ?? false;

  String? get port => _port;

  @override
  Jds6600DeviceInfo? get deviceInfo => _deviceInfo;

  Jds6600ChannelState get ch1 => _ch1;

  Jds6600ChannelState get ch2 => _ch2;

  Jds6600ChannelState channel(int channel) => channel == 1 ? _ch1 : _ch2;

  Jds6600OutputState get outputs => _outputs;

  /// Aggregate phase (CH2). The JDS6600 reports its global CH2-vs-CH1 value
  /// here; use [channel] for the per-channel FY6900 phase.
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

    final driver = _driverFactory(portName);
    try {
      await driver.open();
      _driver = driver;
      _port = portName;
      await _readDeviceInfoInternal();
      await _readStateInternal();
      _lastError = null;
      _pollFailures = 0;
      _startPollingIfNeeded();
      _notify();
    } catch (e) {
      _driver = null;
      _port = null;
      try {
        await driver.close();
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> disconnect() => _guard(() async {
    await _enqueue(_disconnectInternal);
  });

  Future<void> _disconnectInternal() async {
    _stopPolling();
    final driver = _driver;
    _driver = null;
    _port = null;
    _deviceInfo = null;
    _actionActive = false;
    _lastError = null;
    _notify();
    if (driver != null) {
      try {
        await driver.close();
      } catch (e) {
        AppLogger(
          agentName: 'SigGen',
          toolName: 'disconnect',
        ).error('Error closing serial port: $e');
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

    final driver = _driverFactory(portName);
    try {
      await driver.open();
      final info = await driver.readDeviceInfo();
      return 'SUCCESS: ${info.modelName}, serial ${info.serialNumber}';
    } catch (e) {
      return 'FAILURE: $e';
    } finally {
      try {
        await driver.close();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Typed setters
  // ---------------------------------------------------------------------------

  @override
  Future<void> setWaveform(int channel, Jds6600Waveform waveform) =>
      _guard(() async {
        await _enqueue(() async {
          await _requireDriver().setWaveform(channel, waveform);
          _updateChannel(
            channel,
            channel == 1
                ? _ch1.copyWith(waveform: waveform)
                : _ch2.copyWith(waveform: waveform),
          );
        });
      });

  @override
  Future<void> setFrequency(int channel, double hz) => _guard(() async {
    await _enqueue(() async {
      await _requireDriver().setFrequency(channel, hz);
      final state = channel == 1 ? _ch1 : _ch2;
      _updateChannel(channel, state.copyWith(frequencyHz: hz));
    });
  });

  @override
  Future<void> setAmplitude(int channel, double vpp) => _guard(() async {
    await _enqueue(() async {
      await _requireDriver().setAmplitude(channel, vpp);
      final state = channel == 1 ? _ch1 : _ch2;
      _updateChannel(channel, state.copyWith(amplitudeVpp: vpp));
    });
  });

  @override
  Future<void> setOffset(int channel, double volts) => _guard(() async {
    await _enqueue(() async {
      await _requireDriver().setOffset(channel, volts);
      final state = channel == 1 ? _ch1 : _ch2;
      _updateChannel(channel, state.copyWith(offsetV: volts));
    });
  });

  @override
  Future<void> setDuty(int channel, double percent) => _guard(() async {
    await _enqueue(() async {
      await _requireDriver().setDuty(channel, percent);
      final state = channel == 1 ? _ch1 : _ch2;
      _updateChannel(channel, state.copyWith(dutyPercent: percent));
    });
  });

  @override
  Future<void> setPhase(int channel, double degrees) => _guard(() async {
    await _enqueue(() async {
      await _requireDriver().setPhase(channel, degrees);
      // The JDS6600 has one global CH2-vs-CH1 register; the FY6900 has
      // independent per-channel phase.
      if (_deviceInfo?.family == SiggenFamily.jds6600) {
        _ch1 = _ch1.copyWith(phaseDeg: degrees);
        _ch2 = _ch2.copyWith(phaseDeg: degrees);
      } else if (channel == 1) {
        _ch1 = _ch1.copyWith(phaseDeg: degrees);
      } else {
        _ch2 = _ch2.copyWith(phaseDeg: degrees);
      }
      _phaseDeg = _ch2.phaseDeg;
      _lastRefresh = DateTime.now();
      _notify();
    });
  });

  @override
  Future<void> setOutput(int channel, bool enabled) => _guard(() async {
    await _enqueue(() async {
      await _requireDriver().setOutput(channel, enabled);
      _outputs = channel == 1
          ? _outputs.copyWith(ch1: enabled)
          : _outputs.copyWith(ch2: enabled);
      _notify();
    });
  });

  // ---------------------------------------------------------------------------
  // Typed readers (used by the SCPI layer)
  // ---------------------------------------------------------------------------

  @override
  Future<Jds6600Waveform> readWaveform(int channel) =>
      _enqueue(() => _requireDriver().readWaveform(channel));

  @override
  Future<double> readFrequency(int channel) =>
      _enqueue(() => _requireDriver().readFrequency(channel));

  @override
  Future<double> readAmplitude(int channel) =>
      _enqueue(() => _requireDriver().readAmplitude(channel));

  @override
  Future<double> readOffset(int channel) =>
      _enqueue(() => _requireDriver().readOffset(channel));

  @override
  Future<double> readDuty(int channel) =>
      _enqueue(() => _requireDriver().readDuty(channel));

  @override
  Future<double> readPhase(int channel) =>
      _enqueue(() => _requireDriver().readPhase(channel));

  @override
  Future<bool> readOutput(int channel) =>
      _enqueue(() => _requireDriver().readOutput(channel));

  // ---------------------------------------------------------------------------
  // Readback / reset
  // ---------------------------------------------------------------------------

  @override
  Future<void> refreshDeviceInfo() => _enqueue(_readDeviceInfoInternal);

  Future<void> _readDeviceInfoInternal() async {
    final info = await _requireDriver().readDeviceInfo();
    _deviceInfo = info;
    _notify();
  }

  Future<void> refreshAll() => _enqueue(_readStateInternal);

  Future<void> _readStateInternal() async {
    final snapshot = await _requireDriver().readState();
    _applySnapshot(snapshot);
  }

  void _applySnapshot(SiggenStateSnapshot snapshot) {
    _outputs = snapshot.outputs;
    _ch1 = snapshot.ch1;
    _ch2 = snapshot.ch2;
    _phaseDeg = snapshot.phaseDeg;
    _actionActive = snapshot.actionActive;
    _lastRefresh = DateTime.now();
    _notify();
  }

  Future<void> stopActions() => _guard(() async {
    await _enqueue(() async {
      await _requireDriver().stopActions();
      _actionActive = false;
      _notify();
    });
  });

  @override
  Future<void> resetSafeState() => _guard(() async {
    await _enqueue(_resetSafeStateInternal);
  });

  Future<void> _resetSafeStateInternal() async {
    await _requireDriver().resetSafeState();

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
        ).warning('Poll failed ($_pollFailures): $e');
        // A closed/unusable transport means the device is gone; do not wait
        // for further timeouts before reporting the disconnection.
        final driverGone = e is Jds6600DisconnectedException;
        if (_pollFailures >= 3 || driverGone) {
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

  SiggenDriver _requireDriver() {
    final driver = _driver;
    if (driver == null || !driver.isOpen) {
      throw const Jds6600DisconnectedException(
        'Signal generator is not connected',
      );
    }
    return driver;
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
    final driver = _driver;
    _driver = null;
    _port = null;
    if (driver != null) {
      try {
        await driver.close().timeout(const Duration(milliseconds: 500));
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    final driver = _driver;
    _driver = null;
    if (driver != null) {
      unawaited(driver.close());
    }
    super.dispose();
  }
}
