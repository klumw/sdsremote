import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'usb_driver.dart';

// Type definitions for C functions
typedef _libusb_init_c = Int32 Function(Pointer<Pointer<Void>> ctx);
typedef _libusb_init_dart = int Function(Pointer<Pointer<Void>> ctx);

typedef _libusb_exit_c = Void Function(Pointer<Void> ctx);
typedef _libusb_exit_dart = void Function(Pointer<Void> ctx);

typedef _libusb_set_debug_c = Void Function(Pointer<Void> ctx, Int32 level);
typedef _libusb_set_debug_dart = void Function(Pointer<Void> ctx, int level);

typedef _libusb_open_device_with_vid_pid_c = Pointer<Void> Function(
    Pointer<Void> ctx, Uint16 vendor_id, Uint16 product_id);
typedef _libusb_open_device_with_vid_pid_dart = Pointer<Void> Function(
    Pointer<Void> ctx, int vendor_id, int product_id);

typedef _libusb_close_c = Void Function(Pointer<Void> dev_handle);
typedef _libusb_close_dart = void Function(Pointer<Void> dev_handle);

typedef _libusb_claim_interface_c = Int32 Function(
    Pointer<Void> dev_handle, Int32 interface_number);
typedef _libusb_claim_interface_dart = int Function(
    Pointer<Void> dev_handle, int interface_number);

typedef _libusb_release_interface_c = Int32 Function(
    Pointer<Void> dev_handle, Int32 interface_number);
typedef _libusb_release_interface_dart = int Function(
    Pointer<Void> dev_handle, int interface_number);

typedef _libusb_bulk_transfer_c = Int32 Function(
    Pointer<Void> dev_handle,
    Uint8 endpoint,
    Pointer<Uint8> data,
    Int32 length,
    Pointer<Int32> actual_length,
    Uint32 timeout);
typedef _libusb_bulk_transfer_dart = int Function(
    Pointer<Void> dev_handle,
    int endpoint,
    Pointer<Uint8> data,
    int length,
    Pointer<Int32> actual_length,
    int timeout);

typedef _libusb_control_transfer_c = Int32 Function(
    Pointer<Void> dev_handle,
    Uint8 request_type,
    Uint8 request,
    Uint16 value,
    Uint16 index,
    Pointer<Uint8> data,
    Uint16 length,
    Uint32 timeout);
typedef _libusb_control_transfer_dart = int Function(
    Pointer<Void> dev_handle,
    int request_type,
    int request,
    int value,
    int index,
    Pointer<Uint8> data,
    int length,
    int timeout);

typedef _libusb_detach_kernel_driver_c = Int32 Function(
    Pointer<Void> dev_handle, Int32 interface_number);
typedef _libusb_detach_kernel_driver_dart = int Function(
    Pointer<Void> dev_handle, int interface_number);

typedef _libusb_attach_kernel_driver_c = Int32 Function(
    Pointer<Void> dev_handle, Int32 interface_number);
typedef _libusb_attach_kernel_driver_dart = int Function(
    Pointer<Void> dev_handle, int interface_number);

typedef _libusb_clear_halt_c = Int32 Function(
    Pointer<Void> dev_handle, Uint8 endpoint);
typedef _libusb_clear_halt_dart = int Function(
    Pointer<Void> dev_handle, int endpoint);

typedef _libusb_reset_device_c = Int32 Function(
    Pointer<Void> dev_handle);
typedef _libusb_reset_device_dart = int Function(
    Pointer<Void> dev_handle);

/// C-bindings loader for `libusb-1.0`.
class LibusbBindings {
  late final DynamicLibrary _lib;

  late final _libusb_init_dart libusb_init;
  late final _libusb_exit_dart libusb_exit;
  late final _libusb_set_debug_dart libusb_set_debug;
  late final _libusb_open_device_with_vid_pid_dart libusb_open_device_with_vid_pid;
  late final _libusb_close_dart libusb_close;
  late final _libusb_claim_interface_dart libusb_claim_interface;
  late final _libusb_release_interface_dart libusb_release_interface;
  late final _libusb_bulk_transfer_dart libusb_bulk_transfer;
  late final _libusb_control_transfer_dart libusb_control_transfer;
  late final _libusb_detach_kernel_driver_dart libusb_detach_kernel_driver;
  late final _libusb_attach_kernel_driver_dart libusb_attach_kernel_driver;
  late final _libusb_clear_halt_dart libusb_clear_halt;
  late final _libusb_reset_device_dart libusb_reset_device;

