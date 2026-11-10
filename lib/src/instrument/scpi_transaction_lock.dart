import '../core/async_mutex.dart';

/// Process-wide lock registry that serialises SCPI transactions per instrument.
///
/// Every [Vxi11Instrument] instance that drives the same oscilloscope must
/// share one lock. In USB mode all instances use the same shared USBTMC
/// device; over VXI-11 each instance opens its own link but still addresses
/// the same physical instrument.
///
/// Without a shared lock, a write from one instance can slip between the write
/// and the read of a query on another instance. The oscilloscope then answers
/// the wrong Bulk-IN request: the query read times out, the late response
/// desynchronises the USBTMC b-tag sequence, and the instrument resets its USB
/// interface.
class ScpiTransactionLock {
  ScpiTransactionLock._();

  static final Map<String, AsyncMutex> _locks = <String, AsyncMutex>{};

  /// Returns the lock shared by all instruments that drive the same device.
  ///
  /// [usb] selects the single shared USBTMC connection; otherwise [host]
  /// identifies the VXI-11 instrument.
  static AsyncMutex forConnection({required bool usb, required String host}) {
    final key = usb ? 'usb' : 'vxi11:$host';
    return _locks.putIfAbsent(key, AsyncMutex.new);
  }
}
