import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/logger.dart';
import 'vnc_screen_service.dart';

/// Owns the live screen (VNC) session and the availability probe.
///
/// The controller streams frames into an [ui.Image] for the Control Panel,
/// tracks whether the instrument's VNC server is reachable, and restores the
/// periodic screen capture when a session ends. All home-page state is read
/// through callbacks, so the controller stays independent of the widget.
class LiveScreenController extends ChangeNotifier {
  LiveScreenController({
    required this.readHost,
    required this.couldUseVnc,
    required this.isControlPanelVisible,
    required this.isOnline,
    required this.isAcquiring,
    required this.isAcquiringWaveform,
    required this.isProcessingEvent,
    required this.isAutoCaptureEnabled,
    required this.stopAutoCapture,
    required this.setAutoCaptureEnabled,
    required this.clearRefreshTimer,
    required this.acquireScreenDump,
    required this.showInfo,
    required this.onChanged,
  });

  /// Returns the instrument's current IP address.
  final String Function() readHost;

  /// Whether the instrument could in principle stream its screen.
  final bool Function() couldUseVnc;

  /// Whether the Control Panel — and with it the Live toggle — is on screen.
  final bool Function() isControlPanelVisible;

  final bool Function() isOnline;
  final bool Function() isAcquiring;
  final bool Function() isAcquiringWaveform;
  final bool Function() isProcessingEvent;
  final bool Function() isAutoCaptureEnabled;

  /// Stops the periodic automatic screen capture.
  final void Function() stopAutoCapture;

  /// Enables or disables the periodic automatic screen capture.
  final void Function(bool enabled) setAutoCaptureEnabled;

  /// Cancels a pending refresh and clears its pending flag.
  final void Function() clearRefreshTimer;

  /// Fetches a fresh screen dump.
  final Future<void> Function({bool keepPanels}) acquireScreenDump;

  /// Shows an informational snackbar.
  final void Function(String message) showInfo;

  /// Called after the controller's state changed.
  final void Function() onChanged;

  static const Duration _probeInterval = Duration(seconds: 10);

  bool _reachable = false;
  bool _crashed = false;
  bool _live = false;
  bool _probing = false;
  bool _autoCaptureBeforeLive = false;
  DateTime _lastProbe = DateTime.fromMillisecondsSinceEpoch(0);
  VncScreenService? _service;
  ui.Image? _image;
  DateTime? _capturedAt;
  int _sessionId = 0;

  /// Whether the live screen should be restored when the panel returns.
  bool restoreOnPanelReturn = false;
  bool _disposed = false;

  /// Whether the instrument's VNC server answered the last probe.
  bool get isReachable => _reachable;

  /// Whether the last live session failed and the toggle stays disabled.
  bool get isCrashed => _crashed;

  /// Whether a live session is running.
  bool get isLive => _live;

  /// The most recently decoded live frame.
  ui.Image? get image => _image;

  /// Time the current [image] frame was received.
  DateTime? get capturedAt => _capturedAt;

  /// Probes the instrument's VNC server (rate limited).
  Future<void> refreshAvailability({bool force = false}) async {
    if (_disposed || _probing || _live) return;
    if (!couldUseVnc() || !isControlPanelVisible()) {
      clearAvailability();
      return;
    }
    final now = DateTime.now();
    if (!force && now.difference(_lastProbe) < _probeInterval) {
      return;
    }
    _probing = true;
    _lastProbe = now;
    bool reachable;
    try {
      reachable = await VncScreenService.isReachable(readHost());
    } finally {
      _probing = false;
    }
    if (_disposed) return;
    if (!reachable && _reachable) {
      // The server disappeared between sessions.
      _reachable = false;
      _crashed = true;
      _notify();
    } else if (reachable && (!_reachable || _crashed)) {
      _reachable = true;
      _crashed = false;
      _notify();
    }
  }