  LibusbBindings() {
    _lib = _loadLibrary();

    libusb_init = _lib
        .lookup<NativeFunction<_libusb_init_c>>('libusb_init')
        .asFunction();
    libusb_exit = _lib
        .lookup<NativeFunction<_libusb_exit_c>>('libusb_exit')
        .asFunction();
    libusb_set_debug = _lib
        .lookup<NativeFunction<_libusb_set_debug_c>>('libusb_set_debug')
        .asFunction();
    libusb_open_device_with_vid_pid = _lib
        .lookup<NativeFunction<_libusb_open_device_with_vid_pid_c>>(
            'libusb_open_device_with_vid_pid')
        .asFunction();
    libusb_close = _lib
        .lookup<NativeFunction<_libusb_close_c>>('libusb_close')
        .asFunction();
    libusb_claim_interface = _lib
        .lookup<NativeFunction<_libusb_claim_interface_c>>(
            'libusb_claim_interface')
        .asFunction();
    libusb_release_interface = _lib
        .lookup<NativeFunction<_libusb_release_interface_c>>(
            'libusb_release_interface')
        .asFunction();
    libusb_bulk_transfer = _lib
        .lookup<NativeFunction<_libusb_bulk_transfer_c>>('libusb_bulk_transfer')
        .asFunction();
    libusb_control_transfer = _lib
        .lookup<NativeFunction<_libusb_control_transfer_c>>(
            'libusb_control_transfer')
        .asFunction();
    libusb_clear_halt = _lib
        .lookup<NativeFunction<_libusb_clear_halt_c>>('libusb_clear_halt')
        .asFunction();
    libusb_reset_device = _lib
        .lookup<NativeFunction<_libusb_reset_device_c>>('libusb_reset_device')
        .asFunction();
    
    // Kernel driver detach/attach might not be present on Windows, try lookup
    try {
      libusb_detach_kernel_driver = _lib
          .lookup<NativeFunction<_libusb_detach_kernel_driver_c>>(
              'libusb_detach_kernel_driver')
          .asFunction();
    } catch (_) {
      libusb_detach_kernel_driver = (h, i) => -1;
    }

    try {
      libusb_attach_kernel_driver = _lib
          .lookup<NativeFunction<_libusb_attach_kernel_driver_c>>(
              'libusb_attach_kernel_driver')
          .asFunction();
    } catch (_) {
      libusb_attach_kernel_driver = (h, i) => -1;
    }
  }

