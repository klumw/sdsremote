/// Main-engine registrar for the signal-generator command channel.
///
/// Only the main window may register the unidirectional channel; the child
/// engines invoke it. The handler delegates to a callback so the host can be
/// replaced when the generator configuration changes.
library;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

import 'siggen_window_protocol.dart';

/// Handles one bridge command.
typedef SigGenCommandHandler =
    Future<SigGenCommandResult> Function(
      String method,
      Map<String, dynamic> arguments,
    );

/// Registers [SigGenWindowMethods] on the unidirectional control channel.
class SigGenWindowServer {
  SigGenWindowServer({required SigGenCommandHandler handler})
    : _handler = handler;

  static const WindowMethodChannel _channel = WindowMethodChannel(
    sigGenControlChannel,
    mode: ChannelMode.unidirectional,
  );

  final SigGenCommandHandler _handler;
  bool _registered = false;

  /// Registers the method-call handler (idempotent).
  Future<void> register() async {
    if (_registered) return;
    await _channel.setMethodCallHandler(_handleCall);
    _registered = true;
  }

  Future<dynamic> _handleCall(MethodCall call) async {
    final rawArguments = call.arguments;
    final arguments = rawArguments is Map
        ? rawArguments.cast<String, dynamic>()
        : <String, dynamic>{};
    final result = await _handler(call.method, arguments);
    return result.toJson();
  }

  /// Removes the handler. Called when the application shuts down.
  Future<void> dispose() async {
    if (!_registered) return;
    _registered = false;
    try {
      await _channel.setMethodCallHandler(null);
    } catch (_) {
      // Engine may already be shutting down.
    }
  }
}
