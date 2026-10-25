import 'dart:typed_data';

/// A USB transfer failed at the libusb level.
///
/// The numeric [code] is the libusb error code (negative); [codeName] is its
/// symbolic name (`IO_ERROR`, `NO_DEVICE`, `PIPE`, …). Callers use
/// [isConnectionLost] to decide whether the device handle must be discarded
/// and the connection re-established.
class UsbTransferException implements Exception {
  /// libusb error code, e.g. -1 (IO_ERROR), -4 (NO_DEVICE), -9 (PIPE).
  final int code;

  /// Symbolic libusb error name, e.g. `IO_ERROR`.
  final String codeName;

  /// The operation that failed, e.g. `bulk write`, `bulk read`,
  /// `control transfer`.
  final String operation;

  const UsbTransferException(this.code, this.codeName, this.operation);

  /// Whether the connection is unusable after this error.
  ///
  /// IO_ERROR (-1), NO_DEVICE (-4), and PIPE (-9) mean the device handle is
  /// dead and must be closed and reopened. TIMEOUT (-7) and other errors can
  /// be transient, so the connection stays usable.
  bool get isConnectionLost => code == -1 || code == -4 || code == -9;

  @override
  String toString() => 'libusb $operation error: $code ($codeName)';
}

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
