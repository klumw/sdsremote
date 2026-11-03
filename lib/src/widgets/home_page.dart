import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'dart:ui'
    as ui
    show Image, ImageByteFormat, PixelFormat, decodeImageFromPixels;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import '../app/app_config.dart';
import '../app/app_theme.dart';
import '../app/app_preferences.dart';
import '../app/window_state.dart';
import '../waveform/cursor_geometry.dart';
import 'animated_sync_icon.dart';
import 'osci_toolbar_button.dart';
import 'spectrum_view.dart';
import 'reference_file_picker_dialog.dart';
import 'filename_prefix_dialog.dart';
import 'unsaved_changes_dialog.dart';
import 'package:window_manager/window_manager.dart';

import '../instrument/dart_vxi11.dart';
import '../instrument/measurement.dart' show formatMeasurementValue;
import '../instrument/vnc_screen_service.dart';
import '../spectrum/spectrum_analysis.dart';
import '../spectrum/spectrum_csv.dart';
import '../spectrum/spectrum_models.dart';
import '../spectrum/windows.dart';
import '../waveform/waveform_acquisition.dart';
import '../waveform/waveform_converter.dart';
import '../waveform/waveform_processing.dart';
import '../waveform/waveform_csv_parser.dart';
import '../waveform/waveform_csv_writer.dart';
import '../data_logger/data_logger_csv_writer.dart';
import '../waveform/waveform_models.dart';
import '../waveform/waveform_compare.dart';
import '../waveform/waveform_mask.dart';
import '../waveform/waveform_measurements.dart';
import '../waveform/waveform_history.dart';
import '../waveform/waveform_painter.dart';
import '../waveform/waveform_export.dart';
import '../waveform/waveform_report.dart';
import '../waveform/waveform_view_transform.dart';
import '../waveform/ripple_noise.dart';
import '../waveform/clock_detection.dart';
import '../waveform/analysis/waveform_analysis_models.dart';
import '../waveform/analysis/waveform_analysis_service.dart';
import '../waveform/analysis/waveform_fault_analyzer.dart';
import '../waveform/analysis/waveform_fault_models.dart';
import '../waveform/analysis/waveform_fault_profile_store.dart';
import 'waveform_export_dialog.dart';
import 'waveform_measurement_panel.dart';
import 'waveform_analysis_view.dart';
import 'ripple_noise_dialog.dart';
import 'timelapse_dialog.dart';
import '../timelapse/timelapse.dart';
import '../ai/ai_chat_service.dart';
import '../ai/ai_settings.dart';
import '../ai/control_panel_chat_controller.dart';
import '../ai/input_history.dart';
import '../ai/macro_chat_controller.dart';
import '../ai/tools/signal_generator_tool.dart';
import '../ai/waveform_chat_controller.dart';
import '../core/logger.dart';
import '../devices/device_agent_context.dart';
import '../devices/device_profile_models.dart';
import '../devices/device_profile_store.dart';
import '../devices/flutter_device_asset_source.dart';
import 'osci_physical_panel.dart';
import 'osci_chat_window.dart';
import 'osci_help_window.dart';
import 'osci_news_notification.dart';
import 'osci_device_params_panel.dart';
import 'osci_settings_panel.dart';
import 'osci_profiles_panel.dart';
import 'waveform_ai_panel.dart';
import '../data_logger/data_logger_models.dart';
import 'data_logger_panel.dart';
import '../data_logger/data_logger_service.dart';
import '../data_logger/data_logger_report.dart';
import '../calculator/calculator_shortcut.dart';
import '../calculator/calculator_window_launcher.dart';
import '../calculator/calculator_window_protocol.dart';
import '../bode/bode_csv_writer.dart';
import '../bode/bode_models.dart';
import '../bode/bode_plot_service.dart';
import '../bode/bode_report.dart';
import '../signal_generator/fy6900_driver.dart';
import '../signal_generator/fy6900_serial_transport.dart';
import '../signal_generator/jds6600_driver.dart';
import '../signal_generator/jds6600_serial_transport.dart';
import '../signal_generator/models.dart';
import '../signal_generator/signal_generator_detector.dart';
import '../signal_generator/signal_generator_service.dart';
import '../signal_generator/signal_generator_shortcut.dart';
import '../signal_generator/siggen_window_host.dart';
import '../signal_generator/siggen_window_launcher.dart';
import '../signal_generator/siggen_window_protocol.dart';
import '../signal_generator/siggen_window_server.dart';
import 'bode_plot_panel.dart';
import '../app/app_paths.dart';
import '../macro/macro_recorder_models.dart';
import '../macro/macro_print_controller.dart';
import '../macro/macro_ast.dart';
import '../macro/macro_debug.dart';
import 'macro_recorder_panel.dart';
import 'macro_editor_panel.dart';
import '../macro/macro_evaluator.dart';
import '../macro/macro_oscope_status.dart';
import '../macro/macro_siggen.dart';
import '../macro/macro_siggen_app.dart';
import '../macro/macro_templates.dart';
import '../voice/voice_activity_indicator.dart';
import '../voice/voice_input_binding.dart';
import '../voice/voice_input_service.dart';
import '../ai/tools/vxi11_tool.dart' show onScpiCommandSent;

class OsciHomePage extends StatefulWidget {
  const OsciHomePage({super.key, this.debugMode = false});

  /// Whether the app was started with the explicit `--debug` flag.
  ///
  /// Debug-only features such as the waveform Analysis tab are hidden when
  /// this is false.
  final bool debugMode;

  @override
  State<OsciHomePage> createState() => _OsciHomePageState();
}

