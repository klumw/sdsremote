import 'dart:io';

import 'driver/libusb_driver.dart';
import 'driver/usb_driver.dart';
import 'visa_resource.dart';
import 'usbtmc_device.dart';

/// Manages the USBTMC session context and instantiates physical connections.
class UsbtmcContext {
  /// Maximum payload bytes per USBTMC read request for Siglent SDS1x04X-E
  /// oscilloscopes.
  ///
  /// Older firmware (e.g. 8.2.6.1.37R9) only handled short read requests
  /// reliably; larger requests could wedge the USB interface until the
  /// instrument was unplugged and replugged. Firmware 8.1.6.1.37R17 tolerates
  /// 8192-byte requests, and the old 48-byte limit made screen dumps take
  /// about 85 seconds. 8192 bytes keeps the round-trip count low (SCDP about
  /// 0.9 s, a 100k-point waveform about 60 ms) and was stable in repeated
  /// tests. If an instrument with older firmware fails on reads, update its
  /// firmware.
  static const int siglentMaxReadTransferSize = 8192;

  /// USB vendor ID of the Siglent SDS1000X-E four-channel series
  /// (SDS1104X-E, SDS1204X-E). The two-channel SDS1202X-E enumerates as
  /// 0xf4ed and does not need the workaround.
  static const int _siglentFourChannelVendorId = 0xf4ec;

  final UsbDriver _driver;
  late final UsbContext _usbContext;
  bool _initialized = false;

  /// Creates a context with a custom driver (defaults to pure dynamic libusb).
  UsbtmcContext({UsbDriver? driver}) : _driver = driver ?? LibusbDriver();

  /// Starts the low-level USB driver session context.
  Future<void> init() async {
    if (_initialized) return;
    _usbContext = await _driver.newContext();
    _initialized = true;
  }

  /// Sets the low-level log/debug level for libusb.
  Future<void> setDebugLevel(int level) async {
    _checkInit();
    await _usbContext.setDebugLevel(level);
  }

  /// Creates a new [UsbtmcDevice] based on Vendor ID (VID) and Product ID (PID).
  Future<UsbtmcDevice> newDeviceByVidPid(int vendorId, int productId) async {
    _checkInit();
    final usbDevice = await _usbContext.openDevice(vendorId, productId);
    final device = UsbtmcDevice(usbDevice);
    // Workaround for the SDS1x04X-E USBTMC firmware bug, Linux only: cap the
    // payload requested per read so the instrument cannot wedge its USB
    // interface. Limiting every read slows large transfers down, so the cap
    // is applied on Linux only.
    if (Platform.isLinux && vendorId == _siglentFourChannelVendorId) {
      device.maxReadTransferSize = siglentMaxReadTransferSize;
    }
    await device.clear();
    return device;
  }

  /// Creates a new [UsbtmcDevice] by parsing a VISA address string.
  ///
  /// Example: `"USB0::0x0957::0x2818::INSTR"`
  Future<UsbtmcDevice> newDevice(String visaAddress) async {
    final visa = VisaResource.parse(visaAddress);
    return newDeviceByVidPid(visa.manufacturerId, visa.modelCode);
  }

  /// Closes the low-level context session.
  Future<void> close() async {
    if (!_initialized) return;
    await _usbContext.close();
    _initialized = false;
  }

  void _checkInit() {
    if (!_initialized) {
      throw StateError(
          'USBTMC Context has not been initialized. Please call init() first.');
    }
  }
}
