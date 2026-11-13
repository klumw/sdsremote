part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeChrome on _OsciHomePageState {
  Widget _buildMainContent() {
    if (_activePanel != ActivePanel.none) {
      return switch (_activePanel) {
        ActivePanel.help => _buildHelpWindow(),
        ActivePanel.chat => _buildChatWindow(),
        ActivePanel.profiles => _buildProfilesWindow(),
        ActivePanel.dataLogger => _buildDataLoggerWindow(),
        ActivePanel.macroRecorder => _buildMacroRecorderWindow(),
        ActivePanel.bode => _buildBodePlotWindow(),
        _ => const SizedBox.shrink(),
      };
    }
    if (_waveformAcquired) return _buildWaveformAnalysisView();
    if (_screenDump != null) return _buildPhysicalPanel();
    return _buildWelcomeScreen();
  }

  Widget _buildTopBar() {
    return HomePageTopBar(
      voiceStatus: _voiceInputService.status,
      activePanel: _activePanel,
      hasScreenDump: _screenDump != null,
      waveformAcquired: _waveformAcquired,
      isOnline: _isOnline,
      isAcquiring: _isAcquiring,
      isAcquiringWaveform: _isAcquiringWaveform,
      isMacroPlaying: _isMacroPlaying,
      isMacroRecording: _isMacroRecording,
      isAiEnabled: _isAiEnabled,
      signalGenerator: _signalGenerator,
      signalGeneratorDetected: _sigGenDetected,
      hasUnreadUpdate: _hasUnreadUpdate,
      canSave:
          _canSaveStandard || _canSaveDataLoggerReport || _canSaveBodeReport,
      canExportWaveform: _canExportWaveform,
      loggerIcon: _buildDlButtonIcon(),
      onAcquireScreenDump: _acquireScreenDump,
      onAcquireWaveform: _acquireWaveform,
      onTogglePanel: _togglePanel,
      onShowNews: _showNewsDialog,
      onOpenSettings: () => _showConfigDialog(context),
      onSave: _saveCurrentView,
      onShowExport: _showWaveformExportDialog,
    );
  }

  Widget _buildStatusBar() {
    return HomePageStatusBar(
      isUsb: _isUsb,
      ipAddress: _ipAddress,
      isOnline: _isOnline,
      signalGeneratorDetected: _sigGenDetected,
      signalGeneratorModel: _sigGenService?.deviceInfo?.modelName ?? 'JDS6600',
    );
  }

  void _togglePanel(ActivePanel panel) {
    // Switching between top-bar panels always ends an assistant microphone
    // session; the microphone starts switched off when the next panel opens.
    unawaited(_voiceInputService.stop());
    final previousActivePanel = _activePanel;
    final bool wasOnControlPanel =
        _activePanel == ActivePanel.none && !_waveformAcquired;
    // Leaving the Control Panel stops its periodic screen capture and the
    // live screen stream. A running live screen is remembered and restored
    // when the Control Panel is shown again.
    if (panel != ActivePanel.none) {
      if (wasOnControlPanel && _vncLive) {
        _restoreLiveOnPanelReturn = true;
      }
      _stopAutoCapture();
      _stopVncLive(fetchScreen: false, restoreAutoCapture: false);
      _clearVncAvailability();
    }
    // Stop the Data Logger immediately when switching away from it
    if (_activePanel == ActivePanel.dataLogger &&
        panel != ActivePanel.dataLogger) {
      _stopDataLoggerIfRunning();
      _stopBodeIfRunning();
    }
    // Stop a running Bode sweep when leaving its panel.
    if (_activePanel == ActivePanel.bode && panel != ActivePanel.bode) {
      _stopBodeIfRunning();
    }
    // A debug session keeps an instrument connection open; stop it when
    // leaving the macro recorder.
    if (_activePanel == ActivePanel.macroRecorder &&
        panel != ActivePanel.macroRecorder) {
      unawaited(_stopMacroDebugSession());
    }
    _setState(() {
      if (_activePanel == panel) {
        // Toggle off: go back to previous
        _activePanel = _previousPanel;
        _previousPanel = ActivePanel.none;
      } else {
        // Toggle on: store current as previous and set new
        _previousPanel = _activePanel;
        _activePanel = panel;
      }

      // Remember exactly which macro view (player or editor) was visible
      // when the macro panel was left.
      if (previousActivePanel == ActivePanel.macroRecorder &&
          _activePanel != ActivePanel.macroRecorder) {
        _lastMacroPanelWasEditor = _showMacroEditor;
      }

      // Special logic for profiles
      if (_activePanel == ActivePanel.profiles) {
        _loadProfileFiles();
      }

      // Special logic for macro recorder
      if (_activePanel == ActivePanel.macroRecorder) {
        // Restore the view the user left.
        _showMacroEditor = _lastMacroPanelWasEditor;
        _loadMacroFiles();
      }
    });

    // Back on the Control Panel: re-check the VNC server and restore the
    // live screen when it was active before switching away.
    if (_activePanel == ActivePanel.none && !_waveformAcquired) {
      unawaited(_refreshVncAndRestoreLive());
    }
  }

  void _showErrorSnackBar(
    String message, {
    Duration duration = const Duration(seconds: 5),
  }) {
    // Every error that is shown to the user must also be in the log at ERROR
    // level, even when the widget is no longer mounted.
    AppLogger().error('UI error: $message');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: duration,
      ),
    );
  }

  void _showInfoSnackBar(
    String message, {
    Duration duration = const Duration(seconds: 3),
    Color? backgroundColor,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        backgroundColor: backgroundColor,
      ),
    );
  }
}
