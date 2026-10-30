/// Single-instance launcher for the engineering-calculator OS window.
///
/// The multi-window backend is shared with the signal-generator launcher; this
/// class only supplies the calculator window marker and the no-hardware
/// single-instance policy.
library;

import 'dart:async';

import '../signal_generator/siggen_window_launcher.dart';
import 'calculator_window_protocol.dart';

class CalculatorWindowLauncher {
  CalculatorWindowLauncher({required this.backend, this.onOpenChanged}) {
    _subscription = backend.windowChanges.listen(
      (_) => unawaited(syncOpenState()),
    );
  }

  final MultiWindowBackend backend;
  final void Function(bool open)? onOpenChanged;

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
      final existing = await _findWindow();
      if (existing != null) {
        await existing.show();
        await existing.focus();
        _setOpen(true);
        return true;
      }
      await backend.createWindow(CalculatorWindowArguments.toArguments());
      // The child engine shows itself after its first painted frame.
      _setOpen(true);
      return true;
    } catch (_) {
      await syncOpenState();
      return _open;
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
