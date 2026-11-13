import 'dart:async';

import '../core/logger.dart';
import 'signal_generator_service.dart';
import 'siggen_window_host.dart';
import 'siggen_window_launcher.dart';
import 'siggen_window_protocol.dart';
import 'siggen_window_server.dart';

/// Owns the signal generator's OS child window and its command bridge.
///
/// The coordinator creates the host, server, and launcher lazily for the
/// current generator service, tracks whether the window is open, and forwards
/// state snapshots to the child window.
class SigGenWindowCoordinator {
  SigGenWindowCoordinator({
    required this.readService,
    required this.canMutate,
    required this.canOpen,
    required this.isBodeRunning,
    required this.onOpenChanged,
  });

  /// Returns the currently configured signal generator service.
  final SignalGeneratorService? Function() readService;

  /// Whether the generator's channel settings may be changed.
  final bool Function() canMutate;

  /// Whether the child window may be opened.
  final bool Function() canOpen;

  /// Whether a Bode sweep is running.
  final bool Function() isBodeRunning;

  /// Called after the window's open state changed.
  final void Function(bool open) onOpenChanged;

  SigGenWindowHost? _host;
  SigGenWindowServer? _server;
  SigGenWindowLauncher? _launcher;
  bool _open = false;

  /// Whether the child window is currently open.
  bool get isOpen => _open;

  /// Creates the window bridge lazily for the current generator service.
  void ensureSupport() {
    final service = readService();
    if (service == null) return;

    _host ??= SigGenWindowHost(
      service: service,
      sink: _SigGenWindowSink(_pushState),
      canMutate: canMutate,
    );

    _server ??= SigGenWindowServer(
      handler: (method, arguments) async {
        final host = _host;
        if (host == null) {
          return SigGenCommandResult.failure(
            const SigGenWindowState(),
            'Signal generator is not configured',
            errorType: 'disconnected',
          );
        }
        return host.handleCommand(method, arguments);
      },
    );
    unawaited(
      _server!.register().catchError((Object error) {
        AppLogger(
          agentName: 'SigGen',
          toolName: 'window',
        ).error('Signal generator bridge registration failed: $error');
      }),
    );

    _launcher ??= SigGenWindowLauncher(
      backend: const WindowControllerBackend(),
      canOpen: canOpen,
      onOpenChanged: _handleOpenChanged,
    );
  }

  /// Tears down the bridge when the generator configuration changes.
  void disposeSupport({bool closeWindow = false}) {
    final launcher = _launcher;
    _launcher = null;
    if (launcher != null) {
      if (closeWindow) unawaited(launcher.close());
      launcher.dispose();
    }
    _host?.deactivate();
    _host?.dispose();
    _host = null;
    _open = false;
    readService()?.setPanelActive(false);
  }

  /// Disposes the command server owned by the home page.
  void disposeServer() {
    final server = _server;
    _server = null;
    if (server != null) unawaited(server.dispose());
  }

  Future<void> openOrFocus() async {
    await _launcher?.openOrFocus();
  }

  /// Closes the child window during application shutdown.
  Future<void> closeWindow() async {
    try {
      await _launcher?.close().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Continue with the normal shutdown even if the child is unresponsive.
    }
  }

  void _handleOpenChanged(bool open) {
    _open = open;
    readService()?.setPanelActive(open && !isBodeRunning());
    final host = _host;
    if (open) {
      host?.activate();
    } else {
      host?.deactivate();
    }
    onOpenChanged(open);
  }

  Future<void> _pushState(SigGenWindowState state) async {
    final launcher = _launcher;
    if (launcher == null || !_open) return;
    try {
      await launcher.pushState(state);
    } catch (_) {
      // The child window may have closed between the list and the push.
    }
  }
}

/// Adapter that lets [SigGenWindowHost] push snapshots into the launcher.
class _SigGenWindowSink implements SigGenWindowEventSink {
  _SigGenWindowSink(this._push);

  final Future<void> Function(SigGenWindowState) _push;

  @override
  Future<void> pushState(SigGenWindowState state) => _push(state);
}
