import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:ui' as ui show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../app/app_config.dart';
import '../app/app_theme.dart';
import '../app/app_preferences.dart';
import '../waveform/cursor_geometry.dart';
import 'osci_toolbar_button.dart';
import 'reference_file_picker_dialog.dart';
import 'filename_prefix_dialog.dart';
import 'unsaved_changes_dialog.dart';
import 'package:window_manager/window_manager.dart';

import '../instrument/dart_vxi11.dart';
import '../waveform/waveform_acquisition.dart';
import '../waveform/waveform_processing.dart';
import '../waveform/waveform_csv_parser.dart';
import '../waveform/waveform_csv_writer.dart';
import '../data_logger/data_logger_csv_writer.dart';
import '../waveform/waveform_models.dart';
import '../waveform/waveform_painter.dart';
import '../waveform/waveform_view_transform.dart';
import '../ai/ai_chat_service.dart';
import '../core/logger.dart';
import 'osci_physical_panel.dart';
import 'osci_chat_window.dart';
import 'osci_help_window.dart';
import 'osci_news_notification.dart';
import 'osci_device_params_panel.dart';
import 'osci_settings_panel.dart';
import 'osci_profiles_panel.dart';
import '../data_logger/data_logger_models.dart';
import 'data_logger_panel.dart';
import '../data_logger/data_logger_service.dart';
import '../data_logger/data_logger_report.dart';
import '../bode/bode_csv_writer.dart';
import '../bode/bode_models.dart';
import '../bode/bode_plot_service.dart';
import '../bode/bode_report.dart';
import '../signal_generator/fy6900_driver.dart';
import '../signal_generator/fy6900_serial_transport.dart';
import '../signal_generator/jds6600_driver.dart';
import '../signal_generator/jds6600_serial_transport.dart';
import '../signal_generator/signal_generator_detector.dart';
import '../signal_generator/signal_generator_service.dart';
import '../signal_generator/siggen_window_host.dart';
import '../signal_generator/siggen_window_launcher.dart';
import '../signal_generator/siggen_window_protocol.dart';
import '../signal_generator/siggen_window_server.dart';
import 'bode_plot_panel.dart';
import '../app/app_paths.dart';
import '../macro/macro_recorder_models.dart';
import 'macro_recorder_panel.dart';
import 'macro_editor_panel.dart';
import '../macro/macro_evaluator.dart';
import '../ai/tools/vxi11_tool.dart' show onScpiCommandSent;

class OsciHomePage extends StatefulWidget {
  const OsciHomePage({super.key});

  @override
  State<OsciHomePage> createState() => _OsciHomePageState();
}

