/// Live oscilloscope status for the Macro Agent.
///
/// The application owns the instrument connection and learns the model from
/// the device's `*IDN?` response. This file only formats that existing state
/// for the agent's `read_oscilloscope_status` tool; it never talks to the
/// instrument itself.
library;

/// Returns the connection state and, while connected, the detected model.
///
/// [model] is the model designation from the second field of `*IDN?` (for
/// example `SDS1202X-E`). [name] is the vendor-qualified display name shown in
/// the window title (for example `SIGLENT SDS1202X-E`). [channels] is the
/// channel count read with `CHS?`, or the model-based fallback.
///
/// Model, name and channel count are only reported while [connected] is true;
/// a connection that has dropped must not leave a stale model visible to the
/// agent. The configured transport and address are reported either way.
Map<String, dynamic> readMacroOscilloscopeStatus({
  required bool connected,
  String? model,
  String? name,
  int? channels,
  bool isUsb = false,
  String? ipAddress,
}) {
  return <String, dynamic>{
    'connected': connected,
    'model': connected ? model : null,
    'name': connected ? name : null,
    'channels': connected ? channels : null,
    'transport': isUsb ? 'usb' : 'network',
    'address': isUsb ? null : ipAddress,
    'status_available': true,
  };
}

/// Fallback used when the host did not register a live status provider.
Future<Map<String, dynamic>> readUnavailableOscilloscopeStatus() async {
  return <String, dynamic>{
    'connected': false,
    'model': null,
    'name': null,
    'channels': null,
    'transport': null,
    'address': null,
    'status_available': false,
  };
}
