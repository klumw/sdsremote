import 'dart:typed_data';

/// Abstract class representing a dynamic USB backend driver.
abstract class UsbDriver {
  Future<UsbContext> newContext();
}

/// Abstract class representing the initialized USB context / session.
abstract class UsbContext {
  Future<void> setDebugLevel(int level);
  Future<UsbDevice> openDevice(int vendorId, int productId);
  Future<void> close();
}

/// Abstract class representing an opened USB device with endpoint pipes.
abstract class UsbDevice {
  /// Write data to a bulk-OUT endpoint.
  Future<int> write(Uint8List data, {Duration? timeout});

  /// Read data from a bulk-IN endpoint.
  Future<Uint8List> read(int maxBytes, {Duration? timeout});

  /// Perform a synchronous USB control transfer (endpoint 0).
  ///
  /// Required for device configuration and Agilent modular boot escaping.
  Future<Uint8List> controlTransfer({
    required int requestType,
    required int request,
    required int value,
    required int index,
    required Uint8List data,
    Duration? timeout,
  });

  /// Clears standard stall/halt state on bulk endpoints.
  Future<void> clearHalt();

  /// Performs a low-level USB port reset.
  Future<void> reset();

  /// Releases interfaces and closes the device handle.
  Future<void> close();
}
