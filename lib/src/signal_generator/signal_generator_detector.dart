/// Automatic serial-port discovery for the JDS6600.
///
/// The detector tries the last known port first, then all serial ports
/// (CH340 adapters first). It confirms a candidate by connecting and reading
/// the SCPI identity (`*IDN?`), which the JDS6600 driver synthesises from
/// registers 0/1.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'serial_port_info.dart';
import 'serial_port_scanner.dart';
import 'signal_generator_service.dart';

typedef SerialPortLister = Future<List<SerialPortInfo>> Function();

class SignalGeneratorDetector extends ChangeNotifier {
  SignalGeneratorDetector({
    required this.service,
    SerialPortLister? listPorts,
    this.interval = const Duration(seconds: 5),
    String? initialPort,
    this.onPortDetected,
  })  : _listPorts = listPorts ?? (() async => listSerialPorts()),
        _lastPort = initialPort;

  final SignalGeneratorService service;
  final SerialPortLister _listPorts;
  final Duration interval;
  final ValueChanged<String>? onPortDetected;

  String? _lastPort;
  bool _isDetected = false;
  String? _port;
  String? _identity;
  bool _paused = false;
  bool _busy = false;
  bool _disposed = false;
  Timer? _timer;

  bool get isDetected => _isDetected;

  String? get port => _port;

  String? get identity => _identity;

  String? get lastPort => _lastPort;

  bool get paused => _paused;

  void start() {
    if (_disposed) return;
    _paused = false;
    _schedule(Duration.zero);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void setPaused(bool paused) {
    if (_paused == paused) return;
    _paused = paused;
    if (paused) {
      _timer?.cancel();
      _timer = null;
    } else {
      _schedule(Duration.zero);
    }
  }

  Future<void> checkNow() async {
    if (_disposed || _paused || _busy) return;
    _busy = true;
    try {
      await _detect();
    } finally {
      _busy = false;
      if (!_disposed && !_paused) {
        _schedule(interval);
      }
    }
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (_disposed || _paused) return;
    _timer = Timer(delay, checkNow);
  }

  Future<void> _detect() async {
    if (service.isConnected) {
      try {
        await service.refreshDeviceInfo();
        final identity = await service.executeScpi('*IDN?');
        if (identity != null && identity.contains('JDS6600')) {
          _lastPort = service.port ?? _lastPort;
          _setDetected(true, service.port, identity);
          return;
        }
      } catch (_) {
        // Fall through to a fresh scan.
      }
      try {
        await service.disconnect();
      } catch (_) {}
    }

    _setDetected(false, null, null);

    final candidates = <String>[];
    if (_lastPort != null && _lastPort!.isNotEmpty) {
      candidates.add(_lastPort!);
    }
    try {
      final ports = await _listPorts();
      for (final port in ports) {
        if (!candidates.contains(port.name)) candidates.add(port.name);
      }
    } catch (_) {
      // No native scanner available; only the remembered port is tried.
    }

    for (final port in candidates) {
      if (_disposed || _paused) return;
      try {
        final result = await service.testConnection(port);
        if (!result.startsWith('SUCCESS')) continue;

        await service.connect(port);
        await service.refreshDeviceInfo();
        final identity = await service.executeScpi('*IDN?');
        if (identity != null && identity.contains('JDS6600')) {
          _lastPort = port;
          onPortDetected?.call(port);
          _setDetected(true, port, identity);
          return;
        }
        await service.disconnect();
      } catch (_) {
        try {
          await service.disconnect();
        } catch (_) {}
      }
    }

    _setDetected(false, null, null);
  }

  void _setDetected(bool detected, String? port, String? identity) {
    final changed = _isDetected != detected ||
        _port != port ||
        _identity != identity;
    _isDetected = detected;
    _port = port;
    _identity = identity;
    if (changed && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
