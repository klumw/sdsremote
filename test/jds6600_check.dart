// ignore_for_file: avoid_print
//
// Hardware-in-the-loop check for the JOY-IT / Juntek JDS6600.
//
// Usage (Linux):
//   flutter build linux --debug
//   LIBSERIALPORT_PATH="$PWD/build/linux/x64/debug/bundle/lib" \
//     dart run test/jds6600_check.dart /dev/ttyUSB0
//
// On Windows, point LIBSERIALPORT_PATH at the directory containing
// serialport.dll next to the built runner.
//
// The script saves registers 20-31, performs a few writes, verifies the
// readback and restores the saved state in a finally block.

import 'dart:io';

import 'package:sdsremote/src/signal_generator/jds6600_protocol.dart';
import 'package:sdsremote/src/signal_generator/jds6600_serial_transport.dart';
import 'package:sdsremote/src/signal_generator/models.dart';

int _failures = 0;

Future<void> main(List<String> args) async {
  final portName = args.isEmpty ? '/dev/ttyUSB0' : args.first;
  final transport = LibSerialPortJds6600Transport(portName);
  final saved = <int, String>{};

  try {
    await transport.open();
    print('Opened $portName at 115200 8N1');

    final info = await _readInfo(transport);
    print(
      'Device: ${info.modelName} (${info.modelMHz} MHz), '
      'serial ${info.serialNumber}',
    );
    _check(info.modelMHz > 0, 'device type is plausible');

    final stateLines = await transport.transactMany(
      Jds6600Protocol.readCommand(20, count: 12),
      count: 12,
      accept: (line) => line.startsWith(':r'),
      timeout: const Duration(seconds: 3),
    );
    final state = Jds6600Protocol.parseRegisterSequence(20, stateLines);
    for (var index = 0; index < state.length; index++) {
      saved[20 + index] = state[index].join(',');
    }
    print('Saved registers 20-31: $saved');
    _check(state.length == 12, 'read 12 state registers');

    // Preserve CH2 while enabling CH1.
    final outputs = Jds6600Protocol.decodeOutputs(state[0]);
    final outputsPayload = Jds6600Protocol.encodeOutputs(true, outputs.ch2);

    await _write(transport, Jds6600Protocol.waveformRegister(1), '0');
    await _write(transport, Jds6600Protocol.frequencyRegister(1), '100000,0');
    await _write(transport, Jds6600Protocol.amplitudeRegister(1), '1000');
    await _write(transport, Jds6600Protocol.offsetRegister(1), '1000');
    await _write(transport, Jds6600Protocol.dutyRegister(1), '500');
    await _write(transport, Jds6600Protocol.registerOutputs, outputsPayload);

    final readback = await _readRegisters(transport, [
      20,
      21,
      23,
      25,
      27,
      29,
    ]);
    _check(
      readback[20]?.join(',') == outputsPayload,
      'output register readback ($outputsPayload)',
    );
    _check(readback[21]?.join(',') == '0', 'CH1 waveform is sine');
    _check(
      readback[23]?.join(',') == '100000,0',
      'CH1 frequency is 1 kHz',
    );
    _check(readback[25]?.join(',') == '1000', 'CH1 amplitude is 1 Vpp');
    _check(readback[27]?.join(',') == '1000', 'CH1 offset is 0 V');
    _check(readback[29]?.join(',') == '500', 'CH1 duty is 50 %');
  } catch (e) {
    print('FAILURE: $e');
    if (e.toString().contains('libserialport') ||
        e.toString().contains('Failed to load')) {
      print(
        'Hint: set LIBSERIALPORT_PATH to the bundle lib directory '
        '(Linux) or to the directory containing serialport.dll (Windows).',
      );
    }
    _failures++;
  } finally {
    // Restore the saved state, outputs last so the signal is not enabled
    // before its parameters are restored.
    for (final entry in saved.entries) {
      if (entry.key == Jds6600Protocol.registerOutputs) continue;
      try {
        await _write(transport, entry.key, entry.value);
      } catch (e) {
        print('WARN: could not restore register ${entry.key}: $e');
      }
    }
    if (saved.containsKey(Jds6600Protocol.registerOutputs)) {
      try {
        await _write(
          transport,
          Jds6600Protocol.registerOutputs,
          saved[Jds6600Protocol.registerOutputs]!,
        );
      } catch (e) {
        print('WARN: could not restore outputs: $e');
      }
    }
    await transport.close();
    print(_failures == 0 ? 'RESULT: PASS' : 'RESULT: FAIL ($_failures)');
    if (_failures != 0) exitCode = 1;
  }
}

Future<Jds6600DeviceInfo> _readInfo(
  LibSerialPortJds6600Transport transport,
) async {
  final lines = await transport.transactMany(
    Jds6600Protocol.readCommand(0, count: 2),
    count: 2,
    accept: (line) => line.startsWith(':r'),
    timeout: const Duration(seconds: 3),
  );
  final values = Jds6600Protocol.parseRegisterSequence(0, lines);
  return Jds6600DeviceInfo(
    modelMHz: values[0].first,
    serialNumber: values[1].first,
  );
}

Future<Map<int, List<int>>> _readRegisters(
  LibSerialPortJds6600Transport transport,
  List<int> registers,
) async {
  final result = <int, List<int>>{};
  for (final register in registers) {
    final line = await transport.transact(
      Jds6600Protocol.readCommand(register),
      accept: (response) => response.startsWith(':r'),
      timeout: const Duration(seconds: 3),
    );
    result[register] = Jds6600Protocol.parseRegisterResponse(register, line);
  }
  return result;
}

Future<void> _write(
  LibSerialPortJds6600Transport transport,
  int register,
  String value,
) async {
  final command = Jds6600Protocol.writeCommand(register, value);
  final response = await transport.transact(command);
  Jds6600Protocol.ensureAck(response, command);
}

void _check(bool condition, String description) {
  print('${condition ? 'PASS' : 'FAIL'}: $description');
  if (!condition) _failures++;
}
