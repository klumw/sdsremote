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

  Widget _buildLeftToolbarButtons() {
    return Row(
      children: [
        // Control Panel
        OsciToolbarButton(
          label: _isAcquiring ? "Acquiring..." : "Control",
          active:
              _activePanel == ActivePanel.none &&
              !_waveformAcquired &&
              _screenDump != null,
          icon: _isAcquiring
              ? const AnimatedSyncIcon(size: 25, color: Colors.white)
              : const Icon(Icons.tune, size: 25),
          onPressed:
              (_isAcquiring ||
                  _isAcquiringWaveform ||
                  !_isOnline ||
                  _isMacroPlaying)
              ? null
              : _acquireScreenDump,
        ),
        const SizedBox(width: 16),
        // Acquire Waveform
        OsciToolbarButton(
          label: _isAcquiringWaveform ? "Acquiring..." : "Waveform",
          active: _activePanel == ActivePanel.none && _waveformAcquired,
          icon: _isAcquiringWaveform
              ? const AnimatedSyncIcon(size: 25, color: Colors.white)
              : const Icon(Icons.show_chart, size: 25),
          onPressed: (_isAcquiringWaveform || !_isOnline || _isMacroPlaying)
              ? null
              : _acquireWaveform,
        ),
        const SizedBox(width: 16),
        // Profiles
        OsciToolbarButton(
          label: "Profiles",
          icon: const Icon(Icons.save, size: 25),
          active: _activePanel == ActivePanel.profiles,
          onPressed: (_isOnline && !_isMacroPlaying)
              ? () => _togglePanel(ActivePanel.profiles)
              : null,
        ),
        const SizedBox(width: 16),
        // Data Logger
        OsciToolbarButton(
          label: "Logger",
          icon: _buildDlButtonIcon(),
          active: _activePanel == ActivePanel.dataLogger,
          onPressed: (_isOnline && !_isMacroPlaying)
              ? () => _togglePanel(ActivePanel.dataLogger)
              : null,
        ),
        if (_signalGenerator == 'jds6600' || _signalGenerator == 'fy6900') ...[
          const SizedBox(width: 16),
          OsciToolbarButton(
            label: 'Bode',
            icon: const Icon(Icons.analytics_outlined, size: 25),
            active: _activePanel == ActivePanel.bode,
            onPressed:
                (_isOnline &&
                    _sigGenDetected &&
                    !_isMacroPlaying &&
                    !_isAcquiring &&
                    !_isAcquiringWaveform)
                ? () => _togglePanel(ActivePanel.bode)
                : null,
          ),
        ],
        const SizedBox(width: 16),
        // Macro Recorder
        OsciToolbarButton(
          label: _isMacroPlaying
              ? "Playback"
              : (_isMacroRecording ? "Recording..." : "Macro"),
          active: _activePanel == ActivePanel.macroRecorder,
          icon: _isMacroPlaying
              ? const Icon(
                  Icons.play_circle,
                  size: 25,
                  color: Colors.greenAccent,
                )
              : (_isMacroRecording
                    ? const Icon(
                        Icons.fiber_manual_record,
                        size: 25,
                        color: Colors.red,
                      )
                    : const Icon(Icons.movie, size: 25)),
          // Always available so a macro can be reviewed and edited while the
          // oscilloscope is offline; the panel disables the device-dependent
          // actions itself.
          onPressed: () => _togglePanel(ActivePanel.macroRecorder),
        ),
        const SizedBox(width: 16),
        // AI Chat — icon only; its label lives in the tooltip.
        OsciToolbarButton(
          tooltip: 'AI Chat',
          icon: const Icon(Icons.auto_awesome, size: 25),
          active: _activePanel == ActivePanel.chat,
          onPressed: (_isAiEnabled && !_isMacroPlaying)
              ? () => _togglePanel(ActivePanel.chat)
              : null,
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.panelBackground,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildLeftToolbarButtons(),
            ),
          ),
          ValueListenableBuilder<VoiceInputStatus>(
            valueListenable: _voiceInputService.status,
            builder: (context, status, _) {
              final color = status.isTranscribing || status.isResponding
                  ? Colors.greenAccent
                  : Colors.cyanAccent;
              return VoiceActivityIndicator(
                active: status.isActive,
                color: color,
              );
            },
          ),
          const SizedBox(width: 8),
          OsciToolbarButton(
            label: "Help",
            icon: const Icon(Icons.help_outline, size: 25),
            active: _activePanel == ActivePanel.help,
            onPressed: _isMacroPlaying
                ? null
                : () => _togglePanel(ActivePanel.help),
            alwaysEnabled: !_isMacroPlaying,
          ),
          const SizedBox(width: 16),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.campaign, size: 25),
                color: _isMacroPlaying ? Colors.white24 : Colors.white70,
                tooltip: 'News',
                onPressed: _isMacroPlaying ? null : _showNewsDialog,
              ),
              if (_hasUnreadUpdate)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings, size: 25),
            color: _isMacroPlaying ? Colors.white24 : Colors.white70,
            tooltip: 'Settings',
            onPressed: _isMacroPlaying
                ? null
                : () => _showConfigDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.save_alt, size: 25),
            color: (_isMacroPlaying)
                ? Colors.white24
                : (_canSaveStandard ||
                      _canSaveDataLoggerReport ||
                      _canSaveBodeReport)
                ? Colors.white70
                : Colors.white24,
            tooltip: 'Save',
            onPressed:
                (_isMacroPlaying ||
                    !(_canSaveStandard ||
                        _canSaveDataLoggerReport ||
                        _canSaveBodeReport))
                ? null
                : _saveCurrentView,
          ),
          if (_canExportWaveform)
            IconButton(
              icon: const Icon(Icons.ios_share, size: 25),
              color: _isMacroPlaying ? Colors.white24 : Colors.white70,
              tooltip: 'Export Data',
              onPressed: _isMacroPlaying ? null : _showWaveformExportDialog,
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.statusBar,
        border: Border(top: BorderSide(color: Colors.white12, width: 2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (!_isUsb) ...[
                const Icon(Icons.lan, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                const Text(
                  "Device IP:",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  _ipAddress,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ] else ...[
                const Icon(Icons.usb, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                const Text(
                  "Device Mode: USB",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              if (_sigGenDetected) ...[
                const SizedBox(width: 24),
                const Icon(Icons.waves, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                const Text(
                  "Signal Generator:",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  _sigGenService?.deviceInfo?.modelName ?? 'JDS6600',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ],
          ),
          Row(
            children: [
              Text(
                _isOnline ? "ONLINE" : "OFFLINE",
                style: TextStyle(
                  color: _isOnline ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.circle,
                color: _isOnline ? Colors.greenAccent : Colors.redAccent,
                size: 14,
              ),
            ],
          ),
        ],
      ),
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
