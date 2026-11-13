part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeChildWindows on _OsciHomePageState {
  void _configureSigGenDetection() {
    final device = _signalGenerator;
    final supported = device == 'jds6600' || device == 'fy6900';
    if (!supported) {
      _disposeSigGenWindowSupport(closeWindow: true);
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
      _disposeSigGenWindowSupport(closeWindow: true);
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
    _ensureSigGenWindowSupport();
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
    _ensureSigGenWindowSupport();
    unawaited(_sigGenWindowLauncher?.openOrFocus());
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

  /// Creates the window bridge lazily for the current generator service.
  void _ensureSigGenWindowSupport() {
    final service = _sigGenService;
    if (service == null) return;

    _sigGenWindowHost ??= SigGenWindowHost(
      service: service,
      sink: _SigGenWindowSink(_pushSigGenWindowState),
      canMutate: () => !_bodeIsRunning && !_isMacroPlaying,
    );

    _sigGenWindowServer ??= SigGenWindowServer(
      handler: (method, arguments) async {
        final host = _sigGenWindowHost;
        if (host == null) {
          return SigGenCommandResult.failure(
            const SigGenWindowState(),
            'Signal generator is not configured',
            errorType: 'disconnected',
          );
        }
        return host.handleCommand(method, arguments);
      },
    );
    unawaited(
      _sigGenWindowServer!.register().catchError((Object error) {
        AppLogger(
          agentName: 'SigGen',
          toolName: 'window',
        ).error('Signal generator bridge registration failed: $error');
      }),
    );

    _sigGenWindowLauncher ??= SigGenWindowLauncher(
      backend: const WindowControllerBackend(),
      canOpen: () =>
          (_signalGenerator == 'jds6600' || _signalGenerator == 'fy6900') &&
          _sigGenDetected &&
          !_isMacroPlaying,
      onOpenChanged: _onSigGenWindowOpenChanged,
    );
  }

  /// Tears down the bridge when the generator configuration changes.
  void _disposeSigGenWindowSupport({bool closeWindow = false}) {
    final launcher = _sigGenWindowLauncher;
    _sigGenWindowLauncher = null;
    if (launcher != null) {
      if (closeWindow) unawaited(launcher.close());
      launcher.dispose();
    }
    _sigGenWindowHost?.deactivate();
    _sigGenWindowHost?.dispose();
    _sigGenWindowHost = null;
    _sigGenWindowOpen = false;
    _sigGenService?.setPanelActive(false);
  }

  void _onSigGenWindowOpenChanged(bool open) {
    _sigGenWindowOpen = open;
    _sigGenService?.setPanelActive(open && !_bodeIsRunning);
    final host = _sigGenWindowHost;
    if (open) {
      host?.activate();
    } else {
      host?.deactivate();
    }
    if (mounted) _setState(() {});
  }

  Future<void> _pushSigGenWindowState(SigGenWindowState state) async {
    final launcher = _sigGenWindowLauncher;
    if (launcher == null || !_sigGenWindowOpen) return;
    try {
      await launcher.pushState(state);
    } catch (_) {
      // The child window may have closed between the list and the push.
    }
  }

  void _stopBodeIfRunning() {
    if (_bodeIsRunning) {
      unawaited(_bodeService?.stop());
      _bodeIsRunning = false;
    }
    _sigGenDetector?.setPaused(false);
    if (!_sigGenDetected) _sigGenDetector?.start();
    _sigGenService?.setPanelActive(_sigGenWindowOpen);
  }

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
      onRunningChanged: (running) {
        _bodeIsRunning = running;
        _sigGenDetector?.setPaused(running);
        _sigGenService?.setPanelActive(_sigGenWindowOpen && !running);
        if (mounted) _setState(() {});
      },
      onServiceCreated: (bodeService) {
        _bodeService = bodeService;
      },
      onSaveState: (points, config, status) {
        _savedBodePoints = points;
        _savedBodeConfig = config;
        _savedBodeStatus = status;
      },
      savedPoints: _savedBodePoints,
      savedConfig: _savedBodeConfig,
      savedStatus: _savedBodeStatus,
    );
  }
}

/// Adapter that lets [SigGenWindowHost] push snapshots into the launcher.
class _SigGenWindowSink implements SigGenWindowEventSink {
  _SigGenWindowSink(this._push);

  final Future<void> Function(SigGenWindowState) _push;

  @override
  Future<void> pushState(SigGenWindowState state) => _push(state);
}
