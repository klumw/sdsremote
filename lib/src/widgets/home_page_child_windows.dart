part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeChildWindows on _OsciHomePageState {
  bool get _bodeIsRunning => _bodeSessionController.isRunning;
  set _bodeIsRunning(bool value) => _bodeSessionController.isRunning = value;

  BodePlotService? get _bodeService => _bodeSessionController.service;

  List<BodePoint>? get _savedBodePoints => _bodeSessionController.savedPoints;
  BodeConfig? get _savedBodeConfig => _bodeSessionController.savedConfig;
  BodeStatus? get _savedBodeStatus => _bodeSessionController.savedStatus;

  void _configureSigGenDetection() {
    final device = _signalGenerator;
    final supported = device == 'jds6600' || device == 'fy6900';
    if (!supported) {
      _sigGenWindowCoordinator.disposeSupport(closeWindow: true);
      _sigGenDetector?.dispose();
      _sigGenDetector = null;
      _sigGenDetected = false;
      _sigGenPort = null;
      final service = _sigGenService;
      _sigGenService = null;
      _sigGenDeviceType = null;
      if (service != null) {
        service.removeListener(_onSigGenServiceChanged);
        unawaited(service.disconnect());
        service.dispose();
      }
      return;
    }

    // Rebuild the service when the selected generator family changes.
    if (_sigGenService != null && _sigGenDeviceType != device) {
      _sigGenWindowCoordinator.disposeSupport(closeWindow: true);
      _sigGenDetector?.dispose();
      _sigGenDetector = null;
      _sigGenDetected = false;
      final oldService = _sigGenService;
      _sigGenService = null;
      _sigGenDeviceType = null;
      if (oldService != null) {
        oldService.removeListener(_onSigGenServiceChanged);
        unawaited(oldService.disconnect());
        oldService.dispose();
      }
    }

    if (_sigGenService == null) {
      final isFy6900 = device == 'fy6900';
      final service = SignalGeneratorService(
        driverFactory: isFy6900
            ? (port) => Fy6900Driver(LibSerialPortFy6900Transport(port))
            : (port) => Jds6600Driver(LibSerialPortJds6600Transport(port)),
      );
      service.addListener(_onSigGenServiceChanged);
      _sigGenService = service;
      _sigGenDeviceType = device;
    }
    _sigGenWindowCoordinator.ensureSupport();
    if (_sigGenDetector == null) {
      _sigGenDetector = SignalGeneratorDetector(
        service: _sigGenService!,
        initialPort: _sigGenPort,
        identityToken: device == 'fy6900' ? 'FY6900' : 'JDS6600',
        onPortDetected: (port) {
          _sigGenPort = port;
          unawaited(AppPreferences.setString('siggen_port', port));
        },
      );
      _sigGenDetector!.addListener(_onSigGenDetectionChanged);
    }
    _sigGenDetector!.start();
  }

  void _onSigGenDetectionChanged() {
    final detector = _sigGenDetector;
    if (detector == null || !mounted) return;
    if (detector.isDetected == _sigGenDetected &&
        detector.port == _sigGenPort) {
      return;
    }
    _setState(() {
      _sigGenDetected = detector.isDetected;
      _sigGenPort = detector.port ?? _sigGenPort;
    });
  }

  bool _handleSignalGeneratorShortcut(KeyEvent event) {
    if (!_signalGeneratorShortcut.matches(event)) return false;
    if (_signalGenerator != 'jds6600' && _signalGenerator != 'fy6900') {
      return false;
    }
    if (_isMacroPlaying) return false;
    // A closed generator window stays hidden in the multi-window backend.
    // Without this gate openOrFocus would show that stale window again after
    // the generator has been unplugged (detector reports it as no longer
    // present), even though canOpen() is false.
    if (!_sigGenDetected) return false;
    _sigGenWindowCoordinator.ensureSupport();
    unawaited(_sigGenWindowCoordinator.openOrFocus());
    return true;
  }

  /// Restores the configured calculator shortcut from the preferences.
  Future<void> _loadCalculatorShortcut() async {
    final stored = await AppPreferences.getString('calculator_shortcut');
    if (!mounted) return;
    final shortcut = CalculatorShortcut.fromPreference(stored);
    if (shortcut.id == _calculatorShortcut.id) return;
    _setState(() => _calculatorShortcut = shortcut);
  }

  /// Restores the configured signal generator shortcut from the preferences.
  Future<void> _loadSignalGeneratorShortcut() async {
    final stored = await AppPreferences.getString('signal_generator_shortcut');
    if (!mounted) return;
    final shortcut = SignalGeneratorShortcut.fromPreference(stored);
    if (shortcut.id == _signalGeneratorShortcut.id) return;
    _setState(() => _signalGeneratorShortcut = shortcut);
  }

  bool _handleCalculatorShortcut(KeyEvent event) {
    if (!_calculatorShortcut.matches(event)) return false;
    _openCalculatorWindow();
    return true;
  }

  void _openCalculatorWindow() {
    _ensureCalculatorWindowSupport();
    unawaited(_calculatorWindowLauncher?.openOrFocus());
  }

  void _ensureCalculatorWindowSupport() {
    _calculatorWindowLauncher ??= CalculatorWindowLauncher(
      backend: const WindowControllerBackend(),
      positionProvider: _calculatorWindowPosition,
    );
  }

  /// Places the calculator window in the center of the main window.
  Future<CalculatorWindowPosition?> _calculatorWindowPosition() async {
    try {
      final position = await windowManager.getPosition();
      final size = await windowManager.getSize();
      return CalculatorWindowArguments.centeredIn(
        mainLeft: position.dx,
        mainTop: position.dy,
        mainWidth: size.width,
        mainHeight: size.height,
      );
    } catch (error) {
      AppLogger(
        agentName: 'Calculator',
        toolName: 'window-position',
      ).debug('Could not read the main-window geometry: $error');
      return null;
    }
  }

  void _stopBodeIfRunning() => _bodeSessionController.stop();

  Widget _buildBodePlotWindow() {
    final service = _sigGenService;
    if (service == null) {
      return const Center(
        child: Text(
          'Signal Generator is not configured.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return BodePlotPanel(
      getInstrument: _getInstrument,
      signalGenerator: service,
      isOnline: _isOnline,
      generatorDetected: _sigGenDetected,
      plotKey: _bodePlotKey,
      onClose: () => _togglePanel(ActivePanel.bode),
      onRunningChanged: _bodeSessionController.setRunning,
      onServiceCreated: (bodeService) {
        _bodeSessionController.service = bodeService;
      },
      onSaveState: _bodeSessionController.saveState,
      savedPoints: _savedBodePoints,
      savedConfig: _savedBodeConfig,
      savedStatus: _savedBodeStatus,
    );
  }
}
