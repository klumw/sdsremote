/// Serial-port metadata and user-facing labels.
///
/// This file is deliberately free of libserialport/FFI imports so widgets and
/// tests can use [SerialPortInfo] without loading the native library.
library;

/// Metadata for one serial port.
class SerialPortInfo {
  const SerialPortInfo({
    required this.name,
    this.description,
    this.manufacturer,
    this.productName,
    this.vendorId,
    this.productId,
  });

  final String name;
  final String? description;
  final String? manufacturer;
  final String? productName;
  final int? vendorId;
  final int? productId;

  /// The JDS6600 is commonly sold with a QinHeng CH340 bridge.
  bool get isCh340 => vendorId == 0x1A86 && productId == 0x7523;

  /// Label for a dropdown, e.g. `/dev/ttyUSB0 — QinHeng CH340`.
  String get label {
    final details = <String>{};
    for (final value in [description, manufacturer, productName]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty && trimmed != name) {
        details.add(trimmed);
      }
    }
    if (details.isEmpty) return name;
    return '$name — ${details.join(' · ')}';
  }

  @override
  String toString() => label;
}
