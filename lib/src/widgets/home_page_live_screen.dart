part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

/// Bridges the private home-page state to [LiveScreenController].
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
      _couldUseVnc &&
      _isControlPanelVisible &&
      (_liveScreenController.isReachable || _liveScreenController.isCrashed);

  bool get _vncLive => _liveScreenController.isLive;

  bool get _vncReachable => _liveScreenController.isReachable;

  ui.Image? get _liveScreenImage => _liveScreenController.image;

  DateTime? get _liveScreenCapturedAt => _liveScreenController.capturedAt;

  /// Remembers that the live screen was active when the Control Panel was
  /// left, so it can be switched on again when the panel is shown again.
  set _restoreLiveOnPanelReturn(bool value) =>
      _liveScreenController.restoreOnPanelReturn = value;

  Future<void> _refreshVncAvailability({bool force = false}) =>
      _liveScreenController.refreshAvailability(force: force);

  Future<void> _refreshVncAndRestoreLive() =>
      _liveScreenController.refreshAndRestoreLive();

  void _clearVncAvailability() => _liveScreenController.clearAvailability();

  void _setVncLiveEnabled(bool enabled) =>
      _liveScreenController.setLiveEnabled(enabled);

  void _stopVncLive({
    bool crashed = false,
    bool fetchScreen = true,
    bool restoreAutoCapture = true,
  }) => _liveScreenController.stopLive(
    crashed: crashed,
    fetchScreen: fetchScreen,
    restoreAutoCapture: restoreAutoCapture,
  );
}
