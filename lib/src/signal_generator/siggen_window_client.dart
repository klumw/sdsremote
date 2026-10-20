/// Child-engine client for the signal-generator window bridge.
///
/// The interface is intentionally small so the panel controller and widget
/// tests can use an in-memory fake. [DesktopSigGenWindowClient] is the real
/// implementation based on `desktop_multi_window` and `window_manager`.
library;

import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'models.dart';
import 'siggen_window_protocol.dart';

/// Commands and state stream used by the child-window UI.
abstract class SigGenWindowClient {
  /// Pushes from the main window.
  Stream<SigGenWindowState> get states;

  Future<SigGenCommandResult> getSnapshot();
  Future<SigGenCommandResult> refreshGenerator();

  Future<SigGenCommandResult> setWaveform(
    int channel,
    Jds6600Waveform waveform,
  );
  Future<SigGenCommandResult> setFrequency(int channel, double hz);
  Future<SigGenCommandResult> setAmplitude(int channel, double vpp);
  Future<SigGenCommandResult> setOffset(int channel, double volts);
  Future<SigGenCommandResult> setDuty(int channel, double percent);
  Future<SigGenCommandResult> setPhase(int channel, double degrees);
  Future<SigGenCommandResult> setOutput(int channel, bool enabled);

  Future<void> dispose();
}

/// Real client using a unidirectional command channel and the window's
/// controller channel for state pushes and window actions.
class DesktopSigGenWindowClient implements SigGenWindowClient {
  DesktopSigGenWindowClient._(this._controller, this._channel);

  /// Creates the client for the current child engine.
  static Future<DesktopSigGenWindowClient> create() async {
    final controller = await WindowController.fromCurrentEngine();
    final client = DesktopSigGenWindowClient._(
      controller,
      const WindowMethodChannel(
        sigGenControlChannel,
        mode: ChannelMode.unidirectional,
      ),
    );
    await controller.setWindowMethodHandler(client._handleWindowMethod);
    return client;
  }

  final WindowController _controller;
  final WindowMethodChannel _channel;
  final StreamController<SigGenWindowState> _states =
      StreamController<SigGenWindowState>.broadcast();

  @override
  Stream<SigGenWindowState> get states => _states.stream;

  Future<dynamic> _handleWindowMethod(MethodCall call) async {
    switch (call.method) {
      case 'state':
        final arguments = call.arguments;
        if (arguments is Map) {
          final state = SigGenWindowState.fromJson(
            arguments.cast<String, dynamic>(),
          );
          if (!_states.isClosed) _states.add(state);
        }
        return null;
      case 'focus':
        await windowManager.show();
        await windowManager.focus();
        return null;
      case 'closeWindow':
        await windowManager.close();
        return null;
      default:
        throw MissingPluginException('Not implemented: ${call.method}');
    }
  }

  Future<SigGenCommandResult> _invoke(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    try {
      final response = await _channel.invokeMethod<dynamic>(method, arguments);
      if (response is Map) {
        return SigGenCommandResult.fromJson(response.cast<String, dynamic>());
      }
      return SigGenCommandResult.failure(
        const SigGenWindowState(),
        'Invalid response from the main window',
        errorType: 'protocol',
      );
    } on WindowChannelException catch (error) {
      return SigGenCommandResult.failure(
        const SigGenWindowState(),
        'Main window unavailable: $error',
        errorType: 'disconnected',
      );
    } on PlatformException catch (error) {
      return SigGenCommandResult.failure(
        const SigGenWindowState(),
        'Bridge error: ${error.message ?? error.code}',
        errorType: 'protocol',
      );
    }
  }

  @override
  Future<SigGenCommandResult> getSnapshot() =>
      _invoke(SigGenWindowMethods.getSnapshot);

  @override
  Future<SigGenCommandResult> refreshGenerator() =>
      _invoke(SigGenWindowMethods.refreshGenerator);

  @override
  Future<SigGenCommandResult> setWaveform(
    int channel,
    Jds6600Waveform waveform,
  ) => _invoke(SigGenWindowMethods.setWaveform, {
    'channel': channel,
    'waveform': waveform.name,
  });

  @override
  Future<SigGenCommandResult> setFrequency(int channel, double hz) => _invoke(
    SigGenWindowMethods.setFrequency,
    {'channel': channel, 'value': hz},
  );

  @override
  Future<SigGenCommandResult> setAmplitude(int channel, double vpp) => _invoke(
    SigGenWindowMethods.setAmplitude,
    {'channel': channel, 'value': vpp},
  );

  @override
  Future<SigGenCommandResult> setOffset(int channel, double volts) => _invoke(
    SigGenWindowMethods.setOffset,
    {'channel': channel, 'value': volts},
  );

  @override
  Future<SigGenCommandResult> setDuty(int channel, double percent) => _invoke(
    SigGenWindowMethods.setDuty,
    {'channel': channel, 'value': percent},
  );

  @override
  Future<SigGenCommandResult> setPhase(int channel, double degrees) => _invoke(
    SigGenWindowMethods.setPhase,
    {'channel': channel, 'value': degrees},
  );

  @override
  Future<SigGenCommandResult> setOutput(int channel, bool enabled) => _invoke(
    SigGenWindowMethods.setOutput,
    {'channel': channel, 'enabled': enabled},
  );

  @override
  Future<void> dispose() async {
    try {
      await _controller.setWindowMethodHandler(null);
    } catch (_) {
      // Engine may already be shutting down.
    }
    await _states.close();
  }
}
