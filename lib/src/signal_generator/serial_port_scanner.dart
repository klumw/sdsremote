/// Serial-port discovery via libserialport.
///
/// Kept separate from [SerialPortInfo] so the pure metadata/label logic can be
/// imported by widgets and tests without loading the native library.
library;

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'serial_port_info.dart';

/// Lists the serial ports currently present on the system.
///
/// The CH340 ports are sorted first; all other ports follow alphabetically.
/// Ports whose metadata cannot be read are still listed by name.
List<SerialPortInfo> listSerialPorts() {
  final result = <SerialPortInfo>[];
  for (final name in SerialPort.availablePorts) {
    SerialPort? port;
    try {
      port = SerialPort(name);
      result.add(
        SerialPortInfo(
          name: name,
          description: port.description,
          manufacturer: port.manufacturer,
          productName: port.productName,
          vendorId: port.vendorId,
          productId: port.productId,
        ),
      );
    } catch (_) {
      result.add(SerialPortInfo(name: name));
    } finally {
      port?.dispose();
    }
  }

  result.sort((a, b) {
    if (a.isCh340 != b.isCh340) return a.isCh340 ? -1 : 1;
    return a.name.compareTo(b.name);
  });
  return result;
}

/// Whether the given port name is currently present.
bool serialPortExists(String name) =>
    SerialPort.availablePorts.contains(name);
