part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeSettings on _OsciHomePageState {
  Widget _buildSettingsPanel() {
    return SettingsPanel(
      offset: _settingsOffset,
      ipAddress: _ipAddress,
      isUsb: _isUsb,
      signalGenerator: _signalGenerator,
      onSignalGeneratorChanged: (value) async {
        final changed = value != _signalGenerator;
        _setState(() => _signalGenerator = value);
        await AppPreferences.setString('siggen_device', value);
        if (changed) {
          // The Bode service is bound to the service instance; stop it and
          // return to the configuration form before the family changes.
          _stopBodeIfRunning();
          if (_activePanel == ActivePanel.bode) {
            _setState(() => _activePanel = ActivePanel.none);
          }
        }
        _configureSigGenDetection();
      },
      signalGeneratorShortcut: _signalGeneratorShortcut.id,
      onSignalGeneratorShortcutChanged: (value) async {
        final shortcut = SignalGeneratorShortcut.byId(value);
        if (shortcut.id == _signalGeneratorShortcut.id) return;
        _setState(() => _signalGeneratorShortcut = shortcut);
        await AppPreferences.setString(
          'signal_generator_shortcut',
          shortcut.id,
        );
      },
      calculatorShortcut: _calculatorShortcut.id,
      onCalculatorShortcutChanged: (value) async {
        final shortcut = CalculatorShortcut.byId(value);
        if (shortcut.id == _calculatorShortcut.id) return;
        _setState(() => _calculatorShortcut = shortcut);
        await AppPreferences.setString('calculator_shortcut', shortcut.id);
      },
      providerNames: providerConfigs.map((c) => c.providerName).toList(),
      selectedProvider: _aiProvider,
      aiApiToken: _aiApiToken,
      llmModel: _llmModel,
      saveWithParams: _saveWithParams,
      askForFilenamePrefix: _askForFilenamePrefix,
      callbacks: SettingsPanelCallbacks(
        onSave: (newIp, newProvider, newToken, newModel, newIsUsb) async {
          final logger = AppLogger(agentName: 'main', toolName: 'onSave');
          logger.log(
            'Saving config: ip=$newIp, provider=$newProvider, '
            'token=${newToken.isNotEmpty ? "***${newToken.substring(newToken.length - 4)}" : "(empty)"}, '
            'model="$newModel", isUsb=$newIsUsb',
          );

          // The live session belongs to the old address/mode.
          _restoreLiveOnPanelReturn = false;
          _stopVncLive(fetchScreen: false, restoreAutoCapture: false);
          _clearVncAvailability();

          _setState(() {
            _ipAddress = newIp;
            _isUsb = newIsUsb;
            Vxi11Instrument.isUsbMode = newIsUsb;
            _aiProvider = newProvider;
            _aiApiToken = newToken;
            _llmModel = newModel;
            _deviceName = null;
            _deviceModel = null;
            _numChannels = 2;
            _selectedChannel = 1;
            _showSettings = false;
          });
          _configureWaveformAi();
          await _saveConfig();
          _startPingTimer();

          if (_isAiEnabled) {
            logger.log('_isAiEnabled is true, calling _configureAiService()');
            _configureAiService();
          } else if (_aiProvider.isNotEmpty && _aiApiToken.trim().length >= 8) {
            logger.log(
              '_isAiEnabled is false (model probably empty), calling deactivate() '
              '_aiProvider="$_aiProvider", token length=${_aiApiToken.trim().length}, '
              '_llmModel="$_llmModel"',
            );
            // Provider and token are valid but model is empty;
            // deactivate the agent without configuring a new one.
            _aiChatService.deactivate();
            if (mounted) {
              _setState(() {});
            }
          } else {
            logger.log(
              '_isAiEnabled is false and no partial config: '
              '_aiProvider="$_aiProvider", token length=${_aiApiToken.trim().length}, '
              '_llmModel="$_llmModel"',
            );
          }
        },
        onClose: () => _setState(() => _showSettings = false),
        onDrag: (delta) => _setState(() => _settingsOffset += delta),
      ),
      onSaveWithParamsChanged: (v) async {
        _setState(() => _saveWithParams = v);
        await AppPreferences.setBool('save_with_params', v);
      },
      onAskForFilenamePrefixChanged: (v) async {
        _setState(() => _askForFilenamePrefix = v);
        await AppPreferences.setBool('ask_for_filename_prefix', v);
      },
    );
  }

  /// Opens the floating display adjustment panel at [globalPosition].
  void _openDisplayAdjustPanel(Offset globalPosition) {
    _setState(() {
      _displayAdjustOriginal = _screenSettings;
      _displayAdjustOffset = _clampDisplayAdjustOffset(globalPosition);
      _showDisplayAdjust = true;
    });
  }

  /// Restores the settings that were active when the panel was opened.
  void _cancelDisplayAdjust() {
    _setState(() {
      final original = _displayAdjustOriginal;
      if (original != null) _screenSettings = original;
      _showDisplayAdjust = false;
      _displayAdjustOriginal = null;
    });
  }

  /// Applies the values selected in the panel and persists them.
  void _saveDisplayAdjust(ScreenSettings settings) {
    _setState(() {
      _screenSettings = settings;
      _showDisplayAdjust = false;
      _displayAdjustOriginal = null;
    });
    unawaited(ScreenSettingsStore.save(settings));
  }

  /// Keeps the floating panel inside the window.
  Offset _clampDisplayAdjustOffset(Offset position) {
    final size = MediaQuery.sizeOf(context);
    const margin = 8.0;
    final maxX = size.width - displayAdjustPanelWidth - margin;
    final maxY = size.height - displayAdjustPanelApproximateHeight - margin;
    return Offset(
      position.dx.clamp(margin, maxX < margin ? margin : maxX).toDouble(),
      position.dy.clamp(margin, maxY < margin ? margin : maxY).toDouble(),
    );
  }

  Widget _buildDisplayAdjustPanel() {
    return DisplayAdjustPanel(
      offset: _displayAdjustOffset,
      settings: _screenSettings,
      onChanged: (settings) => _setState(() => _screenSettings = settings),
      onSave: _saveDisplayAdjust,
      onCancel: _cancelDisplayAdjust,
      onDrag: (delta) => _setState(
        () => _displayAdjustOffset = _clampDisplayAdjustOffset(
          _displayAdjustOffset + delta,
        ),
      ),
    );
  }
}
