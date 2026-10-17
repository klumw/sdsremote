/// Opens, focuses and closes the signal-generator OS window.
///
/// The launcher is split from `desktop_multi_window` behind [MultiWindowBackend]
/// so the single-instance/open-or-focus logic can be unit-tested without the
/// plugin. [WindowControllerBackend] is the production implementation.
library;

import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import 'siggen_window_protocol.dart';

/// One native window known to the multi-window backend.
abstract class MultiWindowHandle {
  String get windowId;
  String get arguments;
  Future<void> show();
  Future<void> focus();
  Future<void> close();
  Future<void> invoke(String method, [Map<String, dynamic>? arguments]);
}

/// Narrow seam over `desktop_multi_window`.
abstract class MultiWindowBackend {
  /// Notifies whenever the window list changes.
  Stream<void> get windowChanges;

  Future<List<MultiWindowHandle>> listWindows();

  /// Creates a hidden window and returns its handle.
  Future<MultiWindowHandle> createWindow(String arguments);
}

/// Production backend based on `WindowController`.
class WindowControllerBackend implements MultiWindowBackend {
  const WindowControllerBackend();

  @override
  Stream<void> get windowChanges => onWindowsChanged;

  @override
  Future<List<MultiWindowHandle>> listWindows() async {
    final controllers = await WindowController.getAll();
    return controllers.map(WindowControllerHandle.new).toList();
  }

  @override
  Future<MultiWindowHandle> createWindow(String arguments) async {
    final controller = await WindowController.create(
      WindowConfiguration(arguments: arguments, hiddenAtLaunch: true),
    );
    return WindowControllerHandle(controller);
  }
}

/// Handle wrapping one `WindowController`.
class WindowControllerHandle implements MultiWindowHandle {
  WindowControllerHandle(this.controller);

  final WindowController controller;

  @override
  String get windowId => controller.windowId;

  @override
  String get arguments => controller.arguments;

  @override
  Future<void> show() => controller.show();

  @override
  Future<void> focus() async {
    try {
      await controller.invokeMethod<void>('focus');
    } catch (_) {
      // The child engine may not have registered its handler yet.
      await controller.show();
    }
  }

  @override
  Future<void> close() async {
    try {
      await controller.invokeMethod<void>('closeWindow');
    } catch (_) {
      await controller.hide();
    }
  }

  @override
  Future<void> invoke(String method, [Map<String, dynamic>? arguments]) =>
      controller.invokeMethod<void>(method, arguments);
}

/// Ensures at most one signal-generator window exists.
class SigGenWindowLauncher {
  SigGenWindowLauncher({
    required this.backend,
    this.canOpen,
    this.onOpenChanged,
  }) {
    _changeSubscription = backend.windowChanges.listen(
      (_) => unawaited(syncOpenState()),
    );
  }

  final MultiWindowBackend backend;

  /// Gate evaluated before opening, e.g. generator must be detected.
  final bool Function()? canOpen;

  /// Called whenever the open state changes.
  final void Function(bool open)? onOpenChanged;

  StreamSubscription<void>? _changeSubscription;
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
      final windows = await backend.listWindows();
      final existing = _findWindow(windows);
      if (existing != null) {
        await existing.show();
        await existing.focus();
        _setOpen(true);
        return true;
      }

      // Only create a new window when the caller allows it (generator
      // configured and detected). An already open window is always focused.
      if (canOpen != null && !canOpen!()) return false;

      await backend.createWindow(SigGenWindowArguments.toArguments());
      // Do not show the window here: the child engine shows itself after its
      // first fully painted frame. Showing it now would display an empty
      // black window until Flutter renders the UI.
      _setOpen(true);
      return true;
    } catch (_) {
      await syncOpenState();
      return _open;
    }
  }

  /// Closes every signal-generator window and updates the open state.
  Future<void> close() async {
    try {
      final windows = await backend.listWindows();
      for (final window in windows) {
        if (SigGenWindowArguments.isSigGenWindow(window.arguments)) {
          await window.close();
        }
      }
    } catch (_) {
      // Window may already be gone.
    }
    _setOpen(false);
  }

  /// Pushes a state snapshot to the open child window.
  Future<void> pushState(SigGenWindowState state) async {
    final windows = await backend.listWindows();
    final window = _findWindow(windows);
    if (window == null) return;
    await window.invoke('state', state.toJson());
  }

  /// Re-reads the window list, e.g. after the user closed the child window.
  Future<void> syncOpenState() async {
    if (_disposed) return;
    try {
      final windows = await backend.listWindows();
      _setOpen(_findWindow(windows) != null);
    } catch (_) {
      // Keep the last known state on a transient backend error. Treating a
      // failed list call as "closed" would deactivate the host and stop the
      // generator polling, leaving the child window with stale CONNECTED
      // state.
    }
  }

  MultiWindowHandle? _findWindow(List<MultiWindowHandle> windows) {
    for (final window in windows) {
      if (SigGenWindowArguments.isSigGenWindow(window.arguments)) {
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
    _changeSubscription?.cancel();
    _changeSubscription = null;
  }
}