/// Which analysis view the Acquire Waveform screen shows.
enum _WaveformViewMode { time, spectrum, analysis }

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

  /// Device profiles loaded from `assets/devices` at application start.
  DeviceProfileStore? _deviceProfileStore;

  /// De-duplicates concurrent profile-load attempts.
  Future<void>? _deviceProfileLoad;

  /// Context for the oscilloscope instrument agent.
  DeviceAgentContext? _sdsDeviceContext;

  /// Device family the current [_sigGenService] was built for.
  String? _sigGenDeviceType;

  // Signal generator OS window (configurable, default Ctrl+J).
  SigGenWindowHost? _sigGenWindowHost;
  SigGenWindowServer? _sigGenWindowServer;
  SigGenWindowLauncher? _sigGenWindowLauncher;
  SignalGeneratorShortcut _signalGeneratorShortcut =
      SignalGeneratorShortcut.defaultShortcut;
  bool _sigGenWindowOpen = false;

  // Engineering calculator OS window (configurable, default Ctrl+R).
  CalculatorWindowLauncher? _calculatorWindowLauncher;
  CalculatorShortcut _calculatorShortcut = CalculatorShortcut.defaultShortcut;

  // AI
  String _aiProvider = '';
  String _aiApiToken = '';
  String _llmModel = '';
  bool get _isAiEnabled =>
      _aiProvider.isNotEmpty &&
      _aiApiToken.trim().length >= 8 &&
      _llmModel.trim().isNotEmpty;

  /// AI settings shared by the feature assistants (Macro Editor, Control
  /// Panel and help window), or null when the AI is not configured.
  ///
  /// The main chat is configured separately through [AiChatService]; the
  /// assistants use the same provider, token and model so every AI feature
  /// follows the values from the settings panel.
  AiSettings? get _aiSettings {
    if (!_isAiEnabled) return null;
    return AiSettings.fromProviderConfig(
      providerName: _aiProvider,
      apiToken: _aiApiToken,
      modelName: _llmModel,
    );
  }

  // Acquisition
  bool _isAcquiring = false;
  bool _isAcquiringWaveform = false;
  SdsNotification? _latestNews;
  bool _hasUnreadUpdate = false;
  Uint8List? _screenDump;

  // Live screen (VNC) — four-channel instruments connected over IP only.
  //
  // [_vncReachable] mirrors whether the instrument's VNC server answered the
  // last probe; the Live toggle is only offered while it does. When a live
  // session fails, [_vncCrashed] keeps the toggle visible but disabled until
  // a later probe succeeds again.
  bool _vncReachable = false;
  bool _vncCrashed = false;
  bool _vncLive = false;
  bool _vncProbing = false;
  bool _autoCaptureBeforeLive = false;
  DateTime _lastVncProbe = DateTime.fromMillisecondsSinceEpoch(0);
  VncScreenService? _vncService;
  ui.Image? _liveScreenImage;

  /// Incremented whenever a live session starts or ends, so a frame that is
  /// still being decoded cannot be applied to a newer session.
  int _vncSessionId = 0;

  /// Remembers that the live screen was active when the Control Panel was
  /// left, so it can be switched on again when the panel is shown again.
  bool _restoreLiveOnPanelReturn = false;
  WaveformData? _waveformCh1;
  WaveformData? _waveformCh2;
  WaveformData? _waveformCh3;
  WaveformData? _waveformCh4;

  /// Raw samples of the last acquisition, retained for the spectrum analysis
  /// and the PDF report. Invalidated by a new acquisition.
  WaveformRawData? _lastRawData;

  /// Spectrum settings (window, FFT size, unit, peaks). Persisted in the
  /// application preferences; the spectrum view edits them.
  SpectrumSettings _spectrumSettings = const SpectrumSettings();

  /// Cached spectrum of [_lastRawData]; invalidated on a new acquisition or
  /// when the settings change.
  SpectrumResult? _spectrumResult;

  /// Spectrum view state.
  _WaveformViewMode _waveformViewMode = _WaveformViewMode.time;

  /// The view mode actually shown; the Analysis tab falls back to the time
  /// view while the debug flag is off.
  _WaveformViewMode get _effectiveWaveformViewMode =>
      _waveformViewMode == _WaveformViewMode.analysis &&
          !_isWaveformAnalysisAvailable
      ? _WaveformViewMode.time
      : _waveformViewMode;

  /// The Analysis tab is a debug-only feature enabled by the `--debug` start
  /// flag.
  bool get _isWaveformAnalysisAvailable => widget.debugMode;
  String _spectrumChannel = 'ch1';
  bool _spectrumShowAll = true;
  bool _spectrumLogFrequency = false;
  bool _spectrumLoading = false;
  int _spectrumGeneration = 0;
  final GlobalKey _spectrumKey = GlobalKey();

  /// Last four acquisitions for the Waveform AI's history and comparison.
  final WaveformHistoryStore _waveformHistory = WaveformHistoryStore();

  /// Incremented after every successful acquisition so the AI acquisition
  /// tool can distinguish success from a handled failure.
  int _acquisitionGeneration = 0;

  /// Time-domain measurements of the last acquisition, computed from the raw
  /// samples before the display decimation.
  WaveformMeasurements? _measurementsCh1;
  WaveformMeasurements? _measurementsCh2;
  WaveformMeasurements? _measurementsCh3;
  WaveformMeasurements? _measurementsCh4;

  /// Bounded measurement history per channel, used for the statistics line
  /// in the measurement panel.
  static const int _measurementHistoryLimit = 20;
  final List<WaveformMeasurements> _measurementHistoryCh1 = [];
  final List<WaveformMeasurements> _measurementHistoryCh2 = [];
  final List<WaveformMeasurements> _measurementHistoryCh3 = [];
  final List<WaveformMeasurements> _measurementHistoryCh4 = [];

  /// Difference trace and deviation metrics against the loaded reference.
  bool _diffVisible = false;
  WaveformData? _diffTrace;
  ComparisonMetrics? _comparison;

  /// Software mask test state.
  MaskSettings _maskSettings = defaultMaskSettings;
  MaskBand? _maskBand;
  MaskResult? _maskResult;

  /// Timebase suggestion for a detected clock signal.
  ClockSuggestion? _clockSuggestion;
  bool _clockSuggestionDismissed = false;

  /// Cached geometry of the loaded reference, used by the mask slider ranges.
  double _referenceVppCache = 0;
  double _referenceDurationCache = 0;

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

  /// True while a profile is uploaded and applied on the instrument.
  bool _isProfileLoading = false;

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

  /// Output of `print()` statements from the most recent playback. The Macro
  /// Recorder panel listens to this and shows its print panel as soon as a
  /// message arrives.
  final MacroPrintController _macroPrintController = MacroPrintController();

  /// Owns the Macro Editor's AI conversation. It lives as long as the home
  /// page, so closing and reopening the editor keeps the chat open with its
  /// complete history.
  final MacroChatController _macroChatController = MacroChatController();

  /// Side-panel layout of the Macro Editor. It lives as long as the home page,
  /// so panel boundaries dragged by the user survive closing and reopening
  /// the editor.
  final MacroEditorLayout _macroEditorLayout = MacroEditorLayout();
  final ControlPanelChatController _controlPanelChatController =
      ControlPanelChatController();

  /// Active step-by-step debug session, if any.
  _MacroDebugSession? _macroDebugSession;

  /// Status text shown in the Macro Editor's debug bar.
  String? _macroDebugStatus;

  /// Guards against overlapping Step clicks while a session is being started.
  bool _macroDebugStepPending = false;

  /// Breakpoints set in the Macro Editor (1-based source lines).
  Set<int> _macroBreakpoints = <int>{};

  /// Breakpoints that are currently disabled. Disabled breakpoints stay
  /// visible in the gutter but do not pause the debugger.
  Set<int> _macroInactiveBreakpoints = <int>{};

  /// Source line of the statement currently highlighted in the editor.
  int? _macroDebugCurrentLine;

  /// Variables shown in the debug watch panel.
  Map<String, String> _macroDebugVariables = <String, String>{};

  // Macro playback
  Vxi11Instrument? _playbackInstrument;

  Timer? _refreshTimer;
  bool _refreshPending = false;
  static const int _refreshDelayMs = 1758;

  /// Extra settling time after Auto Setup before the screen is captured.
  /// The instrument runs a complete acquisition setup; a live measurement
  /// showed it stays busy for about 6.3 seconds before it serves the updated
  /// display.
  static const Duration _autoSetupExtraDelay = Duration(seconds: 5);

  /// Extra settling time for screen captures triggered by the Control Panel
  /// AI assistant. The instrument needs longer to render settings that were
  /// applied through the separate AI connection.
  static const Duration _controlPanelAiRefreshDelay = Duration(seconds: 2);

  Timer? _autoCaptureTimer;
  bool _autoCaptureEnabled = false;
  static const Duration _autoCaptureInterval = Duration(seconds: 4);

  /// Timelapse capture state. The session tracks the planned frames; the
  /// completer wakes the delay early when the user presses Stop.
  bool _timelapseRunning = false;
  TimelapseSession? _timelapseSession;
  Completer<void>? _timelapseStop;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _timelapseSnackBar;

  /// Minimum delay between two VNC reachability probes. The probe runs on the
  /// 5 s ping tick and only while the Control Panel is visible.
  static const Duration _vncProbeInterval = Duration(seconds: 10);

  /// Width of the Waveform AI panel; twice the 300 px Device Parameters panel.
  static const double _waveformAiPanelWidth = 600;

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
  final InputHistory _chatInputHistory = InputHistory();
  bool _isChatting = false;
  StreamSubscription<String>? _chatSubscription;
  Completer<void>? _chatSendCompleter;
  bool _chatCancelRequested = false;

  // Waveform AI assistant
  final WaveformChatController _waveformChatController =
      WaveformChatController();

  /// Classification and reference-comparison engine shared by the Analysis
  /// view and the Waveform AI tools.
  final WaveformAnalysisService _waveformAnalysisService =
      WaveformAnalysisService();
  final WaveformFaultProfileStore _waveformFaultProfileStore =
      const WaveformFaultProfileStore();
  bool _showWaveformAi = false;

  // Assistant voice input
  /// Owns the microphone and the whisper transcriber shared by the AI
  /// assistants. The microphone always starts switched off when an assistant
  /// opens.
  late final VoiceInputService _voiceInputService;

  /// Microphone binding of the main AI Chat panel.
  late final VoiceInputBinding _aiChatVoice;
  int _lastVoiceErrorCount = 0;

  // Data Logger
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
    _voiceInputService = VoiceInputService();
    _aiChatVoice = VoiceInputBinding(
      ownerId: 'ai_chat',
      service: _voiceInputService,
      onTranscript: _onChatSendMessage,
    );
    _macroChatController.attachDeviceCommandReference(
      _readDeviceCommandReferenceForAi,
    );
    _macroChatController.attachOscilloscopeStatus(_readOscilloscopeStatus);
    // The macro agent can inspect the same runtime output the editor shows:
    // the debug variables and the print() output of the current run.
    _macroChatController.attachMacroOutput(
      readVariables: () => _macroDebugVariables,
      readPrintOutput: () => _macroPrintController.messages,
    );
    _controlPanelChatController.attachOscilloscopeStatus(
      _readOscilloscopeStatus,
    );
    _controlPanelChatController.attachCommandListener(_onControlPanelAiCommand);
    _controlPanelChatController.attachWaveformSummary(_waveformSummaryForAi);
    _controlPanelChatController.attachScreenDumpRefresh(
      _refreshScreenDumpForAi,
    );
    _voiceInputService.status.addListener(_onVoiceStatusChanged);
    windowManager.addListener(this);
    windowManager.setPreventClose(true);
    HardwareKeyboard.instance.addHandler(_onGlobalKeyEvent);
    unawaited(_loadCalculatorShortcut());
    unawaited(_loadSignalGeneratorShortcut());
    // Drop the cached instrument when a fatal USB error invalidates the
    // shared connection, so a replug can reconnect without an app restart.
    Vxi11Instrument.onUsbConnectionLost = _onUsbConnectionLost;
    _initialize();
  }

  void _onVoiceStatusChanged() {
    final current = _voiceInputService.status.value;
    if (current.errorCount <= _lastVoiceErrorCount) return;
    _lastVoiceErrorCount = current.errorCount;
    _showErrorSnackBar(current.errorMessage ?? 'Voice input failed.');
  }

  /// Stops an assistant microphone when its chat panel is no longer visible.
  ///
  /// Most top-bar switches already stop the microphone directly, but the
  /// Control Panel and Acquire Waveform toolbar buttons replace the main view
  /// without going through `_togglePanel`. This check runs on every build and
  /// closes a session whose owning chat disappeared, regardless of the route
  /// that left the panel.
  void _scheduleVoiceInputVisibilityCheck() {
    final status = _voiceInputService.status.value;
    final owner = status.ownerId;
    if (!status.isActive || owner == null) return;
    if (_isVoiceOwnerVisible(owner)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _voiceInputService.status.value;
      if (!current.isActiveFor(owner)) return;
      if (_isVoiceOwnerVisible(owner)) return;
      unawaited(_voiceInputService.stop(ownerId: owner));
    });
  }

  /// Whether the chat that owns the microphone is still on screen.
  bool _isVoiceOwnerVisible(String owner) {
    return switch (owner) {
      'ai_chat' => _activePanel == ActivePanel.chat,
      'control_panel_ai' =>
        _activePanel == ActivePanel.none &&
            !_waveformAcquired &&
            _screenDump != null &&
            _controlPanelChatController.isOpen,
      'waveform_ai' =>
        _activePanel == ActivePanel.none &&
            _waveformAcquired &&
            _showWaveformAi &&
            _waveformChatController.isOpen,
      'macro_ai' =>
        _activePanel == ActivePanel.macroRecorder &&
            _showMacroEditor &&
            _macroChatController.isOpen,
      'help_ai' => _activePanel == ActivePanel.help,
      _ => true,
    };
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
    Vxi11Instrument.onUsbConnectionLost = null;
    HardwareKeyboard.instance.removeHandler(_onGlobalKeyEvent);
    // Cancel a paused/running debug session without calling setState during
    // dispose. Its run future closes the instrument and ignores the cleared
    // session.
    final debugSession = _macroDebugSession;
    _macroDebugSession = null;
    debugSession?.cancel();
    _disposeSigGenWindowSupport();
    _calculatorWindowLauncher?.dispose();
    _calculatorWindowLauncher = null;
    final server = _sigGenWindowServer;
    _sigGenWindowServer = null;
    if (server != null) unawaited(server.dispose());
    _pingTimer?.cancel();
    _refreshTimer?.cancel();
    _autoCaptureTimer?.cancel();
    _vncLive = false;
    _vncSessionId++;
    _vncService?.stop();
    _vncService = null;
    _liveScreenImage?.dispose();
    _liveScreenImage = null;
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
    _chatCancelRequested = true;
    final chatSubscription = _chatSubscription;
    _chatSubscription = null;
    if (chatSubscription != null) unawaited(chatSubscription.cancel());
    final chatCompleter = _chatSendCompleter;
    _chatSendCompleter = null;
    if (chatCompleter != null && !chatCompleter.isCompleted) {
      chatCompleter.complete();
    }
    _aiChatService.dispose();
    _macroChatController.dispose();
    _controlPanelChatController.dispose();
    _waveformChatController.dispose();
    _macroPrintController.dispose();
    _voiceInputService.status.removeListener(_onVoiceStatusChanged);
    unawaited(_voiceInputService.dispose());
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
    // Remember the window geometry for the next launch.
    await WindowStateStore.save();
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
    _scheduleVoiceInputVisibilityCheck();
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              _buildTopBar(),
              Expanded(
                child: Stack(
                  children: [
                    Row(
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
                            diffAvailable: _refWaveform != null,
                            diffVisible: _diffVisible,
                            onDiffToggled: _onDiffToggled,
                            comparison: _comparison,
                            onUseCurrentAsReference: _hasCurrentWaveform()
                                ? _useCurrentWaveformAsReference
                                : null,
                            onOpenAi: _toggleWaveformAi,
                          ),
                      ],
                    ),
                    if (_waveformAcquired && _activePanel == ActivePanel.none)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOutCubic,
                        top: 24,
                        bottom: 24,
                        width: _waveformAiPanelWidth,
                        right: _showWaveformAi
                            ? 24
                            : -_waveformAiPanelWidth - 24,
                        child: IgnorePointer(
                          ignoring: !_showWaveformAi,
                          child: WaveformAiPanel(
                            controller: _waveformChatController,
                            onClose: _closeWaveformAi,
                            voiceInput: _voiceInputService,
                          ),
                        ),
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
    if (_waveformAcquired) return _buildWaveformAnalysisView();
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
  // Signal generator window (configurable, default Ctrl+J)
  // =========================================================================

  /// Global shortcut: the configured combination opens or focuses the signal
  /// generator window.
  ///
  /// The shortcut is intentionally not exposed as a toolbar button.
  bool _onGlobalKeyEvent(KeyEvent event) {
    if (_handleCalculatorShortcut(event)) return true;
    return _handleSignalGeneratorShortcut(event);
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
    setState(() => _calculatorShortcut = shortcut);
  }

  /// Restores the configured signal generator shortcut from the preferences.
  Future<void> _loadSignalGeneratorShortcut() async {
    final stored = await AppPreferences.getString('signal_generator_shortcut');
    if (!mounted) return;
    final shortcut = SignalGeneratorShortcut.fromPreference(stored);
    if (shortcut.id == _signalGeneratorShortcut.id) return;
    setState(() => _signalGeneratorShortcut = shortcut);
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

  Widget _buildWaveformAnalysisView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _buildViewModeButton('Time domain', _WaveformViewMode.time),
              const SizedBox(width: 6),
              _buildViewModeButton('Spectrum', _WaveformViewMode.spectrum),
              if (_isWaveformAnalysisAvailable) ...[
                const SizedBox(width: 6),
                _buildViewModeButton('Analysis', _WaveformViewMode.analysis),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _effectiveWaveformViewMode == _WaveformViewMode.time
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: Center(child: _buildWaveformView())),
                      if (_clockSuggestion != null &&
                          !_clockSuggestionDismissed) ...[
                        const SizedBox(height: 8),
                        _buildClockSuggestionBanner(_clockSuggestion!),
                      ],
                      const SizedBox(height: 8),
                      WaveformMeasurementPanel(
                        measurements: _currentMeasurements(),
                        statistics: _measurementStatistics(),
                        deviceParams: _deviceParams,
                        historyCount: _measurementHistoryCount(),
                        maskAvailable: _refWaveform != null,
                        referenceVppVolts: _referenceVpp(),
                        referenceDurationSeconds: _referenceDurationSeconds(),
                        maskSettings: _maskSettings,
                        maskResult: _maskResult,
                        onMaskSettingsChanged: _onMaskSettingsChanged,
                        onRippleNoise: _showRippleNoiseDialog,
                      ),
                    ],
                  )
                : _effectiveWaveformViewMode == _WaveformViewMode.analysis
                ? WaveformAnalysisView(
                    channels: _acquiredWaveformChannels(),
                    service: _waveformAnalysisService,
                    captureGeneration: _acquisitionGeneration,
                  )
                : SpectrumView(
                    result: _spectrumResult,
                    settings: _spectrumSettings,
                    selectedChannel: _spectrumChannel,
                    showAllChannels: _spectrumShowAll,
                    logFrequency: _spectrumLogFrequency,
                    loading: _spectrumLoading,
                    onChannelSelectionChanged: (channel) => setState(() {
                      _spectrumShowAll = channel == null;
                      if (channel != null) _spectrumChannel = channel;
                    }),
                    onSettingsChanged: _onSpectrumSettingsChanged,
                    onLogFrequencyChanged: (value) =>
                        setState(() => _spectrumLogFrequency = value),
                    onExportCsv: _exportSpectrumCsv,
                    plotKey: _spectrumKey,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeButton(String label, _WaveformViewMode mode) {
    final selected = _effectiveWaveformViewMode == mode;
    return TextButton(
      onPressed: () => _setWaveformViewMode(mode),
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.white : Colors.white54,
        backgroundColor: selected
            ? const Color(0xFF1E3A8A)
            : const Color(0xFF172A45),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: selected ? Colors.blueAccent : AppColors.border,
            width: 0.8,
          ),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _setWaveformViewMode(_WaveformViewMode mode) {
    if (mode == _WaveformViewMode.analysis && !_isWaveformAnalysisAvailable) {
      return;
    }
    if (_effectiveWaveformViewMode == mode) return;
    setState(() => _waveformViewMode = mode);
    if (mode == _WaveformViewMode.spectrum &&
        _spectrumResult == null &&
        !_spectrumLoading) {
      unawaited(_recomputeSpectrum());
    }
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
                      diffTrace: _diffTrace,
                      diffVisible: _diffVisible,
                      maskBand: _maskBand,
                      maskVisible: _maskSettings.enabled,
                      maskViolations: _maskResult?.violationPoints ?? const [],
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
      onNavigationButtonPressed: _handleButtonPress,
      onHorizontalButtonPressed: _handleButtonPress,
      onTriggerButtonPressed: _handleButtonPress,
      autoCaptureEnabled: _autoCaptureEnabled,
      onAutoCaptureChanged: _setAutoCaptureEnabled,
      showLiveButton: _showLiveButton,
      liveEnabled: _vncLive,
      liveAvailable: _vncReachable,
      onLiveChanged: _setVncLiveEnabled,
      liveScreen: _liveScreenImage,
      aiSettings: _aiSettings,
      chatController: _controlPanelChatController,
      vxi11Host: _ipAddress,
      instrumentDeviceContext: _sdsDeviceContext,
      voiceInput: _voiceInputService,
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
            "Version 0.3.0",
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
          IconButton(
            icon: _timelapseRunning
                ? const AnimatedSyncIcon(size: 20, color: Colors.cyanAccent)
                : const Icon(Icons.timelapse, size: 25),
            // A running timelapse can always be stopped, even when the
            // device has gone offline in the meantime.
            color: (_isMacroPlaying || (!_isOnline && !_timelapseRunning))
                ? Colors.white24
                : Colors.white70,
            tooltip: _timelapseRunning
                ? 'Stop timelapse'
                : (_isOnline ? 'Timelapse' : 'Timelapse (device offline)'),
            onPressed: _isMacroPlaying
                ? null
                : (_timelapseRunning
                      ? _stopTimelapse
                      : (_isOnline ? _showTimelapseDialog : null)),
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
    return HelpWindow(aiSettings: _aiSettings, voiceInput: _voiceInputService);
  }

  Widget _buildChatWindow() {
    return ChatWindow(
      chatMessages: _chatMessages,
      isChatting: _isChatting,
      isInitialized: _aiChatService.isInitialized,
      onSendMessage: _onChatSendMessage,
      onCancel: _cancelChat,
      voiceInput: _aiChatVoice,
      inputHistory: _chatInputHistory.entries,
      onHistorySelected: _onChatSendMessage,
    );
  }

  Future<void> _onChatSendMessage(String text) async {
    if (_isChatting) return;
    _chatInputHistory.record(text);
    setState(() {
      _chatMessages.add({'role': 'user', 'content': text});
      _isChatting = true;
      _chatCancelRequested = false;
      // Add a placeholder for the AI response
      _chatMessages.add({'role': 'ai', 'content': ''});
    });

    final aiMsgIndex = _chatMessages.length - 1;
    final completer = Completer<void>();
    _chatSendCompleter = completer;
    var hasReceivedChunk = false;
    var hasError = false;

    final subscription = _aiChatService
        .sendMessageStream(text: text)
        .listen(
          (chunk) {
            if (!mounted || _chatCancelRequested) return;
            hasReceivedChunk = true;
            setState(() {
              _chatMessages[aiMsgIndex]['content'] =
                  (_chatMessages[aiMsgIndex]['content'] ?? '') + chunk;
            });
          },
          onError: (Object e) {
            if (!mounted || _chatCancelRequested) {
              if (!completer.isCompleted) completer.complete();
              return;
            }
            hasError = true;
            setState(() {
              _chatMessages[aiMsgIndex]['content'] =
                  'Error: Failed to connect to AI server ($e)';
            });
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );
    _chatSubscription = subscription;

    await completer.future;

    if (_chatSubscription == subscription) _chatSubscription = null;
    if (_chatSendCompleter == completer) _chatSendCompleter = null;

    if (!mounted || _chatCancelRequested) return;

    if (!hasReceivedChunk && !hasError) {
      setState(() {
        _chatMessages[aiMsgIndex]['content'] = 'No response from AI-Server';
      });
    }
    setState(() {
      _isChatting = false;
    });
  }

  /// Stops the active main-chat response immediately.
  Future<void> _cancelChat() async {
    if (!_isChatting) return;

    _chatCancelRequested = true;
    final subscription = _chatSubscription;
    _chatSubscription = null;

    if (mounted &&
        _chatMessages.isNotEmpty &&
        _chatMessages.last['role'] == 'ai') {
      setState(() {
        _chatMessages.last['content'] = 'terminated by user';
      });
    }

    final completer = _chatSendCompleter;
    _chatSendCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    if (mounted) {
      setState(() {
        _isChatting = false;
      });
    }

    await subscription?.cancel();
  }

  Widget _buildProfilesWindow() {
    return ProfilesPanel(
      profileFiles: _profileFiles,
      isOnline: _isOnline,
      isLoading: _isProfileLoading,
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

  /// Whether the Macro Editor (rather than the recorder file list) was the
  /// view shown when the macro panel was last left. Reopening the panel
  /// restores exactly that view.
  bool _lastMacroPanelWasEditor = false;

  Widget _buildMacroRecorderWindow() {
    if (_showMacroEditor) {
      return MacroEditorPanel(
        initialContent: _currentMacroContent,
        loadedFileName: _loadedMacroFileName,
        isModified: _isMacroModified,
        aiSettings: _aiSettings,
        chatController: _macroChatController,
        voiceInput: _voiceInputService,
        layout: _macroEditorLayout,
        isPlaying: _isMacroPlaying,
        hasDebugSession: _macroDebugSession != null,
        isDebugPaused: _macroDebugSession?.paused ?? false,
        isDebugRunning:
            _macroDebugSession != null &&
            !(_macroDebugSession?.paused ?? false),
        debugStatus: _macroDebugStatus,
        debugCurrentLine: _macroDebugCurrentLine,
        debugVariables: _macroDebugVariables,
        printController: _macroPrintController,
        breakpoints: _macroBreakpoints,
        inactiveBreakpoints: _macroInactiveBreakpoints,
        onBreakpointsChanged: (breakpoints) {
          setState(() {
            final added = breakpoints.difference(_macroBreakpoints);
            _macroBreakpoints = breakpoints;
            // A newly created breakpoint is always active; removed lines no
            // longer belong to the inactive set.
            _macroInactiveBreakpoints.removeAll(added);
            _macroInactiveBreakpoints.removeWhere(
              (line) => !breakpoints.contains(line),
            );
          });
        },
        onDeleteBreakpoint: (line) {
          setState(() {
            _macroBreakpoints.remove(line);
            _macroInactiveBreakpoints.remove(line);
          });
        },
        onSetBreakpointEnabled: (line, enabled) {
          setState(() {
            if (enabled) {
              _macroInactiveBreakpoints.remove(line);
            } else {
              _macroInactiveBreakpoints.add(line);
            }
          });
        },
        onSetAllBreakpointsEnabled: (enabled) {
          setState(() {
            if (enabled) {
              _macroInactiveBreakpoints.clear();
            } else {
              _macroInactiveBreakpoints = Set<int>.of(_macroBreakpoints);
            }
          });
        },
        onDeleteAllBreakpoints: () {
          setState(() {
            _macroBreakpoints.clear();
            _macroInactiveBreakpoints.clear();
          });
        },
        onPlay: _onMacroEditorPlay,
        onStep: _onMacroEditorStep,
        onContinue: _onMacroEditorContinue,
        onStop: _onMacroStop,
        errorMessage: _macroHadPlaybackError ? _macroStatusMessage : null,
        onContentChanged: (content) {
          _currentMacroContent = content;
          // Editing invalidates a paused debug session because its AST no
          // longer matches the editor content.
          if (_macroDebugSession != null) {
            unawaited(_stopMacroDebugSession(status: 'Stopped (macro edited)'));
          }
          // Line numbers and variable values are stale after an edit.
          final hadDebugState =
              _macroDebugCurrentLine != null || _macroDebugVariables.isNotEmpty;
          _macroDebugCurrentLine = null;
          _macroDebugVariables = <String, String>{};
          if (hadDebugState) setState(() {});
          // When a loaded file is edited, enable the Save button.
          if (_loadedMacroFileName != null && !_isMacroModified) {
            setState(() => _isMacroModified = true);
          }
        },
        onSave: _currentMacroContent.trim().isNotEmpty ? _onMacroSave : null,
        onClose: () {
          unawaited(_stopMacroDebugSession());
          setState(() {
            _showMacroEditor = false;
          });
        },
      );
    }

    return MacroRecorderPanel(
      macroFiles: _macroFiles,
      isRecording: _isMacroRecording,
      isPlaying: _isMacroPlaying,
      // Saving is a local file operation; content alone decides whether the
      // button is available, not the device connection.
      isSaveEnabled: _currentMacroContent.trim().isNotEmpty,
      hasContent: _currentMacroContent.trim().isNotEmpty,
      macroStatus: _macroStatus,
      macroStatusMessage: _macroStatusMessage,
      printController: _macroPrintController,
      loadedFileName: _loadedMacroFileName,
      isModified: _isMacroModified,
      onRecord: _onMacroStart,
      onNewFromTemplate: _showMacroTemplatePicker,
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
      AppLogger().error('Error loading macro files: $e');
    }
  }

  void _onMacroStart() {
    unawaited(_stopMacroDebugSession());
    _macroDebugStatus = null;
    _macroBreakpoints = <int>{};
    _macroInactiveBreakpoints = <int>{};
    _macroDebugCurrentLine = null;
    _macroDebugVariables = <String, String>{};
    _macroPrintController.clear();
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
          _currentMacroContent += 'cmd("$command")\n';
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
    unawaited(_stopMacroDebugSession());
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
    // A new playback starts with an empty print panel.
    _macroPrintController.clear();
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
      delay: (duration) => Future.delayed(duration),
      onPrint: _macroPrintController.add,
      siggenConnector: _connectMacroSignalGenerator,
    );

    final success = await evaluator.evaluateSource(source);

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

    // Clean up the dedicated macro playback connections (oscilloscope and
    // signal generator).
    await evaluator.close();
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

  /// Opens the signal generator configured in the settings for a macro's
  /// `connect(SIG, usb)` statement.
  ///
  /// The application's service is reused when available so macro playback and
  /// the signal generator window never open the same serial port twice.
  Future<MacroSiggenSession> _connectMacroSignalGenerator() =>
      AppMacroSiggenConnector(service: _sigGenService).connect();

  /// Reports the oscilloscope connection and detected model to the AI agents'
  /// `read_oscilloscope_status` tools.
  ///
  /// The values come from the same state used by the connection monitor and
  /// the window title, so no additional `*IDN?` query is sent.
  Future<Map<String, dynamic>> _readOscilloscopeStatus() async =>
      readMacroOscilloscopeStatus(
        connected: _isOnline,
        model: _deviceModel,
        name: _deviceName,
        channels: _numChannels,
        isUsb: _isUsb,
        ipAddress: _ipAddress,
      );

  /// Refreshes the screen dump shown next to the Control Panel chat after the
  /// AI assistant changed a setting on the oscilloscope.
  ///
  /// Write commands are passed through the existing debounce with extra
  /// settling time, so the instrument has rendered the new setting before the
  /// capture is taken. Several commands in one agent turn restart the timer,
  /// resulting in a single capture after the last change.
  void _onControlPanelAiCommand(String command, String operation) {
    if (operation != 'write') return;
    _scheduleRefresh(extraDelay: _controlPanelAiRefreshDelay, reschedule: true);
  }

  /// Fetches a fresh Control Panel screen dump for a short capture command
  /// such as "snapshot" or "Aufnahme" in the Control Panel AI assistant.
  Future<Map<String, dynamic>> _refreshScreenDumpForAi() async {
    if (!mounted) {
      return {'error': 'The application window is not available.'};
    }
    if (!_isOnline) {
      return {'error': 'The oscilloscope is offline.'};
    }
    if (_isAcquiring || _isAcquiringWaveform || _timelapseRunning) {
      return {'error': 'The oscilloscope is busy.'};
    }
    await _acquireScreenDump(keepPanels: true);
    if (!mounted || !_isOnline || _screenDump == null) {
      return {
        'error':
            'The screen dump could not be read. Check the connection and the '
            'application log.',
      };
    }
    return {'success': true};
  }

  /// Shows an error snackbar and logs the error.
  /// Also sets [_macroHadPlaybackError] if called during active playback.
  void _showMacroError(String message) {
    if (_isMacroPlaying || _macroDebugSession != null) {
      _macroHadPlaybackError = true;
      _macroStatus = 0; // show error icon immediately
    }
    _macroStatusMessage = message;
    if (_macroDebugSession != null) {
      _macroDebugStatus = 'Error';
    }
    AppLogger().error('Macro error: $message');
    if (mounted) {
      setState(() {});
      _showErrorSnackBar(message);
    }
  }

  // ── Step-by-step debugger ─────────────────────────────────────────────

  /// Starts a paused debug session for the current editor content.
  ///
  /// Returns the session once it is paused before its first executable
  /// statement, or null when the macro is empty, failed to parse, or contains
  /// no statements to execute.
  Future<_MacroDebugSession?> _startMacroDebugSession() async {
    final source = _currentMacroContent;
    if (source.trim().isEmpty) {
      _showMacroError('Macro is empty');
      return null;
    }

    await _stopMacroDebugSession(status: 'Stopped');

    _macroHadPlaybackError = false;
    _macroStatus = null;
    _macroStatusMessage = null;
    _macroDebugCurrentLine = null;
    _macroDebugVariables = <String, String>{};
    _macroPrintController.clear();
    _macroDebugStatus = 'Preparing…';
    if (mounted) setState(() {});

    late final _MacroDebugSession session;
    final evaluator = MacroEvaluator(
      onError: _showMacroError,
      isCancelled: () => session.cancelled,
      delay: (duration) => Future.any([
        Future<void>.delayed(duration),
        session.cancelSignal.future,
      ]),
      onPrint: _macroPrintController.add,
      onBeforeStatement: (statement) =>
          _onDebugBeforeStatement(session, statement),
      siggenConnector: _connectMacroSignalGenerator,
    );
    session = _MacroDebugSession(evaluator);

    final program = evaluator.parseSource(source);
    if (program == null) {
      _macroHadPlaybackError = true;
      _macroStatus = 0;
      _macroDebugStatus = 'Error (parse)';
      if (mounted) setState(() {});
      return null;
    }

    _macroDebugSession = session;
    session.runFuture = _runMacroDebugSession(session, program);

    // Wait until the evaluator pauses before the first statement. A macro
    // without executable statements finishes immediately and marks the
    // session as finished instead.
    await session.armed.future;
    if (session.finished || session.cancelled) {
      if (identical(_macroDebugSession, session)) {
        _macroDebugSession = null;
      }
      if (session.finished && !session.cancelled) {
        _macroDebugStatus = 'Finished';
      }
      if (mounted) setState(() {});
      return null;
    }
    return session;
  }

  Future<void> _runMacroDebugSession(
    _MacroDebugSession session,
    Program program,
  ) async {
    try {
      final success = await session.evaluator.evaluate(program);
      if (!session.cancelled) {
        _macroDebugStatus = _macroHadPlaybackError
            ? 'Error'
            : success
            ? 'Finished'
            : 'Stopped';
      }
    } finally {
      final isCurrentSession = identical(_macroDebugSession, session);
      session.finished = true;
      session.markArmed();
      if (isCurrentSession) {
        // Capture values assigned by the last statement, which has no
        // following gate to read them.
        session.variables = session.evaluator.variables;
        _macroDebugVariables = session.variables;
      }
      try {
        await session.evaluator.close();
      } catch (_) {}
      if (isCurrentSession) {
        _macroDebugSession = null;
      }
      if (mounted) setState(() {});
    }
  }

  /// Gate called by the evaluator before each non-comment statement.
  Future<void> _onDebugBeforeStatement(
    _MacroDebugSession session,
    Statement statement,
  ) async {
    if (session.cancelled) return;

    session.step++;
    session.statement = describeMacroStatement(statement);
    session.currentLine = session.evaluator.lineForStatement(statement);
    session.variables = session.evaluator.variables;
    _macroDebugCurrentLine = session.currentLine;
    _macroDebugVariables = session.variables;

    final line = session.currentLine;
    final hitBreakpoint = isMacroBreakpointActive(
      line: line,
      breakpoints: _macroBreakpoints,
      inactiveBreakpoints: _macroInactiveBreakpoints,
    );

    // Continue mode: skip statements until the next breakpoint. The current
    // line is still updated so the editor highlights what is executing.
    if (session.runToBreakpoint && !hitBreakpoint) {
      _macroDebugStatus =
          !hasActiveMacroBreakpoint(
            breakpoints: _macroBreakpoints,
            inactiveBreakpoints: _macroInactiveBreakpoints,
          )
          ? 'Running to end…'
          : line == null
          ? 'Running…'
          : 'Running to breakpoint · line $line';
      if (mounted && identical(_macroDebugSession, session)) {
        setState(() {});
      }
      return;
    }
    session.runToBreakpoint = false;

    session.paused = true;
    final gate = Completer<void>();
    session.gate = gate;
    session.markArmed();
    final prefix = hitBreakpoint ? 'Paused at breakpoint' : 'Paused';
    _macroDebugStatus = '$prefix · Step ${session.step}: ${session.statement}';
    if (mounted && identical(_macroDebugSession, session)) {
      setState(() {});
    }

    await gate.future;

    session.gate = null;
    session.paused = false;
    if (session.cancelled) return;
    _macroDebugStatus = 'Running step ${session.step}…';
    if (mounted && identical(_macroDebugSession, session)) {
      setState(() {});
    }
  }

  void _onMacroEditorStep() {
    unawaited(_stepMacroDebugSession());
  }

  Future<void> _stepMacroDebugSession() async {
    if (_macroDebugStepPending || _isMacroPlaying) return;
    _macroDebugStepPending = true;

    try {
      var session = _macroDebugSession;
      if (session == null) {
        session = await _startMacroDebugSession();
        if (session == null || !mounted) return;
      }

      final gate = session.gate;
      if (gate == null || gate.isCompleted) return;

      _macroDebugStatus = 'Running step ${session.step}…';
      if (mounted) setState(() {});
      gate.complete();
    } finally {
      _macroDebugStepPending = false;
    }
  }

  void _onMacroEditorContinue() {
    final session = _macroDebugSession;
    if (session == null || !session.paused) return;

    final gate = session.gate;
    if (gate == null || gate.isCompleted) return;

    session.runToBreakpoint = true;
    _macroDebugStatus = 'Continuing…';
    if (mounted) setState(() {});
    gate.complete();
  }

  void _onMacroEditorPlay() {
    unawaited(_runMacroDebugFromEditor());
  }

  /// Starts a fresh debug run from the beginning and lets it execute until
  /// the first breakpoint (or the end). Continue resumes a paused session;
  /// Play always restarts.
  Future<void> _runMacroDebugFromEditor() async {
    if (_macroDebugStepPending || _isMacroPlaying) return;
    _macroDebugStepPending = true;

    try {
      // Starting a session stops any previous paused run.
      final session = await _startMacroDebugSession();
      if (session == null || !mounted) return;

      // The first gate is paused before statement 1. If it sits on an active
      // breakpoint, stop there instead of executing it.
      final line = session.currentLine;
      if (isMacroBreakpointActive(
        line: line,
        breakpoints: _macroBreakpoints,
        inactiveBreakpoints: _macroInactiveBreakpoints,
      )) {
        _macroDebugStatus =
            'Paused at breakpoint · Step ${session.step}: '
            '${session.statement}';
        if (mounted) setState(() {});
        return;
      }

      final gate = session.gate;
      if (gate == null || gate.isCompleted) return;

      session.runToBreakpoint = true;
      _macroDebugStatus = 'Running…';
      if (mounted) setState(() {});
      gate.complete();
    } finally {
      _macroDebugStepPending = false;
    }
  }

  /// Cancels a running debug session and closes its instrument connection.
  Future<void> _stopMacroDebugSession({String status = 'Stopped'}) async {
    final session = _macroDebugSession;
    if (session == null) return;

    session.cancel();
    _macroDebugStatus = status;
    if (mounted) setState(() {});

    final runFuture = session.runFuture;
    if (runFuture != null) {
      // Do not block forever on an in-flight device operation. The run's
      // finally closes the instrument and clears the session.
      await runFuture.timeout(const Duration(seconds: 2), onTimeout: () {});
    }

    if (identical(_macroDebugSession, session)) {
      _macroDebugSession = null;
    }
    if (mounted) setState(() {});
  }

  void _onMacroPlay() {
    AppLogger().log('Macro play requested');
    _macroDebugStatus = null;
    _macroDebugCurrentLine = null;
    _macroDebugVariables = <String, String>{};
    setState(() => _macroStatus = null);
    _macroPlaybackCancelled = false;
    setState(() => _isMacroPlaying = true);
    _playMacro().whenComplete(() {
      if (mounted) setState(() => _isMacroPlaying = false);
    });
  }

  void _onMacroEdit() {
    _macroDebugStatus = null;
    _macroDebugCurrentLine = null;
    _macroDebugVariables = <String, String>{};
    setState(() {
      _macroStatus = null;
      _macroStatusMessage = null;
      _macroHadPlaybackError = false;
      _showMacroEditor = true;
    });
  }

  /// Opens the template picker and loads the selected template into the editor.
  Future<void> _showMacroTemplatePicker() async {
    final template = await showDialog<MacroTemplate>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('New macro from template'),
        children: [
          for (final template in macroTemplates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, template),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(template.name),
                subtitle: Text(template.description),
              ),
            ),
        ],
      ),
    );
    if (template == null || !mounted) return;
    setState(() {
      _currentMacroContent = template.content;
      _loadedMacroFileName = null;
      _isMacroModified = true;
      _showMacroEditor = true;
      _macroStatus = null;
      _macroStatusMessage = null;
      _macroHadPlaybackError = false;
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
        AppLogger().error('Save macro error: $e');
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
      AppLogger().error('Save macro error: $e');
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
      unawaited(_stopMacroDebugSession());
      _macroDebugStatus = null;
      _macroBreakpoints = <int>{};
      _macroInactiveBreakpoints = <int>{};
      _macroDebugCurrentLine = null;
      _macroDebugVariables = <String, String>{};
      _macroPrintController.clear();
      setState(() {
        _macroStatus = null;
        _currentMacroContent = content;
        _loadedMacroFileName = fileName;
        _isMacroModified = false;
        // Loading from the file list keeps the recorder view; the editor
        // opens only when the user presses Edit.
      });
    } catch (e) {
      AppLogger().error('Load macro error: $e');
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
      AppLogger().error('Delete macro error: $e');
    }
  }

  /// Builds the rotating arrows icon for the Data Logger toolbar button.
  Widget _buildDlButtonIcon() {
    return AnimatedSyncIcon(
      size: 25,
      color: _dlIsRunning ? Colors.greenAccent : Colors.white,
      animate: _dlIsRunning,
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
      channelCount: _numChannels,
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
        _dlIsRunning = running;
        if (mounted) setState(() {});
      },
      onClose: () {
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
      _dlIsRunning = false;
      _dlService?.stop();
    }
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
      AppLogger().error('Error loading profile files: $e');
    }
  }

  Future<void> _saveProfile(String name) async {
    final sw = Stopwatch()..start();
    try {
      final instr = await _getInstrument();
      if (instr == null) throw Exception('Device not connected');

      // Send PNSU? to get XML settings.
      // The instrument returns data with an IEEE 488.2 definite-length block
      // header (e.g. "PNSU #9000047692<?xml..."). Decode with lenient UTF-8
      // handling to tolerate any non-UTF-8 bytes in the raw response.
      // The instrument needs ~14 s to build the setup block before it sends
      // the first byte; a 15 s timeout left no margin.
      final data = await instr.readRawResponse(
        'PNSU?',
        timeout: const Duration(seconds: 30),
      );
      final content = utf8.decode(data, allowMalformed: true);

      final dir = await AppPaths.getOrCreateProfilesDir();
      final file = File('${dir.path}/$name.lss');
      await file.writeAsString(content);

      _loadProfileFiles();
      AppLogger().log(
        'Profile "$name" saved successfully (${sw.elapsedMilliseconds} ms).',
      );
      _showInfoSnackBar('Profile "$name" saved.');
    } catch (e) {
      AppLogger().error('Save profile error: $e');
      AppLogger().error('Popup: Save profile failed: $e');
      _showErrorSnackBar('Save profile failed: $e');
    }
  }

  /// Uploads [fileName] to the instrument and marks the panel as busy.
  Future<void> _loadProfile(String fileName) async {
    if (_isProfileLoading) return;
    setState(() => _isProfileLoading = true);
    try {
      await _loadProfileInner(fileName);
    } finally {
      if (mounted) {
        setState(() => _isProfileLoading = false);
      }
    }
  }

  Future<void> _loadProfileInner(String fileName) async {
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

      // Send the XML string via writeProfileData. Over USB, Linux splits it
      // into 64-byte transfers while Windows uses a single bulk transfer
      // that WinUSB segments itself.  For VXI-11 mode this delegates to
      // writeString.
      AppLogger().log(
        'LoadProfile: sending ${xml.length} bytes via writeProfileData '
        '(timeout: 15s, isUsb: $_isUsb)',
      );
      await instr.writeProfileData(xml, timeout: const Duration(seconds: 15));
      // The scope stops answering while it applies the profile. Over VXI-11
      // *OPC? reports completion; over USB the instrument resets its USB
      // interface and is reconnected once it is back on the bus.
      await instr.awaitProfileApplied();

      AppLogger().log('Profile "$fileName" loaded successfully.');
      _showInfoSnackBar('Profile "$fileName" loaded.');
      // Refresh screen dump after loading profile
      _scheduleRefresh();
    } catch (e) {
      AppLogger().error('Load profile error: $e');
      AppLogger().error('Popup: Load profile failed: $e');
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
      AppLogger().error('Delete profile error: $e');
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
      signalGeneratorShortcut: _signalGeneratorShortcut.id,
      onSignalGeneratorShortcutChanged: (value) async {
        final shortcut = SignalGeneratorShortcut.byId(value);
        if (shortcut.id == _signalGeneratorShortcut.id) return;
        setState(() => _signalGeneratorShortcut = shortcut);
        await AppPreferences.setString(
          'signal_generator_shortcut',
          shortcut.id,
        );
      },
      calculatorShortcut: _calculatorShortcut.id,
      onCalculatorShortcutChanged: (value) async {
        final shortcut = CalculatorShortcut.byId(value);
        if (shortcut.id == _calculatorShortcut.id) return;
        setState(() => _calculatorShortcut = shortcut);
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

  /// Called by [Vxi11Instrument] when a fatal USB transfer error invalidated
  /// the shared connection (IO_ERROR, PIPE, NO_DEVICE).
  ///
  /// Drops the cached instrument synchronously, so the next operation opens a
  /// fresh device, and marks the UI offline. Once the device is reachable
  /// again, the ping timer reopens it — replugging is enough, no app restart.
  void _onUsbConnectionLost() {
    if (!_isUsb) {
      // A USB operation from a previous connection mode is still unwinding;
      // do not disturb the current (network) instrument.
      return;
    }
    AppLogger().warning('USB connection lost; dropping cached instrument');
    // _closeInstrument() clears _instrument before its first await, so no
    // follow-up operation can reuse the dead instrument.
    unawaited(_closeInstrument());
    _markUsbDeviceOffline();
  }

  /// Marks the device offline and clears the cached identity after a USB
  /// disconnect or a fatal transfer error.
  void _markUsbDeviceOffline() {
    if (!mounted) return;
    setState(() {
      _isOnline = false;
      _deviceName = null;
      _deviceModel = null;
      _numChannels = 2;
    });
    _setFallbackWindowTitle();
    _restoreLiveOnPanelReturn = false;
    _stopVncLive(fetchScreen: false, restoreAutoCapture: false);
    _clearVncAvailability();
  }

  Future<void> _pingDevice() async {
    if (_isPinging || _isAcquiring || _isAcquiringWaveform || _bodeIsRunning) {
      return;
    }
    _isPinging = true;

    try {
      if (_isUsb) {
        final address = await Vxi11Instrument.detectLiveVisaAddress();
        if (address == null) {
          // The oscilloscope disappeared from the bus. Invalidate the shared
          // handle and drop the cached instrument so a replug opens a fresh
          // connection instead of retrying a dead one.
          if (_instrument != null || Vxi11Instrument.hasSharedUsbConnection) {
            await Vxi11Instrument.invalidateUsbConnection();
          }
          _markUsbDeviceOffline();
          return;
        }

        if (mounted) {
          setState(() => _isOnline = true);
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
          unawaited(_refreshVncAvailability());
        }
      }
    } catch (e) {
      if (_isUsb) {
        // Clear the cached identity so the next successful ping re-queries
        // *IDN? after the device becomes reachable again.
        _markUsbDeviceOffline();
      } else if (mounted) {
        setState(() => _isOnline = false);
        _setFallbackWindowTitle();
        _restoreLiveOnPanelReturn = false;
        _stopVncLive(fetchScreen: false, restoreAutoCapture: false);
        _clearVncAvailability();
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
    _sdsDeviceContext = _sdsDeviceContext?.withInstrumentModel(null);
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
        AppLogger().warning('CHS? query failed, using model number: $e');
      }
      if (mounted) {
        setState(() {
          _deviceName = name;
          _deviceModel = model;
          _sdsDeviceContext = _sdsDeviceContext?.withInstrumentModel(model);
          _numChannels = chsChannels ?? channelCountForModel(model);
          if (_selectedChannel > _numChannels) _selectedChannel = 1;
        });
        windowManager.setTitle(name);
        // Tell the AI which oscilloscope it is answering for. The agent is
        // configured before the first device response, so it learns the model
        // here rather than at construction time.
        _aiChatService.updateInstrumentModel(model);
        if (_numChannels < 4) {
          // A two-channel model has no live screen; drop a stale session and
          // never try to restore one.
          _restoreLiveOnPanelReturn = false;
          if (_vncLive) {
            _stopVncLive(fetchScreen: false, restoreAutoCapture: false);
          }
        }
        unawaited(_refreshVncAvailability(force: true));
      }
    } catch (_) {
      if (mounted) {
        _setFallbackWindowTitle();
      }
    }
  }

  // =========================================================================
  // Live screen (VNC)
  // =========================================================================

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
    if (!force && now.difference(_lastVncProbe) < _vncProbeInterval) return;
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
      setState(() {
        _vncReachable = false;
        _vncCrashed = true;
      });
    } else if (reachable && (!_vncReachable || _vncCrashed)) {
      setState(() {
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
      setState(() {
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
      setState(() {
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
        setState(() => _liveScreenImage = image);
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
    if (image != null) {
      // The panel may still paint the last frame until it rebuilds.
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
    }
    if (!wasLive) return;

    if (mounted) {
      setState(() {
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

  Future<void> _acquireScreenDump({bool keepPanels = false}) async {
    if (_isAcquiring || _isAcquiringWaveform || _timelapseRunning) return;

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
          _measurementsCh1 = null;
          _measurementsCh2 = null;
          _measurementsCh3 = null;
          _measurementsCh4 = null;
          _measurementHistoryCh1.clear();
          _measurementHistoryCh2.clear();
          _measurementHistoryCh3.clear();
          _measurementHistoryCh4.clear();
          _diffTrace = null;
          _comparison = null;
          _maskBand = null;
          _maskResult = null;
          _deviceParams = null;
          _isOnline = true;
          _waveformAcquired = false;
        });
        // Opening the Control Panel is the moment the Live toggle matters;
        // probe right away instead of waiting for the next ping tick, and
        // restore the live screen when it was active before.
        if (!keepPanels) {
          unawaited(_refreshVncAndRestoreLive());
        }
      }
    } catch (e) {
      if (mounted) {
        AppLogger().error('Acquire display error: $e');
        // If it's a connection error, close the instrument so we retry next time
        _closeInstrument();
      }
      setState(() {
        _isOnline = false;
      });
      _restoreLiveOnPanelReturn = false;
      _stopVncLive(fetchScreen: false, restoreAutoCapture: false);
      _clearVncAvailability();
    } finally {
      if (mounted) {
        setState(() {
          _isAcquiring = false;
        });
      }
    }
  }

  Future<void> _acquireWaveform() async {
    if (_timelapseRunning) return;
    // Stop the Data Logger immediately when switching away from it
    _stopDataLoggerIfRunning();
    _stopBodeIfRunning();
    _stopAutoCapture();
    _restoreLiveOnPanelReturn = false;
    _stopVncLive(fetchScreen: false, restoreAutoCapture: false);
    _clearVncAvailability();

    setState(() {
      _isAcquiringWaveform = true;
      _activePanel = ActivePanel.none;
      _previousPanel = ActivePanel.none;
      _clockSuggestion = null;
      // Clear the previous capture immediately: while the new acquisition is
      // in flight the chart and measurement cards must not keep showing the
      // old trace. The device parameters stay so the grid and axes remain.
      _waveformCh1 = null;
      _waveformCh2 = null;
      _waveformCh3 = null;
      _waveformCh4 = null;
      _measurementsCh1 = null;
      _measurementsCh2 = null;
      _measurementsCh3 = null;
      _measurementsCh4 = null;
      _lastRawData = null;
      _spectrumResult = null;
      _diffTrace = null;
      _comparison = null;
      _maskBand = null;
      _maskResult = null;
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
      // Measure the raw samples before the display decimation so rise/fall
      // times and overshoot keep the full acquisition resolution.
      final measurements = _measureRawChannels(raw);

      setState(() {
        _waveformCh1 = result.$1;
        _waveformCh2 = result.$2;
        _waveformCh3 = result.$3;
        _waveformCh4 = result.$4;
        _measurementsCh1 = measurements.$1;
        _measurementsCh2 = measurements.$2;
        _measurementsCh3 = measurements.$3;
        _measurementsCh4 = measurements.$4;
        _recordMeasurementHistory(measurements);
        _deviceParams = result.$5;
        _screenDump = null;
        _isOnline = true;
        _waveformAcquired = true;
        _lastRawData = raw;
        _spectrumResult = null;
        _acquisitionGeneration++;
        // Reset zoom state on every new acquisition so the user sees the full
        // waveform (14 divisions) instead of a zoomed-in view from a previous
        // interaction that showed only ~4 waves.
        _zoomState = const ZoomState();
        _updateClockSuggestion();
      });
      _logWaveformMeasurements();
      _recomputeReferenceAnalysis();
      _recordWaveformHistory();
      if (_effectiveWaveformViewMode == _WaveformViewMode.spectrum) {
        unawaited(_recomputeSpectrum());
      }
    } catch (e) {
      AppLogger().error('Acquire waveform error: $e');
      final reason = e is AcquisitionException ? e.reason : e.toString();
      AppLogger().error('Popup: Waveform error: $reason');
      _showErrorSnackBar('Waveform error: $reason');
    } finally {
      if (mounted) {
        setState(() {
          _isAcquiringWaveform = false;
        });
      }
    }
  }

  /// Measures every acquired raw channel before display decimation.
  ///
  /// Channels that were not acquired, or whose vertical settings are
  /// missing, yield `null`.
  (
    WaveformMeasurements?,
    WaveformMeasurements?,
    WaveformMeasurements?,
    WaveformMeasurements?,
  )
  _measureRawChannels(WaveformRawData raw) {
    /// Effective interval between the transferred samples of a channel.
    ///
    /// With WFSU sparsing the record contains only every `sparsing`-th
    /// acquisition sample, so the spacing is `sparsing / sampleRate`. This
    /// mirrors `WaveformConverter.computeTimeAxis` and avoids stretching a
    /// short sparsed record over the 14-division display window, which would
    /// scale every measured frequency down by the sparsing factor.
    double? sampleIntervalFor(int rawLength) {
      if (rawLength < 2) return null;
      return raw.effectiveSampleRate > 0 ? 1 / raw.effectiveSampleRate : null;
    }

    WaveformMeasurements? measure(
      String channel,
      Uint8List? data,
      double? vdiv,
      double? voffset,
    ) {
      if (data == null || vdiv == null || voffset == null || data.isEmpty) {
        return null;
      }
      return measureRawChannel(
        channel: channel,
        rawData: data,
        vdiv: vdiv,
        voffset: voffset,
        sampleRate: raw.effectiveSampleRate,
        sampleIntervalSeconds: sampleIntervalFor(data.length),
      );
    }

    return (
      measure('ch1', raw.ch1Raw, raw.vdivCh1, raw.voffsetCh1),
      measure('ch2', raw.ch2Raw, raw.vdivCh2, raw.voffsetCh2),
      measure('ch3', raw.ch3Raw, raw.vdivCh3, raw.voffsetCh3),
      measure('ch4', raw.ch4Raw, raw.vdivCh4, raw.voffsetCh4),
    );
  }

  /// Writes the latest waveform measurements to the debug log.
  ///
  /// The values are consumed by the measurement panel in the next phase; the
  /// debug entry keeps the computation observable in the meantime.
  void _logWaveformMeasurements() {
    for (final measurement in [
      _measurementsCh1,
      _measurementsCh2,
      _measurementsCh3,
      _measurementsCh4,
    ]) {
      if (measurement == null) continue;
      AppLogger().debug(
        'Measurements ${measurement.channel}: '
        'Vpp=${measurement.vPp}, '
        'frequency=${measurement.frequencyHz}, '
        'duty=${measurement.dutyPercent}, '
        'samples=${measurement.sampleCount}, '
        'notes=${measurement.notes}',
      );
    }
  }

  /// Appends the current measurements to the bounded per-channel history.
  void _recordMeasurementHistory(
    (
      WaveformMeasurements?,
      WaveformMeasurements?,
      WaveformMeasurements?,
      WaveformMeasurements?,
    )
    measurements,
  ) {
    void add(List<WaveformMeasurements> history, WaveformMeasurements? value) {
      if (value == null) return;
      history.add(value);
      if (history.length > _measurementHistoryLimit) {
        history.removeAt(0);
      }
    }

    add(_measurementHistoryCh1, measurements.$1);
    add(_measurementHistoryCh2, measurements.$2);
    add(_measurementHistoryCh3, measurements.$3);
    add(_measurementHistoryCh4, measurements.$4);
  }

  /// Measurements of the channels currently enabled for display.
  Map<String, WaveformMeasurements> _currentMeasurements() {
    final measurements = <String, WaveformMeasurements>{};
    void add(String channel, bool enabled, WaveformMeasurements? value) {
      if (enabled && value != null) measurements[channel] = value;
    }

    add('ch1', _ch1Enabled, _measurementsCh1);
    add('ch2', _ch2Enabled, _measurementsCh2);
    add('ch3', _numChannels >= 4 && _ch3Enabled, _measurementsCh3);
    add('ch4', _numChannels >= 4 && _ch4Enabled, _measurementsCh4);
    return measurements;
  }

  /// All acquired measurements, regardless of the display channel toggles.
  Map<String, WaveformMeasurements> _acquiredMeasurements() => {
    'ch1': ?_measurementsCh1,
    'ch2': ?_measurementsCh2,
    'ch3': ?_measurementsCh3,
    'ch4': ?_measurementsCh4,
  };

  /// Computes (or returns the cached) spectrum of the last acquisition.
  ///
  /// The FFT runs in an isolate so a large record does not block the UI. The
  /// result feeds the PDF report and the spectrum view.
  Future<SpectrumResult?> _spectrumForReport() async {
    final cached = _spectrumResult;
    if (cached != null) return cached;
    final result = await _computeSpectrumNow();
    _spectrumResult = result;
    return result;
  }

  /// Recomputes the spectrum for the current acquisition and settings.
  Future<void> _recomputeSpectrum() async {
    final generation = ++_spectrumGeneration;
    if (_lastRawData == null) return;
    setState(() => _spectrumLoading = true);

    SpectrumResult? result;
    try {
      result = await _computeSpectrumNow();
    } catch (e) {
      AppLogger().error('Spectrum computation failed: $e');
      if (mounted) _showErrorSnackBar('Spectrum computation failed: $e');
    }

    if (!mounted || generation != _spectrumGeneration) return;
    setState(() {
      _spectrumResult = result;
      _spectrumLoading = false;
      if (result != null &&
          result.traceFor(_spectrumChannel) == null &&
          result.traces.isNotEmpty) {
        _spectrumChannel = result.traces.first.channel;
      }
    });
  }

  void _onSpectrumSettingsChanged(SpectrumSettings settings) {
    setState(() {
      _spectrumSettings = settings;
      _spectrumResult = null;
    });
    unawaited(_persistSpectrumSettings());
    if (_effectiveWaveformViewMode == _WaveformViewMode.spectrum) {
      unawaited(_recomputeSpectrum());
    }
  }

  Future<void> _persistSpectrumSettings() async {
    await AppPreferences.setAll(_spectrumPreferenceEntries());
  }

  /// Preference entries of the current spectrum settings.
  ///
  /// Shared by the immediate persistence of the spectrum controls and the
  /// configuration dialog so both always write the same keys.
  Map<String, dynamic> _spectrumPreferenceEntries() => {
    'spectrum_window': _spectrumSettings.window.name,
    'spectrum_unit': _spectrumSettings.unit.name,
    'spectrum_fft_size': _spectrumSettings.fftSize,
    'spectrum_max_fft_size': _spectrumSettings.maxFftSize,
    'spectrum_remove_dc': _spectrumSettings.removeDc,
    'spectrum_peak_count': _spectrumSettings.peakCount,
    'spectrum_harmonic_count': _spectrumSettings.harmonicCount,
    'spectrum_skip_samples': _spectrumSettings.leadingSamplesToSkip,
  };

  Future<SpectrumResult?> _computeSpectrumNow() async {
    final raw = _lastRawData;
    if (raw == null) return null;

    final channels = <SpectrumChannelInput>[];
    void addChannel(
      int number,
      Uint8List? bytes,
      double? vdiv,
      double? voffset,
    ) {
      if (bytes == null || bytes.isEmpty || vdiv == null || vdiv <= 0) return;
      channels.add(
        SpectrumChannelInput(
          label: 'ch$number',
          raw: bytes,
          vdiv: vdiv,
          voffset: voffset ?? 0,
        ),
      );
    }

    addChannel(1, raw.ch1Raw, raw.vdivCh1, raw.voffsetCh1);
    addChannel(2, raw.ch2Raw, raw.vdivCh2, raw.voffsetCh2);
    addChannel(3, raw.ch3Raw, raw.vdivCh3, raw.voffsetCh3);
    addChannel(4, raw.ch4Raw, raw.vdivCh4, raw.voffsetCh4);
    // The scope may sparse the transfer (WFSU SP); the stored raw bytes are
    // therefore sampled at the effective rate, not at the acquisition rate.
    final effectiveSampleRate = raw.effectiveSampleRate;
    if (channels.isEmpty || effectiveSampleRate <= 0) return null;

    final request = SpectrumRequest(
      channels: channels,
      sampleRate: effectiveSampleRate,
      settings: _spectrumSettings,
    );
    return compute(computeSpectrum, request);
  }

  /// Writes the spectrum of all acquired channels to a CSV file in
  /// `waveform/spectrum/`.
  Future<void> _exportSpectrumCsv() async {
    try {
      final prefix = await _askForFilenamePrefixIfNeeded();
      if (prefix == null) return; // user cancelled
      final result = await _spectrumForReport();
      if (result == null || result.traces.isEmpty) {
        _showInfoSnackBar('No spectrum data available.');
        return;
      }
      final directory = await AppPaths.getOrCreateWaveformSpectrumDir();
      final baseName = prefix.isNotEmpty ? prefix : 'spectrum_data';
      final file = await AppPaths.getUniqueFilePath(directory, baseName, 'csv');
      await writeSpectrumCsv(
        file: file,
        result: result,
        deviceName: _deviceName ?? _ipAddress,
      );
      if (mounted) {
        _showInfoSnackBar('Saved ${file.uri.pathSegments.last}');
      }
    } catch (e) {
      AppLogger().error('Spectrum CSV export failed: $e');
      _showErrorSnackBar('Spectrum CSV export failed: $e');
    }
  }

  /// Stores the current acquisition in the four-entry Waveform AI history.
  ///
  /// Manual and AI-triggered acquisitions both pass through
  /// [_acquireWaveform], so the history always reflects the last four captures.
  void _recordWaveformHistory() {
    final summary = _waveformSummaryForAi();
    if (summary == null) return;
    _waveformHistory.add(summary);
  }

  /// Last four acquisitions for the `read_waveform_history` tool.
  List<Map<String, dynamic>> _waveformHistoryForAi() =>
      _waveformHistory.entries;

  /// Runs a complete acquisition for the `acquire_waveform` tool.
  ///
  /// Returns a structured error instead of throwing so the agent can explain
  /// the failure. The acquisition itself updates the chart and measurements
  /// and appends to the history.
  Future<Map<String, dynamic>> _acquireWaveformForAi() async {
    if (_isAcquiringWaveform) {
      return {'error': 'A waveform acquisition is already running.'};
    }
    if (!_isOnline) {
      return {'error': 'The oscilloscope is offline.'};
    }
    final generation = _acquisitionGeneration;
    await _acquireWaveform();
    if (_acquisitionGeneration == generation) {
      return {
        'error':
            'The waveform acquisition failed. Check the connection and the '
            'application log.',
      };
    }
    final summary = _waveformSummaryForAi();
    if (summary == null) {
      return {
        'error': 'The acquisition completed but no measurements are available.',
      };
    }
    return {'acquired': true, 'measurements': summary};
  }

  /// Compact description of the displayed waveform for the Control Panel AI's
  /// `read_waveform_summary` tool.
  ///
  /// Returns null while no waveform is displayed so the tool can tell the user
  /// to acquire one first. The values are the already computed measurements;
  /// the assistant only explains them and never recalculates them.
  Map<String, dynamic>? _waveformSummaryForAi() {
    if (!_waveformAcquired) return null;
    final measurements = _currentMeasurements();
    if (measurements.isEmpty) return null;

    final params = _deviceParams;
    final comparison = _comparison;
    final mask = _maskResult;

    return <String, dynamic>{
      'displayed': true,
      'channels': {
        for (final entry in measurements.entries)
          entry.key: _measurementSummaryForAi(entry.value, params),
      },
      if (params != null)
        'device': {
          'timebaseSecondsPerDiv': params.timebase,
          'triggerDelaySeconds': params.trdl,
          'sampleRatePerSecond': params.sampleRate,
        },
      if (comparison != null)
        'referenceComparison': {
          'rmsErrorVolts': comparison.rmsErrorVolts,
          'maxAbsDeviationVolts': comparison.maxAbsDeviationVolts,
          'meanErrorVolts': comparison.meanErrorVolts,
          'coveragePercent': comparison.coveragePercent,
        },
      if (_maskSettings.enabled && mask != null)
        'mask': {
          'passed': mask.passed,
          'violations': mask.violations,
          'checkedPoints': mask.checkedPoints,
          'maxViolationVolts': mask.maxViolationVolts,
          'toleranceValue': _maskSettings.toleranceValue,
          'toleranceIsPercentOfVpp': _maskSettings.usePercent,
        },
    };
  }

  /// Spectrum analysis of the displayed waveform for the Waveform AI's
  /// `read_spectrum_summary` tool.
  ///
  /// The spectrum is computed on demand with the current settings, so the
  /// assistant sees the same data as the Spectrum tab even when it has not
  /// been opened yet. Returns null while no waveform is displayed.
  Future<Map<String, dynamic>?> _spectrumSummaryForAi() async {
    if (!_waveformAcquired || _lastRawData == null) return null;

    SpectrumResult? result;
    try {
      result = await _spectrumForReport();
    } catch (e) {
      AppLogger().warning('Spectrum summary for AI failed: $e');
      return null;
    }
    if (result == null) return null;

    final settings = result.settings;
    return <String, dynamic>{
      'available': true,
      'viewMode': _effectiveWaveformViewMode.name,
      'selectedChannel': _spectrumChannel,
      'showAllChannels': _spectrumShowAll,
      'settings': {
        'window': settings.window.name,
        'requestedFftSize': settings.fftSize == 0 ? 'auto' : settings.fftSize,
        'maxFftSize': settings.maxFftSize,
        'unit': settings.unit.name,
        'removeDc': settings.removeDc,
        'peakCount': settings.peakCount,
        'harmonicCount': settings.harmonicCount,
        'leadingSamplesSkipped': settings.leadingSamplesToSkip,
      },
      'channels': [
        for (final trace in result.traces)
          {
            'channel': trace.channel,
            'fftSize': trace.fftSize,
            'sampleRateHz': trace.sampleRate,
            'frequencyResolutionHz': trace.resolutionHz,
            'fullScaleVolts': trace.fullScaleVolts,
            'metrics': {
              'fundamentalFrequencyHz': _finiteOrNull(
                trace.metrics.fundamentalHz,
              ),
              'fundamentalAmplitudeVpk': _finiteOrNull(
                trace.metrics.fundamentalVpk,
              ),
              'fundamentalDbfs': _finiteOrNull(trace.metrics.fundamentalDbfs),
              'thdPercent': _finiteOrNull(trace.metrics.thdPercent),
              'thdDb': _finiteOrNull(trace.metrics.thdDb),
              'thdPlusNoiseDb': _finiteOrNull(trace.metrics.thdPlusNDb),
              'snrDb': _finiteOrNull(trace.metrics.snrDb),
              'sinadDb': _finiteOrNull(trace.metrics.sinadDb),
              'enobBits': _finiteOrNull(trace.metrics.enobBits),
              'sfdrDbc': _finiteOrNull(trace.metrics.sfdrDb),
              'noiseFloorDbfs': _finiteOrNull(trace.metrics.noiseFloorDbfs),
              'harmonicsUsed': trace.metrics.harmonicsUsed,
              'nyquistHz': _finiteOrNull(trace.metrics.nyquistHz),
              'resolutionHz': _finiteOrNull(trace.metrics.resolutionHz),
            },
            'peaks': [
              for (final peak in trace.peaks)
                {
                  'marker': peak.marker,
                  'frequencyHz': _finiteOrNull(peak.frequencyHz),
                  'amplitudeVpk': _finiteOrNull(peak.amplitudeVpk),
                  'levelDb': _finiteOrNull(peak.levelDb),
                  'dbfs': _finiteOrNull(peak.dbfs),
                  'relativeToFundamentalDb': _finiteOrNull(
                    peak.relativeToFundamentalDb,
                  ),
                  'isFundamental': peak.isFundamental,
                },
            ],
          },
      ],
    };
  }

  /// JSON-safe representation of a spectrum value.
  ///
  /// THD, SINAD, ENOB and similar metrics are infinite or NaN for signals
  /// without a usable carrier (for example pure noise), and JSON has no
  /// representation for those values.
  double? _finiteOrNull(double value) => value.isFinite ? value : null;

  /// Serializes one channel's measurements for [_waveformSummaryForAi].
  Map<String, dynamic> _measurementSummaryForAi(
    WaveformMeasurements measurement,
    DeviceParams? params,
  ) => {
    'verticalScaleVoltsPerDiv': params?.vdivFor(measurement.channel),
    'offsetVolts': params?.voffsetFor(measurement.channel),
    'vMaxVolts': measurement.vMax,
    'vMinVolts': measurement.vMin,
    'vppVolts': measurement.vPp,
    'meanVolts': measurement.vMean,
    'rmsVolts': measurement.vRms,
    'topVolts': measurement.vTop,
    'baseVolts': measurement.vBase,
    'frequencyHz': measurement.frequencyHz,
    'periodSeconds': measurement.periodSeconds,
    'dutyPercent': measurement.dutyPercent,
    'pulseWidthSeconds': measurement.pulseWidthSeconds,
    'riseTimeSeconds': measurement.riseTimeSeconds,
    'fallTimeSeconds': measurement.fallTimeSeconds,
    'overshootPercent': measurement.overshootPercent,
    'undershootPercent': measurement.undershootPercent,
    'risingEdgeCount': measurement.risingEdgeCount,
    'fallingEdgeCount': measurement.fallingEdgeCount,
    'sampleCount': measurement.sampleCount,
    'sampleIntervalSeconds': measurement.sampleIntervalSeconds,
    'notes': measurement.notes,
  };

  /// Statistics over the stored measurement history.
  ///
  /// Channels with only one stored acquisition are omitted: a standard
  /// deviation needs at least two runs.
  Map<String, WaveformChannelStatistics> _measurementStatistics() {
    final statistics = <String, WaveformChannelStatistics>{};
    void add(String channel, List<WaveformMeasurements> history) {
      if (history.length > 1) {
        statistics[channel] = measureChannelStatistics(history);
      }
    }

    add('ch1', _measurementHistoryCh1);
    add('ch2', _measurementHistoryCh2);
    add('ch3', _measurementHistoryCh3);
    add('ch4', _measurementHistoryCh4);
    return statistics;
  }

  /// Longest stored history across all channels.
  int _measurementHistoryCount() {
    var count = 0;
    for (final history in [
      _measurementHistoryCh1,
      _measurementHistoryCh2,
      _measurementHistoryCh3,
      _measurementHistoryCh4,
    ]) {
      if (history.length > count) count = history.length;
    }
    return count;
  }

  /// Enabled live channels that can serve as a reference.
  Map<String, WaveformData> _enabledLiveChannels() {
    final channels = <String, WaveformData>{};
    void add(String channel, bool enabled, WaveformData? data) {
      if (enabled && data != null && data.points.isNotEmpty) {
        channels[channel] = data;
      }
    }

    add('ch1', _ch1Enabled, _waveformCh1);
    add('ch2', _ch2Enabled, _waveformCh2);
    add('ch3', _numChannels >= 4 && _ch3Enabled, _waveformCh3);
    add('ch4', _numChannels >= 4 && _ch4Enabled, _waveformCh4);
    return channels;
  }

  bool _hasCurrentWaveform() => _enabledLiveChannels().isNotEmpty;

  /// Live waveform belonging to the loaded reference channel.
  WaveformData? _liveWaveformForReference() => switch (_refChannelOrigin) {
    'ch1' => _waveformCh1,
    'ch2' => _waveformCh2,
    'ch3' => _waveformCh3,
    'ch4' => _waveformCh4,
    _ => null,
  };

  double _referenceVpp() => _referenceVppCache;

  double _referenceDurationSeconds() => _referenceDurationCache;

  /// Recomputes the cached reference geometry after a reference change.
  void _cacheReferenceGeometry() {
    final points = _refWaveform?.points;
    if (points == null || points.isEmpty) {
      _referenceVppCache = 0;
      _referenceDurationCache = 0;
      return;
    }
    var min = double.infinity;
    var max = -double.infinity;
    for (final (_, voltage) in points) {
      if (voltage < min) min = voltage;
      if (voltage > max) max = voltage;
    }
    _referenceVppCache = max - min;
    _referenceDurationCache = points.length < 2
        ? 0
        : points.last.$1 - points.first.$1;
  }

  void _onDiffToggled(bool visible) {
    setState(() => _diffVisible = visible);
    if (visible) _recomputeReferenceAnalysis();
  }

  void _onMaskSettingsChanged(MaskSettings settings) {
    setState(() => _maskSettings = settings);
    _recomputeReferenceAnalysis();
  }

  /// Picks the first displayed channel whose measurements look like a clock.
  void _updateClockSuggestion() {
    _clockSuggestion = null;
    _clockSuggestionDismissed = false;
    for (final measurement in _currentMeasurements().values) {
      final suggestion = detectClock(measurement);
      if (suggestion != null) {
        _clockSuggestion = suggestion;
        return;
      }
    }
  }

  /// Applies the suggested timebase through the normal command path.
  Future<void> _applyClockSuggestion() async {
    final suggestion = _clockSuggestion;
    if (suggestion == null) return;
    final value = suggestion.suggestedTimebaseSeconds
        .toStringAsExponential(2)
        .toUpperCase();
    if (!await _sendCommand('TDIV $value')) return;
    if (!mounted) return;
    setState(() => _clockSuggestionDismissed = true);
    _showInfoSnackBar(
      'Timebase set to ${formatTimebase(suggestion.suggestedTimebaseSeconds)}',
    );
  }

  /// Banner for a detected clock signal. It only suggests a timebase; the
  /// setting is applied when the user presses Apply.
  Widget _buildClockSuggestionBanner(ClockSuggestion suggestion) {
    final channel = suggestion.channel.toUpperCase();
    final frequency = formatMeasurementValue(suggestion.frequencyHz, 'Hz');
    final timebase = formatTimebase(suggestion.suggestedTimebaseSeconds);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF172A45),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 16, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Clock signal on $channel: $frequency, '
              '${suggestion.dutyPercent.toStringAsFixed(1)} % duty. '
              'Suggested timebase: $timebase '
              '(${suggestion.periodsOnScreen.toStringAsFixed(1)} periods).',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: _applyClockSuggestion,
            child: const Text('Apply'),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: () => setState(() => _clockSuggestionDismissed = true),
            icon: const Icon(Icons.close, size: 16, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  /// Opens the timelapse settings dialog and starts the run.
  Future<void> _showTimelapseDialog() async {
    if (!_isOnline) {
      _showErrorSnackBar('Device is offline');
      return;
    }
    final plan = await showDialog<TimelapsePlan>(
      context: context,
      builder: (_) =>
          TimelapseDialog(targetDirectory: AppPaths.timelapseDirectory.path),
    );
    if (plan == null || !mounted) return;
    await _runTimelapse(plan);
  }

  /// Aborts a running timelapse immediately, including the current interval
  /// wait.
  void _stopTimelapse() {
    _timelapseSession?.abort();
    final stop = _timelapseStop;
    if (stop != null && !stop.isCompleted) stop.complete();
  }

  /// Captures [plan] frames into a timestamped folder under
  /// [AppPaths.timelapseDirectory].
  ///
  /// Auto capture and the live screen are stopped first; both stay blocked
  /// while the run is active.
  Future<void> _runTimelapse(TimelapsePlan plan) async {
    if (_timelapseRunning) return;
    if (_isAcquiring || _isAcquiringWaveform || _bodeIsRunning) {
      _showInfoSnackBar('Another capture is running. Try again afterwards.');
      return;
    }
    _stopAutoCapture();
    _restoreLiveOnPanelReturn = false;
    _stopVncLive(fetchScreen: false, restoreAutoCapture: false);
    _clearVncAvailability();

    final Directory runDirectory;
    try {
      final base = await AppPaths.getOrCreateTimelapseDir();
      runDirectory = await Directory(
        '${base.path}${Platform.pathSeparator}'
        '${timelapseRunFolderName(DateTime.now())}',
      ).create(recursive: true);
    } catch (e) {
      AppLogger().error('Timelapse folder error: $e');
      _showErrorSnackBar('Timelapse folder error: $e');
      return;
    }

    if (!mounted) return;

    final session = TimelapseSession(plan: plan);
    final stop = Completer<void>();
    final progress = ValueNotifier<int>(0);
    _timelapseSession = session;
    _timelapseStop = stop;
    setState(() => _timelapseRunning = true);

    _timelapseSnackBar = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(days: 1),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, value, _) =>
              Text('Timelapse: frame $value / ${plan.frameCount}'),
        ),
        action: SnackBarAction(label: 'Stop', onPressed: _stopTimelapse),
      ),
    );

    try {
      while (session.isActive) {
        final fileName = session.nextFileName;
        if (fileName == null) break;
        final instr = await _getInstrument();
        if (instr == null) throw Exception('Device is offline');
        final data = await instr.getScreenDump();
        final processed = await compute(processScreenDump, data);
        await File(
          '${runDirectory.path}${Platform.pathSeparator}$fileName',
        ).writeAsBytes(processed);
        session.recordCaptured();
        progress.value = session.captured;
        if (!session.isActive) break;
        final delay = Future<void>.delayed(plan.interval);
        await Future.any<void>([delay, stop.future]);
      }
    } catch (e) {
      AppLogger().error('Timelapse frame failed: $e');
      session.abort();
      if (mounted) _showErrorSnackBar('Timelapse stopped: $e');
    } finally {
      _timelapseSnackBar?.close();
      _timelapseSnackBar = null;
      _timelapseSession = null;
      _timelapseStop = null;
      // The snackbar animates out while it may still rebuild its content.
      unawaited(
        Future<void>.delayed(const Duration(seconds: 1), progress.dispose),
      );
      if (mounted) {
        setState(() => _timelapseRunning = false);
        final frames = session.captured;
        if (session.isComplete) {
          _showInfoSnackBar(
            'Timelapse finished: $frames frames saved in ${runDirectory.path}',
            duration: const Duration(seconds: 8),
          );
        } else if (frames > 0) {
          _showInfoSnackBar('Timelapse stopped after $frames frames');
        }
      } else {
        _timelapseRunning = false;
      }
    }
  }

  /// Opens the ripple/noise dialog for the connected instrument.
  Future<void> _showRippleNoiseDialog() async {
    if (!_isOnline) {
      _showErrorSnackBar('Device is offline');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => RippleNoiseDialog(
        channels: _numChannels >= 4 ? const [1, 2, 3, 4] : const [1, 2],
        run: _runRippleNoiseMeasurement,
      ),
    );
  }

  /// Applies the ripple/noise preset, reads RMS and Vpp, then restores the
  /// previous channel settings.
  ///
  /// The previous coupling, bandwidth limit, V/div and offset are queried
  /// first; a failed query falls back to the documented defaults instead of
  /// aborting the measurement.
  Future<String> _runRippleNoiseMeasurement({
    required int channel,
    required double vdiv,
    required double offset,
    required bool bandwidthLimit,
    required bool restore,
  }) async {
    final instr = await _getInstrument();
    if (instr == null) throw Exception('Device is offline');

    Future<String?> queryOrNull(String command) async {
      try {
        return await instr.queryString(command);
      } catch (e) {
        AppLogger().warning('Ripple preset: $command failed: $e');
        return null;
      }
    }

    var previousCoupling = 'D1M';
    var previousBandwidthLimit = false;
    double? previousVdiv;
    double? previousOffset;
    if (restore) {
      previousCoupling =
          parseCouplingResponse(await queryOrNull('C$channel:CPL?') ?? '') ??
          previousCoupling;
      previousBandwidthLimit =
          parseBandwidthLimitResponse(
            await queryOrNull('BWL?') ?? '',
            channel,
          ) ??
          previousBandwidthLimit;
      previousVdiv = parseVoltageResponse(
        await queryOrNull('C$channel:VDIV?') ?? '',
      );
      previousOffset = parseVoltageResponse(
        await queryOrNull('C$channel:OFST?') ?? '',
      );
    }

    final plan = buildRippleNoisePlan(
      channel: channel,
      vdiv: vdiv,
      offset: offset,
      bandwidthLimit: bandwidthLimit,
      previousCoupling: previousCoupling,
      previousBandwidthLimit: previousBandwidthLimit,
      previousVdiv: previousVdiv,
      previousOffset: previousOffset,
    );

    final responses = <String>[];
    try {
      for (final command in plan.applyCommands) {
        await instr.writeString(command);
      }
      // Give the acquisition a moment to settle on the new scale.
      await Future.delayed(const Duration(milliseconds: 300));
      for (final command in plan.measureCommands) {
        responses.add(await instr.queryString(command));
      }
    } finally {
      if (restore) {
        for (final command in plan.restoreCommands) {
          try {
            await instr.writeString(command);
          } catch (e) {
            AppLogger().warning('Ripple restore failed: $e');
          }
        }
      }
    }

    return formatRippleNoiseResult(
      rms: responses.isEmpty ? null : parseVoltageResponse(responses[0]),
      vpp: responses.length < 2 ? null : parseVoltageResponse(responses[1]),
    );
  }

  /// Copies the current waveform of an enabled channel into the reference.
  Future<void> _useCurrentWaveformAsReference() async {
    final channels = _enabledLiveChannels();
    if (channels.isEmpty) {
      _showInfoSnackBar('No current waveform available.');
      return;
    }

    final channel = channels.length == 1
        ? channels.keys.first
        : await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Use which channel as reference?'),
              children: [
                for (final entry in channels.entries)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, entry.key),
                    child: Text(
                      entry.key.toUpperCase(),
                      style: TextStyle(color: waveformChannelColor(entry.key)),
                    ),
                  ),
              ],
            ),
          );
    if (channel == null || !mounted) return;

    final points = channels[channel]!.points;
    setState(() {
      _refWaveform = WaveformData(points: points);
      _refVisible = true;
      _refFileName = '${channel.toUpperCase()} (current)';
      _refChannelOrigin = channel;
      _refOffset = const ReferenceOffset();
      _cacheReferenceGeometry();
    });
    _recomputeReferenceAnalysis();
  }

  /// Recomputes difference trace, deviation metrics and the mask test.
  ///
  /// Called after an acquisition, a reference change, a reference drag and a
  /// mask settings change. The result only covers the live points that the
  /// (shifted) reference actually spans.
  void _recomputeReferenceAnalysis() {
    final params = _deviceParams;
    final reference = _refWaveform;
    final live = _liveWaveformForReference();

    if (params == null ||
        reference == null ||
        reference.points.isEmpty ||
        live == null ||
        live.points.isEmpty) {
      if (_diffTrace != null ||
          _comparison != null ||
          _maskBand != null ||
          _maskResult != null) {
        setState(() {
          _diffTrace = null;
          _comparison = null;
          _maskBand = null;
          _maskResult = null;
        });
      }
      return;
    }

    final referenceVdiv = params.vdivFor(_refChannelOrigin) ?? 1.0;
    final trace = differenceTrace(
      live: live.points,
      reference: reference.points,
      offset: _refOffset,
      timebase: params.timebase,
      referenceVdiv: referenceVdiv,
    );
    final comparison = comparisonMetrics(
      live: live.points,
      reference: reference.points,
      offset: _refOffset,
      timebase: params.timebase,
      referenceVdiv: referenceVdiv,
    );

    MaskBand? band;
    MaskResult? result;
    if (_maskSettings.enabled) {
      final shifted = shiftReference(
        reference.points,
        offset: _refOffset,
        timebase: params.timebase,
        referenceVdiv: referenceVdiv,
      );
      final toleranceVolts = _maskSettings.usePercent
          ? _referenceVpp() * _maskSettings.toleranceValue / 100
          : _maskSettings.toleranceValue;
      band = buildMaskBand(
        shifted,
        toleranceVolts: toleranceVolts,
        toleranceTime: _maskSettings.timeToleranceSeconds > 0
            ? _maskSettings.timeToleranceSeconds
            : null,
      );
      result = evaluateMask(live.points, band);
    }

    setState(() {
      _diffTrace = WaveformData(points: trace);
      _comparison = comparison;
      _maskBand = band;
      _maskResult = result;
    });
  }

  /// Whether the standard save (screen dump or waveform) is available.
  bool get _canSaveStandard =>
      _activePanel == ActivePanel.none &&
      (_screenDump != null || _waveformAcquired);

  /// Whether the current waveform can be exported in an external format.
  bool get _canExportWaveform =>
      _activePanel == ActivePanel.none &&
      _waveformAcquired &&
      (_waveformCh1 != null ||
          _waveformCh2 != null ||
          _waveformCh3 != null ||
          _waveformCh4 != null);

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
        generatorFamily: info?.family,
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
      final liveImage = _vncLive ? _liveScreenImage : null;
      if (liveImage != null) {
        // While live, the SCDP dump above is stale — save the current frame.
        final data = await liveImage.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw Exception('Failed to encode live screen');
        }
        await file.writeAsBytes(data.buffer.asUint8List());
      } else {
        await file.writeAsBytes(_screenDump!);
      }
      final fileName = file.uri.pathSegments.last;
      _showInfoSnackBar('Saved $fileName');
    } catch (e) {
      _showErrorSnackBar('Save failed: $e');
    }
  }

  /// Saves the waveform measurement report (PDF) and the CSV data.
  ///
  /// The chart is captured only as the report image; no standalone image file
  /// is written.
  Future<void> _saveWaveform() async {
    try {
      final prefix = await _askForFilenamePrefixIfNeeded();
      if (prefix == null) return; // user cancelled
      final reportBaseName = prefix.isNotEmpty ? prefix : 'waveform_report';
      final csvBaseName = prefix.isNotEmpty ? prefix : 'waveform_data';

      final chartKey = _effectiveWaveformViewMode == _WaveformViewMode.spectrum
          ? _spectrumKey
          : _waveformKey;
      final boundary =
          chartKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Waveform not rendered yet');

      final uiImage = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await uiImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        throw Exception('Failed to capture waveform image');
      }
      final image = img.Image.fromBytes(
        width: uiImage.width,
        height: uiImage.height,
        bytes: byteData.buffer,
        numChannels: 4,
      );

      SpectrumResult? spectrum;
      try {
        spectrum = await _spectrumForReport();
      } catch (e) {
        AppLogger().warning('Spectrum computation for the report failed: $e');
      }

      final pdfBytes = await WaveformReport.generatePdf(
        chartImageBytes: img.encodePng(image),
        params: _deviceParams!,
        measurements: _acquiredMeasurements(),
        comparison: _comparison,
        maskResult: _maskSettings.enabled ? _maskResult : null,
        spectrum: spectrum,
        reportName: prefix.isEmpty ? null : prefix,
        deviceName: _deviceName ?? _ipAddress,
      );

      final reportDir = await AppPaths.getOrCreateWaveformReportsDir();
      final reportFile = await AppPaths.getUniqueFilePath(
        reportDir,
        reportBaseName,
        'pdf',
      );
      await reportFile.writeAsBytes(pdfBytes);
      final reportName = reportFile.uri.pathSegments.last;

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
        _showInfoSnackBar('Saved $reportName + $csvName');
      }
    } catch (e) {
      _showErrorSnackBar('Save failed: $e');
    }
  }

  /// Acquired waveform channels with their display points.
  Map<String, WaveformData> _acquiredWaveformChannels() => {
    'ch1': ?_waveformCh1,
    'ch2': ?_waveformCh2,
    'ch3': ?_waveformCh3,
    'ch4': ?_waveformCh4,
  };

  Future<void> _showWaveformExportDialog() async {
    final channels = _acquiredWaveformChannels();
    if (channels.isEmpty) {
      _showInfoSnackBar('No waveform data available.');
      return;
    }
    final request = await showDialog<WaveformExportRequest>(
      context: context,
      builder: (_) => WaveformExportDialog(channels: channels.keys.toList()),
    );
    if (request == null || !mounted) return;
    await _performWaveformExport(request);
  }

  Future<void> _performWaveformExport(WaveformExportRequest request) async {
    try {
      if (request.format == WaveformExportFormat.clipboard) {
        await Clipboard.setData(
          ClipboardData(text: buildClipboardText(_acquiredMeasurements())),
        );
        _showInfoSnackBar('Measurements copied to the clipboard.');
        return;
      }

      final channels = _acquiredWaveformChannels();
      final String extension;
      Uint8List? bytes;
      String? text;
      switch (request.format) {
        case WaveformExportFormat.ltspicePwl:
          final points = channels[request.channel]?.points ?? const [];
          text = buildLtspicePwl(points, wrap: request.wrapPwl);
          extension = 'txt';
          break;
        case WaveformExportFormat.wav:
          final points = channels[request.channel]?.points ?? const [];
          bytes = buildWav(points, sampleRate: _waveformPointRate(points));
          extension = 'wav';
          break;
        case WaveformExportFormat.vcd:
          text = buildVcd({
            for (final entry in channels.entries) entry.key: entry.value.points,
          }, thresholdVolts: request.thresholdVolts);
          extension = 'vcd';
          break;
        case WaveformExportFormat.clipboard:
          throw StateError('clipboard export is handled above');
      }

      final dir = await AppPaths.getOrCreateWaveformExportsDir();
      final base = request.fileName.trim().isEmpty
          ? 'waveform_export'
          : request.fileName.trim();
      final file = await AppPaths.getUniqueFilePath(dir, base, extension);
      if (bytes != null) {
        await file.writeAsBytes(bytes);
      } else {
        await file.writeAsString(text ?? '');
      }
      if (mounted) _showInfoSnackBar('Saved ${file.uri.pathSegments.last}');
    } catch (e) {
      _showErrorSnackBar('Export failed: $e');
    }
  }

  /// Effective sample rate of the displayed points (1 / first interval).
  double _waveformPointRate(List<(double, double)> points) {
    if (points.length >= 2) {
      final dt = points[1].$1 - points[0].$1;
      if (dt.isFinite && dt > 0) return 1 / dt;
    }
    return _deviceParams?.sampleRate ?? 1000;
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
      setState(() {
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
    await _loadSpectrumSettings();
  }

  /// Loads the persisted spectrum settings.
  Future<void> _loadSpectrumSettings() async {
    const defaults = SpectrumSettings();
    final windowName = await AppPreferences.getString('spectrum_window');
    final unitName = await AppPreferences.getString('spectrum_unit');
    final window = windowName == null
        ? defaults.window
        : SpectrumWindow.values.firstWhere(
            (value) => value.name == windowName,
            orElse: () => defaults.window,
          );
    final unit = unitName == null
        ? defaults.unit
        : SpectrumUnit.values.firstWhere(
            (value) => value.name == unitName,
            orElse: () => defaults.unit,
          );

    final settings = SpectrumSettings(
      window: window,
      fftSize:
          await AppPreferences.getInt('spectrum_fft_size') ?? defaults.fftSize,
      maxFftSize:
          await AppPreferences.getInt('spectrum_max_fft_size') ??
          defaults.maxFftSize,
      unit: unit,
      removeDc:
          await AppPreferences.getBool('spectrum_remove_dc') ??
          defaults.removeDc,
      peakCount:
          await AppPreferences.getInt('spectrum_peak_count') ??
          defaults.peakCount,
      harmonicCount:
          await AppPreferences.getInt('spectrum_harmonic_count') ??
          defaults.harmonicCount,
      leadingSamplesToSkip:
          await AppPreferences.getInt('spectrum_skip_samples') ??
          defaults.leadingSamplesToSkip,
    );

    if (!mounted) return;
    setState(() {
      _spectrumSettings = settings;
      _spectrumResult = null;
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
      ..._spectrumPreferenceEntries(),
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
  // =========================================================================
  // Waveform AI assistant
  // =========================================================================

  void _toggleWaveformAi() {
    final open = !_showWaveformAi;
    if (!open) unawaited(_voiceInputService.stop());
    setState(() => _showWaveformAi = open);
    _waveformChatController.setOpen(open);
  }

  void _closeWaveformAi() {
    if (!_showWaveformAi) return;
    unawaited(_voiceInputService.stop());
    setState(() => _showWaveformAi = false);
    _waveformChatController.setOpen(false);
  }

  /// Configures the Waveform AI assistant from the current AI settings.
  void _configureWaveformAi() {
    _waveformChatController.configure(
      _aiSettings,
      readWaveformSummary: _waveformSummaryForAi,
      readSpectrumSummary: _spectrumSummaryForAi,
      acquireWaveform: _acquireWaveformForAi,
      readWaveformHistory: _waveformHistoryForAi,
      classifyWaveform: _classifyWaveformForAi,
      compareWaveformToReferences: _compareWaveformToReferencesForAi,
      readWaveformFeatures: _waveformFeaturesForAi,
      compareWaveforms: _compareWaveformsForAi,
      generateReferenceWaveform: _generateWaveformReferenceForAi,
      analyzeWaveformFaults: _analyzeWaveformFaultsForAi,
      manageFaultProfile: _manageFaultAnalysisProfileForAi,
      clearMeasurementHistory: _clearMeasurementHistory,
      vxi11Host: _ipAddress,
      instrumentDeviceContext: _sdsDeviceContext,
      readSignalGeneratorStatus: _readSignalGeneratorStatusForAi,
      applySignalGenerator: _applySignalGeneratorForAi,
      controlSignalGenerator: _controlSignalGeneratorForAi,
    );
  }

  /// Returns authorized command definitions and knowledge for the Macro
  /// Editor's dynamic command-reference tool.
  Future<Map<String, dynamic>> _readDeviceCommandReferenceForAi({
    String? profileId,
    String? commandId,
    String? query,
  }) async {
    final store = await _deviceProfiles();
    if (store == null) {
      return {
        'error_code': DeviceErrorCode.profileNotLoaded.code,
        'error': 'The device profiles are not available.',
      };
    }

    if (profileId == null) {
      final details = <Map<String, dynamic>>[];
      for (final id in store.loadedProfileIds) {
        final profile = store.getProfile(id);
        if (profile == null) continue;
        details.add({
          'profile_id': profile.profileId,
          'display_name': profile.displayName,
          'package_id': profile.metadata.packageId,
          'command_count': profile.commands.length,
          'knowledge_version': profile.knowledge.metadata.version,
        });
      }
      return {
        'profiles': store.loadedProfileIds,
        'configured_signal_generator': _signalGenerator,
        'profiles_detail': details,
      };
    }

    DeviceProfile profile;
    try {
      profile = await store.loadProfile(profileId);
    } on DeviceCommandException catch (error) {
      return error.toJson();
    }

    if (commandId != null) {
      try {
        return profile.getCommandDocumentation(commandId).toJson();
      } on DeviceCommandException catch (error) {
        return error.toJson();
      }
    }

    if (query != null) {
      final commands = profile.registry
          .findCommands(query)
          .take(20)
          .map(
            (command) => {
              'command_id': command.commandId,
              'name': command.name,
              'description': command.description,
              'scpi_pattern': command.scpiPattern,
              'query_pattern': command.queryPattern,
              'operation_kind': command.operationKind.wireName,
              'query_support': command.querySupport.wireName,
            },
          )
          .toList(growable: false);
      final knowledge = profile
          .searchKnowledge(query)
          .map((result) => result.toJson())
          .toList(growable: false);
      return {
        'profile_id': profile.profileId,
        'query': query,
        'commands': commands,
        'knowledge': knowledge,
      };
    }

    return {
      'profile_id': profile.profileId,
      'display_name': profile.displayName,
      'package_id': profile.metadata.packageId,
      'schema_version': profile.metadata.schemaVersion,
      'device_scope': profile.metadata.deviceScope,
      'knowledge_version': profile.knowledge.metadata.version,
      'commands': [
        for (final command in profile.commands)
          {
            'command_id': command.commandId,
            'name': command.name,
            'description': command.description,
            'scpi_pattern': command.scpiPattern,
            'query_pattern': command.queryPattern,
            'operation_kind': command.operationKind.wireName,
            'query_support': command.querySupport.wireName,
          },
      ],
      'knowledge_sections': [
        for (final section in profile.knowledge.sections)
          {'id': section.id, 'title': section.title},
      ],
    };
  }

  /// Reports the live signal-generator status to the Waveform Agent.
  Future<Map<String, dynamic>> _readSignalGeneratorStatusForAi() async {
    final device = _signalGenerator;
    final supported = device == 'jds6600' || device == 'fy6900';
    final service = _sigGenService;
    final store = await _deviceProfiles();
    final profileId = DeviceProfileIds.normalize(device);
    final profile = profileId == null ? null : store?.getProfile(profileId);
    final profileError = store != null && profileId != null && profile == null
        ? store.errorFor(profileId)?.toJson() ??
              {
                'error_code': DeviceErrorCode.profileNotLoaded.code,
                'error': 'The device profile "$profileId" is not loaded.',
              }
        : null;
    final profileStatus = profile == null
        ? null
        : buildDeviceProfileStatus(
            profile,
            identity: store!.resolveIdentity(
              service?.deviceInfo?.scpiIdentity,
              configuredDevice: device,
            ),
          );
    if (!supported || service == null) {
      return {
        'configured_device': device,
        'supported': supported,
        'connected': false,
        'error':
            'No signal generator is configured. Select JDS6600 or FY6900 in '
            'Settings -> Signal Generator.',
        'device_profile': ?profileStatus,
        'device_profile_error': ?profileError,
      };
    }
    if (!service.isConnected) {
      return {
        'configured_device': device,
        'supported': true,
        'detected': _sigGenDetected,
        'connected': false,
        'port': _sigGenPort,
        'error':
            'The signal generator is not connected. Check the USB connection '
            'and the device selection.',
        'device_profile': ?profileStatus,
        'device_profile_error': ?profileError,
      };
    }
    try {
      await service.refreshAll();
    } catch (_) {
      // Keep the cached values; the status below reports the last error.
    }
    final status = readMacroSiggenStatus(
      configuredDevice: device,
      detected: _sigGenDetected,
      service: service,
      rememberedPort: _sigGenPort,
    );
    final info = service.deviceInfo;
    if (profileStatus != null) {
      status['device_profile'] = profileStatus;
    }
    if (profileError != null) {
      status['device_profile_error'] = profileError;
    }
    if (info != null) {
      status['limits'] = {
        'min_frequency_hz': info.limits.minFrequencyHz,
        'max_frequency_hz_by_waveform': {
          for (final waveform in Jds6600Waveform.selectableFor(info.family))
            waveform.scpiMnemonic: info.maxFrequencyHz(waveform),
        },
        'min_offset_v': info.limits.minOffsetV,
        'max_offset_v': info.limits.maxOffsetV,
        'min_duty_percent': info.limits.minDutyPercent,
        'max_duty_percent': info.limits.maxDutyPercent,
        'min_phase_deg': info.limits.minPhaseDegrees,
        'max_phase_deg': info.limits.maxPhaseDegrees,
      };
    }
    return status;
  }

  /// Applies a Waveform Agent signal-generator change request.
  ///
  /// The request is validated against the active device profile before the
  /// first command is sent. Unsupported waveforms, channels, units and unknown
  /// values return a structured error; they are never mapped silently.
  Future<Map<String, dynamic>> _applySignalGeneratorForAi(
    SignalGeneratorSettings settings,
  ) async {
    final service = _sigGenService;
    if (service == null || !service.isConnected) {
      return {'error': 'The signal generator is not connected.'};
    }

    final store = await _deviceProfiles();
    if (store == null) {
      return {
        'error_code': DeviceErrorCode.profileNotLoaded.code,
        'error': 'The device profiles are not available.',
      };
    }
    final profileId = DeviceProfileIds.normalize(_signalGenerator);
    if (profileId == null) {
      return {
        'error_code': DeviceErrorCode.profileUnknown.code,
        'error': 'No signal generator profile is configured.',
        'configured_device': _signalGenerator,
      };
    }
    DeviceProfile profile;
    try {
      profile = await store.loadProfile(profileId);
    } on DeviceCommandException catch (error) {
      return error.toJson();
    }

    final allowedChannels = profile.syntax.sourceChannelAllowedValues;
    if (allowedChannels.isNotEmpty &&
        !allowedChannels.contains(settings.channel)) {
      return DeviceCommandException(
        DeviceErrorCode.unsupportedChannel,
        'Channel ${settings.channel} is not supported by profile '
        '"$profileId".',
        profile: profileId,
        requestedValue: settings.channel,
        supportedValues: allowedChannels
            .map((value) => value.toString())
            .toList(growable: false),
      ).toJson();
    }

    final validatedCommands = <String, String>{};
    DeviceWaveformResolution? waveformResolution;
    Jds6600Waveform? resolvedWaveform;
    try {
      final channel = settings.channel;
      final frequency = settings.frequencyHz;
      if (frequency != null) {
        validatedCommands['freq'] = profile.registry.resolveCommand('freq', {
          'n': channel,
          'value': frequency,
          'unit': 'HZ',
        }).scpi;
      }
      final amplitude = settings.amplitudeVpp;
      if (amplitude != null) {
        validatedCommands['volt'] = profile.registry.resolveCommand('volt', {
          'n': channel,
          'value': amplitude,
          'unit': 'V',
        }).scpi;
      }
      final offset = settings.offsetV;
      if (offset != null) {
        validatedCommands['volt_offs'] = profile.registry.resolveCommand(
          'volt_offs',
          {'n': channel, 'value': offset, 'unit': 'V'},
        ).scpi;
      }
      final duty = settings.dutyPercent;
      if (duty != null) {
        validatedCommands['puls_dcyc'] = profile.registry.resolveCommand(
          'puls_dcyc',
          {'n': channel, 'value': duty, 'unit': '%'},
        ).scpi;
      }
      final phase = settings.phaseDeg;
      if (phase != null) {
        validatedCommands['phas'] = profile.registry.resolveCommand('phas', {
          'n': channel,
          'value': phase,
          'unit': 'DEG',
        }).scpi;
      }
      final output = settings.output;
      if (output != null) {
        validatedCommands['output_state'] = profile.registry.resolveCommand(
          'output_state',
          {'n': channel, 'state': output ? 'ON' : 'OFF'},
        ).scpi;
      }
      final requestedWaveform =
          settings.requestedWaveform ?? settings.waveform?.scpiMnemonic;
      if (requestedWaveform != null) {
        final resolved = profile.registry.resolveCommand('func', {
          'n': channel,
          'shape': requestedWaveform,
        });
        validatedCommands['func'] = resolved.scpi;
        waveformResolution = resolved.waveformResolution;
        resolvedWaveform = Jds6600Waveform.fromScpi(
          resolved.parameters['shape']!.toString(),
        );
        if (resolvedWaveform == null) {
          return DeviceCommandException(
            DeviceErrorCode.profileInconsistent,
            'The profile resolved the waveform to '
            '"${resolved.parameters['shape']}", which the driver does not '
            'know.',
            profile: profileId,
            parameter: 'shape',
            requestedValue: requestedWaveform,
          ).toJson();
        }
      }
    } on DeviceCommandException catch (error) {
      return error.toJson();
    }

    final applied = <String, dynamic>{};
    final logger = AppLogger(agentName: 'SigGen', toolName: 'applyForAi');
    logger.debug('Validated signal-generator commands: $validatedCommands');
    try {
      // Order matters: the device limits depend on the waveform and the
      // frequency, so set the waveform first and the frequency before the
      // amplitude.
      if (resolvedWaveform != null) {
        await service.setWaveform(settings.channel, resolvedWaveform);
        applied['waveform'] = resolvedWaveform.scpiMnemonic;
        final mapping = waveformResolution;
        if (mapping != null && mapping.mapped) {
          applied['waveform_mapping'] = mapping.toJson();
          logger.warning(
            'Signal generator waveform mapping: requested '
            '"${mapping.requested}", resolved "${mapping.resolved}", '
            'channel ${mapping.channel}.',
          );
        }
      }
      if (settings.frequencyHz != null) {
        await service.setFrequency(settings.channel, settings.frequencyHz!);
        applied['frequency_hz'] = settings.frequencyHz;
      }
      if (settings.amplitudeVpp != null) {
        await service.setAmplitude(settings.channel, settings.amplitudeVpp!);
        applied['amplitude_vpp'] = settings.amplitudeVpp;
      }
      if (settings.offsetV != null) {
        await service.setOffset(settings.channel, settings.offsetV!);
        applied['offset_v'] = settings.offsetV;
      }
      if (settings.dutyPercent != null) {
        await service.setDuty(settings.channel, settings.dutyPercent!);
        applied['duty_percent'] = settings.dutyPercent;
      }
      if (settings.phaseDeg != null) {
        await service.setPhase(settings.channel, settings.phaseDeg!);
        applied['phase_deg'] = settings.phaseDeg;
      }
      if (settings.output != null) {
        await service.setOutput(settings.channel, settings.output!);
        applied['output'] = settings.output;
      }
      // Read the real state back so a duty-driven waveform change (square to
      // RECT on the FY6900) is visible to the agent.
      try {
        await service.refreshAll();
      } catch (_) {
        // The cached values remain; the status below reports them.
      }
      final actualWaveform = service.channel(settings.channel).waveform;
      if (settings.dutyPercent != null &&
          applied['waveform'] != null &&
          actualWaveform.scpiMnemonic != applied['waveform']) {
        applied['waveform_after_apply'] = actualWaveform.scpiMnemonic;
        applied['note'] =
            'The FY6900 switches a square shape to RECT so the duty cycle '
            'takes effect. The channel is now ${actualWaveform.scpiMnemonic}.';
      }
      final identity = store.resolveIdentity(
        service.deviceInfo?.scpiIdentity,
        configuredDevice: _signalGenerator,
      );
      return {
        'success': true,
        'channel': settings.channel,
        'applied': applied,
        'device_profile': buildDeviceProfileStatus(profile, identity: identity),
        'status': readMacroSiggenStatus(
          configuredDevice: _signalGenerator,
          detected: _sigGenDetected,
          service: service,
          rememberedPort: _sigGenPort,
        ),
      };
    } on Jds6600Exception catch (error) {
      return {
        'error_code': DeviceErrorCode.deviceCommunicationFailed.code,
        'error': error.message,
        'profile': profileId,
        'channel': settings.channel,
        'applied': applied,
      };
    } catch (error) {
      return {
        'error_code': DeviceErrorCode.deviceCommunicationFailed.code,
        'error': 'Signal generator command failed: $error',
        'profile': profileId,
        'channel': settings.channel,
        'applied': applied,
      };
    }
  }

  /// Runs a reset or stop action on the connected signal generator.
  Future<Map<String, dynamic>> _controlSignalGeneratorForAi(
    String operation,
  ) async {
    final service = _sigGenService;
    if (service == null || !service.isConnected) {
      return {'error': 'The signal generator is not connected.'};
    }
    try {
      switch (operation) {
        case 'reset_safe_state':
          await service.resetSafeState();
        case 'stop_action':
          await service.stopActions();
        default:
          return {'error': 'Unknown signal generator operation "$operation".'};
      }
      return {
        'success': true,
        'operation': operation,
        'status': readMacroSiggenStatus(
          configuredDevice: _signalGenerator,
          detected: _sigGenDetected,
          service: service,
          rememberedPort: _sigGenPort,
        ),
      };
    } on Jds6600Exception catch (error) {
      return {'error': error.message};
    } catch (error) {
      return {'error': 'Signal generator command failed: $error'};
    }
  }

  /// Clears the Waveform AI acquisition history and the per-channel
  /// measurement history used by the statistics line.
  void _clearMeasurementHistory() {
    _waveformHistory.clear();
    if (!mounted) return;
    setState(() {
      _measurementHistoryCh1.clear();
      _measurementHistoryCh2.clear();
      _measurementHistoryCh3.clear();
      _measurementHistoryCh4.clear();
    });
  }

  /// First acquired channel, used when an analysis tool omits the channel.
  String? _defaultAnalysisChannel() {
    if (_waveformCh1?.points.isNotEmpty ?? false) return 'ch1';
    if (_waveformCh2?.points.isNotEmpty ?? false) return 'ch2';
    if (_waveformCh3?.points.isNotEmpty ?? false) return 'ch3';
    if (_waveformCh4?.points.isNotEmpty ?? false) return 'ch4';
    return null;
  }

  /// Trace of an acquired channel for the analysis engine.
  WaveformTrace? _analysisTraceForChannel(String? channel) {
    final requested = channel?.trim().toLowerCase();
    final selected = requested == null || requested.isEmpty
        ? _defaultAnalysisChannel()
        : requested;
    if (selected == null) return null;
    final data = switch (selected) {
      'ch1' => _waveformCh1,
      'ch2' => _waveformCh2,
      'ch3' => _waveformCh3,
      'ch4' => _waveformCh4,
      _ => null,
    };
    if (data == null || data.points.isEmpty) return null;
    return WaveformTrace.fromPoints(data.points, channel: selected);
  }

  ({List<WaveformSignalType>? types, String? error}) _parseReferenceTypes(
    List<String>? ids,
  ) {
    if (ids == null || ids.isEmpty) {
      return (types: null, error: null);
    }
    final types = <WaveformSignalType>[];
    final invalid = <String>[];
    for (final id in ids) {
      final type = WaveformSignalType.parse(id);
      if (type == null) {
        invalid.add(id);
      } else if (!types.contains(type)) {
        types.add(type);
      }
    }
    if (invalid.isNotEmpty) {
      return (
        types: null,
        error:
            'Unknown reference type(s): ${invalid.join(', ')}. Valid types: '
            '${WaveformSignalType.values.map((type) => type.id).join(', ')}.',
      );
    }
    return (types: types.isEmpty ? null : types, error: null);
  }

  /// `classify_waveform` provider for the Waveform AI.
  Future<Map<String, dynamic>> _classifyWaveformForAi({
    String? channel,
    List<String>? referenceTypes,
  }) async {
    if (!_waveformAcquired) {
      return <String, dynamic>{
        'error': 'No waveform is displayed. Acquire a waveform first.',
      };
    }
    final parsed = _parseReferenceTypes(referenceTypes);
    if (parsed.error != null) return <String, dynamic>{'error': parsed.error};
    final trace = _analysisTraceForChannel(channel);
    if (trace == null) {
      return <String, dynamic>{
        'error':
            'No acquired waveform data is available for '
            '${channel ?? 'the first channel'}. Acquire the channel first.',
      };
    }
    final result = await _waveformAnalysisService.classifyAsync(
      trace,
      options: WaveformAnalysisOptions(referenceTypes: parsed.types),
      channel: trace.channel,
    );
    return result.toMap();
  }

  /// `compare_waveform_to_references` provider for the Waveform AI.
  Future<Map<String, dynamic>> _compareWaveformToReferencesForAi({
    String? channel,
    List<String>? referenceTypes,
  }) async {
    final map = await _classifyWaveformForAi(
      channel: channel,
      referenceTypes: referenceTypes,
    );
    if (map.containsKey('error')) return map;
    final ranking = map['allCandidates'];
    final individualScores = <String, dynamic>{};
    if (ranking is List) {
      for (final candidate in ranking) {
        if (candidate is Map) {
          individualScores[candidate['referenceLabel']?.toString() ??
                  candidate['referenceType']?.toString() ??
                  'unknown'] =
              candidate['similarityPercent'];
        }
      }
    }
    return <String, dynamic>{
      ...map,
      'ranking': ranking,
      'bestMatch': ranking is List && ranking.isNotEmpty ? ranking.first : null,
      'individualSimilarityScores': individualScores,
    };
  }

  /// `get_waveform_features` provider for the Waveform AI.
  Future<Map<String, dynamic>> _waveformFeaturesForAi({String? channel}) async {
    if (!_waveformAcquired) {
      return <String, dynamic>{
        'error': 'No waveform is displayed. Acquire a waveform first.',
      };
    }
    final trace = _analysisTraceForChannel(channel);
    if (trace == null) {
      return <String, dynamic>{
        'error':
            'No acquired waveform data is available for '
            '${channel ?? 'the first channel'}. Acquire the channel first.',
      };
    }
    final features = await _waveformAnalysisService.featuresAsync(trace);
    return <String, dynamic>{'channel': trace.channel, ...features.toMap()};
  }

  /// `compare_waveforms` provider for the Waveform AI.
  Future<Map<String, dynamic>> _compareWaveformsForAi({
    required String channelA,
    required String channelB,
  }) async {
    if (!_waveformAcquired) {
      return <String, dynamic>{
        'error': 'No waveform is displayed. Acquire a waveform first.',
      };
    }
    if (channelA == channelB) {
      return <String, dynamic>{
        'error': 'Choose two different channels for the comparison.',
      };
    }
    final traceA = _analysisTraceForChannel(channelA);
    if (traceA == null) {
      return <String, dynamic>{
        'error': 'No acquired waveform data is available for $channelA.',
      };
    }
    final traceB = _analysisTraceForChannel(channelB);
    if (traceB == null) {
      return <String, dynamic>{
        'error': 'No acquired waveform data is available for $channelB.',
      };
    }
    final result = await _waveformAnalysisService.compareWaveformsAsync(
      traceA,
      traceB,
      channelA: channelA,
      channelB: channelB,
    );
    return result.toMap();
  }

  /// `generate_reference_waveform` provider for the Waveform AI.
  Future<Map<String, dynamic>> _generateWaveformReferenceForAi({
    required String referenceType,
    Map<String, dynamic>? parameters,
  }) async {
    final type = WaveformSignalType.parse(referenceType);
    if (type == null) {
      return <String, dynamic>{
        'error':
            'Unknown reference type "$referenceType". Valid types: '
            '${WaveformSignalType.values.map((type) => type.id).join(', ')}.',
      };
    }
    final parsed = parameters == null || parameters.isEmpty
        ? const ReferenceParameters()
        : ReferenceParameters.fromMap(parameters);
    final reference = _waveformAnalysisService.generateReference(type, parsed);
    return _waveformAnalysisService.referencePreview(reference);
  }

  /// `analyze_waveform_faults` provider for the Waveform AI.
  ///
  /// The analysis runs on the complete raw acquisition, not on the decimated
  /// display copy. A background isolate keeps the UI responsive for long
  /// records.
  Future<Map<String, dynamic>> _analyzeWaveformFaultsForAi({
    required List<String> tests,
    String? channel,
    String? channelB,
    Map<String, dynamic>? specification,
  }) async {
    final raw = _lastRawData;
    if (!_waveformAcquired || raw == null) {
      return <String, dynamic>{
        'error': 'No raw waveform data is available. Acquire a waveform first.',
      };
    }
    final primary = _faultTraceForChannel(channel);
    if (primary == null) {
      return <String, dynamic>{
        'error':
            'No raw waveform data is available for '
            '${channel ?? 'the first acquired channel'}.',
      };
    }
    final requested = <WaveformFaultTest>[];
    final invalid = <String>[];
    for (final id in tests) {
      final test = WaveformFaultTest.parse(id);
      if (test == null) {
        invalid.add(id);
      } else if (!requested.contains(test)) {
        requested.add(test);
      }
    }
    if (invalid.isNotEmpty) {
      return <String, dynamic>{
        'error':
            'Unknown fault test(s): ${invalid.join(', ')}. Valid tests: '
            '${WaveformFaultTest.values.map((test) => test.id).join(', ')}.',
      };
    }
    WaveformTrace? secondaryTrace;
    if (channelB != null && channelB.trim().isNotEmpty) {
      final secondary = _faultTraceForChannel(channelB);
      if (secondary == null) {
        return <String, dynamic>{
          'error': 'No raw waveform data is available for ${channelB.trim()}.',
        };
      }
      if (secondary.trace.channel == primary.trace.channel) {
        return <String, dynamic>{
          'error':
              'Choose two different channels for phase or crosstalk '
              'analysis.',
        };
      }
      secondaryTrace = secondary.trace;
    }
    final spec = specification ?? const <String, dynamic>{};
    final artifactValue = spec['measurement_artifacts'];
    final artifactSpec = artifactValue is Map
        ? Map<String, dynamic>.from(artifactValue)
        : const <String, dynamic>{};
    final probe = _faultNumberFrom(artifactSpec['probeAttenuation']);
    final adcBits = _faultNumberFrom(artifactSpec['adcBits'])?.round() ?? 8;
    final triggerLevel = _faultNumberFrom(artifactSpec['triggerLevelVolts']);
    final requests = requested.isEmpty
        ? [
            for (final test in WaveformFaultTest.values)
              WaveformFaultRequest(
                test: test,
                specification: _faultSpecificationForTest(spec, test),
              ),
          ]
        : [
            for (final test in requested)
              WaveformFaultRequest(
                test: test,
                specification: _faultSpecificationForTest(spec, test),
              ),
          ];
    final context = WaveformFaultContext(
      trace: primary.trace,
      channel: primary.trace.channel ?? 'ch1',
      secondTrace: secondaryTrace,
      secondChannel: secondaryTrace?.channel,
      sampleRateHz: raw.effectiveSampleRate,
      verticalScaleVoltsPerDiv: _rawVdiv(raw, primary.trace.channel),
      verticalOffsetVolts: _rawVoffset(raw, primary.trace.channel),
      timebaseSecondsPerDiv: raw.timebase,
      adcBits: adcBits <= 0 ? 8 : adcBits,
      probeAttenuation: probe ?? 1.0,
      probeAttenuationAssumed: probe == null,
      triggerLevelVolts: triggerLevel,
      triggerPosition: raw.triggerPosition,
      triggerDelaySeconds: raw.trdl,
      leadingSamplesExcluded: primary.leadingSamplesExcluded,
    );
    try {
      final report = await Isolate.run(
        () => const WaveformFaultAnalyzer().analyze(context, requests),
      );
      return report.toMap();
    } on Object catch (error) {
      AppLogger().error('Waveform fault analysis failed: $error');
      return <String, dynamic>{
        'error': 'Waveform fault analysis failed: $error',
      };
    }
  }

  /// Builds a trace from the complete raw channel data.
  ///
  /// The returned trace contains every transferred sample except the leading
  /// acquisition artifact that the display conversion also removes.
  ({WaveformTrace trace, int leadingSamplesExcluded})? _faultTraceForChannel(
    String? channel,
  ) {
    final raw = _lastRawData;
    if (raw == null) return null;
    final requested = channel?.trim().toLowerCase();
    final selected = requested == null || requested.isEmpty
        ? _defaultAnalysisChannel()
        : requested;
    if (selected == null) return null;
    final bytes = switch (selected) {
      'ch1' => raw.ch1Raw,
      'ch2' => raw.ch2Raw,
      'ch3' => raw.ch3Raw,
      'ch4' => raw.ch4Raw,
      _ => null,
    };
    final vdiv = _rawVdiv(raw, selected);
    final voffset = _rawVoffset(raw, selected);
    if (bytes == null || bytes.isEmpty || vdiv == null || voffset == null) {
      return null;
    }
    final voltages = WaveformConverter.convertVoltages(bytes, vdiv, voffset);
    final times = WaveformConverter.computeTimeAxis(
      voltages.length,
      raw.trdl,
      raw.timebase,
      raw.sampleRate,
      triggerPosition: raw.triggerPosition,
      sparsing: raw.sparsing,
    );
    const int leadingSamplesToSkip = 8;
    final start = voltages.length > leadingSamplesToSkip * 4
        ? leadingSamplesToSkip
        : 0;
    if (voltages.length - start < 2) return null;
    return (
      trace: WaveformTrace(
        times: Float64List.fromList([
          for (var index = start; index < voltages.length; index++)
            times[index],
        ]),
        volts: Float64List.fromList([
          for (var index = start; index < voltages.length; index++)
            voltages[index],
        ]),
        channel: selected,
      ),
      leadingSamplesExcluded: start,
    );
  }

  Map<String, dynamic> _faultSpecificationForTest(
    Map<String, dynamic> specification,
    WaveformFaultTest test,
  ) {
    final nested = specification[test.id];
    return nested is Map
        ? Map<String, dynamic>.from(nested)
        : const <String, dynamic>{};
  }

  double? _rawVdiv(WaveformRawData raw, String? channel) => switch (channel) {
    'ch1' => raw.vdivCh1,
    'ch2' => raw.vdivCh2,
    'ch3' => raw.vdivCh3,
    'ch4' => raw.vdivCh4,
    _ => null,
  };

  double? _rawVoffset(WaveformRawData raw, String? channel) =>
      switch (channel) {
        'ch1' => raw.voffsetCh1,
        'ch2' => raw.voffsetCh2,
        'ch3' => raw.voffsetCh3,
        'ch4' => raw.voffsetCh4,
        _ => null,
      };

  double? _faultNumberFrom(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  /// `manage_fault_analysis_profile` provider for the Waveform AI.
  ///
  /// The profile is a JSON file below the application data directory. It
  /// stores only user-supplied specifications, per channel, and never
  /// measured values or analysis results.
  Future<Map<String, dynamic>> _manageFaultAnalysisProfileForAi({
    required String action,
    String? channel,
    Map<String, dynamic>? specification,
    String? mode,
  }) async {
    try {
      switch (action.trim().toLowerCase()) {
        case 'read':
          return await _waveformFaultProfileStore.read(channel: channel);
        case 'save':
          if (channel == null || channel.trim().isEmpty) {
            return <String, dynamic>{'error': 'channel is required for save.'};
          }
          return await _waveformFaultProfileStore.save(
            channel: channel,
            specification: specification ?? const <String, dynamic>{},
            mode: mode ?? 'replace',
          );
        case 'clear':
          return await _waveformFaultProfileStore.clear(channel: channel);
        default:
          return <String, dynamic>{
            'error':
                'Unknown profile action "$action". Valid actions: read, save, '
                'clear.',
          };
      }
    } on Object catch (error) {
      AppLogger().error('Fault analysis profile operation failed: $error');
      return <String, dynamic>{
        'error': 'Fault analysis profile operation failed: $error',
      };
    }
  }

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
      instrumentDeviceContext: _sdsDeviceContext,
      readSignalGeneratorStatus: _readSignalGeneratorStatusForAi,
      applySignalGenerator: _applySignalGeneratorForAi,
      controlSignalGenerator: _controlSignalGeneratorForAi,
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
      AppLogger().error('Failed to open $transport connection: $e');
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
        AppLogger().error('Error closing instrument: $e');
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

  void _scheduleRefresh({
    Duration extraDelay = Duration.zero,
    bool reschedule = false,
  }) {
    // While the live screen streams the current display there is no point in
    // fetching SCPI screen dumps; the VNC stream already shows every change.
    if (_vncLive) return;
    if (_refreshPending && !reschedule) return;
    _refreshPending = true;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(
      Duration(milliseconds: _refreshDelayMs) + extraDelay,
      () {
        _refreshPending = false;
        if (mounted && _isOnline && !_isAcquiringWaveform && !_bodeIsRunning) {
          _acquireScreenDump(keepPanels: true);
        }
      },
    );
  }

  /// Starts or stops the periodic screen capture requested by the toggle at
  /// the bottom right of the Control Panel. While enabled, a fresh screen
  /// dump is fetched every [_autoCaptureInterval].
  void _setAutoCaptureEnabled(bool enabled) {
    // The periodic capture and the live screen are mutually exclusive; the
    // toggle is disabled in the UI while live, this guards programmatic calls.
    if (enabled && _vncLive) return;
    if (enabled && _timelapseRunning) return;
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    setState(() => _autoCaptureEnabled = enabled);
    if (!enabled) return;

    _autoCaptureTimer = Timer.periodic(_autoCaptureInterval, (_) {
      if (!mounted ||
          !_isOnline ||
          _isAcquiring ||
          _isAcquiringWaveform ||
          _bodeIsRunning ||
          _timelapseRunning ||
          _screenDump == null ||
          _activePanel != ActivePanel.none) {
        return;
      }
      _acquireScreenDump(keepPanels: true);
    });
  }

  /// Stops the periodic screen capture and resets the toggle to "off".
  void _stopAutoCapture() {
    if (_autoCaptureTimer == null && !_autoCaptureEnabled) return;
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    if (mounted) {
      setState(() => _autoCaptureEnabled = false);
    } else {
      _autoCaptureEnabled = false;
    }
  }

  /// Sends a SCPI command to the instrument and returns true if successful.
  /// Shows error message on failure.
  /// If a macro recording is in progress the command is captured into
  /// [_currentMacroContent].
  Future<bool> _sendCommand(String command) async {
    // Capture SCPI commands during macro recording
    if (_isMacroRecording) {
      _currentMacroContent += 'cmd("$command")\n';
    }

    if (!_isOnline) {
      AppLogger().error('Popup: Device is offline');
      _showErrorSnackBar('Device is offline');
      return false;
    }

    try {
      final instr = await _getInstrument();
      if (instr == null) return false;

      await instr.writeString(command);
      return true;
    } catch (e) {
      AppLogger().error('Send command error: $e');
      _closeInstrument(); // Connection might be bad
      AppLogger().error('Popup: Failed to send command: $e');
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

  // =========================================================================
  // Shared SCPI Event-Processing Helper
  // =========================================================================

  /// Sends a SCPI command, waits for the instrument to process it,
  /// refreshes the screen dump, and enforces a cooldown.
  ///
  /// Returns `true` if the command was sent and screen refreshed successfully.
  Future<bool> _processScpiEvent(
    String command, {
    String? errorContext,
    Duration extraProcessingDelay = Duration.zero,
  }) async {
    if (_isProcessingEvent || !_isOnline) return false;

    _isProcessingEvent = true;
    if (mounted) setState(() {});

    try {
      if (await _sendCommand(command)) {
        // Wait for oscilloscope to process the command. Auto Setup passes a
        // longer delay because a full acquisition setup takes extra time.
        await Future.delayed(
          Duration(
            milliseconds: _refreshDelayMs + extraProcessingDelay.inMilliseconds,
          ),
        );
        // Fetch the screen dump synchronously — except while the live screen
        // is active: the VNC stream already reflects the new display state.
        if (!_vncLive) {
          await _acquireScreenDump(keepPanels: true);
        }
        // Final cooldown before next event is allowed
        await Future.delayed(const Duration(milliseconds: 500));
        return true;
      }
    } catch (e) {
      final ctx = errorContext ?? command;
      AppLogger().error('$ctx handler error: $e');
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
  Future<bool> _handleSoftKeyPress(int buttonNumber) => _processScpiEvent(
    '\$\$SY_FP $buttonNumber,1',
    errorContext: 'M$buttonNumber',
  );

  /// Handles MENU button press.
  /// Sends $$SY_FP 0,1 command (VXI special SPCI command for MENU button),
  /// then immediately requests a screen dump image.
  Future<bool> _handleMenuPress() =>
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
  Future<bool> _handleChannelButtonPress(String channel) async {
    final number = int.tryParse(channel.replaceFirst('CH', ''));
    if (number != null && number >= 1 && number <= _numChannels) {
      setState(() => _selectedChannel = number);
    }
    return _handleButtonPress(channel);
  }

  /// Generic handler for any button press (menu, vertical, horizontal, trigger, channel).
  /// Looks up the SCPI command from [buttonCommands] and sends it.
  Future<bool> _handleButtonPress(String buttonLabel) async {
    final command = buttonCommands[buttonLabel];
    if (command == null) {
      AppLogger().log('Button "$buttonLabel" not implemented yet');
      if (mounted) {
        _showInfoSnackBar('Button "$buttonLabel" not implemented yet');
      }
      return false;
    }
    return _processScpiEvent(
      command,
      errorContext: buttonLabel,
      // Auto Setup needs the instrument's full acquisition setup to finish
      // before the display reflects the result.
      extraProcessingDelay: buttonLabel == autoSetupButtonLabel
          ? _autoSetupExtraDelay
          : Duration.zero,
    );
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
    _recomputeReferenceAnalysis();
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
        _cacheReferenceGeometry();
      });
      _recomputeReferenceAnalysis();
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
    // Only the difference trace and the mask depend on the offset; skip the
    // resampling work while both are hidden.
    if (_diffVisible || _maskSettings.enabled) {
      _recomputeReferenceAnalysis();
    }
  }
}

/// Adapter that lets [SigGenWindowHost] push snapshots into the launcher.
class _SigGenWindowSink implements SigGenWindowEventSink {
  _SigGenWindowSink(this._push);

  final Future<void> Function(SigGenWindowState) _push;

  @override
  Future<void> pushState(SigGenWindowState state) => _push(state);
}

/// One step-by-step debugging run of the macro in the editor.
///
/// The evaluator runs in the background and pauses before every statement at
/// [gate]. Releasing the gate executes that statement; [cancel] interrupts a
/// paused gate and any in-flight `wait()` delay.
class _MacroDebugSession {
  final MacroEvaluator evaluator;

  /// Completed when the first statement gate is reached, or when the run
  /// ends without reaching one (empty or comment-only macro).
  final Completer<void> armed = Completer<void>();

  /// Completed when the session is cancelled. Races against `wait()` delays
  /// so Stop takes effect immediately.
  final Completer<void> cancelSignal = Completer<void>();

  bool cancelled = false;
  bool paused = false;
  bool finished = false;
  int step = 0;
  String statement = '';
  bool runToBreakpoint = false;
  int? currentLine;
  Map<String, String> variables = <String, String>{};
  Completer<void>? gate;
  Future<void>? runFuture;

  _MacroDebugSession(this.evaluator);

  void markArmed() {
    if (!armed.isCompleted) armed.complete();
  }

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    if (!cancelSignal.isCompleted) cancelSignal.complete();
    final pendingGate = gate;
    if (pendingGate != null && !pendingGate.isCompleted) {
      pendingGate.complete();
    }
    paused = false;
  }
}