  /// Probes the server when the Control Panel becomes visible and restores
  /// the live screen if it was active before switching panels.
  Future<void> refreshAndRestoreLive() async {
    final bool restore = restoreOnPanelReturn;
    restoreOnPanelReturn = false;
    if (_disposed || !couldUseVnc() || !isControlPanelVisible()) return;
    await refreshAvailability(force: true);
    // A ping-triggered probe may still be in flight; wait for its result.
    var waited = 0;
    while (_probing && !_disposed && waited < 20) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      waited++;
    }
    if (!restore || _disposed || _live || !_reachable) return;
    if (!couldUseVnc() || !isControlPanelVisible()) return;
    setLiveEnabled(true);
  }

  /// Drops the cached availability, e.g. when the connection mode changes.
  void clearAvailability() {
    if (!_reachable && !_crashed) return;
    _reachable = false;
    _crashed = false;
    _notify();
  }

  /// Switches the live screen on or off.
  ///
  /// Live streaming replaces both the periodic automatic capture and the
  /// per-command screen dumps; while it runs, no SCPI driven screen captures
  /// are performed.
  void setLiveEnabled(bool enabled) {
    if (enabled == _live) return;
    if (enabled) {
      if (!_reachable || !couldUseVnc()) return;
      // Live streaming and the periodic capture are mutually exclusive.
      // Remember the toggle so it can be restored when live ends.
      _autoCaptureBeforeLive = isAutoCaptureEnabled();
      stopAutoCapture();
      clearRefreshTimer();
      final service = VncScreenService(
        host: readHost(),
        onFrame: _onFrame,
        onClosed: _onClosed,
      );
      _sessionId++;
      _service = service;
      _live = true;
      _crashed = false;
      _notify();
      unawaited(service.start());
    } else {
      stopLive();
    }
  }

  void _onFrame(VncFrame frame) {
    if (_disposed || !_live) return;
    final session = _sessionId;
    ui.decodeImageFromPixels(
      frame.rgba,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      (image) {
        if (_disposed || !_live || session != _sessionId) {
          image.dispose();
          return;
        }
        final previous = _image;
        _image = image;
        _capturedAt = DateTime.now();
        _notify();
        if (previous != null) {
          // The old frame may still be painted in this frame; release it
          // only after the widgets have rebuilt.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => previous.dispose(),
          );
        }
      },
    );
  }

  /// Called by the VNC service when the session ends without [stopLive]
  /// asking for it — typically because the instrument's VNC daemon died.
  void _onClosed(Object? error) {
    if (!_live) return;
    AppLogger().warning('Live screen session ended: ${error ?? 'closed'}');
    stopLive(crashed: true);
  }

  /// Stops the live screen and returns to ordinary screen captures.
  ///
  /// On [crashed] the Live toggle is disabled until a probe succeeds again.
  /// [fetchScreen] fetches a fresh screen dump immediately; it is disabled
  /// when the Control Panel is being left anyway. [restoreAutoCapture] puts
  /// the periodic capture back into the state it had before live started.
  void stopLive({
    bool crashed = false,
    bool fetchScreen = true,
    bool restoreAutoCapture = true,
  }) {
    final service = _service;
    final wasLive = _live;
    _service = null;
    _sessionId++;
    service?.stop();
    final image = _image;
    _image = null;
    _capturedAt = null;
    if (image != null) {
      // The panel may still paint the last frame until it rebuilds.
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
    }
    if (!wasLive) return;

    _live = false;
    if (crashed) {
      _reachable = false;
      _crashed = true;
    }
    _notify();

    final restore = restoreAutoCapture && _autoCaptureBeforeLive;
    _autoCaptureBeforeLive = false;
    if (restore && !_disposed && isOnline()) setAutoCaptureEnabled(true);
    if (crashed && !_disposed) {
      showInfo('Live screen lost — switched back to screen captures');
    }
    if (fetchScreen &&
        !_disposed &&
        isOnline() &&
        !isAcquiring() &&
        !isAcquiringWaveform() &&
        !isProcessingEvent()) {
      unawaited(acquireScreenDump(keepPanels: true));
    }
  }

  void _notify() {
    if (_disposed) return;
    onChanged();
  }

  @override
  void dispose() {
    _disposed = true;
    _live = false;
    _sessionId++;
    _service?.stop();
    _service = null;
    _image?.dispose();
    _image = null;
    _capturedAt = null;
    super.dispose();
  }
}
