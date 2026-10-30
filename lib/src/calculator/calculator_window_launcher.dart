/// Single-instance launcher for the engineering-calculator OS window.
///
/// The multi-window backend is shared with the signal-generator launcher; this
/// class only supplies the calculator window marker and the no-hardware
/// single-instance policy.
library;

import 'dart:async';

import '../signal_generator/siggen_window_launcher.dart';
import 'calculator_window_protocol.dart';

/// Supplies the calculator window's target position in the main window.
typedef CalculatorWindowPositionProvider =
    Future<CalculatorWindowPosition?> Function();

class CalculatorWindowLauncher {
  CalculatorWindowLauncher({
    required this.backend,
    this.onOpenChanged,
    this.positionProvider,
  }) {
    _subscription = backend.windowChanges.listen(
      (_) => unawaited(syncOpenState()),
    );
  }

  final MultiWindowBackend backend;
  final void Function(bool open)? onOpenChanged;
  final CalculatorWindowPositionProvider? positionProvider;

  StreamSubscription<void>? _subscription;
  Future<bool>? _inFlight;
  bool _open = false;
  bool _disposed = false;

  bool get isOpen => _open;

  /// Shows and focuses the existing window, or creates exactly one.
  Future<bool> openOrFocus() {
    if (_disposed) return Future<bool>.value(false);
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final future = _openOrFocus();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<bool> _openOrFocus() async {
    try {
      final position = await _targetPosition();
      final existing = await _findWindow();
      if (existing != null) {
        await existing.show();
        if (position != null) {
          try {
            await existing.invoke('positionWindow', {
              'left': position.left,
              'top': position.top,
            });
          } catch (_) {
            // Older child engines may not provide the positioning handler.
          }
        }
        await existing.focus();
        _setOpen(true);
        return true;
      }
      await backend.createWindow(
        CalculatorWindowArguments.toArguments(position: position),
      );
      // The child engine shows itself after its first painted frame.
      _setOpen(true);
      return true;
    } catch (_) {
      await syncOpenState();
      return _open;
    }
  }

  Future<CalculatorWindowPosition?> _targetPosition() async {
    final provider = positionProvider;
    if (provider == null) return null;
    try {
      return await provider();
    } catch (_) {
      return null;
    }
  }

  Future<void> close() async {
    try {
      final windows = await backend.listWindows();
      for (final window in windows) {
        if (CalculatorWindowArguments.isCalculatorWindow(window.arguments)) {
          await window.close();
        }
      }
    } catch (_) {
      // Window may already be gone.
    }
    _setOpen(false);
  }

  Future<void> syncOpenState() async {
    if (_disposed) return;
    try {
      _setOpen(await _findWindow() != null);
    } catch (_) {
      // Keep the last known state on a transient backend error.
    }
  }

  Future<MultiWindowHandle?> _findWindow() async {
    final windows = await backend.listWindows();
    for (final window in windows) {
      if (CalculatorWindowArguments.isCalculatorWindow(window.arguments)) {
        return window;
      }
    }
    return null;
  }

  void _setOpen(bool open) {
    if (_disposed || _open == open) return;
    _open = open;
    onOpenChanged?.call(open);
  }

  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
  }
}
