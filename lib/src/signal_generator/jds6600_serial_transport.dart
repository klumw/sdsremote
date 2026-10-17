/// libserialport-backed transport for the JDS6600.
///
/// The device is a CH340-style USB-serial adapter speaking 115200 8N1 with
/// ASCII, line-terminated commands. Reads run in libserialport's reader
/// isolate; small writes stay on the calling isolate.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'jds6600_transport.dart';
import 'models.dart';

/// libserialport-backed implementation.
class LibSerialPortJds6600Transport implements Jds6600Transport {
  LibSerialPortJds6600Transport(
    this.portName, {
    this.baudRate = 115200,
    this.retries = 1,
  });

  final String portName;
  final int baudRate;

  /// Number of additional attempts after a timeout. JDS6600 commands are
  /// idempotent register reads/writes, so a retry is safe.
  final int retries;

  SerialPort? _port;
  SerialPortReader? _reader;
  StreamSubscription<Uint8List>? _subscription;

  String _rxBuffer = '';
  final Queue<String> _lines = Queue<String>();
  Completer<void>? _lineWaiter;
  bool _isOpen = false;
  Future<void> _tail = Future<void>.value();

  @override
  bool get isOpen => _isOpen && (_port?.isOpen ?? false);

  @override
  Future<void> open() async {
    if (isOpen) return;

    final port = SerialPort(portName);
    if (!port.openReadWrite()) {
      final error = SerialPort.lastError;
      port.dispose();
      throw Jds6600OpenException(_friendlyOpenError(error), error);
    }

    try {
      // sp_set_config requires an open port handle. The returned object is
      // owned by the port; mutate it and assign it back without disposing it.
      final config = port.config;
      config.baudRate = baudRate;
      config.bits = 8;
      config.parity = SerialPortParity.none;
      config.stopBits = 1;
      config.setFlowControl(SerialPortFlowControl.none);
      port.config = config;
    } catch (e) {
      port.close();
      port.dispose();
      throw Jds6600OpenException(
        'Could not configure $portName for 115200 8N1: $e',
        e,
      );
    }

    _rxBuffer = '';
    _lines.clear();
    _port = port;
    _reader = SerialPortReader(port);
    _subscription = _reader!.stream.listen(
      _onData,
      onError: _onError,
      cancelOnError: false,
    );
    _isOpen = true;
  }

  void _onData(Uint8List data) {
    _rxBuffer += utf8.decode(data, allowMalformed: true);
    var newline = _rxBuffer.indexOf('\n');
    while (newline >= 0) {
      final line = _rxBuffer.substring(0, newline).replaceAll('\r', '').trim();
      _rxBuffer = _rxBuffer.substring(newline + 1);
      if (line.isNotEmpty) {
        _lines.add(line);
        _wakeWaiter();
      }
      newline = _rxBuffer.indexOf('\n');
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    _isOpen = false;
    final waiter = _lineWaiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(
        Jds6600DisconnectedException(
          'Serial connection to $portName failed: $error',
          error,
        ),
        stackTrace,
      );
    }
  }

  void _wakeWaiter() {
    final waiter = _lineWaiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  @override
  Future<String> transact(
    String command, {
    Duration timeout = const Duration(milliseconds: 1000),
    bool Function(String line)? accept,
  }) async {
    final lines = await transactMany(
      command,
      count: 1,
      timeout: timeout,
      accept: accept,
    );
    return lines.single;
  }

  @override
  Future<List<String>> transactMany(
    String command, {
    required int count,
    Duration timeout = const Duration(milliseconds: 1000),
    bool Function(String line)? accept,
  }) {
    if (count < 1) {
      throw ArgumentError.value(count, 'count', 'Must be at least 1');
    }
    final result = Completer<List<String>>();
    _tail = _tail.then((_) async {
      try {
        final lines = await _transactWithRetries(
          command,
          count,
          timeout,
          accept,
        );
        if (!result.isCompleted) result.complete(lines);
      } catch (e, stackTrace) {
        if (!result.isCompleted) result.completeError(e, stackTrace);
      }
    });
    return result.future;
  }

  Future<List<String>> _transactWithRetries(
    String command,
    int count,
    Duration timeout,
    bool Function(String line)? accept,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        return await _transactOnce(command, count, timeout, accept);
      } on Jds6600TimeoutException catch (e) {
        lastError = e;
        // Discard partial input from the timed-out attempt.
        _rxBuffer = '';
        _lines.clear();
      }
    }
    throw lastError is Jds6600TimeoutException
        ? lastError
        : Jds6600TimeoutException(
            'No response from $portName for command "$command"',
          );
  }

  Future<List<String>> _transactOnce(
    String command,
    int count,
    Duration timeout,
    bool Function(String line)? accept,
  ) async {
    final port = _port;
    if (!_isOpen || port == null || !port.isOpen) {
      throw Jds6600DisconnectedException('Serial port $portName is not open');
    }

    // Drain complete stale replies before sending a new command.
    _lines.clear();
    _rxBuffer = '';

    final bytes = Uint8List.fromList(utf8.encode(command));
    try {
      final written = port.write(bytes, timeout: 250);
      if (written != bytes.length) {
        throw Jds6600DisconnectedException(
          'Only $written of ${bytes.length} bytes were written to $portName',
        );
      }
    } catch (e) {
      throw Jds6600DisconnectedException('Could not write to $portName: $e', e);
    }

    final accepted = <String>[];
    final deadline = DateTime.now().add(timeout);
    while (accepted.length < count) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw Jds6600TimeoutException(
          'Timeout waiting for reply ${accepted.length + 1}/$count '
          'from $portName (command "$command")',
        );
      }
      final line = await _nextLine(remaining);
      if (accept == null || accept(line)) {
        accepted.add(line);
      }
      // Otherwise: stale line from an earlier transaction; keep waiting.
    }
    return accepted;
  }

  Future<String> _nextLine(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      if (_lines.isNotEmpty) return _lines.removeFirst();

      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw Jds6600TimeoutException(
          'Timeout waiting for a line from $portName',
        );
      }

      final waiter = Completer<void>();
      _lineWaiter = waiter;
      try {
        await waiter.future.timeout(remaining, onTimeout: () {});
      } finally {
        if (identical(_lineWaiter, waiter)) _lineWaiter = null;
      }
    }
  }

  @override
  Future<void> close() async {
    if (!_isOpen && _port == null) return;
    _isOpen = false;

    final waiter = _lineWaiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(
        Jds6600DisconnectedException('Serial port $portName was closed'),
      );
    }
    _lineWaiter = null;
    _lines.clear();
    _rxBuffer = '';

    await _subscription?.cancel();
    _subscription = null;
    _reader?.close();
    _reader = null;

    final port = _port;
    _port = null;
    if (port != null) {
      try {
        port.close();
      } finally {
        port.dispose();
      }
    }
  }

  String _friendlyOpenError(SerialPortError? error) {
    if (Platform.isLinux && error?.errorCode == 13) {
      return 'Permission denied opening $portName. Add your user to the '
          '"dialout" group (sudo usermod -aG dialout \$USER) and log in again.';
    }
    if (error?.errorCode == 16) {
      return '$portName is busy. Close other serial-port programs '
          '(JDS software, PulseView, another app) and retry.';
    }
    return 'Could not open $portName: ${error?.message ?? 'unknown error'}';
  }
}