class _OsciHomePageState extends State<OsciHomePage>
    with WindowListener, SingleTickerProviderStateMixin {
  // =========================================================================
  // State Fields
  // =========================================================================

  // Connection
  String _ipAddress = '192.168.1.100';
  bool _isUsb = false;
  bool _isOnline = false;
  String? _deviceName;

  /// Model designation reported by the device (e.g. `SDS1202X-E`), without the
  /// vendor prefix of [_deviceName]. This is what the AI searches for and what
  /// the knowledge base uses.
  String? _deviceModel;

  /// Analog channel count of the detected instrument (2 or 4).
  int _numChannels = 2;

  /// Channel the shared vertical knobs act on (four-channel layout).
  int _selectedChannel = 1;
  Vxi11Instrument? _instrument;

  // Bode Plot / JDS6600
  SignalGeneratorService? _sigGenService;
  SignalGeneratorDetector? _sigGenDetector;
  bool _sigGenDetected = false;
  String? _sigGenPort;
  bool _bodeIsRunning = false;
  BodePlotService? _bodeService;
  List<BodePoint>? _savedBodePoints;
  BodeConfig? _savedBodeConfig;
  BodeStatus? _savedBodeStatus;

  // Signal generator selection (Settings → Signal Generator).
  String _signalGenerator = 'none';

  /// Device family the current [_sigGenService] was built for.
  String? _sigGenDeviceType;

  // Signal generator OS window (Ctrl+J).
  SigGenWindowHost? _sigGenWindowHost;
  SigGenWindowServer? _sigGenWindowServer;
  SigGenWindowLauncher? _sigGenWindowLauncher;
  bool _sigGenWindowOpen = false;

  // AI
  String _aiProvider = '';
  String _aiApiToken = '';
  String _llmModel = '';
  bool get _isAiEnabled =>
      _aiProvider.isNotEmpty &&
      _aiApiToken.trim().length >= 8 &&
      _llmModel.trim().isNotEmpty;

  // Acquisition
  bool _isAcquiring = false;
  bool _isAcquiringWaveform = false;
  SdsNotification? _latestNews;
  bool _hasUnreadUpdate = false;
  Uint8List? _screenDump;
  WaveformData? _waveformCh1;
  WaveformData? _waveformCh2;
  WaveformData? _waveformCh3;
  WaveformData? _waveformCh4;
  DeviceParams? _deviceParams;
  bool _waveformAcquired = false;

  // Reference waveform
  WaveformData? _refWaveform;
  bool _refVisible = false;
  String? _refFileName;
  String? _refChannelOrigin; // 'ch1' … 'ch4'

  /// Manual alignment of the reference against the live trace. Kept next to
  /// [_refWaveform] instead of being added to its points, so it can be reset
  /// and read out, and so dragging never rewrites the loaded data.
  ReferenceOffset _refOffset = const ReferenceOffset();

  /// Whether "Move Reference" is armed: while it is, a drag in the plot moves
  /// the reference instead of a cursor.
  bool _refMoving = false;
  bool _draggingRef = false;

  /// Offset and pointer position at the start of the current drag. Each
  /// update recomputes the offset from these rather than accumulating pointer
  /// deltas, so snapping and clamping cannot make the trace drift away from
  /// the pointer.
  ReferenceOffset _refDragAnchor = const ReferenceOffset();
  Offset _refDragOriginPx = Offset.zero;

  /// The reference may be moved by at most half of the visible graticule —
  /// seven divisions horizontally, four vertically — so it can never be
  /// dragged completely out of view.
  static const double _refMaxDivX = 7.0;
  static const double _refMaxDivY = 4.0;

  /// Snap step with Shift held: one minor grid division (a fifth of a major
  /// one), as the visible grid shows it at the current zoom.
  static const double _refMinorDiv = 0.2;

  // Zoom
  ZoomState _zoomState = const ZoomState();

  // Cursors
  CursorState _cursorState = const CursorState();
  int? _draggingCursorIndex; // 0=cursorX1, 1=cursorX2, 2=cursorY1, 3=cursorY2
  bool _draggingCursorInfo = false;

  /// null = not hovering, 'x' = hovering over X-axis cursor, 'y' = hovering over Y-axis cursor, 'info' = hovering over cursor info panel
  String? _hoveredCursorType;

  bool _ch1Enabled = true;
  bool _ch2Enabled = true;
  bool _ch3Enabled = true;
  bool _ch4Enabled = true;
  bool _saveWithParams = false;
  bool _askForFilenamePrefix = false;

  // Event processing lock: prevents overlapping button/knob events
  // Lock is held across the full sequence: SCPI send → wait → screen dump → 500ms cooldown
  bool _isProcessingEvent = false;

  // Knob handling (generic)
  final Map<KnobId, double> _knobPreviousValues = {
    for (final knob in KnobId.values) knob: 0.5,
  };

  // Timers
  Timer? _pingTimer;

  // Profiles
  List<ProfileInfo> _profileFiles = [];

  // Macro Recorder
  List<MacroInfo> _macroFiles = [];
  bool _isMacroRecording = false;
  bool _isMacroPlaying = false;
  bool _macroPlaybackCancelled = false;
  String _currentMacroContent = '';
  String? _loadedMacroFileName;
  bool _isMacroModified = false;

  // Macro playback status: null = none, 0 = error, 1 = success, 2 = cancelled
  int? _macroStatus;
  String? _macroStatusMessage;
  bool _macroHadPlaybackError = false;

  // Macro playback
  Vxi11Instrument? _playbackInstrument;

  Timer? _refreshTimer;
  bool _refreshPending = false;
  static const int _refreshDelayMs = 800;

  // UI State
  bool _showSettings = false;
  ActivePanel _activePanel = ActivePanel.none;
  ActivePanel _previousPanel = ActivePanel.none;
  Offset _settingsOffset = const Offset(
    0,
    0,
  ); // Will be calculated when dialog opens

  // Chat
  final AiChatService _aiChatService = AiChatService();
  final List<Map<String, String>> _chatMessages = [];
  bool _isChatting = false;

  // Data Logger
  late final AnimationController _dlAnimationController;
  bool _dlIsRunning = false;

  // Keys

  final GlobalKey _waveformKey = GlobalKey();
  final GlobalKey _dlPlotKey = GlobalKey();
  final GlobalKey _bodePlotKey = GlobalKey();

  // =========================================================================
  // Computed Properties
  // =========================================================================

  // =========================================================================
  // Lifecycle
  // =========================================================================

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    HardwareKeyboard.instance.addHandler(_onGlobalKeyEvent);
    _dlAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _initialize();
  }

  Future<void> _checkNewsNotification() async {
    final service = NewsNotificationService();
    final news = await service.fetchNotification();
    if (news == null) return;

    final lastReadId = await service.getLastReadId();
    setState(() {
      _latestNews = news;
      _hasUnreadUpdate = lastReadId == null || news.id > lastReadId;
    });

    if (news.forceShow) {
      _showNewsDialog();
    }
  }

  Future<void> _showNewsDialog() async {
    if (_latestNews == null) {
      await _checkNewsNotification();
    }

    if (_latestNews == null) {
      _showInfoSnackBar(
        'News service is currently unavailable. Please check your connection.',
        backgroundColor: const Color(0xFF1E293B),
      );
      return;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => NewsNotificationDialog(
        notification: _latestNews!,
        onDismiss: () async {
          await NewsNotificationService().markAsRead(_latestNews!.id);
          setState(() {
            _hasUnreadUpdate = false;
          });
        },
      ),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKeyEvent);
    _disposeSigGenWindowSupport();
    final server = _sigGenWindowServer;
    _sigGenWindowServer = null;
    if (server != null) unawaited(server.dispose());
    _pingTimer?.cancel();
    _refreshTimer?.cancel();
    _closeInstrument();
    _sigGenDetector?.dispose();
    _sigGenDetector = null;
    final sigGen = _sigGenService;
    _sigGenService = null;
    if (sigGen != null) {
      sigGen.removeListener(_onSigGenServiceChanged);
      unawaited(sigGen.disconnect());
      sigGen.dispose();
    }
    unawaited(_bodeService?.stop());
    _aiChatService.dispose();
    _dlAnimationController.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Close the signal-generator child window first; otherwise its engine can
    // keep the process alive after the main window is gone.
    try {
      await _sigGenWindowLauncher?.close().timeout(const Duration(seconds: 2));
    } catch (_) {
      // Continue with the normal shutdown even if the child is unresponsive.
    }

    // If a macro has unsaved changes, prompt the user before closing.
    if (mounted && _isMacroModified) {
      final action = await showDialog<UnsavedMacroAction>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const UnsavedChangesDialog(),
      );

      switch (action) {
        case UnsavedMacroAction.save:
          await _saveMacro();
          // If the save was cancelled (e.g. filename dialog dismissed),
          // abort the close.
          if (_isMacroModified) return;
          break;
        case UnsavedMacroAction.discard:
          break;
        case null:
          // User cancelled — keep the app open.
          return;
      }
    }

    // Fire-and-forget the final log entry. On Windows, awaiting this
    // log call would block until the entire sequential _writeQueue
    // (see logger.dart) drains, which can take 4-5 seconds due to
    // expensive flush-on-every-write semantics.  The OS will flush the
    // file buffer on process exit anyway.
    unawaited(AppLogger().log('SDS-Remote: application stopping'));

    // IMPORTANT: Do NOT call windowManager.destroy() — the window_manager
    // plugin's Destroy() simply calls PostQuitMessage(0), which immediately
    // exits the Win32 message loop WITHOUT triggering the proper
    // WM_DESTROY → OnDestroy() → Flutter engine shutdown sequence.
    // The engine then gets destroyed much later during C++ static/global
    // cleanup (outside the message loop), which is very slow.
    //
    // Instead, first disable the close interceptor, then close normally.
    // This sends WM_SYSCOMMAND SC_CLOSE → WM_CLOSE → DefWindowProc →
    // DestroyWindow → WM_DESTROY → FlutterWindow::OnDestroy() →
    // flutter_controller_ = nullptr (engine shutdown) → PostQuitMessage(0)
    // — the proper, fast shutdown path.
    _stopBodeIfRunning();
    // The generator outputs are deliberately left in their current state:
    // shutting them off here would also switch the channels off on the next
    // application start.
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  // =========================================================================
  // Build Method
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.panelBackground,
                          border: Border.all(
                            color: AppColors.border,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(child: _buildMainContent()),
                      ),
                    ),
                    if (_waveformAcquired &&
                        _activePanel == ActivePanel.none &&
                        _deviceParams != null)
                      DeviceParametersPanel(
                        params: _deviceParams!,
                        ch1Enabled: _ch1Enabled,
                        ch2Enabled: _ch2Enabled,
                        ch3Enabled: _ch3Enabled,
                        ch4Enabled: _ch4Enabled,
                        channelCount: _numChannels,
                        isOnline: _isOnline,
                        cursorsXEnabled: _cursorState.cursorsXEnabled,
                        cursorsYEnabled: _cursorState.cursorsYEnabled,
                        zoomFactor: _zoomState.zoomFactor,
                        onChannelToggle: _onDeviceParamChannelToggle,
                        onCursorXToggled: _onCursorXToggled,
                        onCursorYToggled: _onCursorYToggled,
                        onZoomFactorChanged: _onZoomFactorChanged,
                        refVisible: _refVisible,
                        refLabel: _refFileName != null ? 'REF' : null,
                        onLoadReference: _loadReferenceWaveform,
                        onRefToggled: _onRefToggled,
                        refMoving: _refMoving,
                        onRefMovingToggled: _onRefMovingToggled,
                        refOffset: _refOffset,
                        onRefReset: _onRefReset,
                      ),
                  ],
                ),
              ),
              _buildStatusBar(),
            ],
          ),
          if (_showSettings) _buildSettingsPanel(),
        ],
      ),
    );
  }

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
    if (_waveformAcquired) return _buildWaveformView();
    if (_screenDump != null) return _buildPhysicalPanel();
    return _buildWelcomeScreen();
  }

  // =========================================================================
  // Bode Plot / Signal Generator detection
  // =========================================================================

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
    setState(() {
      _sigGenDetected = detector.isDetected;
      _sigGenPort = detector.port ?? _sigGenPort;
    });
  }

  /// Reacts to the driver dropping the connection (generator switched off or
  /// unplugged) and resumes discovery so the UI can recover.
  void _onSigGenServiceChanged() {
    final service = _sigGenService;
    if (service == null || !mounted) return;
    if (service.isConnected) return;
    if (!_sigGenDetected || _bodeIsRunning) return;
    setState(() => _sigGenDetected = false);
    _sigGenDetector?.start();
  }

  // =========================================================================
  // Signal generator window (Ctrl+J)
  // =========================================================================

  /// Global shortcut: Ctrl+J opens or focuses the signal generator window.
  ///
  /// The shortcut is intentionally not exposed as a toolbar button.
  bool _onGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!HardwareKeyboard.instance.isControlPressed) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyJ) return false;
    if (_signalGenerator != 'jds6600' && _signalGenerator != 'fy6900') {
      return false;
    }
    if (_isMacroPlaying) return false;
    _ensureSigGenWindowSupport();
    unawaited(_sigGenWindowLauncher?.openOrFocus());
    return true;
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
        ).log('Signal generator bridge registration failed: $error');
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
    if (mounted) setState(() {});
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
        if (mounted) setState(() {});
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

  /// First and last timestamp across all acquired channels, used to place
  /// the cursor read-out along the visible time axis.
  (double?, double?) _waveformTimeBounds() {
    double? tMin;
    double? tMax;
    for (final data in [
      _waveformCh1,
      _waveformCh2,
      _waveformCh3,
      _waveformCh4,
    ]) {
      if (data == null || data.points.isEmpty) continue;
      final first = data.points.first.$1;
      final last = data.points.last.$1;
      if (tMin == null || first < tMin) tMin = first;
      if (tMax == null || last > tMax) tMax = last;
    }
    return (tMin, tMax);
  }

  Widget _buildWaveformView() {
    final (dataTMin, dataTMax) = _waveformTimeBounds();
    return AspectRatio(
      aspectRatio: 14 / 8,
      child: RepaintBoundary(
        key: _waveformKey,
        child: MouseRegion(
          cursor: _refMoving
              ? (_draggingRef
                    ? SystemMouseCursors.grabbing
                    : SystemMouseCursors.move)
              : _hoveredCursorType == 'x'
              ? SystemMouseCursors.resizeColumn
              : _hoveredCursorType == 'y'
              ? SystemMouseCursors.resizeRow
              : _hoveredCursorType == 'info'
              ? SystemMouseCursors.move
              : SystemMouseCursors.basic,
          onHover: _onCursorHover,
          child: GestureDetector(
            // Both modes share the same pan gesture; the dispatcher decides
            // between aligning the reference and dragging a cursor.
            onPanStart: _onWaveformPanStart,
            onPanUpdate: _onWaveformPanUpdate,
            onPanEnd: _onWaveformPanEnd,
            child: Stack(
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: WaveformBasePainter(
                      ch1: _waveformCh1,
                      ch2: _waveformCh2,
                      ch3: _waveformCh3,
                      ch4: _waveformCh4,
                      ref: _refWaveform,
                      refVisible: _refVisible,
                      refChannelOrigin: _refChannelOrigin,
                      refOffset: _refOffset,
                      refHighlighted: _refMoving,
                      params: _deviceParams!,
                      ch1Enabled: _ch1Enabled,
                      ch2Enabled: _ch2Enabled,
                      ch3Enabled: _numChannels >= 4 && _ch3Enabled,
                      ch4Enabled: _numChannels >= 4 && _ch4Enabled,
                      zoom: _zoomState,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
                CustomPaint(
                  painter: CursorPainter(
                    cursors: _cursorState,
                    params: _deviceParams!,
                    zoom: _zoomState,
                    dataTMin: dataTMin,
                    dataTMax: dataTMax,
                  ),
                  child: const SizedBox.expand(),
                ),
                if (_refMoving && _refVisible && _refWaveform != null)
                  Positioned(left: 12, top: 12, child: _buildRefMoveHint()),
                if (_zoomState.zoomFactor > 1.0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 24,
                    child: _buildHorizontalPanSlider(),
                  ),
                if (_zoomState.zoomFactor > 1.0)
                  Positioned(
                    top: 0,
                    bottom: 24,
                    right: 0,
                    width: 24,
                    child: _buildVerticalPanSlider(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhysicalPanel() {
    return PhysicalControlPanel(
      isOnline: _isOnline,
      isProcessingEvent: _isProcessingEvent,
      screenDump: _screenDump!,
      ch1Enabled: _ch1Enabled,
      ch2Enabled: _ch2Enabled,
      channelCount: _numChannels,
      selectedChannel: _selectedChannel,
      onChannelToggle: _handleChannelButtonPress,
      onSoftKeyPressed: _handleSoftKeyPress,
      onMenuPressed: _handleMenuPress,
      onKnobChanged: _handleKnobChanged,
      onKnobTapped: _handleKnobTapped,
      onMenuButtonPressed: _handleButtonPress,
      onVerticalButtonPressed: _handleButtonPress,
      onHorizontalButtonPressed: _handleButtonPress,
      onTriggerButtonPressed: _handleButtonPress,
    );
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.8,
            child: Image.asset(
              'assets/icons/sds-remote.png',
              width: 400,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Version 0.2.6",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 16,
              fontWeight: FontWeight.w300,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // Top Bar
  // =========================================================================

  Widget _buildLeftToolbarButtons() {
    return Row(
      children: [
        // Control Panel
        OsciToolbarButton(
          label: _isAcquiring ? "Acquiring..." : "Control Panel",
          icon: _isAcquiring
              ? const SizedBox(
                  width: 25,
                  height: 25,
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : const Icon(Icons.tune, size: 25),
          onPressed: (_isAcquiring || !_isOnline || _isMacroPlaying)
              ? null
              : _acquireScreenDump,
        ),
        const SizedBox(width: 16),
        // Acquire Waveform
        OsciToolbarButton(
          label: _isAcquiringWaveform ? "Acquiring..." : "Acquire Waveform",
          icon: _isAcquiringWaveform
              ? const SizedBox(
                  width: 25,
                  height: 25,
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : const Icon(Icons.show_chart, size: 25),
          onPressed: (_isAcquiringWaveform || !_isOnline || _isMacroPlaying)
              ? null
              : _acquireWaveform,
        ),
        const SizedBox(width: 16),
        // AI
        OsciToolbarButton(
          label: "AI",
          icon: const Icon(Icons.auto_awesome, size: 25),
          onPressed: (_isAiEnabled && !_isMacroPlaying)
              ? () => _togglePanel(ActivePanel.chat)
              : null,
        ),
        const SizedBox(width: 16),
        // Profiles
        OsciToolbarButton(
          label: "Profiles",
          icon: const Icon(Icons.save, size: 25),
          onPressed: (_isOnline && !_isMacroPlaying)
              ? () => _togglePanel(ActivePanel.profiles)
              : null,
        ),
        const SizedBox(width: 16),
        // Data Logger
        OsciToolbarButton(
          label: "Data Logger",
          icon: _buildDlButtonIcon(),
          onPressed: (_isOnline && !_isMacroPlaying)
              ? () => _togglePanel(ActivePanel.dataLogger)
              : null,
        ),
        if (_signalGenerator == 'jds6600' || _signalGenerator == 'fy6900') ...[
          const SizedBox(width: 16),
          OsciToolbarButton(
            label: 'Bode',
            icon: const Icon(Icons.analytics_outlined, size: 25),
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
              : (_isMacroRecording ? "Recording..." : "Macro Recorder"),
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
          onPressed: _isOnline
              ? () => _togglePanel(ActivePanel.macroRecorder)
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
          OsciToolbarButton(
            label: "Help",
            icon: const Icon(Icons.help_outline, size: 25),
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
          const SizedBox(width: 16),
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
        ],
      ),
    );
  }

  // =========================================================================
  // Status Bar
  // =========================================================================

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

  // =========================================================================
  // Help & Chat Windows
  // =========================================================================

  Widget _buildHelpWindow() {
    return HelpWindow();
  }

  Widget _buildChatWindow() {
    return ChatWindow(
      aiChatService: _aiChatService,
      chatMessages: _chatMessages,
      isChatting: _isChatting,
      isInitialized: _aiChatService.isInitialized,
      onSendMessage: _onChatSendMessage,
    );
  }

  void _onChatSendMessage(String text) async {
    setState(() {
      _chatMessages.add({'role': 'user', 'content': text});
      _isChatting = true;
      // Add a placeholder for the AI response
      _chatMessages.add({'role': 'ai', 'content': ''});
    });

    final aiMsgIndex = _chatMessages.length - 1;
    bool hasReceivedChunk = false;

    try {
      final stream = _aiChatService.sendMessageStream(text: text);

      await for (final chunk in stream) {
        hasReceivedChunk = true;
        setState(() {
          _chatMessages[aiMsgIndex]['content'] =
              _chatMessages[aiMsgIndex]['content']! + chunk;
        });
      }

      if (!hasReceivedChunk) {
        setState(() {
          _chatMessages[aiMsgIndex]['content'] = 'No response from AI-Server';
        });
      }
    } catch (e) {
      setState(() {
        _chatMessages[aiMsgIndex]['content'] =
            'Error: Failed to connect to AI server ($e)';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isChatting = false;
        });
      }
    }
  }

  Widget _buildProfilesWindow() {
    return ProfilesPanel(
      profileFiles: _profileFiles,
      isOnline: _isOnline,
      onSave: _saveProfile,
      onLoad: _loadProfile,
      onDelete: _deleteProfile,
      onClose: () => _togglePanel(ActivePanel.profiles),
    );
  }

  // =========================================================================
  // Macro Recorder
  // =========================================================================

  bool _showMacroEditor = false;

  Widget _buildMacroRecorderWindow() {
    if (_showMacroEditor) {
      return MacroEditorPanel(
        initialContent: _currentMacroContent,
        loadedFileName: _loadedMacroFileName,
        isModified: _isMacroModified,
        errorMessage: _macroHadPlaybackError ? _macroStatusMessage : null,
        onContentChanged: (content) {
          _currentMacroContent = content;
          // When a loaded file is edited, enable the Save button.
          if (_loadedMacroFileName != null && !_isMacroModified) {
            setState(() => _isMacroModified = true);
          }
        },
        onSave: _isMacroModified ? _onMacroSave : null,
        onClose: () {
          setState(() {
            _showMacroEditor = false;
          });
        },
      );
    }

    return MacroRecorderPanel(
      macroFiles: _macroFiles,
      isOnline: _isOnline,
      isRecording: _isMacroRecording,
      isPlaying: _isMacroPlaying,
      isSaveEnabled: _isMacroRecording || _isMacroModified,
      hasContent: _currentMacroContent.trim().isNotEmpty,
      macroStatus: _macroStatus,
      macroStatusMessage: _macroStatusMessage,
      loadedFileName: _loadedMacroFileName,
      isModified: _isMacroModified,
      onRecord: _onMacroStart,
      onStop: _onMacroStop,
      onPlay: _onMacroPlay,
      onEdit: _onMacroEdit,
      onSave: _onMacroSave,
      onLoad: _onMacroLoad,
      onDelete: _onMacroDelete,
      onClose: () => _togglePanel(ActivePanel.macroRecorder),
    );
  }

  void _loadMacroFiles() {
    try {
      final dir = AppPaths.macrosDirectory;
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.m'))
          .map(
            (f) => MacroInfo(
              fileName: f.uri.pathSegments.last,
              lastModified: f.lastModifiedSync(),
            ),
          )
          .toList();
      setState(() {
        _macroFiles = files;
      });
    } catch (e) {
      AppLogger().log('Error loading macro files: $e');
    }
  }

  void _onMacroStart() {
    setState(() {
      _macroStatus = null;
      _macroStatusMessage = null;
      _isMacroRecording = true;
      _isMacroModified = true;
      _loadedMacroFileName = null;
      _currentMacroContent = _isUsb
          ? 'connect(usb)\n'
          : 'connect("$_ipAddress")\n';
    });

    onScpiCommandSent = (command, operation) {
      if (!_isMacroRecording) return;
      switch (operation) {
        case 'write':
          _currentMacroContent += 'scpi("$command")\n';
        case 'query':
          _currentMacroContent += 'query("$command")\n';
      }
    };

    AppLogger().log('Macro recording started');
  }

  void _onMacroStop() {
    setState(() => _macroStatus = null);
    if (_isMacroPlaying) {
      _macroPlaybackCancelled = true;
    }
    if (_isMacroRecording) {
      onScpiCommandSent = null;
      setState(() {
        _isMacroRecording = false;
      });
      AppLogger().log('Macro recording stopped');
    }
  }

  /// Parses and executes the macro commands in [_currentMacroContent]
  /// using the petitparser-based Grammar → AST → Evaluator pipeline.
  ///
  /// See [MacroGrammarDefinition] and [MacroEvaluator] for the full
  /// list of supported commands.
  Future<void> _playMacro() async {
    _macroHadPlaybackError = false;
    final source = _currentMacroContent;

    if (source.trim().isEmpty) {
      _showMacroError('Macro is empty');
      return;
    }

    _playbackInstrument = null;

    final evaluator = MacroEvaluator(
      instrument: _playbackInstrument,
      onError: _showMacroError,
      isCancelled: () => _macroPlaybackCancelled,
      delay: (seconds) => Future.delayed(Duration(seconds: seconds)),
    );

    final success = await evaluator.evaluateSource(source);

    // Keep the instrument reference updated
    _playbackInstrument = evaluator.instrument;

    // Set macro status for the header icon
    if (mounted) {
      setState(() {
        if (!success && _macroPlaybackCancelled) {
          _macroStatus = 2; // cancelled
        } else if (!success) {
          _macroStatus = 0; // error
        } else {
          _macroStatus = 1; // success
        }
      });
    }

    // Clean up the dedicated macro playback connection.
    await _playbackInstrument?.close();
    _playbackInstrument = null;

    AppLogger().log(
      _macroPlaybackCancelled
          ? 'Macro playback: stopped by user'
          : 'Macro playback: finished',
    );

    if (mounted && !_macroHadPlaybackError) {
      if (_macroPlaybackCancelled) {
        _showInfoSnackBar(
          'Macro playback stopped',
          backgroundColor: Colors.orange,
        );
      } else if (success) {
        _showInfoSnackBar(
          'Macro playback completed',
          backgroundColor: Colors.green,
        );
      }
    }
  }

  /// Shows an error snackbar and logs the error.
  /// Also sets [_macroHadPlaybackError] if called during active playback.
  void _showMacroError(String message) {
    if (_isMacroPlaying) {
      _macroHadPlaybackError = true;
      _macroStatus = 0; // show error icon immediately
    }
    _macroStatusMessage = message;
    AppLogger().log('Macro error: $message');
    if (mounted) {
      setState(() {});
      _showErrorSnackBar(message);
    }
  }

  void _onMacroPlay() {
    AppLogger().log('Macro play requested');
    setState(() => _macroStatus = null);
    _macroPlaybackCancelled = false;
    setState(() => _isMacroPlaying = true);
    _playMacro().whenComplete(() {
      if (mounted) setState(() => _isMacroPlaying = false);
    });
  }

  void _onMacroEdit() {
    setState(() {
      _macroStatus = null;
      _macroStatusMessage = null;
      _macroHadPlaybackError = false;
      _showMacroEditor = true;
    });
  }

  /// Core save logic — extracted so it can be awaited from [onWindowClose].
  Future<void> _saveMacro() async {
    setState(() => _macroStatus = null);
    if (!mounted) return;

    // When a macro was loaded from file, save back under the same filename
    // without prompting.
    if (_loadedMacroFileName != null) {
      try {
        final dir = AppPaths.macrosDirectory;
        final file = File('${dir.path}/$_loadedMacroFileName');
        await file.writeAsString(_currentMacroContent);
        _loadMacroFiles();
        setState(() {
          _isMacroModified = false;
        });
        _showInfoSnackBar('Macro "$_loadedMacroFileName" saved.');
      } catch (e) {
        AppLogger().log('Save macro error: $e');
        _showErrorSnackBar('Save macro failed: $e');
      }
      return;
    }

    // No loaded filename — ask for a name via the prefix dialog.
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const FilenamePrefixDialog(),
    );
    if (name == null || name.trim().isEmpty) return;

    try {
      final dir = await AppPaths.getOrCreateMacrosDir();
      final file = File('${dir.path}/${name.trim()}.m');
      await file.writeAsString(_currentMacroContent);
      _loadMacroFiles();
      setState(() {
        _loadedMacroFileName = '${name.trim()}.m';
        _isMacroModified = false;
      });
      _showInfoSnackBar('Macro "$name" saved.');
    } catch (e) {
      AppLogger().log('Save macro error: $e');
      _showErrorSnackBar('Save macro failed: $e');
    }
  }

  void _onMacroSave() {
    // Fire-and-forget: the recorder-panel button expects a VoidCallback.
    _saveMacro();
  }

  Future<void> _onMacroLoad(String fileName) async {
    try {
      final dir = AppPaths.macrosDirectory;
      final file = File('${dir.path}/$fileName');
      if (!await file.exists()) throw Exception('Macro file not found');
      final content = await file.readAsString();
      setState(() {
        _macroStatus = null;
        _currentMacroContent = content;
        _loadedMacroFileName = fileName;
        _isMacroModified = false;
        _showMacroEditor = true;
      });
    } catch (e) {
      AppLogger().log('Load macro error: $e');
      _showErrorSnackBar('Load macro failed: $e');
    }
  }

  Future<void> _onMacroDelete(String fileName) async {
    try {
      final dir = AppPaths.macrosDirectory;
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) {
        await file.delete();
      }
      _loadMacroFiles();
    } catch (e) {
      AppLogger().log('Delete macro error: $e');
    }
  }

  /// Builds the rotating arrows icon for the Data Logger toolbar button.
  Widget _buildDlButtonIcon() {
    return AnimatedBuilder(
      animation: _dlAnimationController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _dlIsRunning ? _dlAnimationController.value * 2 * 3.14159 : 0,
          child: Icon(
            Icons.sync,
            size: 25,
            color: _dlIsRunning ? Colors.greenAccent : Colors.white,
          ),
        );
      },
    );
  }

  // Saved Data Logger state for panel reopen
  List<DataLoggerPoint>? _savedDlPoints;
  DataLoggerConfig? _savedDlConfig;
  DataLoggerStatus? _savedDlStatus;
  Set<String>? _savedDlHiddenLines;
  DataLoggerService? _dlService;

  Widget _buildDataLoggerWindow() {
    return DataLoggerPanel(
      plotKey: _dlPlotKey,
      getInstrument: _getInstrument,
      isOnline: _isOnline,
      savedPoints: _savedDlPoints,
      savedConfig: _savedDlConfig,
      savedStatus: _savedDlStatus,
      savedHiddenLines: _savedDlHiddenLines,
      onServiceCreated: (service) {
        _dlService = service;
      },
      onSaveState: (points, config, status, hiddenLines) {
        _savedDlPoints = points;
        _savedDlConfig = config;
        _savedDlStatus = status;
        _savedDlHiddenLines = hiddenLines;
      },
      onRecordingFinished: (points, config) {
        _savedDlPoints = points;
        _savedDlConfig = config;
        _savedDlStatus = DataLoggerStatus.stopped;
        if (mounted) setState(() {});
      },
      onRunningChanged: (running) {
        if (running) {
          _dlAnimationController.repeat();
        } else {
          _dlAnimationController.stop();
        }
        _dlIsRunning = running;
        if (mounted) setState(() {});
      },
      onClose: () {
        _dlAnimationController.stop();
        _dlIsRunning = false;
        if (mounted) setState(() {});
        _togglePanel(ActivePanel.dataLogger);
      },
    );
  }

  /// Stops the Data Logger recording immediately, including the animation
  /// and the background SCPI service. Safe to call when logger is not running.
  void _stopDataLoggerIfRunning() {
    if (_activePanel == ActivePanel.dataLogger) {
      _dlAnimationController.stop();
      _dlIsRunning = false;
      _dlService?.stop();
    }
  }

  void _togglePanel(ActivePanel panel) {
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
    setState(() {
      if (_activePanel == panel) {
        // Toggle off: go back to previous
        _activePanel = _previousPanel;
        _previousPanel = ActivePanel.none;
      } else {
        // Toggle on: store current as previous and set new
        _previousPanel = _activePanel;
        _activePanel = panel;
      }

      // Special logic for profiles
      if (_activePanel == ActivePanel.profiles) {
        _loadProfileFiles();
      }

      // Special logic for macro recorder
      if (_activePanel == ActivePanel.macroRecorder) {
        _showMacroEditor = false;
        _loadMacroFiles();
      }
    });
  }

  // =========================================================================
  // Profile Operations
  // =========================================================================

  void _loadProfileFiles() {
    try {
      final dir = AppPaths.profilesDirectory;
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.lss'))
          .map(
            (f) => ProfileInfo(
              fileName: f.uri.pathSegments.last,
              lastModified: f.lastModifiedSync(),
            ),
          )
          .toList();
      setState(() {
        _profileFiles = files;
      });
    } catch (e) {
      AppLogger().log('Error loading profile files: $e');
    }
  }

  Future<void> _saveProfile(String name) async {
    try {
      final instr = await _getInstrument();
      if (instr == null) throw Exception('Device not connected');

      // Send PNSU? to get XML settings.
      // The instrument returns data with an IEEE 488.2 definite-length block
      // header (e.g. "PNSU #9000047692<?xml..."). Decode with lenient UTF-8
      // handling to tolerate any non-UTF-8 bytes in the raw response.
      final data = await instr.readRawResponse(
        'PNSU?',
        timeout: const Duration(seconds: 15),
      );
      final content = utf8.decode(data, allowMalformed: true);

      final dir = await AppPaths.getOrCreateProfilesDir();
      final file = File('${dir.path}/$name.lss');
      await file.writeAsString(content);

      _loadProfileFiles();
      AppLogger().log('Profile "$name" saved successfully.');
      _showInfoSnackBar('Profile "$name" saved.');
    } catch (e) {
      AppLogger().log('Save profile error: $e');
      AppLogger().log('Popup: Save profile failed: $e');
      _showErrorSnackBar('Save profile failed: $e');
    }
  }

  Future<void> _loadProfile(String fileName) async {
    // Capture profile load during macro recording
    if (_isMacroRecording) {
      final fullPath = '${AppPaths.profilesDirectory.path}/$fileName';
      _currentMacroContent += 'loadProfile("$fullPath")\n';
    }

    try {
      final dir = AppPaths.profilesDirectory;
      final file = File('${dir.path}/$fileName');
      if (!await file.exists()) throw Exception('File not found');

      final xml = await file.readAsString();
      AppLogger().log(
        'LoadProfile: reading "$fileName" (${xml.length} bytes / '
        '${(xml.length / 1024).toStringAsFixed(1)} KB)',
      );
      final instr = await _getInstrument();
      if (instr == null) throw Exception('Device not connected');

      // Send the entire XML string via profileWrite — a single USB bulk
      // transfer (no chunking), which the instrument requires for atomic
      // profile upload.  For VXI-11 mode this delegates to writeString.
      AppLogger().log(
        'LoadProfile: sending ${xml.length} bytes via writeProfileData '
        '(timeout: 15s, isUsb: $_isUsb)',
      );
      await instr.writeProfileData(xml, timeout: const Duration(seconds: 15));

      AppLogger().log('Profile "$fileName" loaded successfully.');
      _showInfoSnackBar('Profile "$fileName" loaded.');
      // Refresh screen dump after loading profile
      _scheduleRefresh();
    } catch (e) {
      AppLogger().log('Load profile error: $e');
      AppLogger().log('Popup: Load profile failed: $e');
      _showErrorSnackBar('Load profile failed: $e');
    }
  }

  Future<void> _deleteProfile(String fileName) async {
    try {
      final dir = AppPaths.profilesDirectory;
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) {
        await file.delete();
      }
      _loadProfileFiles();
    } catch (e) {
      AppLogger().log('Delete profile error: $e');
    }
  }

  // =========================================================================
  // Settings Panel
  // =========================================================================

  Widget _buildSettingsPanel() {
    return SettingsPanel(
      offset: _settingsOffset,
      ipAddress: _ipAddress,
      isUsb: _isUsb,
      signalGenerator: _signalGenerator,
      onSignalGeneratorChanged: (value) async {
        final changed = value != _signalGenerator;
        setState(() => _signalGenerator = value);
        await AppPreferences.setString('siggen_device', value);
        if (changed) {
          // The Bode service is bound to the service instance; stop it and
          // return to the configuration form before the family changes.
          _stopBodeIfRunning();
          if (_activePanel == ActivePanel.bode) {
            setState(() => _activePanel = ActivePanel.none);
          }
        }
        _configureSigGenDetection();
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

          setState(() {
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
              setState(() {});
            }
          } else {
            logger.log(
              '_isAiEnabled is false and no partial config: '
              '_aiProvider="$_aiProvider", token length=${_aiApiToken.trim().length}, '
              '_llmModel="$_llmModel"',
            );
          }
        },
        onClose: () => setState(() => _showSettings = false),
        onDrag: (delta) => setState(() => _settingsOffset += delta),
      ),
      onSaveWithParamsChanged: (v) async {
        setState(() => _saveWithParams = v);
        await AppPreferences.setBool('save_with_params', v);
      },
      onAskForFilenamePrefixChanged: (v) async {
        setState(() => _askForFilenamePrefix = v);
        await AppPreferences.setBool('ask_for_filename_prefix', v);
      },
    );
  }

  // =========================================================================
  // Device Operations
  // =========================================================================

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pingDevice(),
    );
    _pingDevice();
  }

  bool _isPinging = false;

  Future<void> _pingDevice() async {
    if (_isPinging || _isAcquiring || _isAcquiringWaveform || _bodeIsRunning) {
      return;
    }
    _isPinging = true;

    try {
      if (_isUsb) {
        final address = await Vxi11Instrument.detectLiveVisaAddress();
        if (mounted) {
          setState(() => _isOnline = address != null);
          if (address != null) {
            if (_deviceName == null) {
              // Awaited so _isPinging stays set until the IDN query finishes;
              // otherwise the next tick starts a second device query while
              // this one is still in flight.
              await _updateWindowTitle();
            } else {
              windowManager.setTitle(_deviceName!);
              // Re-assert the name: a transient ping failure clears it (see
              // _setFallbackWindowTitle) and _updateWindowTitle() is only
              // called while _deviceName is still unknown, so the agent would
              // otherwise never learn it again.
              _aiChatService.updateInstrumentModel(_deviceModel);
            }
          } else {
            _setFallbackWindowTitle();
          }
        }
      } else {
        final socket = await Socket.connect(
          _ipAddress,
          111,
          timeout: const Duration(seconds: 3),
        );
        socket.destroy();
        if (mounted) {
          setState(() => _isOnline = true);
          if (_deviceName == null) {
            await _updateWindowTitle();
          } else {
            windowManager.setTitle(_deviceName!);
            // Re-assert the name; see the note in the USB branch above.
            _aiChatService.updateInstrumentModel(_deviceModel);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isOnline = false);
        _setFallbackWindowTitle();
      }
    } finally {
      _isPinging = false;
    }
  }

  /// Sets the window title to the fallback value when the device name
  /// cannot be determined (offline, connection error, etc.).
  void _setFallbackWindowTitle() {
    if (_isUsb) {
      windowManager.setTitle('SDS-Remote — USB');
    } else {
      windowManager.setTitle('SDS-Remote — $_ipAddress');
    }
    // No instrument is reachable, so the AI must stop naming a specific model.
    // It answers knowledge and software questions either way.
    _aiChatService.updateInstrumentModel(null);
  }

  Future<void> _updateWindowTitle() async {
    try {
      // Use the cached instrument to avoid creating a separate USB connection
      // that would fight with the kernel driver detach/attach cycle.
      final instr = _instrument ?? await _getInstrument();
      if (instr == null) {
        _setFallbackWindowTitle();
        return;
      }
      final idn = (await instr.queryString('*IDN?')).trim();
      final parts = idn.split(',');
      final name = parts.length >= 2
          ? '${parts[0].trim()} ${parts[1].trim()}'
          : idn;
      // The model designation alone ("SDS1202X-E") is what identifies the
      // instrument in the knowledge base. The vendor prefix of the display
      // name is not part of the model and does not appear in the knowledge
      // base text, so it must not be used for searching.
      final model = parts.length >= 2 ? parts[1].trim() : idn;
      // The instrument reports its available channels directly; fall back to
      // the model number when the query is unavailable.
      int? chsChannels;
      try {
        chsChannels = channelCountFromChs(await instr.queryString('CHS?'));
      } catch (e) {
        AppLogger().log('CHS? query failed, using model number: $e');
      }
      if (mounted) {
        setState(() {
          _deviceName = name;
          _deviceModel = model;
          _numChannels = chsChannels ?? channelCountForModel(model);
          if (_selectedChannel > _numChannels) _selectedChannel = 1;
        });
        windowManager.setTitle(name);
        // Tell the AI which oscilloscope it is answering for. The agent is
        // configured before the first device response, so it learns the model
        // here rather than at construction time.
        _aiChatService.updateInstrumentModel(model);
      }
    } catch (_) {
      if (mounted) {
        _setFallbackWindowTitle();
      }
    }
  }

  Future<void> _acquireScreenDump({bool keepPanels = false}) async {
    if (_isAcquiring) return;

    // Stop the Data Logger immediately when switching away from it
    if (!keepPanels && _activePanel == ActivePanel.dataLogger) {
      _stopDataLoggerIfRunning();
      _stopBodeIfRunning();
    }

    setState(() {
      _isAcquiring = true;
      if (!keepPanels) {
        _activePanel = ActivePanel.none;
        _previousPanel = ActivePanel.none;
      }
    });

    try {
      final instr = await _getInstrument();
      if (instr == null) return;

      setState(() => _isOnline = true);
      final data = await instr.getScreenDump();

      final processedData = await compute(processScreenDump, data);

      if (mounted) {
        setState(() {
          _screenDump = processedData;
          _waveformCh1 = null;
          _waveformCh2 = null;
          _waveformCh3 = null;
          _waveformCh4 = null;
          _deviceParams = null;
          _isOnline = true;
          _waveformAcquired = false;
        });
      }
    } catch (e) {
      if (mounted) {
        AppLogger().log('Acquire display error: $e');
        // If it's a connection error, close the instrument so we retry next time
        _closeInstrument();
      }
      setState(() {
        _isOnline = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAcquiring = false;
        });
      }
    }
  }

  void _acquireWaveform() async {
    // Stop the Data Logger immediately when switching away from it
    _stopDataLoggerIfRunning();
    _stopBodeIfRunning();

    setState(() {
      _isAcquiringWaveform = true;
      _activePanel = ActivePanel.none;
      _previousPanel = ActivePanel.none;
    });

    try {
      final instr = await _getInstrument();
      final bool fourChannel = _numChannels >= 4;
      final raw = await WaveformAcquisition(_ipAddress).acquire(
        ch1: _ch1Enabled,
        ch2: _ch2Enabled,
        ch3: fourChannel && _ch3Enabled,
        ch4: fourChannel && _ch4Enabled,
        instr: instr,
      );

      // Run conversion on the main thread instead of via compute() because
      // Dart's isolate serialization does not support record types
      // ((double, double) pairs) — they get silently truncated to ~726 points
      // instead of the full 1201 points sent by the scope (WFSU NP=1201).
      final result = convertRawData(raw);

      setState(() {
        _waveformCh1 = result.$1;
        _waveformCh2 = result.$2;
        _waveformCh3 = result.$3;
        _waveformCh4 = result.$4;
        _deviceParams = result.$5;
        _screenDump = null;
        _isOnline = true;
        _waveformAcquired = true;
        // Reset zoom state on every new acquisition so the user sees the full
        // waveform (14 divisions) instead of a zoomed-in view from a previous
        // interaction that showed only ~4 waves.
        _zoomState = const ZoomState();
      });
    } catch (e) {
      AppLogger().log('Acquire waveform error: $e');
      final reason = e is AcquisitionException ? e.reason : e.toString();
      AppLogger().log('Popup: Waveform error: $reason');
      _showErrorSnackBar('Waveform error: $reason');
    } finally {
      if (mounted) {
        setState(() {
          _isAcquiringWaveform = false;
        });
      }
    }
  }

  /// Whether the standard save (screen dump or waveform) is available.
  bool get _canSaveStandard =>
      _activePanel == ActivePanel.none &&
      (_screenDump != null || _waveformAcquired);

  /// Whether a data logger report can be saved.
  bool get _canSaveDataLoggerReport =>
      _activePanel == ActivePanel.dataLogger &&
      _savedDlStatus == DataLoggerStatus.stopped &&
      (_savedDlPoints?.length ?? 0) > 1;

  /// Whether a Bode plot report can be saved.
  bool get _canSaveBodeReport =>
      _activePanel == ActivePanel.bode &&
      (_savedBodeStatus == BodeStatus.completed ||
          _savedBodeStatus == BodeStatus.cancelled) &&
      (_savedBodePoints?.any((point) => point.valid) ?? false);

  Future<void> _saveCurrentView() async {
    if (_canSaveBodeReport) {
      await _saveBodeReport();
    } else if (_canSaveDataLoggerReport) {
      await _saveDataLoggerReport();
    } else if (_screenDump != null) {
      await _saveScreenDump();
    } else if (_waveformCh1 != null ||
        _waveformCh2 != null ||
        _waveformCh3 != null ||
        _waveformCh4 != null) {
      await _saveWaveform();
    }
  }

  /// Captures the Bode plot as a PNG image, generates a PDF report, and
  /// saves it to the application's default save directory. When "Save csv
  /// data" is enabled, the sweep data is written as CSV as well.
  Future<void> _saveBodeReport() async {
    try {
      final prefix = await _askForFilenamePrefixIfNeeded();
      if (prefix == null) return; // user cancelled
      final pdfBaseName = prefix.isNotEmpty ? prefix : 'bode_plot_report';
      final csvBaseName = prefix.isNotEmpty ? prefix : 'bode_plot_data';

      final points = _savedBodePoints;
      final config = _savedBodeConfig;
      if (points == null || config == null || points.isEmpty) {
        throw Exception('No Bode plot data available');
      }

      // Capture the plot image from the RepaintBoundary
      final boundary =
          _bodePlotKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Bode plot not rendered yet');
      }

      // Capture at higher pixel ratio for better quality
      final uiImage = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await uiImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        throw Exception('Failed to capture Bode plot');
      }
      final rgba = byteData.buffer.asUint8List();

      // Brighten each pixel the same way the Data Logger report does, so the
      // dark plot background stays readable in the printed PDF.
      final image = img.Image.fromBytes(
        width: uiImage.width,
        height: uiImage.height,
        bytes: rgba.buffer,
        numChannels: 4,
      );
      for (final pixel in image) {
        pixel.r = (pixel.r * 2.5).clamp(0, 255).toInt();
        pixel.g = (pixel.g * 2.5).clamp(0, 255).toInt();
        pixel.b = (pixel.b * 2.5).clamp(0, 255).toInt();
      }
      final chartImageBytes = img.encodePng(image);

      final info = _sigGenService?.deviceInfo;
      final generatorIdentity = info?.scpiIdentity ?? 'Signal Generator';
      final deviceName = _deviceModel ?? _deviceName ?? _ipAddress;

      // Generate the PDF report
      final pdfBytes = await BodeReport.generatePdf(
        config: config,
        points: points,
        chartImageBytes: chartImageBytes,
        deviceName: deviceName,
        generatorIdentity: generatorIdentity,
      );

      // Write to the Bode reports subdirectory
      final dir = await AppPaths.getOrCreateBodeReportsDir();
      final file = await AppPaths.getUniqueFilePath(dir, pdfBaseName, 'pdf');
      await file.writeAsBytes(pdfBytes);
      final pdfName = file.uri.pathSegments.last;

      // If "Save csv data" is enabled, also write the sweep data as CSV
      String? csvName;
      if (_saveWithParams) {
        final csvDir = await AppPaths.getOrCreateBodeCsvDir();
        final csvFile = await AppPaths.getUniqueFilePath(
          csvDir,
          csvBaseName,
          'csv',
        );
        await csvFile.writeAsString(
          buildBodeCsv(
            config: config,
            points: points,
            deviceName: deviceName,
            generatorIdentity: generatorIdentity,
          ),
        );
        csvName = csvFile.uri.pathSegments.last;
      }

      if (mounted) {
        final msg = _saveWithParams
            ? 'Saved $pdfName + $csvName'
            : 'Saved $pdfName';
        _showInfoSnackBar(msg);
      }
    } catch (e) {
      _showErrorSnackBar('Save failed: $e');
    }
  }

  /// Shows the filename prefix dialog when [askForFilenamePrefix] is enabled.
  ///
  /// Returns the user-entered prefix, or null if the user cancelled.
  /// Returns an empty string when the flag is disabled (meaning "use default").
  Future<String?> _askForFilenamePrefixIfNeeded() async {
    if (!_askForFilenamePrefix) return '';
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (_) => const FilenamePrefixDialog(),
    );
  }

  Future<void> _saveScreenDump() async {
    try {
      final prefix = await _askForFilenamePrefixIfNeeded();
      if (prefix == null) return; // user cancelled
      final baseName = prefix.isNotEmpty ? prefix : 'screen_dump';

      final dir = await AppPaths.getOrCreateScreenshotsDir();
      final file = await AppPaths.getUniqueFilePath(dir, baseName, 'png');
      await file.writeAsBytes(_screenDump!);
      final fileName = file.uri.pathSegments.last;
      _showInfoSnackBar('Saved $fileName');
    } catch (e) {
      _showErrorSnackBar('Save failed: $e');
    }
  }

  Future<void> _saveWaveform() async {
    try {
      final prefix = await _askForFilenamePrefixIfNeeded();
      if (prefix == null) return; // user cancelled
      final imageBaseName = prefix.isNotEmpty ? prefix : 'waveform';
      final csvBaseName = prefix.isNotEmpty ? prefix : 'waveform_data';

      final boundary =
          _waveformKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Waveform not rendered yet');

      final uiImage = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await uiImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        throw Exception('Failed to capture waveform image');
      }

      final rgba = byteData.buffer.asUint8List();

      // Save waveform as PNG
      final pngBytes = img.encodePng(
        img.Image.fromBytes(
          width: uiImage.width,
          height: uiImage.height,
          bytes: rgba.buffer,
          numChannels: 4,
        ),
      );

      final dir = await AppPaths.getOrCreateWaveformImagesDir();
      final file = await AppPaths.getUniqueFilePath(dir, imageBaseName, 'png');
      await file.writeAsBytes(pngBytes);
      final pngName = file.uri.pathSegments.last;

      // Build waveform CSV using the extracted pure function.
      final csvContent = buildWaveformCsv(
        ch1: _waveformCh1,
        ch2: _waveformCh2,
        ch3: _waveformCh3,
        ch4: _waveformCh4,
        params: _deviceParams!,
        deviceName: _deviceName ?? _ipAddress,
        cursorState: _cursorState,
        channelCount: _numChannels,
      );

      final csvDir = await AppPaths.getOrCreateWaveformCsvDir();
      final csvFile = await AppPaths.getUniqueFilePath(
        csvDir,
        csvBaseName,
        'csv',
      );
      await csvFile.writeAsString(csvContent);
      final csvName = csvFile.uri.pathSegments.last;

      if (mounted) {
        final msg = 'Saved $pngName + $csvName';
        _showInfoSnackBar(msg);
      }
    } catch (e) {
      _showErrorSnackBar('Save failed: $e');
    }
  }

  /// Captures the Data Logger chart as a PNG image, generates a PDF report,
  /// and saves it to the application's default save directory.
  Future<void> _saveDataLoggerReport() async {
    try {
      final prefix = await _askForFilenamePrefixIfNeeded();
      if (prefix == null) return; // user cancelled
      final pdfBaseName = prefix.isNotEmpty ? prefix : 'data_logging_report';
      final csvBaseName = prefix.isNotEmpty ? prefix : 'data_logger_data';

      final points = _savedDlPoints;
      final config = _savedDlConfig;
      if (points == null || config == null) {
        throw Exception('No data logger data available');
      }

      // Capture the chart image from the RepaintBoundary
      final boundary =
          _dlPlotKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Data logger chart not rendered yet');
      }

      // Capture at higher pixel ratio for better quality
      final uiImage = await boundary.toImage(pixelRatio: 2.0);
      // Use raw RGBA (same format as waveform capture) for reliable decoding
      final byteData = await uiImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        throw Exception('Failed to capture data logger chart');
      }
      final rgba = byteData.buffer.asUint8List();

      // Brighten each pixel: scale RGB values to lighten the dark background.
      // The background is 0xFF0A192F (R=10, G=25, B=47).
      final image = img.Image.fromBytes(
        width: uiImage.width,
        height: uiImage.height,
        bytes: rgba.buffer,
        numChannels: 4,
      );
      // First pass: multiply brightness (2.5x to lighten the very dark bg)
      for (final pixel in image) {
        pixel.r = (pixel.r * 2.5).clamp(0, 255).toInt();
        pixel.g = (pixel.g * 2.5).clamp(0, 255).toInt();
        pixel.b = (pixel.b * 2.5).clamp(0, 255).toInt();
      }
      final chartImageBytes = img.encodePng(image);

      // Generate the PDF report
      final pdfBytes = await DataLoggerReport.generatePdf(
        points: points,
        config: config,
        chartImageBytes: chartImageBytes,
      );

      // Write to the logger reports subdirectory
      final dir = await AppPaths.getOrCreateLoggerReportsDir();
      final file = await AppPaths.getUniqueFilePath(dir, pdfBaseName, 'pdf');
      await file.writeAsBytes(pdfBytes);
      final pdfName = file.uri.pathSegments.last;

      // If "Save csv data" is enabled, also write data logger data as CSV
      String? csvName;
      if (_saveWithParams) {
        csvName = await _saveDataLoggerCsv(
          await AppPaths.getOrCreateLoggerCsvDir(),
          config,
          points,
          csvBaseName,
        );
      }

      if (mounted) {
        final msg = _saveWithParams
            ? 'Saved $pdfName + $csvName'
            : 'Saved $pdfName';
        _showInfoSnackBar(msg);
      }
    } catch (e) {
      _showErrorSnackBar('Save failed: $e');
    }
  }

  /// Writes a CSV file with the data logger's recorded data points.
  ///
  /// Returns the saved filename.
  ///
  /// Only includes columns for measurements that are enabled in the config
  /// AND not hidden via the chip toggle buttons ([_savedDlHiddenLines]).
  Future<String> _saveDataLoggerCsv(
    Directory dir,
    DataLoggerConfig config,
    List<DataLoggerPoint> points, [
    String baseName = 'data_logger_data',
  ]) async {
    final csvContent = buildDataLoggerCsv(
      config: config,
      points: points,
      hiddenLines: _savedDlHiddenLines ?? <String>{},
      deviceName: _deviceName ?? _ipAddress,
    );

    final csvFile = await AppPaths.getUniqueFilePath(dir, baseName, 'csv');
    await csvFile.writeAsString(csvContent);
    return csvFile.uri.pathSegments.last;
  }

  // =========================================================================
  // Initialization & Config
  // =========================================================================

  Future<void> _initialize() async {
    await _loadConfig();
    await _checkNewsNotification();
    _loadProfileFiles();
    _startPingTimer();
    _configureSigGenDetection();
    // Configure AI agent on startup if provider, token, and model are valid
    if (_isAiEnabled) {
      _configureAiService();
    }
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
    setState(() {
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
    });
  }

  Future<void> _saveConfig() async {
    await AppPreferences.setAll({
      'osci_ip': _ipAddress,
      'osci_is_usb': _isUsb,
      'ai_provider': _aiProvider,
      'ai_api_token': _aiApiToken,
      'llm_model': _llmModel,
      'siggen_device': _signalGenerator,
    });
  }

  void _showConfigDialog(BuildContext context) {
    setState(() {
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
      final panelWidth = 400.0;
      // Approximate height including the signal-generator section.
      final panelHeight = 780.0;

      final centerX = ((windowSize.width - panelWidth) / 2)
          .clamp(20.0, 1e9)
          .toDouble();
      final centerY = ((windowSize.height - panelHeight) / 2)
          .clamp(20.0, 1e9)
          .toDouble();

      setState(() {
        _settingsOffset = Offset(centerX, centerY);
      });
    } catch (e) {
      // Fallback to a reasonable position if we can't get window size
      setState(() {
        _settingsOffset = const Offset(100, 100);
      });
    }
  }

  // =========================================================================
  // AI Operations
  // =========================================================================

  /// Configures the [AiChatService] with the current provider, API token,
  /// model, and device IP.
  ///
  /// Looks up the [providerConfigs] table to map the selected provider name
  /// to the correct API key environment variable name and model prefix.
  /// The full model string is constructed as `<prefix>:<model>` (e.g.
  /// `openai:gpt-4o`).
  void _configureAiService() {
    final logger = AppLogger(
      agentName: 'main',
      toolName: '_configureAiService',
    );
    logger.log('ENTER: _configureAiService()');

    if (_aiProvider.isEmpty || _aiApiToken.trim().length < 8) {
      logger.log(
        'EXIT: AI provider or token not valid, skipping configuration. '
        '_aiProvider="$_aiProvider", token length=${_aiApiToken.trim().length}',
      );
      return;
    }

    if (_llmModel.trim().isEmpty) {
      logger.log('EXIT: LLM model is empty, deactivating AI agent');
      _aiChatService.deactivate();
      if (mounted) {
        setState(() {});
      }
      return;
    }

    // Look up the provider configuration from the table.
    final config = providerConfigs.firstWhere(
      (c) => c.providerName == _aiProvider,
      orElse: () => ProviderConfig(
        modelPrefix: _aiProvider.toLowerCase(),
        providerName: _aiProvider,
        apiKeyName: '${_aiProvider.toUpperCase()}_API_KEY',
      ),
    );

    final apiKeyName = config.apiKeyName;
    final modelPrefix = config.modelPrefix;
    final modelName = _llmModel.isNotEmpty ? _llmModel : 'gpt-4o';
    final fullModel = '$modelPrefix:$modelName';

    logger.log(
      'Configuring AI service: provider=$_aiProvider, '
      'apiKeyName=$apiKeyName, model=$fullModel, ip=$_ipAddress',
    );

    _aiChatService.configure(
      apiKey: apiKeyName,
      apiToken: _aiApiToken,
      model: fullModel,
      vxi11Host: _ipAddress,
      // Null until the device has answered its first *IDN? query; the ping
      // timer reports the name via updateInstrumentModel() once it is known.
      instrumentModel: _deviceModel,
    );

    logger.log(
      'After _aiChatService.configure(): isInitialized=${_aiChatService.isInitialized}',
    );

    if (mounted) {
      setState(() {
        // Trigger rebuild after AI service is configured
      });
    }
  }

  /// Open attempt currently in progress, if any.
  ///
  /// Without this, two callers racing on a cold cache (e.g. the 5 s ping timer
  /// and a user action) would both see [_instrument] == null and both try to
  /// claim the USB interface. One wins, the other fails with
  /// "claim interface 0 ... BUSY" — and its error path then tears down the
  /// shared USB connection the winner is still using.
  Future<Vxi11Instrument?>? _instrumentOpenInFlight;

  Future<Vxi11Instrument?> _getInstrument() async {
    if (_instrument != null) return _instrument;
    // Join an open that is already running instead of starting a second one.
    final inFlight = _instrumentOpenInFlight;
    if (inFlight != null) return inFlight;

    final future = _openInstrument();
    _instrumentOpenInFlight = future;
    try {
      return await future;
    } finally {
      _instrumentOpenInFlight = null;
    }
  }

  Future<Vxi11Instrument?> _openInstrument() async {
    try {
      final instr = Vxi11Instrument(_ipAddress, sourceLabel: 'getInstrument');
      await instr.open(timeoutSeconds: 5.0);
      _instrument = instr;
      return _instrument;
    } catch (e) {
      // open() drives either transport; naming the wrong one here sends the
      // reader hunting in the wrong layer (a USB claim failure used to be
      // reported as a VXI-11 failure).
      final transport = Vxi11Instrument.isUsbMode ? 'USB (USBTMC)' : 'VXI-11';
      AppLogger().log('Failed to open $transport connection: $e');
      setState(() => _isOnline = false);
      return null;
    }
  }

  Future<void> _closeInstrument() async {
    if (_instrument != null) {
      final instr = _instrument!;
      _instrument = null;
      try {
        // Use a tight timeout: instr.close() sends a DESTROY_LINK RPC
        // and closes the TCP socket.  If the instrument is unresponsive
        // this must not block application shutdown for more than 1 s.
        await instr.close().timeout(const Duration(seconds: 1));
      } catch (e) {
        AppLogger().log('Error closing instrument: $e');
      }
    }
  }

  /// NOTE: In USB mode the connection is deliberately NOT released after each
  /// SCPI transaction any more.
  ///
  /// Releasing it made the kernel driver re-attach (and re-probe the device)
  /// after every transaction, then detach again on the next claim. That
  /// detach/attach churn — 40 open cycles in a single session — de-stabilised
  /// the USB link: the instrument re-enumerated underneath the app and opens
  /// started failing with "Failed to claim interface 0: error code -6 (BUSY)".
  /// The interface is now claimed once and held for the lifetime of the app,
  /// and released in [dispose].

  void _scheduleRefresh() {
    if (_refreshPending) return;
    _refreshPending = true;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(Duration(milliseconds: _refreshDelayMs), () {
      _refreshPending = false;
      if (mounted && _isOnline && !_isAcquiringWaveform && !_bodeIsRunning) {
        _acquireScreenDump(keepPanels: true);
      }
    });
  }

  /// Sends a SCPI command to the instrument and returns true if successful.
  /// Shows error message on failure.
  /// If a macro recording is in progress the command is captured into
  /// [_currentMacroContent].
  Future<bool> _sendCommand(String command) async {
    // Capture SCPI commands during macro recording
    if (_isMacroRecording) {
      _currentMacroContent += 'scpi("$command")\n';
    }

    if (!_isOnline) {
      AppLogger().log('Popup: Device is offline');
      _showErrorSnackBar('Device is offline');
      return false;
    }

    try {
      final instr = await _getInstrument();
      if (instr == null) return false;

      await instr.writeString(command);
      return true;
    } catch (e) {
      AppLogger().log('Send command error: $e');
      _closeInstrument(); // Connection might be bad
      AppLogger().log('Popup: Failed to send command: $e');
      _showErrorSnackBar('Failed to send command: $e');
      return false;
    }
  }

  // =========================================================================
  // SnackBar Helpers
  // =========================================================================

  void _showErrorSnackBar(
    String message, {
    Duration duration = const Duration(seconds: 5),
  }) {
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

  // =========================================================================
  // Shared SCPI Event-Processing Helper
  // =========================================================================

  /// Sends a SCPI command, waits for the instrument to process it,
  /// refreshes the screen dump, and enforces a cooldown.
  ///
  /// Returns `true` if the command was sent and screen refreshed successfully.
  Future<bool> _processScpiEvent(String command, {String? errorContext}) async {
    if (_isProcessingEvent || !_isOnline) return false;

    _isProcessingEvent = true;
    if (mounted) setState(() {});

    try {
      if (await _sendCommand(command)) {
        // Wait for oscilloscope to process the command
        await Future.delayed(const Duration(milliseconds: _refreshDelayMs));
        // Fetch the screen dump synchronously
        await _acquireScreenDump(keepPanels: true);
        // Final cooldown before next event is allowed
        await Future.delayed(const Duration(milliseconds: 500));
        return true;
      }
    } catch (e) {
      final ctx = errorContext ?? command;
      AppLogger().log('$ctx handler error: $e');
      if (mounted) {
        _showErrorSnackBar('Error processing $ctx: $e');
      }
    } finally {
      _isProcessingEvent = false;
      if (mounted) setState(() {});
    }
    return false;
  }

  /// Handles soft key button press (M1-M6).
  /// Sends $$SY_FP X,1 command where X is button number, then refreshes screen.
  void _handleSoftKeyPress(int buttonNumber) => _processScpiEvent(
    '\$\$SY_FP $buttonNumber,1',
    errorContext: 'M$buttonNumber',
  );

  /// Handles MENU button press.
  /// Sends $$SY_FP 0,1 command (VXI special SPCI command for MENU button),
  /// then immediately requests a screen dump image.
  void _handleMenuPress() =>
      _processScpiEvent('\$\$SY_FP 0,1', errorContext: 'MENU');

  /// Generic handler for knob rotation (value changes).
  /// Sends `$$SY_FP <cmd>,1` when turned right or `$$SY_FP <cmd>,-1` when left.
  Future<void> _handleKnobChanged(KnobId knob, double newValue) async {
    final prev = _knobPreviousValues[knob]!;
    if (newValue == prev || !_isOnline || _isProcessingEvent) return;
    final dir = newValue > prev ? 1 : -1;
    await _processScpiEvent(
      '\$\$SY_FP ${knob.scpiCommandNumber},$dir',
      errorContext: '${knob.name} knob',
    );
    _knobPreviousValues[knob] = newValue;
  }

  /// Generic handler for knob tap/click.
  /// Sends `$$SY_FP <cmd>,0`.
  Future<void> _handleKnobTapped(KnobId knob) => _processScpiEvent(
    '\$\$SY_FP ${knob.scpiCommandNumber},0',
    errorContext: '${knob.name} knob tap',
  );

  // =========================================================================
  // Button Operations (generic handler)
  // =========================================================================

  /// Channel buttons select the channel the shared vertical knobs act on and
  /// then send the front-panel toggle command for it.
  Future<void> _handleChannelButtonPress(String channel) async {
    final number = int.tryParse(channel.replaceFirst('CH', ''));
    if (number != null && number >= 1 && number <= _numChannels) {
      setState(() => _selectedChannel = number);
    }
    await _handleButtonPress(channel);
  }

  /// Generic handler for any button press (menu, vertical, horizontal, trigger, channel).
  /// Looks up the SCPI command from [buttonCommands] and sends it.
  Future<void> _handleButtonPress(String buttonLabel) async {
    final command = buttonCommands[buttonLabel];
    if (command == null) {
      AppLogger().log('Button "$buttonLabel" not implemented yet');
      if (mounted) {
        _showInfoSnackBar('Button "$buttonLabel" not implemented yet');
      }
      return;
    }
    await _processScpiEvent(command, errorContext: buttonLabel);
  }

  // =========================================================================
  // Cursor Operations
  // =========================================================================

  /// Threshold for cursor proximity detection (in relative coordinates 0.0-1.0)
  static const double _cursorHitThreshold = 0.02;

  /// Checks if the mouse position is near any cursor line.
  /// Returns the index of the nearest cursor, or null if none is close enough.
  int? _findNearestCursor(double relX, double relY) {
    double minDist = double.infinity;
    int? closestIndex;

    if (_cursorState.cursorsXEnabled) {
      final d1 = (relX - _cursorState.cursorX1).abs();
      final d2 = (relX - _cursorState.cursorX2).abs();
      if (d1 < minDist) {
        minDist = d1;
        closestIndex = 0;
      }
      if (d2 < minDist) {
        minDist = d2;
        closestIndex = 1;
      }
    }

    if (_cursorState.cursorsYEnabled) {
      final d1 = (relY - _cursorState.cursorY1).abs();
      final d2 = (relY - _cursorState.cursorY2).abs();
      if (d1 < minDist) {
        minDist = d1;
        closestIndex = 2;
      }
      if (d2 < minDist) {
        minDist = d2;
        closestIndex = 3;
      }
    }

    // Only return a cursor if it's within the hit threshold
    if (closestIndex != null && minDist <= _cursorHitThreshold) {
      return closestIndex;
    }
    return null;
  }

  // =========================================================================
  // Zoom / Pan
  // =========================================================================

  void _onZoomFactorChanged(double factor) {
    setState(() {
      // When zooming out completely to 1.0x, reset pan to center
      // so the waveform returns to its original centered position.
      _zoomState = _zoomState.copyWith(
        zoomFactor: factor,
        panX: factor == 1.0 ? 0.5 : null,
        panY: factor == 1.0 ? 0.5 : null,
      );
    });
  }

  void _onPanXChanged(double panX) {
    setState(() {
      _zoomState = _zoomState.copyWith(panX: panX);
    });
  }

  void _onPanYChanged(double panY) {
    setState(() {
      _zoomState = _zoomState.copyWith(panY: panY);
    });
  }

  Widget _buildHorizontalPanSlider() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.scaffoldBackground.withValues(alpha: 0.8),
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SliderTheme(
        data: const SliderThemeData(
          trackHeight: 4,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
          activeTrackColor: Colors.cyanAccent,
          inactiveTrackColor: Colors.white24,
          thumbColor: Colors.cyanAccent,
        ),
        child: Slider(value: _zoomState.panX, onChanged: _onPanXChanged),
      ),
    );
  }

  Widget _buildVerticalPanSlider() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.scaffoldBackground.withValues(alpha: 0.8),
        border: const Border(left: BorderSide(color: AppColors.border)),
      ),
      child: RotatedBox(
        quarterTurns: 1,
        child: SliderTheme(
          data: const SliderThemeData(
            trackHeight: 4,
            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: Colors.orangeAccent,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.orangeAccent,
          ),
          child: Slider(value: _zoomState.panY, onChanged: _onPanYChanged),
        ),
      ),
    );
  }

  void _onDeviceParamChannelToggle(String channel) {
    setState(() {
      switch (channel) {
        case 'CH1':
          _ch1Enabled = !_ch1Enabled;
        case 'CH2':
          _ch2Enabled = !_ch2Enabled;
        case 'CH3':
          _ch3Enabled = !_ch3Enabled;
        case 'CH4':
          _ch4Enabled = !_ch4Enabled;
      }
    });
  }

  void _onRefToggled(bool visible) {
    setState(() {
      _refVisible = visible;
      // Aligning a hidden reference would move something the user cannot see.
      if (!visible) _refMoving = false;
    });
  }

  void _onRefMovingToggled(bool moving) {
    setState(() {
      _refMoving = moving;
      _draggingRef = false;
      // The hover highlight belongs to the cursor drag, which is suspended
      // while the reference is being moved.
      _hoveredCursorType = null;
    });
  }

  void _onRefReset() {
    setState(() => _refOffset = const ReferenceOffset());
  }

  // =========================================================================
  // Reference Waveform Helpers
  // =========================================================================

  /// Lists CSV waveform files in the waveform/csv directory and shows a
  /// file-picker dialog. Returns the selected file path, or null if the
  /// user cancelled or no files are available.
  Future<String?> _pickReferenceCsvFile() async {
    final dir = AppPaths.waveformCsvDirectory;
    if (!await dir.exists()) {
      _showInfoSnackBar('No saved waveform CSV files found.');
      return null;
    }

    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.csv'))
            .toList()
          ..sort(
            (a, b) =>
                a.uri.pathSegments.last.compareTo(b.uri.pathSegments.last),
          );

    if (files.isEmpty) {
      _showInfoSnackBar('No waveform CSV files found.');
      return null;
    }

    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) => ReferenceFilePickerDialog(files: files),
    );
  }

  /// Aligns reference waveform points so their time axis matches the
  /// live waveform: the CSV always starts at t=0, but live data may use
  /// trigger-relative times starting at a negative value.
  static List<(double, double)> _alignReferencePoints(
    List<(double, double)> points,
    double? liveFirstTime,
  ) {
    final shift = (liveFirstTime ?? points.first.$1) - points.first.$1;
    if (shift == 0) return points;
    return points.map((p) => (p.$1 + shift, p.$2)).toList();
  }

  /// Opens a file selection dialog showing CSV waveform files in the
  /// application's waveform/csv subdirectory. When the file contains more
  /// than one channel the user is asked which channel to load.
  Future<void> _loadReferenceWaveform() async {
    final selected = await _pickReferenceCsvFile();
    if (selected == null || !mounted) return;

    try {
      final file = File(selected);
      final content = await file.readAsString();
      final csv = parseWaveformCsv(content);
      final channels = <String, List<(double, double)>>{
        if (csv.ch1 != null) 'ch1': csv.ch1!,
        if (csv.ch2 != null) 'ch2': csv.ch2!,
        if (csv.ch3 != null) 'ch3': csv.ch3!,
        if (csv.ch4 != null) 'ch4': csv.ch4!,
      };
      if (channels.isEmpty) {
        _showErrorSnackBar(
          'Invalid waveform CSV. Expected header: '
          'Time (s),CH1 (V),CH2 (V) or '
          'Time (s),CH1 (V),CH2 (V),CH3 (V),CH4 (V)',
        );
        return;
      }

      if (!mounted) return;

      final channel = channels.length == 1
          ? channels.keys.first
          : await showDialog<String>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: const Text('Select Channel'),
                children: [
                  for (final entry in channels.entries)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, entry.key),
                      child: Text(
                        entry.key.toUpperCase(),
                        style: TextStyle(
                          color: waveformChannelColor(entry.key),
                        ),
                      ),
                    ),
                ],
              ),
            );
      if (channel == null) return;

      final points = channels[channel]!;

      final (liveFirstTime, _) = _waveformTimeBounds();
      final alignedPoints = _alignReferencePoints(points, liveFirstTime);

      setState(() {
        _refWaveform = WaveformData(points: alignedPoints);
        _refVisible = true;
        _refFileName = file.uri.pathSegments.last;
        _refChannelOrigin = channel;
        // The load aligns the reference itself, so an offset from a previous
        // reference would be meaningless for this one.
        _refOffset = const ReferenceOffset();
      });
    } catch (e) {
      _showErrorSnackBar('Error loading reference: $e');
    }
  }

  void _onCursorXToggled(bool enabled) {
    setState(() {
      _cursorState = _cursorState.copyWith(cursorsXEnabled: enabled);
    });
  }

  void _onCursorYToggled(bool enabled) {
    setState(() {
      _cursorState = _cursorState.copyWith(cursorsYEnabled: enabled);
    });
  }

  /// Returns the size of the waveform widget, or null if not available.
  Size? _getWaveformSize() {
    final renderBox =
        _waveformKey.currentContext?.findRenderObject() as RenderBox?;
    return renderBox?.size;
  }

  Rect? _getCursorInfoPanelRect(Size size) =>
      getCursorInfoPanelRect(size, _cursorState);

  void _onCursorHover(PointerHoverEvent event) {
    // While the reference is being moved the cursor drag is suspended, so no
    // cursor highlight is computed either.
    if (_refMoving) {
      if (_hoveredCursorType != null) {
        setState(() => _hoveredCursorType = null);
      }
      return;
    }

    final size = _getWaveformSize();
    if (size == null || size.width == 0 || size.height == 0) return;

    final localPos = event.localPosition;
    final relX = localPos.dx / size.width;
    final relY = localPos.dy / size.height;

    // Check if hovering over cursor info panel
    final panelRect = _getCursorInfoPanelRect(size);
    final bool overPanel = panelRect != null && panelRect.contains(localPos);

    if (overPanel) {
      if (_hoveredCursorType != 'info') {
        setState(() => _hoveredCursorType = 'info');
      }
      return;
    }

    if (!_cursorState.cursorsXEnabled && !_cursorState.cursorsYEnabled) {
      if (_hoveredCursorType != null) {
        setState(() => _hoveredCursorType = null);
      }
      return;
    }

    final nearest = _findNearestCursor(relX, relY);
    final newType = switch (nearest) {
      null => null,
      0 || 1 => 'x',
      _ => 'y',
    };

    if (newType != _hoveredCursorType) {
      setState(() => _hoveredCursorType = newType);
    }
  }

  void _onCursorDragStart(DragStartDetails details) {
    final size = _getWaveformSize();
    if (size == null || size.width == 0 || size.height == 0) return;

    final localPos = details.localPosition;

    // Check if starting drag on cursor info panel
    final panelRect = _getCursorInfoPanelRect(size);
    if (panelRect != null && panelRect.contains(localPos)) {
      _draggingCursorInfo = true;
      return;
    }

    if (!_cursorState.cursorsXEnabled && !_cursorState.cursorsYEnabled) return;

    final relX = localPos.dx / size.width;
    final relY = localPos.dy / size.height;

    // Only start drag if directly over a cursor line
    final nearest = _findNearestCursor(relX, relY);
    if (nearest != null) {
      _draggingCursorIndex = nearest;
    }
  }

  Offset _clampCursorInfoOffset(Offset proposedOffset, Size size) =>
      clampCursorInfoOffset(proposedOffset, size, _cursorState);

  void _onCursorDragUpdate(DragUpdateDetails details) {
    if (_draggingCursorInfo) {
      final size = _getWaveformSize();
      if (size == null || size.width == 0 || size.height == 0) return;

      final newOffset = _cursorState.cursorInfoOffset + details.delta;
      final clampedOffset = _clampCursorInfoOffset(newOffset, size);
      setState(() {
        _cursorState = _cursorState.copyWith(cursorInfoOffset: clampedOffset);
      });
      return;
    }

    if (_draggingCursorIndex == null) return;

    final size = _getWaveformSize();
    if (size == null || size.width == 0 || size.height == 0) return;

    final localPos = details.localPosition;
    final relX = (localPos.dx / size.width).clamp(0.0, 1.0);
    final relY = (localPos.dy / size.height).clamp(0.0, 1.0);

    setState(() {
      switch (_draggingCursorIndex) {
        case 0:
          _cursorState = _cursorState.copyWith(cursorX1: relX);
          break;
        case 1:
          _cursorState = _cursorState.copyWith(cursorX2: relX);
          break;
        case 2:
          _cursorState = _cursorState.copyWith(cursorY1: relY);
          break;
        case 3:
          _cursorState = _cursorState.copyWith(cursorY2: relY);
          break;
      }
    });
  }

  void _onCursorDragEnd(DragEndDetails details) {
    _draggingCursorIndex = null;
    _draggingCursorInfo = false;
  }

  // =========================================================================
  // Reference Waveform Alignment ("Move Reference" mode)
  // =========================================================================

  /// Overlay hint shown while the reference can be moved: what the gesture
  /// does and how far the reference currently sits from its loaded position.
  Widget _buildRefMoveHint() {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xCC0D1117),
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.open_with,
              size: 14,
              color: Colors.lightBlueAccent,
            ),
            const SizedBox(width: 8),
            Text(
              'Move reference  ·  ΔX ${formatOffsetDivisions(_refOffset.dxDiv)}'
              '  ·  ΔY ${formatOffsetDivisions(_refOffset.dyDiv)}'
              '  ·  Shift = snap',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// Pan dispatcher: with "Move Reference" armed the drag aligns the
  /// reference, otherwise it drags a cursor.
  void _onWaveformPanStart(DragStartDetails details) {
    if (_refMoving && _refVisible && _startRefDrag(details)) return;
    _onCursorDragStart(details);
  }

  void _onWaveformPanUpdate(DragUpdateDetails details) {
    if (_draggingRef) {
      _updateRefDrag(details);
      return;
    }
    _onCursorDragUpdate(details);
  }

  void _onWaveformPanEnd(DragEndDetails details) {
    if (_draggingRef) {
      _draggingRef = false;
      return;
    }
    _onCursorDragEnd(details);
  }

  /// Starts a reference drag. Returns false when the gesture belongs to the
  /// cursor info panel, which stays draggable in every mode.
  bool _startRefDrag(DragStartDetails details) {
    final size = _getWaveformSize();
    if (size == null || size.width == 0 || size.height == 0) return false;

    final panelRect = _getCursorInfoPanelRect(size);
    if (panelRect != null && panelRect.contains(details.localPosition)) {
      _draggingCursorInfo = true;
      return false;
    }

    // setState so the pointer switches to the "grabbing" cursor right away.
    setState(() {
      _draggingRef = true;
      _refDragAnchor = _refOffset;
      _refDragOriginPx = details.localPosition;
    });
    return true;
  }

  /// Moves the reference by the pointer movement since the drag started,
  /// converted through the same mapping the painter draws the reference with
  /// — so the trace stays under the pointer at any zoom and pan position.
  void _updateRefDrag(DragUpdateDetails details) {
    final size = _getWaveformSize();
    final params = _deviceParams;
    if (size == null || size.width == 0 || size.height == 0 || params == null) {
      return;
    }

    final transform = WaveformViewTransform.forReference(
      params: params,
      zoom: _zoomState,
      size: size,
      origin: _refChannelOrigin,
    );

    final double dxPx = details.localPosition.dx - _refDragOriginPx.dx;
    final double dyPx = details.localPosition.dy - _refDragOriginPx.dy;

    var offset = ReferenceOffset(
      dxDiv: _refDragAnchor.dxDiv + dxPx * transform.dxDivPerPixel,
      // Screen y grows downwards, voltage upwards.
      dyDiv: _refDragAnchor.dyDiv - dyPx * transform.dyDivPerPixel,
    );

    if (HardwareKeyboard.instance.isShiftPressed) {
      offset = offset.snappedTo(_refMinorDiv / _zoomState.zoomFactor);
    }

    setState(() {
      _refOffset = offset.clampedTo(
        maxDivX: _refMaxDivX / _zoomState.zoomFactor,
        maxDivY: _refMaxDivY / _zoomState.zoomFactor,
      );
    });
  }
}

/// Adapter that lets [SigGenWindowHost] push snapshots into the launcher.
class _SigGenWindowSink implements SigGenWindowEventSink {
  _SigGenWindowSink(this._push);

  final Future<void> Function(SigGenWindowState) _push;

  @override
  Future<void> pushState(SigGenWindowState state) => _push(state);
}
