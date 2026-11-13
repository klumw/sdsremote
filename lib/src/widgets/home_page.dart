import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'dart:ui' as ui show Image, ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../app/app_config.dart';
import '../app/app_theme.dart';
import '../app/app_preferences.dart';
import '../app/screen_settings.dart';
import '../app/window_state.dart';
import '../waveform/cursor_geometry.dart';
import 'animated_sync_icon.dart';
import 'home_page_status_bar.dart';
import 'home_page_top_bar.dart';
import 'spectrum_view.dart';
import 'reference_file_picker_dialog.dart';
import 'filename_prefix_dialog.dart';
import 'unsaved_changes_dialog.dart';

import 'package:window_manager/window_manager.dart';

import '../instrument/dart_vxi11.dart';
import '../instrument/screen_report.dart';
import '../instrument/scpi_parser.dart';
import '../instrument/live_screen_controller.dart';
import '../spectrum/spectrum_controller.dart';
import '../spectrum/spectrum_models.dart';
import '../waveform/waveform_acquisition.dart';
import '../waveform/waveform_acquisition_controller.dart';
import '../waveform/waveform_converter.dart';
import '../waveform/waveform_processing.dart';
import '../waveform/waveform_csv_parser.dart';
import '../waveform/waveform_csv_writer.dart';
import '../data_logger/data_logger_csv_writer.dart';
import '../waveform/waveform_models.dart';
import '../waveform/waveform_compare.dart';
import '../waveform/reference_waveform_controller.dart';
import '../waveform/reference_timing.dart';
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
import '../waveform/analysis/digital_measurements.dart';
import '../waveform/analysis/waveform_fault_analyzer.dart';
import '../waveform/analysis/waveform_fault_models.dart';
import '../waveform/analysis/waveform_fault_profile_store.dart';
import 'waveform_export_dialog.dart';
import 'waveform_measurement_panel.dart';
import 'reference_timing_banner.dart';
import 'waveform_analysis_view.dart';
import 'ripple_noise_dialog.dart';
import 'timelapse_dialog.dart';
import '../timelapse/timelapse.dart';
import '../ai/ai_chat_service.dart';
import '../ai/ai_settings.dart';
import '../ai/control_panel_chat_controller.dart';
import '../ai/input_history.dart';
import '../ai/macro_chat_controller.dart';
import '../ai/tools/audio/audio_analysis_context.dart';
import '../audio/frequency_series_service.dart';
import '../audio/vxi11_frequency_series_scope.dart';
import '../ai/tools/digital_frequency_series_tool.dart';
import '../ai/tools/digital_measurement_tools.dart';
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
import 'display_adjust_panel.dart';
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
import '../bode/vxi11_bode_scope.dart';
import '../signal_generator/fy6900_driver.dart';
import '../signal_generator/fy6900_serial_transport.dart';
import '../signal_generator/jds6600_driver.dart';
import '../signal_generator/jds6600_serial_transport.dart';
import '../signal_generator/models.dart';
import '../signal_generator/signal_generator_detector.dart';
import '../signal_generator/signal_generator_service.dart';
import '../signal_generator/signal_generator_shortcut.dart';
import '../signal_generator/siggen_window_coordinator.dart';
import '../signal_generator/siggen_window_launcher.dart';
import 'bode_plot_panel.dart';
import '../app/app_paths.dart';
import '../macro/macro_recorder_models.dart';
import '../macro/macro_print_controller.dart';
import '../macro/macro_debug_controller.dart';
import 'macro_recorder_panel.dart';
import 'macro_editor_panel.dart';
import '../macro/macro_evaluator.dart';
import '../macro/macro_oscope_status.dart';
import '../macro/macro_siggen.dart';
import '../macro/macro_siggen_app.dart';
import '../macro/macro_templates.dart';
import '../voice/voice_input_binding.dart';
import '../voice/voice_input_service.dart';
import '../ai/tools/vxi11_tool.dart' show onScpiCommandSent;

