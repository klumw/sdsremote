import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:ui' as ui show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'src/app_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'dart_vxi11.dart';
import 'waveform_acquisition.dart';
import 'waveform_converter.dart';
import 'waveform_models.dart';
import 'waveform_painter.dart';
import 'ai_chat_service.dart';
import 'logger.dart';
import 'src/osci_physical_panel.dart';
import 'src/osci_chat_window.dart';
import 'src/osci_help_window.dart';
import 'src/osci_news_notification.dart';
import 'src/osci_device_params_panel.dart';
import 'src/osci_settings_panel.dart';
import 'src/osci_profiles_panel.dart';
import 'src/data_logger_models.dart';
import 'src/data_logger_panel.dart';
import 'src/data_logger_service.dart';
import 'src/data_logger_report.dart';
import 'src/app_paths.dart';
import 'src/macro_recorder_models.dart';
import 'src/macro_recorder_panel.dart';
import 'src/macro_editor_panel.dart';
import 'src/macro_evaluator.dart';
import 'src/vxi11_tool.dart' show onScpiCommandSent;

// ===========================================================================
// Provider Configuration Table
// ===========================================================================

/// Configuration for an AI provider.
///
/// Maps a [providerName] (shown in the UI dropdown) to its [modelPrefix]
/// (used to construct the model string like "openai:gpt-4o") and its
/// [apiKeyName] (the environment variable name like "OPENAI_API_KEY").
class ProviderConfig {
  final String modelPrefix;
  final String providerName;
  final String apiKeyName;

  const ProviderConfig({
    required this.modelPrefix,
    required this.providerName,
    required this.apiKeyName,
  });
}

/// The canonical list of supported AI providers.
///
/// Each entry defines:
/// - [ProviderConfig.modelPrefix]: used to prefix the model name (e.g. "openai:gpt-4o")
/// - [ProviderConfig.providerName]: displayed in the UI dropdown
/// - [ProviderConfig.apiKeyName]: the environment variable name for the API key
const List<ProviderConfig> providerConfigs = [
  ProviderConfig(
    modelPrefix: 'deepseek',
    providerName: 'DeepSeek',
    apiKeyName: 'DEEPSEEK_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'openai',
    providerName: 'OpenAI',
    apiKeyName: 'OPENAI_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'anthropic',
    providerName: 'Anthropic',
    apiKeyName: 'ANTHROPIC_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'google',
    providerName: 'Google',
    apiKeyName: 'GOOGLE_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'mistral',
    providerName: 'Mistral',
    apiKeyName: 'MISTRAL_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'cohere',
    providerName: 'Cohere',
    apiKeyName: 'COHERE_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'edenai',
    providerName: 'EdenAI',
    apiKeyName: 'EDENAI_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'openrouter',
    providerName: 'OpenRouter',
    apiKeyName: 'OPENROUTER_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'xai',
    providerName: 'xAI',
    apiKeyName: 'XAI_API_KEY',
  ),
];

enum ActivePanel { none, help, chat, profiles, dataLogger, macroRecorder }

/// A reusable toolbar button with the standard SDS-Remote dark theme styling.
/// Used in the top bar for Control Panel, Acquire Waveform, AI, Profiles, and Help buttons.
class _OsciToolbarButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final bool alwaysEnabled;

  const _OsciToolbarButton({
    required this.label,
    required this.icon,
    this.onPressed,
    this.alwaysEnabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = !alwaysEnabled && onPressed == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(
              0xFF172A45,
            ).withValues(alpha: isDisabled ? 0.3 : 1.0),
            borderRadius: BorderRadius.circular(8),
            boxShadow: isDisabled
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      offset: const Offset(1, 1),
                      blurRadius: 2,
                    ),
                  ],
            border: Border.all(
              color: const Color(
                0xFF475569,
              ).withValues(alpha: isDisabled ? 0.3 : 1.0),
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDisabled)
                ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.white.withValues(alpha: 0.3),
                    BlendMode.srcIn,
                  ),
                  child: icon,
                )
              else
                icon,
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: isDisabled ? 0.3 : 1.0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Identifies a physical knob on the oscilloscope for the generic
/// [_handleKnobChanged] and [_handleKnobTapped] methods.
enum KnobId {
  intensityAdjust(15),
  ch1Voltage(35),
  ch2Voltage(36),
  ch1Position(43),
  ch2Position(44),
  horizontalTime(7),
  horizontalPosition(10),
  triggerLevel(16);

  final int scpiCommandNumber;
  const KnobId(this.scpiCommandNumber);
}

// ===========================================================================
// Top-level functions (used with compute())
// ===========================================================================

Uint8List _processScreenDump(Uint8List data) {
  final img.Image? decoded = img.decodeImage(data);
  if (decoded == null) return data;
  // Apply slight contrast reduction for better visibility
  img.contrast(decoded, contrast: 90);
  return Uint8List.fromList(img.encodePng(decoded));
}

WaveformData? _convertChannel({
  required Uint8List? rawData,
  required double? vdiv,
  required double? voffset,
  required double trdl,
  required double timebase,
  required double sampleRate,
  required int triggerPosition,
}) {
  if (rawData == null || vdiv == null || voffset == null) return null;
  final voltages = WaveformConverter.convertVoltages(rawData, vdiv, voffset);
  final times = WaveformConverter.computeTimeAxis(
    voltages.length,
    trdl,
    timebase,
    sampleRate,
    triggerPosition: triggerPosition,
  );
  final combined = WaveformConverter.combine(times, voltages);
  // Downsample to 50% by taking every 2nd point
  final downsampled = <(double, double)>[
    for (var i = 0; i < combined.length; i += 2) combined[i],
  ];
  return WaveformData(points: downsampled);
}

