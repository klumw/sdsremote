part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeLiveScreen on _OsciHomePageState {
  /// Whether the instrument could in principle stream its screen: a
  /// four-channel model connected over IP.
  bool get _couldUseVnc => !_isUsb && _isOnline && _numChannels >= 4;

  /// Whether the Control Panel — and with it the Live toggle — is on screen.
  bool get _isControlPanelVisible =>
      _activePanel == ActivePanel.none &&
      !_waveformAcquired &&
      _screenDump != null;

  /// Whether the Live toggle should be rendered. After a failed session it
  /// stays visible but disabled until a probe succeeds again.
  bool get _showLiveButton =>
      _couldUseVnc && _isControlPanelVisible && (_vncReachable || _vncCrashed);

  /// Probes the instrument's VNC server (rate limited) and updates the
  /// availability of the Live toggle.
  Future<void> _refreshVncAvailability({bool force = false}) async {
    if (!mounted || _vncProbing || _vncLive) return;
    if (!_couldUseVnc || !_isControlPanelVisible) {
      _clearVncAvailability();
      return;
    }
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastVncProbe) < _OsciHomePageState._vncProbeInterval) {
      return;
    }
    _vncProbing = true;
    _lastVncProbe = now;
    bool reachable;
    try {
      reachable = await VncScreenService.isReachable(_ipAddress);
    } finally {
      _vncProbing = false;
    }
    if (!mounted) return;
    if (!reachable && _vncReachable) {
      // The server disappeared between sessions.
      _setState(() {
        _vncReachable = false;
        _vncCrashed = true;
      });
    } else if (reachable && (!_vncReachable || _vncCrashed)) {
      _setState(() {
        _vncReachable = true;
        _vncCrashed = false;
      });
    }
  }

  /// Probes the VNC server when the Control Panel becomes visible and
  /// restores the live screen if it was active before switching panels.
  Future<void> _refreshVncAndRestoreLive() async {
    final bool restore = _restoreLiveOnPanelReturn;
    _restoreLiveOnPanelReturn = false;
    if (!mounted || !_couldUseVnc || !_isControlPanelVisible) return;
    await _refreshVncAvailability(force: true);
    // A ping-triggered probe may still be in flight; wait for its result.
    var waited = 0;
    while (_vncProbing && mounted && waited < 20) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      waited++;
    }
    if (!restore || !mounted || _vncLive || !_vncReachable) return;
    if (!_couldUseVnc || !_isControlPanelVisible) return;
    _setVncLiveEnabled(true);
  }

  /// Drops the cached VNC availability, e.g. when the connection mode changes.
  void _clearVncAvailability() {
    if (!_vncReachable && !_vncCrashed) return;
    if (mounted) {
      _setState(() {
        _vncReachable = false;
        _vncCrashed = false;
      });
    } else {
      _vncReachable = false;
      _vncCrashed = false;
    }
  }

  /// Switches the live screen on or off.
  ///
  /// Live streaming replaces both the periodic automatic capture and the
  /// per-command screen dumps; while it runs, no SCPI driven screen captures
  /// are performed.
  void _setVncLiveEnabled(bool enabled) {
    if (enabled == _vncLive) return;
    if (enabled) {
      if (!_vncReachable || !_couldUseVnc) return;
      // Live streaming and the periodic capture are mutually exclusive.
      // Remember the toggle so it can be restored when live ends.
      _autoCaptureBeforeLive = _autoCaptureEnabled;
      _stopAutoCapture();
      _refreshTimer?.cancel();
      _refreshPending = false;
      final service = VncScreenService(
        host: _ipAddress,
        onFrame: _onVncFrame,
        onClosed: _onVncClosed,
      );
      _vncSessionId++;
      _setState(() {
        _vncService = service;
        _vncLive = true;
        _vncCrashed = false;
      });
      unawaited(service.start());
    } else {
      _stopVncLive();
    }
  }

  void _onVncFrame(VncFrame frame) {
    if (!mounted || !_vncLive) return;
    final session = _vncSessionId;
    ui.decodeImageFromPixels(
      frame.rgba,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      (image) {
        if (!mounted || !_vncLive || session != _vncSessionId) {
          image.dispose();
          return;
        }
        final previous = _liveScreenImage;
        _setState(() {
          _liveScreenImage = image;
          _liveScreenCapturedAt = DateTime.now();
        });
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

  /// Called by the VNC service when the session ends without [_stopVncLive]
  /// asking for it — typically because the instrument's VNC daemon died.
  void _onVncClosed(Object? error) {
    if (!_vncLive) return;
    AppLogger().warning('Live screen session ended: ${error ?? 'closed'}');
    _stopVncLive(crashed: true);
  }

  /// Stops the live screen and returns to ordinary screen captures.
  ///
  /// On [crashed] the Live toggle is disabled until a probe succeeds again.
  /// [fetchScreen] fetches a fresh screen dump immediately; it is disabled
  /// when the Control Panel is being left anyway. [restoreAutoCapture] puts
  /// the periodic capture back into the state it had before live started.
  void _stopVncLive({
    bool crashed = false,
    bool fetchScreen = true,
    bool restoreAutoCapture = true,
  }) {
    final service = _vncService;
    final wasLive = _vncLive;
    _vncService = null;
    _vncSessionId++;
    service?.stop();
    final image = _liveScreenImage;
    _liveScreenImage = null;
    _liveScreenCapturedAt = null;
    if (image != null) {
      // The panel may still paint the last frame until it rebuilds.
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
    }
    if (!wasLive) return;

    if (mounted) {
      _setState(() {
        _vncLive = false;
        if (crashed) {
          _vncReachable = false;
          _vncCrashed = true;
        }
      });
    } else {
      _vncLive = false;
      if (crashed) {
        _vncReachable = false;
        _vncCrashed = true;
      }
    }

    final restore = restoreAutoCapture && _autoCaptureBeforeLive;
    _autoCaptureBeforeLive = false;
    if (restore && mounted && _isOnline) _setAutoCaptureEnabled(true);
    if (crashed && mounted) {
      _showInfoSnackBar('Live screen lost — switched back to screen captures');
    }
    if (fetchScreen &&
        mounted &&
        _isOnline &&
        !_isAcquiring &&
        !_isAcquiringWaveform &&
        !_isProcessingEvent) {
      unawaited(_acquireScreenDump(keepPanels: true));
    }
  }
}
