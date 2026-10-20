/// libserialport-backed transport for the FeelElec FY6900.
///
/// The FY6900 is a CH340-style USB-serial adapter speaking 115200 8N1 with
/// ASCII, line-terminated commands. Unlike the JDS6600 it acknowledges every
/// write with a bare line feed, so blank lines must be delivered to the
/// caller instead of being discarded.
library;

import 'jds6600_serial_transport.dart';

/// FY6900 transport: the JDS6600 implementation with empty lines preserved.
class LibSerialPortFy6900Transport extends LibSerialPortJds6600Transport {
  LibSerialPortFy6900Transport(super.portName, {super.retries})
    : super(keepEmptyLines: true);
}