  DynamicLibrary _loadLibrary() {
    if (Platform.isLinux) {
      try {
        return DynamicLibrary.open('libusb-1.0.so.0');
      } catch (_) {
        return DynamicLibrary.open('libusb-1.0.so');
      }
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('libusb-1.0.dll');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libusb-1.0.dylib');
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

final LibusbBindings _bindings = LibusbBindings();

class LibusbDriver implements UsbDriver {
  @override
  Future<UsbContext> newContext() async {
    final ctxPtr = calloc<Pointer<Void>>();
    try {
      final res = _bindings.libusb_init(ctxPtr);
      if (res < 0) {
        throw Exception('Failed to initialize libusb: error code $res');
      }
      return LibusbContext._(ctxPtr.value);
    } finally {
      calloc.free(ctxPtr);
    }
  }
}

class LibusbContext implements UsbContext {
  final Pointer<Void> _ctx;
  bool _closed = false;

  LibusbContext._(this._ctx);

  @override
  Future<void> setDebugLevel(int level) async {
    if (_closed) throw StateError('Context is closed');
    _bindings.libusb_set_debug(_ctx, level);
  }

  @override
  Future<UsbDevice> openDevice(int vendorId, int productId) async {
    if (_closed) throw StateError('Context is closed');

    // Handle modular boot evasion if vendor matches Agilent/Keysight (0x0957)
    if (vendorId == 0x0957) {
      await _checkAndExitAgilentBootMode(vendorId, productId);
    }

    final handle = _bindings.libusb_open_device_with_vid_pid(_ctx, vendorId, productId);
    if (handle == nullptr) {
      throw Exception(
          'Failed to open USB device with VID 0x${vendorId.toRadixString(16)} and PID 0x${productId.toRadixString(16)}. Please check physical connection and USB permissions.');
    }

    // Detach kernel driver if needed (highly relevant for Linux USBTMC drivers)
    if (Platform.isLinux) {
      _bindings.libusb_detach_kernel_driver(handle, 0);
    }

    final res = _bindings.libusb_claim_interface(handle, 0);
    if (res < 0) {
      _bindings.libusb_close(handle);
      throw Exception('Failed to claim interface 0: error code $res');
    }

    // In USBTMC, endpoints are standardized as:
    // Bulk-OUT (Host -> Device): 0x01, 0x02, or 0x03
    // Bulk-IN (Device -> Host): 0x81, 0x82, or 0x83
    // We default to 0x01 and 0x81 as they represent the primary channels.
    return LibusbDevice._(handle, bulkOutEp: 0x01, bulkInEp: 0x81);
  }

  /// Escapes modular boot mode for Agilent/Keysight devices if necessary.
  Future<void> _checkAndExitAgilentBootMode(int vid, int targetPid) async {
    final bootPids = {
      0x2818: 0x2918, // U2702A Oscilloscope
      0x3D18: 0x3E18, // U2751A Switch Matrix
      0x4118: 0x4218, // U2722A SMU
      0x4318: 0x4418, // U2723A SMU
    };

    final bootPid = bootPids[targetPid];
    if (bootPid == null) return;

    // Check if the device is currently in boot mode
    final bootHandle = _bindings.libusb_open_device_with_vid_pid(_ctx, vid, bootPid);
    if (bootHandle == nullptr) return; // Not in boot mode

    print('Found Keysight modular device in boot mode. Initiating escape sequence...');
    
    // Sequence of specific control transfers to exit boot mode
    int thirdIndex = (bootPid == 0x2818 || bootPid == 0x3E18) ? 0x0484 : 0x0487;
    final packets = [
      _ControlTransferPacket(0xC0, 0x0C, 0x0000, 0x047E, Uint8List(1)),
      _ControlTransferPacket(0xC0, 0x0C, 0x0000, 0x047D, Uint8List(6)),
      _ControlTransferPacket(0xC0, 0x0C, 0x0000, thirdIndex, Uint8List(5)),
      _ControlTransferPacket(0xC0, 0x0C, 0x0000, 0x0472, Uint8List(12)),
      _ControlTransferPacket(0xC0, 0x0C, 0x0000, 0x047A, Uint8List(1)),
      _ControlTransferPacket(0x40, 0x0C, 0x0000, 0x0475, Uint8List.fromList([0x00, 0x00, 0x01, 0x01, 0x00, 0x00, 0x08, 0x01])),
    ];

    try {
      for (final p in packets) {
        final dataPtr = calloc<Uint8>(p.data.length);
        for (int i = 0; i < p.data.length; i++) {
          dataPtr[i] = p.data[i];
        }

        final res = _bindings.libusb_control_transfer(
          bootHandle,
          p.requestType,
          p.request,
          p.value,
          p.index,
          dataPtr,
          p.data.length,
          2000,
        );

        calloc.free(dataPtr);
        if (res < 0) {
          throw Exception('Control transfer failed during boot mode escape: $res');
        }
      }
    } finally {
      _bindings.libusb_close(bootHandle);
    }

    print('Modular device exiting boot mode. Waiting 7 seconds for re-enumeration...');
    await Future.delayed(const Duration(seconds: 7));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _bindings.libusb_exit(_ctx);
    _closed = true;
  }
}

class LibusbDevice implements UsbDevice {
  final Pointer<Void> _handle;
  final int bulkOutEp;
  final int bulkInEp;
  bool _closed = false;

  LibusbDevice._(this._handle, {required this.bulkOutEp, required this.bulkInEp});

  /// Maps a libusb error code to a human-readable description.
  static String _libusbErrorString(int code) {
    switch (code) {
      case 0:  return 'SUCCESS';
      case -1: return 'IO_ERROR';
      case -2: return 'INVALID_PARAM';
      case -3: return 'ACCESS';
      case -4: return 'NO_DEVICE';
      case -5: return 'NOT_FOUND';
      case -6: return 'BUSY';
      case -7: return 'TIMEOUT';
      case -8: return 'OVERFLOW';
      case -9: return 'PIPE';
      case -10: return 'INTERRUPTED';
      case -11: return 'NO_MEM';
      case -12: return 'NOT_SUPPORTED';
      default: return 'UNKNOWN';
    }
  }

  @override
  Future<int> write(Uint8List data, {Duration? timeout}) async {
    if (_closed) throw StateError('Device is closed');
    final timeoutMs = timeout?.inMilliseconds ?? 2000;

    final dataPtr = calloc<Uint8>(data.length);
    final actualLengthPtr = calloc<Int32>();

    try {
      for (int i = 0; i < data.length; i++) {
        dataPtr[i] = data[i];
      }

      final res = _bindings.libusb_bulk_transfer(
        _handle,
        bulkOutEp,
        dataPtr,
        data.length,
        actualLengthPtr,
        timeoutMs,
      );

      if (res < 0) {
        final errDesc = _libusbErrorString(res);
        throw Exception('libusb bulk write error: $res ($errDesc)');
      }

      return actualLengthPtr.value;
    } finally {
      calloc.free(dataPtr);
      calloc.free(actualLengthPtr);
    }
  }

  @override
  Future<Uint8List> read(int maxBytes, {Duration? timeout}) async {
    if (_closed) throw StateError('Device is closed');
    final timeoutMs = timeout?.inMilliseconds ?? 2000;

    final dataPtr = calloc<Uint8>(maxBytes);
    final actualLengthPtr = calloc<Int32>();

    try {
      final res = _bindings.libusb_bulk_transfer(
        _handle,
        bulkInEp,
        dataPtr,
        maxBytes,
        actualLengthPtr,
        timeoutMs,
      );

      if (res < 0) {
        final errDesc = _libusbErrorString(res);
        print('libusb: bulk_read FAILED: error code $res ($errDesc)');
        throw Exception('libusb bulk read error: $res ($errDesc)');
      }

      final readLen = actualLengthPtr.value;
      final out = Uint8List(readLen);
      for (int i = 0; i < readLen; i++) {
        out[i] = dataPtr[i];
      }
      return out;
    } finally {
      calloc.free(dataPtr);
      calloc.free(actualLengthPtr);
    }
  }

  @override
  Future<Uint8List> controlTransfer({
    required int requestType,
    required int request,
    required int value,
    required int index,
    required Uint8List data,
    Duration? timeout,
  }) async {
    if (_closed) throw StateError('Device is closed');
    final timeoutMs = timeout?.inMilliseconds ?? 2000;

    final dataPtr = calloc<Uint8>(data.length);
    try {
      for (int i = 0; i < data.length; i++) {
        dataPtr[i] = data[i];
      }

      final res = _bindings.libusb_control_transfer(
        _handle,
        requestType,
        request,
        value,
        index,
        dataPtr,
        data.length,
        timeoutMs,
      );

      if (res < 0) {
        throw Exception('libusb control transfer error: $res');
      }

      final out = Uint8List(data.length);
      for (int i = 0; i < data.length; i++) {
        out[i] = dataPtr[i];
      }
      return out;
    } finally {
      calloc.free(dataPtr);
    }
  }

  @override
  Future<void> clearHalt() async {
    if (_closed) return;
    print('USBTMC low-level: Clearing halt on bulk-IN (0x${bulkInEp.toRadixString(16)}) and bulk-OUT (0x${bulkOutEp.toRadixString(16)})...');
    final resIn = _bindings.libusb_clear_halt(_handle, bulkInEp);
    if (resIn < 0) {
      print('USBTMC low-level: libusb_clear_halt on Bulk-IN failed: $resIn');
    }
    final resOut = _bindings.libusb_clear_halt(_handle, bulkOutEp);
    if (resOut < 0) {
      print('USBTMC low-level: libusb_clear_halt on Bulk-OUT failed: $resOut');
    }
  }

  @override
  Future<void> reset() async {
    if (_closed) return;
    print('USBTMC low-level: Performing USB Port Reset via libusb_reset_device...');
    final res = _bindings.libusb_reset_device(_handle);
    if (res < 0) {
      print('USBTMC low-level: libusb_reset_device failed: error code $res');
    } else {
      print('USBTMC low-level: libusb_reset_device completed successfully.');
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _bindings.libusb_release_interface(_handle, 0);
    
    // Attach kernel driver back on Linux
    if (Platform.isLinux) {
      _bindings.libusb_attach_kernel_driver(_handle, 0);
    }

    _bindings.libusb_close(_handle);
    _closed = true;
  }
}

class _ControlTransferPacket {
  final int requestType;
  final int request;
  final int value;
  final int index;
  final Uint8List data;

  _ControlTransferPacket(
      this.requestType, this.request, this.value, this.index, this.data);
}
