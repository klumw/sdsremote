part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeInitConfig on _OsciHomePageState {
  Future<void> _initialize() async {
    await _loadConfig();
    // Load the device profiles before the agents are configured so the
    // instrument agent has its command registry and knowledge from the start.
    await _ensureDeviceProfilesLoaded();
    await _checkNewsNotification();
    _loadProfileFiles();
    _startPingTimer();
    _configureSigGenDetection();
    _configureWaveformAi();
    // Configure AI agent on startup if provider, token, and model are valid
    if (_isAiEnabled) {
      _configureAiService();
    }
  }

  /// Loads all device profiles once and keeps the oscilloscope context.
  ///
  /// Profile failures are logged but do not stop the application: the affected
  /// feature reports a controlled [DeviceErrorCode] when it is used.
  Future<void> _ensureDeviceProfilesLoaded() {
    final existing = _deviceProfileLoad;
    if (existing != null) return existing;
    final future = _loadDeviceProfiles();
    _deviceProfileLoad = future;
    return future;
  }

  Future<void> _loadDeviceProfiles() async {
    final logger = AppLogger(agentName: 'main', toolName: 'loadDeviceProfiles');
    final store = DeviceProfileStore(
      assetSource: const FlutterDeviceAssetSource(),
    );
    DeviceAgentContext? sdsContext;
    try {
      final report = await store.loadAll();
      for (final entry in report.errors.entries) {
        logger.warning(
          'Device profile "${entry.key}" failed to load: ${entry.value}',
        );
      }
      final sds = store.getProfile(DeviceProfileIds.sds1000xe);
      sdsContext = sds == null
          ? null
          : DeviceAgentContext(
              profile: sds,
              identity: store.resolveModel(
                _deviceModel,
                configuredDevice: sds.profileId,
              ),
            );
      logger.log(
        'Loaded device profiles: ${store.loadedProfileIds.join(', ')}',
      );
    } catch (error) {
      // A profile failure must not stop application startup. The affected
      // features report PROFILE_NOT_LOADED when they are used.
      logger.error('Device profile initialization failed: $error');
    }
    if (mounted) {
      _setState(() {
        _deviceProfileStore = store;
        _sdsDeviceContext = sdsContext;
      });
    } else {
      _deviceProfileStore = store;
      _sdsDeviceContext = sdsContext;
    }
  }

  /// Returns the profile store, loading it on first use if necessary.
  Future<DeviceProfileStore?> _deviceProfiles() async {
    await _ensureDeviceProfilesLoaded();
    return _deviceProfileStore;
  }

  Future<void> _loadConfig() async {
    final ip = await AppPreferences.getString('osci_ip');
    final isUsb = await AppPreferences.getBool('osci_is_usb');
    final provider = await AppPreferences.getString('ai_provider');
    final token = await AppPreferences.getString('ai_api_token');
    final model = await AppPreferences.getString('llm_model');
    final saveWithParams = await AppPreferences.getBool('save_with_params');
    final askForFilenamePrefix = await AppPreferences.getBool(
      'ask_for_filename_prefix',
    );
    final signalGenerator = await AppPreferences.getString('siggen_device');
    final sigGenPort = await AppPreferences.getString('siggen_port');
    final screenSettings = await ScreenSettingsStore.load();
    _setState(() {
      _ipAddress = ip ?? '192.168.1.100';
      _isUsb = isUsb ?? false;
      Vxi11Instrument.isUsbMode = _isUsb;
      _aiProvider = provider ?? '';
      _aiApiToken = token ?? '';
      _llmModel = model ?? '';
      _saveWithParams = saveWithParams ?? false;
      _askForFilenamePrefix = askForFilenamePrefix ?? false;
      _signalGenerator =
          signalGenerator == 'jds6600' || signalGenerator == 'fy6900'
          ? signalGenerator!
          : 'none';
      _sigGenPort = sigGenPort;
      _screenSettings = screenSettings;
    });
    await _spectrumController.loadSettings();
  }

  Future<void> _saveConfig() async {
    await AppPreferences.setAll({
      'osci_ip': _ipAddress,
      'osci_is_usb': _isUsb,
      'ai_provider': _aiProvider,
      'ai_api_token': _aiApiToken,
      'llm_model': _llmModel,
      'siggen_device': _signalGenerator,
      ..._spectrumPreferenceEntries(),
    });
  }

  void _showConfigDialog(BuildContext context) {
    _setState(() {
      _showSettings = !_showSettings;
      if (_showSettings) {
        // Calculate center position for the settings panel
        // Panel width is 400, we need to position it in the center of the window
        // We'll get the window size and calculate the center
        _calculateAndSetCenterPosition();
      }
    });
  }

  Future<void> _calculateAndSetCenterPosition() async {
    try {
      final windowSize = await windowManager.getSize();
      final panelWidth = settingsPanelWidth;
      // Approximate height including the signal-generator section.
      final panelHeight = settingsPanelApproximateHeight;

      final centerX = ((windowSize.width - panelWidth) / 2)
          .clamp(20.0, 1e9)
          .toDouble();
      final centerY = ((windowSize.height - panelHeight) / 2)
          .clamp(20.0, 1e9)
          .toDouble();

      _setState(() {
        _settingsOffset = Offset(centerX, centerY);
      });
    } catch (e) {
      // Fallback to a reasonable position if we can't get window size
      _setState(() {
        _settingsOffset = const Offset(100, 100);
      });
    }
  }
}