part 'home_page_voice_news.dart';
part 'home_page_child_windows.dart';
part 'home_page_waveform_view.dart';
part 'home_page_chrome.dart';
part 'home_page_chat.dart';
part 'home_page_profiles.dart';
part 'home_page_macro_recorder.dart';
part 'home_page_data_logger.dart';
part 'home_page_settings.dart';
part 'home_page_connection.dart';
part 'home_page_live_screen.dart';
part 'home_page_acquisition.dart';
part 'home_page_spectrum.dart';
part 'home_page_snapshots.dart';
part 'home_page_reference.dart';
part 'home_page_capture_tools.dart';
part 'home_page_save_export.dart';
part 'home_page_init_config.dart';
part 'home_page_ai_service.dart';
part 'home_page_ai_signal_generator.dart';
part 'home_page_ai_waveform_analysis.dart';
part 'home_page_ai_digital.dart';
part 'home_page_ai_audio.dart';
part 'home_page_ai_faults.dart';
part 'home_page_scpi_events.dart';
part 'home_page_cursors_zoom.dart';

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
  SignalGeneratorShortcut _signalGeneratorShortcut =
      SignalGeneratorShortcut.defaultShortcut;

  /// Owns the signal generator's OS child window and command bridge.
  late final SigGenWindowCoordinator _sigGenWindowCoordinator;

  // Engineering calculator OS window (configurable, default Ctrl+R).
  CalculatorWindowLauncher? _calculatorWindowLauncher;
  CalculatorShortcut _calculatorShortcut = CalculatorShortcut.defaultShortcut;

  // AI
  String _aiProvider = '';
  String _aiApiToken = '';
  String _llmModel = '';

  // Acquisition
  /// Owns the acquisition state, derived measurements, and history.
  late final WaveformAcquisitionController _acquisitionController;
  SdsNotification? _latestNews;
  bool _hasUnreadUpdate = false;

  /// Brightness and contrast applied to the displayed screenshot and live
  /// frame. Persisted in `preferences/screen.json`.
  ScreenSettings _screenSettings = ScreenSettings.defaults;

  /// Whether the floating display adjustment panel is open.
  bool _showDisplayAdjust = false;

  /// Top-left position of the display adjustment panel.
  Offset _displayAdjustOffset = Offset.zero;

  /// Settings active when the panel was opened; Cancel restores them.
  ScreenSettings? _displayAdjustOriginal;

  // Live screen (VNC) — four-channel instruments connected over IP only.
  //
  /// Owns the live session, its availability probe, and the last frame.
  late final LiveScreenController _liveScreenController;

  /// Spectrum view state.
  _WaveformViewMode _waveformViewMode = _WaveformViewMode.time;

  /// Owns the spectrum settings, result, and view state.
  late final SpectrumController _spectrumController;

  final GlobalKey _spectrumKey = GlobalKey();

  /// Last four acquisitions for the Waveform AI's history and comparison.
  final WaveformHistoryStore _waveformHistory = WaveformHistoryStore();

  /// Owns the loaded reference waveform and the difference/mask analysis.
  late final ReferenceWaveformController _referenceController;

  /// Channel used as the oscilloscope trigger source (`'ch1'`…`'ch4'`), or
  /// null when the trigger source is not an analog channel.
  String? _triggerSourceChannel;

  DeviceParams? _deviceParams;
  bool _waveformAcquired = false;

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

  /// Owns the Macro Editor's step-by-step debug session and breakpoints.
  late final MacroDebugController _macroDebugController;

  // Macro playback
  Vxi11Instrument? _playbackInstrument;

  Timer? _refreshTimer;
  bool _refreshPending = false;
  static const int _refreshDelayMs = 1758;

  /// Width of the gutter left of the waveform chart that hosts the
  /// per-channel vertical-offset markers.
  static const double _waveformMarkerGutterWidth = 78;

  /// Width of the gutter right of the waveform chart that hosts the original
  /// zero-point marker.
  static const double _waveformZeroMarkerGutterWidth = 24;

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

  // Fields declared later in the original file; order preserved.

  // =========================================================================
  // Macro Recorder
  // =========================================================================

  bool _showMacroEditor = false;

  /// Whether the Macro Editor (rather than the recorder file list) was the
  /// view shown when the macro panel was last left. Reopening the panel
  /// restores exactly that view.
  bool _lastMacroPanelWasEditor = false;

  // Saved Data Logger state for panel reopen
  List<DataLoggerPoint>? _savedDlPoints;
  DataLoggerConfig? _savedDlConfig;
  DataLoggerStatus? _savedDlStatus;
  Set<String>? _savedDlHiddenLines;
  DataLoggerService? _dlService;

  bool _isPinging = false;

  /// Open attempt currently in progress, if any.
  ///
  /// Without this, two callers racing on a cold cache (e.g. the 5 s ping timer
  /// and a user action) would both see [_instrument] == null and both try to
  /// claim the USB interface. One wins, the other fails with
  /// "claim interface 0 ... BUSY" — and its error path then tears down the
  /// shared USB connection the winner is still using.
  Future<Vxi11Instrument?>? _instrumentOpenInFlight;

  /// Threshold for cursor proximity detection (in relative coordinates 0.0-1.0)
  static const double _cursorHitThreshold = 0.02;

  // =========================================================================
  // Helpers
  // =========================================================================

  /// Runs [fn] inside [setState].
  ///
  /// The extension-based parts cannot call the protected [State.setState]
  /// directly; routing through this wrapper keeps `flutter analyze` clean.
  void _setState(VoidCallback fn) => setState(fn);

  void _onMacroDebugChanged() {
    if (mounted) _setState(() {});
  }

  // =========================================================================
  // Lifecycle
  // =========================================================================

  @override
  void initState() {
    super.initState();
    _macroDebugController = MacroDebugController(
      readSource: () => _currentMacroContent,
      beforeStart: () {
        _macroHadPlaybackError = false;
        _macroStatus = null;
        _macroStatusMessage = null;
        _macroPrintController.clear();
      },
      markPlaybackError: () {
        _macroHadPlaybackError = true;
        _macroStatus = 0;
      },
      hasPlaybackError: () => _macroHadPlaybackError,
      onError: _showMacroError,
      onPrint: _macroPrintController.add,
      connectSignalGenerator: _connectMacroSignalGenerator,
      isMacroPlaying: () => _isMacroPlaying,
    );
    _macroDebugController.addListener(_onMacroDebugChanged);
    _sigGenWindowCoordinator = SigGenWindowCoordinator(
      readService: () => _sigGenService,
      canMutate: () => !_bodeIsRunning && !_isMacroPlaying,
      canOpen: () =>
          (_signalGenerator == 'jds6600' || _signalGenerator == 'fy6900') &&
          _sigGenDetected &&
          !_isMacroPlaying,
      isBodeRunning: () => _bodeIsRunning,
      onOpenChanged: (open) {
        if (mounted) _setState(() {});
      },
    );
    _liveScreenController = LiveScreenController(
      readHost: () => _ipAddress,
      couldUseVnc: () => !_isUsb && _isOnline && _numChannels >= 4,
      isControlPanelVisible: () =>
          _activePanel == ActivePanel.none &&
          !_waveformAcquired &&
          _screenDump != null,
      isOnline: () => _isOnline,
      isAcquiring: () => _isAcquiring,
      isAcquiringWaveform: () => _isAcquiringWaveform,
      isProcessingEvent: () => _isProcessingEvent,
      isAutoCaptureEnabled: () => _autoCaptureEnabled,
      stopAutoCapture: _stopAutoCapture,
      setAutoCaptureEnabled: _setAutoCaptureEnabled,
      clearRefreshTimer: () {
        _refreshTimer?.cancel();
        _refreshPending = false;
      },
      acquireScreenDump: ({bool keepPanels = false}) =>
          _acquireScreenDump(keepPanels: keepPanels),
      showInfo: _showInfoSnackBar,
      onChanged: () {
        if (mounted) _setState(() {});
      },
    );
    _spectrumController = SpectrumController(
      readRawData: () => _lastRawData,
      readMeasurements: _acquiredMeasurements,
      isChannelEnabled: (channel) => switch (channel) {
        1 => _ch1Enabled,
        2 => _ch2Enabled,
        3 => _ch3Enabled,
        _ => _ch4Enabled,
      },
      channelCount: () => _numChannels,
      onShowError: _showErrorSnackBar,
      onChanged: () {
        if (mounted) _setState(() {});
      },
    );
    _acquisitionController = WaveformAcquisitionController(
      isChannelEnabled: (channel) => switch (channel) {
        1 => _ch1Enabled,
        2 => _ch2Enabled,
        3 => _ch3Enabled,
        _ => _ch4Enabled,
      },
      channelCount: () => _numChannels,
    );
    _referenceController = ReferenceWaveformController(
      liveWaveformForChannel: (channel) => switch (channel) {
        'ch1' => _waveformCh1,
        'ch2' => _waveformCh2,
        'ch3' => _waveformCh3,
        'ch4' => _waveformCh4,
        _ => null,
      },
      deviceParams: () => _deviceParams,
      acquiredMeasurements: _acquiredMeasurements,
      triggerSourceChannel: () => _triggerSourceChannel,
    );
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
      readVariables: () => _macroDebugController.variables,
      readPrintOutput: () => _macroPrintController.messages,
    );
    _controlPanelChatController.attachOscilloscopeStatus(
      _readOscilloscopeStatus,
    );
    _controlPanelChatController.attachCommandListener(_onControlPanelAiCommand);
    _controlPanelChatController.attachWaveformSummary(_waveformSummaryForAi);
    _controlPanelChatController.attachWaveformAcquisition(
      ({int delaySeconds = 0}) => _acquireWaveformForAi(),
    );
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

  @override
  void dispose() {
    Vxi11Instrument.onUsbConnectionLost = null;
    HardwareKeyboard.instance.removeHandler(_onGlobalKeyEvent);
    // Cancel a paused/running debug session without calling setState during
    // dispose. Its run future closes the instrument and ignores the cleared
    // session.
    _macroDebugController.removeListener(_onMacroDebugChanged);
    _macroDebugController.dispose();
    _sigGenWindowCoordinator.disposeSupport();
    _calculatorWindowLauncher?.dispose();
    _calculatorWindowLauncher = null;
    _sigGenWindowCoordinator.disposeServer();
    _pingTimer?.cancel();
    _refreshTimer?.cancel();
    _autoCaptureTimer?.cancel();
    _liveScreenController.dispose();
    _spectrumController.dispose();
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
    await _sigGenWindowCoordinator.closeWindow();

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
                            referenceTimingNote: _referenceTimingNote,
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
          if (_showDisplayAdjust) ...[
            // Clicking outside the floating panel cancels the adjustment.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _cancelDisplayAdjust,
                onSecondaryTap: _cancelDisplayAdjust,
              ),
            ),
            _buildDisplayAdjustPanel(),
          ],
        ],
      ),
    );
  }

  // =========================================================================
  // Listener-Identity Helpers
  // =========================================================================

  // Registered and removed by identity (HardwareKeyboard / ChangeNotifier).
  // These stay real instance methods: extension tear-offs are not equal
  // across expressions, so removeListener/removeHandler would not match.

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

  /// Global shortcut: the configured combination opens or focuses the signal
  /// generator window.
  ///
  /// The shortcut is intentionally not exposed as a toolbar button.
  bool _onGlobalKeyEvent(KeyEvent event) {
    if (_handleCalculatorShortcut(event)) return true;
    return _handleSignalGeneratorShortcut(event);
  }
}
