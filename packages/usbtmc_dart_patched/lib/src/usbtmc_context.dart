import 'driver/libusb_driver.dart';
import 'driver/usb_driver.dart';
import 'visa_resource.dart';
import 'usbtmc_device.dart';

/// Manages the USBTMC session context and instantiates physical connections.
class UsbtmcContext {
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