(WaveformData?, WaveformData?, DeviceParams) _convertRawData(
  WaveformRawData raw,
) {
  final ch1 = _convertChannel(
    rawData: raw.ch1Raw,
    vdiv: raw.vdivCh1,
    voffset: raw.voffsetCh1,
    trdl: raw.trdl,
    timebase: raw.timebase,
    sampleRate: raw.sampleRate,
    triggerPosition: raw.triggerPosition,
  );
  final ch2 = _convertChannel(
    rawData: raw.ch2Raw,
    vdiv: raw.vdivCh2,
    voffset: raw.voffsetCh2,
    trdl: raw.trdl,
    timebase: raw.timebase,
    sampleRate: raw.sampleRate,
    triggerPosition: raw.triggerPosition,
  );

  final params = DeviceParams(
    vdivCh1: raw.vdivCh1,
    voffsetCh1: raw.voffsetCh1,
    vdivCh2: raw.vdivCh2,
    voffsetCh2: raw.voffsetCh2,
    timebase: raw.timebase,
    trdl: raw.trdl,
    sampleRate: raw.sampleRate,
  );

  return (ch1, ch2, params);
}

/// Parses a waveform CSV file content and returns (ch1Points, ch2Points).
/// Returns null if the CSV is unparseable or has no data rows.
///
/// The CSV format is:
///   # comment lines (ignored)
///   Time (s),CH1 (V),CH2 (V)
///   0,0.16,1.24
///   0.000000002,-1.12,1.20
///
/// Both channels may be present, one may be empty, or one may be missing.
(List<(double, double)>?, List<(double, double)>?) _parseWaveformCsv(
  String content,
) {
  final lines = content.split('\n');
  List<(double, double)>? ch1;
  List<(double, double)>? ch2;

  bool inData = false;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (!inData) {
      // Validate the CSV header exactly matches the expected format.
      if (trimmed == 'Time (s),CH1 (V),CH2 (V)') {
        inData = true;
        ch1 = [];
        ch2 = [];
      } else if (trimmed.contains(',') &&
          (trimmed.toLowerCase().contains('time') ||
              trimmed.toLowerCase().contains('ch1') ||
              trimmed.toLowerCase().contains('ch2'))) {
        // Looks like a header row but doesn't match — reject the file.
        return (null, null);
      }
      continue;
    }

    final parts = trimmed.split(',');
    if (parts.length < 3) continue;

    final time = double.tryParse(parts[0].trim());
    if (time == null) continue;

    final ch1Str = parts[1].trim();
    final ch2Str = parts[2].trim();

    if (ch1Str.isNotEmpty) {
      final v = double.tryParse(ch1Str);
      if (v != null) ch1?.add((time, v));
    }
    if (ch2Str.isNotEmpty) {
      final v = double.tryParse(ch2Str);
      if (v != null) ch2?.add((time, v));
    }
  }

  // Return null lists as null so caller knows they're unavailable
  final hasCh1 = ch1 != null && ch1.isNotEmpty;
  final hasCh2 = ch2 != null && ch2.isNotEmpty;
  if (!hasCh1 && !hasCh2) return (null, null);
  return (hasCh1 ? ch1 : null, hasCh2 ? ch2 : null);
}

/// A simple dialog that lists CSV waveform files and lets the user pick one.
class _ReferenceFilePickerDialog extends StatelessWidget {
  final List<File> files;
  const _ReferenceFilePickerDialog({required this.files});

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Select Waveform CSV'),
      children: files.map((file) {
        final name = file.uri.pathSegments.last;
        return SimpleDialogOption(
          onPressed: () => Navigator.pop(context, file.path),
          child: Text(name, style: const TextStyle(fontSize: 13)),
        );
      }).toList(),
    );
  }
}

/// A dialog that prompts for a filename prefix with validation.
///
/// Only allows [a-zA-Z0-9_-], max 30 characters.
/// Returns the entered prefix on confirm, or null on cancel.
class _FilenamePrefixDialog extends StatefulWidget {
  const _FilenamePrefixDialog();

  @override
  State<_FilenamePrefixDialog> createState() => _FilenamePrefixDialogState();
}

class _FilenamePrefixDialogState extends State<_FilenamePrefixDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  static final _validChars = RegExp(r'^[a-zA-Z0-9_-]*$');

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSubmit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _errorText = 'Prefix cannot be empty');
      return;
    }
    if (text.length > 30) {
      setState(() => _errorText = 'Max 30 characters allowed');
      return;
    }
    if (!_validChars.hasMatch(text)) {
      setState(
        () => _errorText = 'Only a-z, A-Z, 0-9, underscore and hyphen allowed',
      );
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filename Prefix'),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: 'e.g. lab_measurement_1',
          errorText: _errorText,
        ),
        autofocus: true,
        onSubmitted: (_) => _onSubmit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _onSubmit, child: const Text('Save')),
      ],
    );
  }
}

/// Actions the user can take when closing with unsaved macro changes.
enum _UnsavedMacroAction { save, discard }

/// A dialog shown when the user tries to close the app while a macro has
/// unsaved changes, prompting them to save, discard, or cancel.
class _UnsavedChangesDialog extends StatelessWidget {
  const _UnsavedChangesDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unsaved Macro Changes'),
      content: const Text(
        'The current macro has unsaved changes.\n'
        'Do you want to save before closing?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _UnsavedMacroAction.discard),
          child: const Text('Discard'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _UnsavedMacroAction.save),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// ===========================================================================
// Application Entry Point
// ===========================================================================

Level _getRequestedLogLevel(List<String> args) {
  // 1. Check --dart-define=loglevel=VALUE (compile-time constant).
  const dartDefineLevel = String.fromEnvironment('loglevel');
  if (dartDefineLevel.isNotEmpty) {
    return AppLogger.parseLevel(dartDefineLevel);
  }

  // 2. Check runtime CLI arguments (--loglevel=VALUE or --loglevel VALUE).
  final cliArgs = args.isNotEmpty ? args : Platform.executableArguments;
  for (var index = 0; index < cliArgs.length; index++) {
    final arg = cliArgs[index];
    if (arg.startsWith('--loglevel=')) {
      return AppLogger.parseLevel(arg.substring('--loglevel='.length));
    }
    if (arg == '--loglevel' && index + 1 < cliArgs.length) {
      return AppLogger.parseLevel(cliArgs[index + 1]);
    }
  }
  return AppLogger.parseLevel(null);
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final logLevel = _getRequestedLogLevel(args);
  AppLogger.minimumLevel = logLevel;
  Agent.loggingOptions = LoggingOptions(
    level: AppLogger.traceLevel,
    onRecord: (record) {
      final logger = AppLogger(agentName: 'AI', toolName: record.loggerName);
      final message = record.message;
      if (record.level >= Level.FINE) {
        logger.debug(message);
      } else {
        logger.trace(message);
      }
    },
  );

  AppLogger().info('SDS-Remote: application starting');

  const windowOptions = WindowOptions(
    size: Size(1400, 900),
    minimumSize: Size(1400, 900),
    title: 'SDS-Remote',
    center: true,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const OscilloscopeApp());
}

// ===========================================================================
// Root Application Widget
// ===========================================================================

class OscilloscopeApp extends StatelessWidget {
  const OscilloscopeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SDS-Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
      ),
      home: const OsciHomePage(),
    );
  }
}

// ===========================================================================
// Main Home Page
// ===========================================================================

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
  Vxi11Instrument? _instrument;

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
  DeviceParams? _deviceParams;
  bool _waveformAcquired = false;

  // Reference waveform
  WaveformData? _refWaveform;
  bool _refVisible = false;
  String? _refFileName;
  String? _refChannelOrigin; // 'ch1' or 'ch2'

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
  bool _isRunningDiagnostic = false;
  List<String> _diagnosticResults = [];

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'News service is currently unavailable. Please check your connection.',
            ),
            backgroundColor: Color(0xFF1E293B),
            duration: Duration(seconds: 3),
          ),
        );
      }
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
    _pingTimer?.cancel();
    _refreshTimer?.cancel();
    _closeInstrument();
    _aiChatService.dispose();
    _dlAnimationController.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // If a macro has unsaved changes, prompt the user before closing.
    if (_isMacroModified) {
      final action = await showDialog<_UnsavedMacroAction>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const _UnsavedChangesDialog(),
      );

      switch (action) {
        case _UnsavedMacroAction.save:
          await _saveMacro();
          // If the save was cancelled (e.g. filename dialog dismissed),
          // abort the close.
          if (_isMacroModified) return;
          break;
        case _UnsavedMacroAction.discard:
          break;
        case null:
          // User cancelled — keep the app open.
          return;
      }
    }

    await AppLogger().log('SDS-Remote: application stopping');
    await windowManager.destroy();
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
                          color: const Color(0xFF0A192F),
                          border: Border.all(
                            color: const Color(0xFF475569),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: _activePanel == ActivePanel.help
                              ? _buildHelpWindow()
                              : _activePanel == ActivePanel.chat
                              ? _buildChatWindow()
                              : _activePanel == ActivePanel.profiles
                              ? _buildProfilesWindow()
                              : _activePanel == ActivePanel.dataLogger
                              ? _buildDataLoggerWindow()
                              : _activePanel == ActivePanel.macroRecorder
                              ? _buildMacroRecorderWindow()
                              : _waveformAcquired
                              ? AspectRatio(
                                  aspectRatio: 14 / 8,
                                  child: RepaintBoundary(
                                    key: _waveformKey,
                                    child: MouseRegion(
                                      cursor: _hoveredCursorType == 'x'
                                          ? SystemMouseCursors.resizeColumn
                                          : _hoveredCursorType == 'y'
                                          ? SystemMouseCursors.resizeRow
                                          : _hoveredCursorType == 'info'
                                          ? SystemMouseCursors.move
                                          : SystemMouseCursors.basic,
                                      onHover: _onCursorHover,
                                      child: GestureDetector(
                                        onPanStart: _onCursorDragStart,
                                        onPanUpdate: _onCursorDragUpdate,
                                        onPanEnd: _onCursorDragEnd,
                                        child: Stack(
                                          children: [
                                            RepaintBoundary(
                                              child: CustomPaint(
                                                painter: WaveformBasePainter(
                                                  ch1: _waveformCh1,
                                                  ch2: _waveformCh2,
                                                  ref: _refWaveform,
                                                  refVisible: _refVisible,
                                                  refChannelOrigin:
                                                      _refChannelOrigin,
                                                  params: _deviceParams!,
                                                  ch1Enabled: _ch1Enabled,
                                                  ch2Enabled: _ch2Enabled,
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
                                                dataTMin:
                                                    _waveformCh1
                                                        ?.points
                                                        .first
                                                        .$1 ??
                                                    _waveformCh2
                                                        ?.points
                                                        .first
                                                        .$1,
                                                dataTMax:
                                                    _waveformCh1
                                                        ?.points
                                                        .last
                                                        .$1 ??
                                                    _waveformCh2
                                                        ?.points
                                                        .last
                                                        .$1,
                                              ),
                                              child: const SizedBox.expand(),
                                            ),
                                            // Horizontal pan slider (only visible when zoomed)
                                            if (_zoomState.zoomFactor > 1.0)
                                              Positioned(
                                                left: 0,
                                                right: 0,
                                                bottom: 0,
                                                height: 24,
                                                child:
                                                    _buildHorizontalPanSlider(),
                                              ),
                                            // Vertical pan slider (only visible when zoomed)
                                            if (_zoomState.zoomFactor > 1.0)
                                              Positioned(
                                                top: 0,
                                                bottom: 24,
                                                right: 0,
                                                width: 24,
                                                child:
                                                    _buildVerticalPanSlider(),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : _screenDump != null
                              ? PhysicalControlPanel(
                                  isOnline: _isOnline,
                                  isProcessingEvent: _isProcessingEvent,
                                  screenDump: _screenDump!,
                                  ch1Enabled: _ch1Enabled,
                                  ch2Enabled: _ch2Enabled,
                                  onChannelToggle: _handleButtonPress,
                                  onSoftKeyPressed: _handleSoftKeyPress,
                                  onMenuPressed: _handleMenuPress,
                                  onKnobChanged: _handleKnobChanged,
                                  onKnobTapped: _handleKnobTapped,
                                  onMenuButtonPressed: _handleButtonPress,
                                  onVerticalButtonPressed: _handleButtonPress,
                                  onHorizontalButtonPressed: _handleButtonPress,
                                  onTriggerButtonPressed: _handleButtonPress,
                                )
                              : Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Opacity(
                                        opacity: 0.8,
                                        child: Image.asset(
                                          'assets/sds-remote.png',
                                          width: 400,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        "Version 0.2.4",
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.4,
                                          ),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w300,
                                          letterSpacing: 1.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                      ),
                    ),
                    if (_waveformAcquired &&
                        _activePanel == ActivePanel.none &&
                        _deviceParams != null)
                      DeviceParametersPanel(
                        params: _deviceParams!,
                        ch1Enabled: _ch1Enabled,
                        ch2Enabled: _ch2Enabled,
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

  // =========================================================================
  // Top Bar
  // =========================================================================

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0A192F),
        border: Border(
          bottom: BorderSide(color: Color(0xFF475569), width: 1.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  _OsciToolbarButton(
                    label: _isAcquiring ? "Acquiring..." : "Control Panel",
                    icon: _isAcquiring
                        ? const SizedBox(
                            width: 25,
                            height: 25,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.tune, size: 25),
                    onPressed: (_isAcquiring || !_isOnline || _isMacroPlaying)
                        ? null
                        : _acquireScreenDump,
                  ),
                  const SizedBox(width: 16),
                  _OsciToolbarButton(
                    label: _isAcquiringWaveform
                        ? "Acquiring..."
                        : "Acquire Waveform",
                    icon: _isAcquiringWaveform
                        ? const SizedBox(
                            width: 25,
                            height: 25,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.show_chart, size: 25),
                    onPressed:
                        (_isAcquiringWaveform || !_isOnline || _isMacroPlaying)
                        ? null
                        : _acquireWaveform,
                  ),
                  const SizedBox(width: 16),
                  _OsciToolbarButton(
                    label: "AI",
                    icon: const Icon(Icons.auto_awesome, size: 25),
                    onPressed: (_isAiEnabled && !_isMacroPlaying)
                        ? () => _togglePanel(ActivePanel.chat)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  _OsciToolbarButton(
                    label: "Profiles",
                    icon: const Icon(Icons.save, size: 25),
                    onPressed: (_isOnline && !_isMacroPlaying)
                        ? () => _togglePanel(ActivePanel.profiles)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  _OsciToolbarButton(
                    label: "Data Logger",
                    icon: _buildDlButtonIcon(),
                    onPressed: (_isOnline && !_isMacroPlaying)
                        ? () => _togglePanel(ActivePanel.dataLogger)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  _OsciToolbarButton(
                    label: _isMacroPlaying
                        ? "Playback"
                        : (_isMacroRecording
                              ? "Recording..."
                              : "Macro Recorder"),
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
              ),
            ),
          ),
          _OsciToolbarButton(
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
                : (_canSaveStandard || _canSaveDataLoggerReport)
                ? Colors.white70
                : Colors.white24,
            tooltip: 'Save',
            onPressed:
                (_isMacroPlaying ||
                    !(_canSaveStandard || _canSaveDataLoggerReport))
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
        color: Color(0xFF151515),
        border: Border(top: BorderSide(color: Colors.white12, width: 2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (!_isUsb)
            Row(
              children: [
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
              ],
            )
          else
            Row(
              children: [
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Macro playback stopped'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      } else if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Macro playback completed'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Macro error: $message'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Macro "$_loadedMacroFileName" saved.')),
          );
        }
      } catch (e) {
        AppLogger().log('Save macro error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Save macro failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      return;
    }

    // No loaded filename — ask for a name via the prefix dialog.
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _FilenamePrefixDialog(),
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Macro "$name" saved.')));
      }
    } catch (e) {
      AppLogger().log('Save macro error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save macro failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Load macro failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
      if (mounted) {
        AppLogger().log('Profile "$name" saved successfully.');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Profile "$name" saved.')));
      }
    } catch (e) {
      AppLogger().log('Save profile error: $e');
      if (mounted) {
        AppLogger().log('Popup: Save profile failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save profile failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (_isUsb) {
        await _closeInstrument();
      }
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

      if (mounted) {
        AppLogger().log('Profile "$fileName" loaded successfully.');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Profile "$fileName" loaded.')));
      }
      // Refresh screen dump after loading profile
      _scheduleRefresh();
    } catch (e) {
      AppLogger().log('Load profile error: $e');
      if (mounted) {
        AppLogger().log('Popup: Load profile failed: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Load profile failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (_isUsb) {
        await _closeInstrument();
      }
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
      providerNames: providerConfigs.map((c) => c.providerName).toList(),
      selectedProvider: _aiProvider,
      aiApiToken: _aiApiToken,
      llmModel: _llmModel,
      saveWithParams: _saveWithParams,
      askForFilenamePrefix: _askForFilenamePrefix,
      isRunningDiagnostic: _isRunningDiagnostic,
      diagnosticResults: _diagnosticResults,
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
      onRunDiagnostic: _runConnectionDiagnostic,
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
    if (_isPinging || _isAcquiring || _isAcquiringWaveform) return;
    _isPinging = true;

    try {
      if (_isUsb) {
        final address = await Vxi11Instrument.detectLiveVisaAddress();
        if (mounted) {
          setState(() => _isOnline = address != null);
          if (address != null) {
            if (_deviceName == null) {
              _updateWindowTitle();
            } else {
              windowManager.setTitle(_deviceName!);
            }
          } else {
            windowManager.setTitle('SDS-Remote');
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
            _updateWindowTitle();
          } else {
            windowManager.setTitle(_deviceName!);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isOnline = false);
        windowManager.setTitle('SDS-Remote');
      }
    } finally {
      _isPinging = false;
    }
  }

  Future<void> _updateWindowTitle() async {
    try {
      // Use the cached instrument to avoid creating a separate USB connection
      // that would fight with the kernel driver detach/attach cycle.
      final instr = _instrument ?? await _getInstrument();
      if (instr == null) {
        if (_isUsb) {
          windowManager.setTitle('SDS-Remote — USB');
        } else {
          windowManager.setTitle('SDS-Remote — $_ipAddress');
        }
        return;
      }
      await instr.writeString('*IDN?');
      final idn = (await instr.readString()).trim();
      final parts = idn.split(',');
      final name = parts.length >= 2
          ? '${parts[0].trim()} ${parts[1].trim()}'
          : idn;
      if (mounted) {
        _deviceName = name;
        windowManager.setTitle(name);
      }
    } catch (_) {
      if (mounted) {
        if (_isUsb) {
          windowManager.setTitle('SDS-Remote — USB');
        } else {
          windowManager.setTitle('SDS-Remote — $_ipAddress');
        }
      }
    }
  }

  Future<void> _acquireScreenDump({bool keepPanels = false}) async {
    if (_isAcquiring) return;

    // Stop the Data Logger immediately when switching away from it
    if (!keepPanels && _activePanel == ActivePanel.dataLogger) {
      _stopDataLoggerIfRunning();
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

      final processedData = await compute(_processScreenDump, data);

      if (mounted) {
        setState(() {
          _screenDump = processedData;
          _waveformCh1 = null;
          _waveformCh2 = null;
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
      if (_isUsb) {
        await _closeInstrument();
      }
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

    setState(() {
      _isAcquiringWaveform = true;
      _activePanel = ActivePanel.none;
      _previousPanel = ActivePanel.none;
    });

    try {
      final instr = await _getInstrument();
      final raw = await WaveformAcquisition(
        _ipAddress,
      ).acquire(ch1: _ch1Enabled, ch2: _ch2Enabled, instr: instr);

      // Run conversion on the main thread instead of via compute() because
      // Dart's isolate serialization does not support record types
      // ((double, double) pairs) — they get silently truncated to ~726 points
      // instead of the full 1201 points sent by the scope (WFSU NP=1201).
      final result = _convertRawData(raw);

      setState(() {
        _waveformCh1 = result.$1;
        _waveformCh2 = result.$2;
        _deviceParams = result.$3;
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
      if (mounted) {
        final reason = e is AcquisitionException ? e.reason : e.toString();
        AppLogger().log('Popup: Waveform error: $reason');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Waveform error: $reason'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (_isUsb) {
        await _closeInstrument();
      }
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

  Future<void> _saveCurrentView() async {
    if (_canSaveDataLoggerReport) {
      await _saveDataLoggerReport();
    } else if (_screenDump != null) {
      await _saveScreenDump();
    } else if (_waveformCh1 != null || _waveformCh2 != null) {
      await _saveWaveform();
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
      builder: (_) => const _FilenamePrefixDialog(),
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
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved $fileName')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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

      // Always save waveform data as CSV alongside the PNG, including device
      // parameters (Timebase, Trigger Delay, Sample Rate, V/div and Offset per channel).
      final csvBuffer = StringBuffer();
      csvBuffer.writeln('# SDS-Remote Waveform Data');
      csvBuffer.writeln('# Saved: ${DateTime.now().toIso8601String()}');
      csvBuffer.writeln('# Device: ${_deviceName ?? _ipAddress}');
      if (_deviceParams != null) {
        csvBuffer.writeln('# Timebase: ${_deviceParams!.timebase} s/div');
        csvBuffer.writeln('# Trigger Delay: ${_deviceParams!.trdl} s');
        csvBuffer.writeln('# Sample Rate: ${_deviceParams!.sampleRate} Sa/s');
        if (_deviceParams!.vdivCh1 != null) {
          csvBuffer.writeln('# CH1 V/div: ${_deviceParams!.vdivCh1} V');
          csvBuffer.writeln('# CH1 Offset: ${_deviceParams!.voffsetCh1} V');
        }
        if (_deviceParams!.vdivCh2 != null) {
          csvBuffer.writeln('# CH2 V/div: ${_deviceParams!.vdivCh2} V');
          csvBuffer.writeln('# CH2 Offset: ${_deviceParams!.voffsetCh2} V');
        }
      }
      csvBuffer.writeln('# Cursors X Enabled: ${_cursorState.cursorsXEnabled}');
      csvBuffer.writeln('# Cursors Y Enabled: ${_cursorState.cursorsYEnabled}');
      csvBuffer.writeln('#');
      csvBuffer.writeln('Time (s),CH1 (V),CH2 (V)');

      // Determine the maximum number of points across both channels
      final int maxPoints = [
        if (_waveformCh1 != null) _waveformCh1!.points.length,
        if (_waveformCh2 != null) _waveformCh2!.points.length,
      ].fold(0, (a, b) => a > b ? a : b);

      // CSV time starts at 0 and increments by 1/sampleRate for each sample.
      final csvDt = _deviceParams != null
          ? 1.0 / _deviceParams!.sampleRate
          : 0.0;
      for (int i = 0; i < maxPoints; i++) {
        final time = i * csvDt;
        final ch1V = _waveformCh1 != null && i < _waveformCh1!.points.length
            ? _waveformCh1!.points[i].$2.toStringAsFixed(6)
            : '';
        final ch2V = _waveformCh2 != null && i < _waveformCh2!.points.length
            ? _waveformCh2!.points[i].$2.toStringAsFixed(6)
            : '';
        csvBuffer.writeln('$time,$ch1V,$ch2V');
      }

      final csvDir = await AppPaths.getOrCreateWaveformCsvDir();
      final csvFile = await AppPaths.getUniqueFilePath(
        csvDir,
        csvBaseName,
        'csv',
      );
      await csvFile.writeAsString(csvBuffer.toString());
      final csvName = csvFile.uri.pathSegments.last;

      if (mounted) {
        final msg = 'Saved $pngName + $csvName';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Writes a CSV file with the data logger's recorded data points.
  ///
  /// Returns the saved filename (e.g. `data_logger_data.csv` or
  /// `data_logger_data(1).csv` if the original name was already taken).
  ///
  /// Only includes columns for measurements that are enabled in the config
  /// AND not hidden via the chip toggle buttons ([_savedDlHiddenLines]).
  Future<String> _saveDataLoggerCsv(
    Directory dir,
    DataLoggerConfig config,
    List<DataLoggerPoint> points, [
    String baseName = 'data_logger_data',
  ]) async {
    final hidden = _savedDlHiddenLines ?? <String>{};
    final csvBuffer = StringBuffer();

    // ---- Header comments ----
    csvBuffer.writeln('# SDS-Remote Data Logger Data');
    csvBuffer.writeln('# Saved: ${DateTime.now().toIso8601String()}');
    csvBuffer.writeln('# Device: ${_deviceName ?? _ipAddress}');
    csvBuffer.writeln('# Duration: ${config.durationMinutes} min');
    csvBuffer.writeln('# Interval: ${config.intervalSeconds} s');
    if (config.description.isNotEmpty) {
      csvBuffer.writeln('# Description: ${config.description}');
    }
    csvBuffer.writeln('#');

    // Determine which columns to include based on config AND chip visibility.
    final columns = <String>[];
    final getters = <String, double? Function(DataLoggerPoint)>{};

    columns.add('Time (s)');
    // (no getter for time — handled inline)

    if (config.ch1VppEnabled && !hidden.contains('ch1_vpp')) {
      columns.add('CH1 Vpp (V)');
      getters['CH1 Vpp (V)'] = (p) => p.ch1Vpp;
    }
    if (config.ch1MeanEnabled && !hidden.contains('ch1_mean')) {
      columns.add('CH1 Mean (V)');
      getters['CH1 Mean (V)'] = (p) => p.ch1Mean;
    }
    if (config.ch1RmsEnabled && !hidden.contains('ch1_rms')) {
      columns.add('CH1 Rms (V)');
      getters['CH1 Rms (V)'] = (p) => p.ch1Rms;
    }
    if (config.ch1DutyEnabled && !hidden.contains('ch1_duty')) {
      columns.add('CH1 Duty (%)');
      getters['CH1 Duty (%)'] = (p) => p.ch1Duty;
    }
    if (config.ch1FreqEnabled && !hidden.contains('ch1_freq')) {
      columns.add('CH1 Freq (Hz)');
      getters['CH1 Freq (Hz)'] = (p) => p.ch1Freq;
    }
    if (config.ch2VppEnabled && !hidden.contains('ch2_vpp')) {
      columns.add('CH2 Vpp (V)');
      getters['CH2 Vpp (V)'] = (p) => p.ch2Vpp;
    }
    if (config.ch2MeanEnabled && !hidden.contains('ch2_mean')) {
      columns.add('CH2 Mean (V)');
      getters['CH2 Mean (V)'] = (p) => p.ch2Mean;
    }
    if (config.ch2RmsEnabled && !hidden.contains('ch2_rms')) {
      columns.add('CH2 Rms (V)');
      getters['CH2 Rms (V)'] = (p) => p.ch2Rms;
    }
    if (config.ch2DutyEnabled && !hidden.contains('ch2_duty')) {
      columns.add('CH2 Duty (%)');
      getters['CH2 Duty (%)'] = (p) => p.ch2Duty;
    }
    if (config.ch2FreqEnabled && !hidden.contains('ch2_freq')) {
      columns.add('CH2 Freq (Hz)');
      getters['CH2 Freq (Hz)'] = (p) => p.ch2Freq;
    }

    // CSV header row
    csvBuffer.writeln(columns.join(','));

    // Data rows
    for (final point in points) {
      final row = <String>[point.elapsedSeconds.toStringAsFixed(1)];
      for (final col in columns.skip(1)) {
        final getter = getters[col];
        if (getter == null) continue;
        final value = getter(point);
        if (value == null) {
          row.add('');
        } else {
          row.add(value.toStringAsFixed(6));
        }
      }
      csvBuffer.writeln(row.join(','));
    }

    final csvFile = await AppPaths.getUniqueFilePath(dir, baseName, 'csv');
    await csvFile.writeAsString(csvBuffer.toString());
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
    setState(() {
      _ipAddress = ip ?? '192.168.1.100';
      _isUsb = isUsb ?? false;
      Vxi11Instrument.isUsbMode = _isUsb;
      _aiProvider = provider ?? '';
      _aiApiToken = token ?? '';
      _llmModel = model ?? '';
      _saveWithParams = saveWithParams ?? false;
      _askForFilenamePrefix = askForFilenamePrefix ?? false;
    });
  }

  Future<void> _saveConfig() async {
    await AppPreferences.setAll({
      'osci_ip': _ipAddress,
      'osci_is_usb': _isUsb,
      'ai_provider': _aiProvider,
      'ai_api_token': _aiApiToken,
      'llm_model': _llmModel,
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
      final panelHeight = 600.0; // Approximate height of the settings panel

      final centerX = (windowSize.width - panelWidth) / 2;
      final centerY = (windowSize.height - panelHeight) / 2;

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

  // =========================================================================
  // Connection Diagnostic
  // =========================================================================

  Future<void> _runConnectionDiagnostic() async {
    setState(() {
      _isRunningDiagnostic = true;
      _diagnosticResults = [];
    });

    try {
      final instr = Vxi11Instrument(_ipAddress, sourceLabel: 'diag');
      final results = await instr.testConnection(timeoutSeconds: 5.0);
      setState(() {
        _diagnosticResults = results;
      });
    } catch (e) {
      setState(() {
        _diagnosticResults.add('FAILURE: Connection diagnostic failed: $e');
      });
    } finally {
      setState(() {
        _isRunningDiagnostic = false;
      });
    }
  }

  Future<Vxi11Instrument?> _getInstrument() async {
    if (_instrument != null) return _instrument;
    try {
      final instr = Vxi11Instrument(_ipAddress, sourceLabel: 'getInstrument');
      await instr.open(timeoutSeconds: 5.0);
      _instrument = instr;
      return _instrument;
    } catch (e) {
      AppLogger().log('Failed to open VXI-11 connection: $e');
      setState(() => _isOnline = false);
      return null;
    }
  }

  Future<void> _closeInstrument() async {
    if (_instrument != null) {
      final instr = _instrument!;
      _instrument = null;
      try {
        await instr.close();
      } catch (e) {
        AppLogger().log('Error closing instrument: $e');
      }
    }
  }

  void _scheduleRefresh() {
    if (_refreshPending) return;
    _refreshPending = true;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(Duration(milliseconds: _refreshDelayMs), () {
      _refreshPending = false;
      if (mounted && _isOnline && !_isAcquiringWaveform) {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device is offline'),
          backgroundColor: Colors.red,
        ),
      );
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
      if (mounted) {
        AppLogger().log('Popup: Failed to send command: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send command: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    } finally {
      if (_isUsb) {
        await _closeInstrument();
      }
    }
  }

  /// Handles soft key button press (M1-M6).
  /// Sends $$SY_FP X,1 command where X is button number, then refreshes screen.
  void _handleSoftKeyPress(int buttonNumber) async {
    // Discard event if already processing another event or offline
    if (_isProcessingEvent || !_isOnline) {
      return;
    }

    _isProcessingEvent = true;
    if (mounted) setState(() {});

    try {
      // Send the SCPI command
      final command = '\$\$SY_FP $buttonNumber,1';
      final success = await _sendCommand(command);

      if (success) {
        // Wait for oscilloscope to process the command
        await Future.delayed(const Duration(milliseconds: _refreshDelayMs));
        // Fetch the screen dump synchronously
        await _acquireScreenDump(keepPanels: true);
        // Final cooldown before next event is allowed
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      AppLogger().log('Soft key handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing button M$buttonNumber: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _isProcessingEvent = false;
      if (mounted) setState(() {});
    }
  }

  /// Handles MENU button press.
  /// Sends $$SY_FP 0,1 command (VXI special SPCI command for MENU button),
  /// then immediately requests a screen dump image.
  void _handleMenuPress() async {
    // Discard event if already processing another event or offline
    if (_isProcessingEvent || !_isOnline) {
      return;
    }

    _isProcessingEvent = true;
    if (mounted) setState(() {});

    try {
      // Send the VXI special SPCI command for MENU button
      final command = '\$\$SY_FP 0,1';
      final success = await _sendCommand(command);

      if (success) {
        // Wait for oscilloscope to process the command
        await Future.delayed(const Duration(milliseconds: _refreshDelayMs));
        // Fetch the screen dump synchronously
        await _acquireScreenDump(keepPanels: true);
        // Final cooldown before next event is allowed
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      AppLogger().log('MENU button handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing MENU button: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _isProcessingEvent = false;
      if (mounted) setState(() {});
    }
  }

  /// Handles Intensity/Adjust knob turned right or left.
  /// Sends $$SY_FP 15,1 command when turned right (value increases)
  /// Sends $$SY_FP 15,-1 command when turned left (value decreases)
  /// then immediately requests a screen dump image.
  /// Reuses functionality from button M1.
  /// Generic handler for knob rotation (value changes).
  /// Sends `$$SY_FP <cmd>,1` when turned right or `$$SY_FP <cmd>,-1` when left.
  Future<void> _handleKnobChanged(KnobId knob, double newValue) async {
    final prev = _knobPreviousValues[knob]!;
    if (newValue == prev || !_isOnline || _isProcessingEvent) return;

    _isProcessingEvent = true;
    if (mounted) setState(() {});
    try {
      final dir = newValue > prev ? 1 : -1;
      final command = '\$\$SY_FP ${knob.scpiCommandNumber},$dir';
      if (await _sendCommand(command)) {
        // Wait for oscilloscope to process the command
        await Future.delayed(const Duration(milliseconds: _refreshDelayMs));
        // Fetch the screen dump synchronously
        await _acquireScreenDump(keepPanels: true);
        // Final cooldown before next event is allowed
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      AppLogger().log('${knob.name} knob handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing ${knob.name} knob: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _isProcessingEvent = false;
      if (mounted) setState(() {});
    }
    _knobPreviousValues[knob] = newValue;
  }

  /// Generic handler for knob tap/click.
  /// Sends `$$SY_FP <cmd>,0`.
  Future<void> _handleKnobTapped(KnobId knob) async {
    if (!_isOnline || _isProcessingEvent) return;

    _isProcessingEvent = true;
    if (mounted) setState(() {});
    try {
      final command = '\$\$SY_FP ${knob.scpiCommandNumber},0';
      if (await _sendCommand(command)) {
        // Wait for oscilloscope to process the command
        await Future.delayed(const Duration(milliseconds: _refreshDelayMs));
        // Fetch the screen dump synchronously
        await _acquireScreenDump(keepPanels: true);
        // Final cooldown before next event is allowed
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      AppLogger().log('${knob.name} knob tap handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing ${knob.name} knob tap: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _isProcessingEvent = false;
      if (mounted) setState(() {});
    }
  }

  // =========================================================================
  // Button Operations (generic handler)
  // =========================================================================

  /// Maps button labels to their SCPI command strings.
  static const Map<String, String> _buttonCommands = {
    // Menu buttons
    'Cursors': '\$\$SY_FP 22,1',
    'Acquire': '\$\$SY_FP 27,1',
    'Save/Recall': '\$\$SY_FP 28,1',
    'Measure': '\$\$SY_FP 26,1',
    'Clear Sweeps': '\$\$SY_FP 47,1',
    'Utility': '\$\$SY_FP 24,1',
    'Default': '\$\$SY_FP 13,1',
    'Display/Persist': '\$\$SY_FP 23,1',
    'Print': '\$\$SY_FP 25,1',
    // Vertical buttons
    'Math': '\$\$SY_FP 31,1',
    'Ref': '\$\$SY_FP 32,1',
    'History': '\$\$SY_FP 48,1',
    'Decode': '\$\$SY_FP 29,1',
    'Run/Stop': '\$\$SY_FP 12,1',
    'Auto\nSetup': '\$\$SY_FP 11,1',
    // Horizontal buttons
    'Roll': '\$\$SY_FP 49,1',
    // Trigger buttons
    'Setup': '\$\$SY_FP 18,1',
    'Auto': '\$\$SY_FP 17,1',
    'Normal': '\$\$SY_FP 19,1',
    'Single': '\$\$SY_FP 20,1',
    // Channel
    'CH1': '\$\$SY_FP 39,1',
    'CH2': '\$\$SY_FP 40,1',
  };

  /// Generic handler for any button press (menu, vertical, horizontal, trigger, channel).
  /// Looks up the SCPI command from [_buttonCommands] and sends it.
  Future<void> _handleButtonPress(String buttonLabel) async {
    if (_isProcessingEvent || !_isOnline) return;

    _isProcessingEvent = true;
    if (mounted) setState(() {});
    try {
      final command = _buttonCommands[buttonLabel];
      if (command == null) {
        AppLogger().log('Button "$buttonLabel" not implemented yet');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Button "$buttonLabel" not implemented yet'),
              backgroundColor: Colors.blue,
            ),
          );
        }
        return;
      }
      if (await _sendCommand(command)) {
        // Wait for oscilloscope to process the command
        await Future.delayed(const Duration(milliseconds: _refreshDelayMs));
        // Fetch the screen dump synchronously
        await _acquireScreenDump(keepPanels: true);
        // Final cooldown before next event is allowed
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      AppLogger().log('Button "$buttonLabel" handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing $buttonLabel button: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _isProcessingEvent = false;
      if (mounted) setState(() {});
    }
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
      decoration: const BoxDecoration(
        color: Color(0xCC0D1117),
        border: Border(top: BorderSide(color: Color(0xFF475569))),
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
      decoration: const BoxDecoration(
        color: Color(0xCC0D1117),
        border: Border(left: BorderSide(color: Color(0xFF475569))),
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
      if (channel == 'CH1') {
        _ch1Enabled = !_ch1Enabled;
      } else if (channel == 'CH2') {
        _ch2Enabled = !_ch2Enabled;
      }
    });
  }

  void _onRefToggled(bool visible) {
    setState(() => _refVisible = visible);
  }

  /// Opens a file selection dialog showing CSV waveform files in the
  /// application's waveform/csv subdirectory.  When both CH1 and CH2 columns
  /// are present the user is asked which channel to load.
  Future<void> _loadReferenceWaveform() async {
    final dir = AppPaths.waveformCsvDirectory;
    if (!await dir.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No saved waveform CSV files found.')),
        );
      }
      return;
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No waveform CSV files found.')),
        );
      }
      return;
    }

    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => _ReferenceFilePickerDialog(files: files),
    );
    if (selected == null || !mounted) return;

    try {
      final file = File(selected);
      final content = await file.readAsString();
      final (ch1Points, ch2Points) = _parseWaveformCsv(content);
      if (ch1Points == null && ch2Points == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Invalid waveform CSV. Expected header: '
                'Time (s),CH1 (V),CH2 (V)',
              ),
            ),
          );
        }
        return;
      }

      final bothPresent = ch1Points != null && ch2Points != null;

      String? channel;
      if (bothPresent) {
        if (!mounted) return;
        channel = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('Select Channel'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'ch1'),
                child: const Text(
                  'CH1',
                  style: TextStyle(color: Colors.yellow),
                ),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'ch2'),
                child: const Text(
                  'CH2',
                  style: TextStyle(color: Color(0xFFFF20FF)),
                ),
              ),
            ],
          ),
        );
        if (channel == null) return;
      } else if (ch1Points != null) {
        channel = 'ch1';
      } else if (ch2Points != null) {
        channel = 'ch2';
      } else {
        return;
      }

      final points = channel == 'ch1' ? ch1Points! : ch2Points!;

      // Align reference time axis with the live waveform: the CSV time
      // starts at 0 but the live data may use trigger-relative times
      // starting at a negative value (e.g. -0.00035).  Shift the
      // reference so its first sample lines up with the first live sample.
      final liveFirstTime =
          _waveformCh1 != null && _waveformCh1!.points.isNotEmpty
          ? _waveformCh1!.points.first.$1
          : _waveformCh2 != null && _waveformCh2!.points.isNotEmpty
          ? _waveformCh2!.points.first.$1
          : null;
      final shift = (liveFirstTime ?? points.first.$1) - points.first.$1;
      final alignedPoints = shift != 0
          ? points.map((p) => (p.$1 + shift, p.$2)).toList()
          : points;

      setState(() {
        _refWaveform = WaveformData(points: alignedPoints);
        _refVisible = true;
        _refFileName = file.uri.pathSegments.last;
        _refChannelOrigin = channel;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading reference: $e')));
      }
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

  /// Computes the cursor info panel dimensions based on enabled cursor types.
  static const double _cursorPanelWidth = 200.0;
  static const double _cursorPanelPadding = 12.0;
  static const double _cursorRowHeight = 20.0;
  static const double _cursorHeaderHeight = 24.0;
  static const double _cursorSectionGap = 8.0;

  double _computeCursorPanelHeight() {
    final int yRows = _cursorState.cursorsYEnabled ? 3 : 0;
    final int xRows = _cursorState.cursorsXEnabled ? 2 : 0;
    final double sectionsGap = (yRows > 0 && xRows > 0) ? _cursorSectionGap : 0;
    return _cursorHeaderHeight +
        (yRows + xRows) * _cursorRowHeight +
        sectionsGap +
        _cursorPanelPadding * 2;
  }

  /// Returns the bounding rectangle of the cursor info panel in local widget
  /// coordinates, or null if cursors are not enabled.
  Rect? _getCursorInfoPanelRect(Size size) {
    if (!_cursorState.cursorsXEnabled && !_cursorState.cursorsYEnabled) {
      return null;
    }
    final double panelHeight = _computeCursorPanelHeight();
    final double panelX =
        size.width - _cursorPanelWidth - 12 + _cursorState.cursorInfoOffset.dx;
    final double panelY = 12 + _cursorState.cursorInfoOffset.dy;
    return Rect.fromLTWH(panelX, panelY, _cursorPanelWidth, panelHeight);
  }

  void _onCursorHover(PointerHoverEvent event) {
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

  /// Clamps the cursor info panel offset so the panel stays within the waveform
  /// display area. The panel position is computed in waveform_painter.dart as:
  ///   panelX = size.width - panelWidth - 12 + offset.dx
  ///   panelY = 12 + offset.dy
  /// We constrain the panel so it stays fully visible within the waveform widget
  /// with a small margin on each side.
  Offset _clampCursorInfoOffset(Offset proposedOffset, Size size) {
    final double panelHeight = _computeCursorPanelHeight();
    const double margin = 12.0;

    // Constrain panelX within [margin, size.width - panelWidth - margin]
    // panelX = size.width - panelWidth - 12 + dx
    // => dx = panelX - (size.width - panelWidth - 12)
    // min dx: panelX = margin => dx = margin - (size.width - panelWidth - 12)
    // max dx: panelX = size.width - panelWidth - margin => dx = margin - 12
    final double minDx = margin - (size.width - _cursorPanelWidth - margin);
    final double maxDx = margin - margin;
    final double clampedDx = proposedOffset.dx.clamp(minDx, maxDx);

    // Constrain panelY within [margin, size.height - panelHeight - margin]
    // panelY = 12 + dy
    // => dy = panelY - 12
    // min dy: panelY = margin => dy = margin - 12
    // max dy: panelY = size.height - panelHeight - margin => dy = size.height - panelHeight - margin - 12
    final double minDy = margin - margin;
    final double maxDy = size.height - panelHeight - margin - margin;
    final double clampedDy = proposedOffset.dy.clamp(minDy, maxDy);

    return Offset(clampedDx, clampedDy);
  }

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
}
