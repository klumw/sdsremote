import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'dart:ui' as ui show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
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

enum ActivePanel { none, help, chat, profiles }

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

(WaveformData?, WaveformData?, DeviceParams) _convertRawData(
  WaveformRawData raw,
) {
  WaveformData? ch1;
  WaveformData? ch2;

  if (raw.ch1Raw != null && raw.vdivCh1 != null && raw.voffsetCh1 != null) {
    final voltages = WaveformConverter.convertVoltages(
      raw.ch1Raw!,
      raw.vdivCh1!,
      raw.voffsetCh1!,
    );
    final times = WaveformConverter.computeTimeAxis(
      voltages.length,
      raw.trdl,
      raw.timebase,
      raw.sampleRate,
    );
    ch1 = WaveformData(points: WaveformConverter.combine(times, voltages));
  }

  if (raw.ch2Raw != null && raw.vdivCh2 != null && raw.voffsetCh2 != null) {
    final voltages = WaveformConverter.convertVoltages(
      raw.ch2Raw!,
      raw.vdivCh2!,
      raw.voffsetCh2!,
    );
    final times = WaveformConverter.computeTimeAxis(
      voltages.length,
      raw.trdl,
      raw.timebase,
      raw.sampleRate,
    );
    ch2 = WaveformData(points: WaveformConverter.combine(times, voltages));
  }

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

// ===========================================================================
// Application Entry Point
// ===========================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Log application startup
  AppLogger().log('SDS-Remote: application starting');

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

class _OsciHomePageState extends State<OsciHomePage> with WindowListener {
  // =========================================================================
  // State Fields
  // =========================================================================

  // Connection
  String _ipAddress = '192.168.1.100';
  bool _isOnline = false;
  String? _deviceName;
  Vxi11Instrument? _instrument;

  // AI
  String _aiApiKey = '';
  String _aiApiToken = '';
  String _llmModel = '';
  bool get _isAiEnabled =>
      _aiApiKey.trim().length >= 8 &&
      _aiApiToken.trim().length >= 8;

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

  // Cursors
  CursorState _cursorState = const CursorState();
  int? _draggingCursorIndex; // 0=cursorX1, 1=cursorX2, 2=cursorY1, 3=cursorY2
  bool _draggingCursorInfo = false;

  /// null = not hovering, 'x' = hovering over X-axis cursor, 'y' = hovering over Y-axis cursor, 'info' = hovering over cursor info panel
  String? _hoveredCursorType;

  bool _ch1Enabled = true;
  bool _ch2Enabled = true;
  bool _saveWithParams = false;

  // Soft key handling
  bool _isProcessingSoftKey = false;

  // Timers
  Timer? _pingTimer;

  // Profiles
  List<ProfileInfo> _profileFiles = [];

  Timer? _refreshTimer;
  bool _refreshPending = false;
  static const int _refreshDelayMs = 1000;

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

  // Keys

  final GlobalKey _waveformKey = GlobalKey();

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
    super.dispose();
  }

  @override
  void onWindowClose() async {
    await AppLogger().log('SDS-Remote: application stopping');
    exit(0);
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
                                                  params: _deviceParams!,
                                                  ch1Enabled: _ch1Enabled,
                                                  ch2Enabled: _ch2Enabled,
                                                ),
                                                child: const SizedBox.expand(),
                                              ),
                                            ),
                                            CustomPaint(
                                              painter: CursorPainter(
                                                cursors: _cursorState,
                                                params: _deviceParams!,
                                              ),
                                              child: const SizedBox.expand(),
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
                                  screenDump: _screenDump!,
                                  ch1Enabled: _ch1Enabled,
                                  ch2Enabled: _ch2Enabled,
                                  onChannelToggle: _handleChannelToggle,
                                  onSoftKeyPressed: _handleSoftKeyPress,
                                  onMenuPressed: _handleMenuPress,
                                  onIntensityAdjustChanged:
                                      _handleIntensityAdjustChanged,
                                  onIntensityAdjustTapped:
                                      _handleIntensityAdjustTapped,
                                  onCh1VoltageKnobChanged:
                                      _handleCh1VoltageKnobChanged,
                                  onCh1VoltageKnobTapped:
                                      _handleCh1VoltageKnobTapped,
                                  onCh1PositionKnobChanged:
                                      _handleCh1PositionKnobChanged,
                                  onCh2VoltageKnobChanged:
                                      _handleCh2VoltageKnobChanged,
                                  onCh2VoltageKnobTapped:
                                      _handleCh2VoltageKnobTapped,
                                  onCh2PositionKnobChanged:
                                      _handleCh2PositionKnobChanged,
                                  onCh1PositionKnobTapped:
                                      _handleCh1PositionKnobTapped,
                                  onCh2PositionKnobTapped:
                                      _handleCh2PositionKnobTapped,
                                  onHorizontalTimeKnobChanged:
                                      _handleHorizontalTimeKnobChanged,
                                  onHorizontalTimeKnobTapped:
                                      _handleHorizontalTimeKnobTapped,
                                  onHorizontalPositionKnobTapped:
                                      _handleHorizontalPositionKnobTapped,
                                  onTriggerLevelKnobChanged:
                                      _handleTriggerLevelKnobChanged,
                                  onTriggerLevelKnobTapped:
                                      _handleTriggerLevelKnobTapped,
                                  onMenuButtonPressed: _handleMenuButtonPress,
                                  onVerticalButtonPressed:
                                      _handleVerticalButtonPress,
                                  onHorizontalButtonPressed:
                                      _handleHorizontalButtonPress,
                                  onTriggerButtonPressed:
                                      _handleTriggerButtonPress,
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
                                        "Version 0.11",
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
                        onChannelToggle: _onDeviceParamChannelToggle,
                        onCursorXToggled: _onCursorXToggled,
                        onCursorYToggled: _onCursorYToggled,
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
                  _buildActionButton(
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
                    onPressed: (_isAcquiring || !_isOnline)
                        ? null
                        : _acquireScreenDump,
                  ),
                  const SizedBox(width: 16),
                  _buildWaveformControls(),
                  const SizedBox(width: 16),
                  _buildAiButton(),
                  const SizedBox(width: 16),
                  _buildProfilesButton(),
                ],
              ),
            ),
          ),
          _buildHelpButton(),
          const SizedBox(width: 16),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.campaign, size: 25),
                color: Colors.white70,
                tooltip: 'News',
                onPressed: _showNewsDialog,
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
            color: Colors.white70,
            tooltip: 'Settings',
            onPressed: () => _showConfigDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.save_alt, size: 25),
            color:
                (_activePanel == ActivePanel.none &&
                    (_screenDump != null || _waveformAcquired))
                ? Colors.white70
                : Colors.white24,
            tooltip: 'Save',
            onPressed:
                (_activePanel == ActivePanel.none &&
                    (_screenDump != null || _waveformAcquired))
                ? _saveCurrentView
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required Widget icon,
    VoidCallback? onPressed,
  }) {
    final isDisabled = onPressed == null;
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
              isDisabled
                  ? ColorFiltered(
                      colorFilter: ColorFilter.mode(
                        Colors.white.withValues(alpha: 0.3),
                        BlendMode.srcIn,
                      ),
                      child: icon,
                    )
                  : icon,
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

  Widget _buildWaveformControls() {
    final isDisabled = _isAcquiringWaveform || !_isOnline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isDisabled ? null : _acquireWaveform,
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
                  _isAcquiringWaveform
                      ? const SizedBox(
                          width: 25,
                          height: 25,
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : Icon(
                          Icons.show_chart,
                          size: 25,
                          color: Colors.white.withValues(
                            alpha: isDisabled ? 0.3 : 1.0,
                          ),
                        ),
                  const SizedBox(width: 8),
                  Text(
                    _isAcquiringWaveform ? "Acquiring..." : "Acquire Waveform",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withValues(
                        alpha: isDisabled ? 0.3 : 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiButton() {
    final isDisabled = !_isAiEnabled;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : () => _togglePanel(ActivePanel.chat),
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
              Icon(
                Icons.auto_awesome,
                size: 25,
                color: Colors.white.withValues(alpha: isDisabled ? 0.3 : 1.0),
              ),
              const SizedBox(width: 8),
              Text(
                "AI",
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

  Widget _buildProfilesButton() {
    final isDisabled = !_isOnline;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : () => _togglePanel(ActivePanel.profiles),
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
              Icon(
                Icons.save,
                size: 25,
                color: Colors.white.withValues(alpha: isDisabled ? 0.3 : 1.0),
              ),
              const SizedBox(width: 8),
              Text(
                "Profiles",
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

  Widget _buildHelpButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _togglePanel(ActivePanel.help),
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF172A45),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                offset: const Offset(1, 1),
                blurRadius: 2,
              ),
            ],
            border: Border.all(color: const Color(0xFF475569), width: 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.help_outline, size: 25, color: Colors.white),
              const SizedBox(width: 8),
              const Text(
                "Help",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
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

  void _togglePanel(ActivePanel panel) {
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
    });
  }

  // =========================================================================
  // Profile Operations
  // =========================================================================

  void _loadProfileFiles() {
    try {
      final dir = Directory.current;
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

      // Send PNSU? to get XML settings
      final data = await instr.readRawResponse('PNSU?');
      final xml = utf8.decode(data);

      final file = File('$name.lss');
      await file.writeAsString(xml);

      _loadProfileFiles();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Profile "$name" saved.')));
      }
    } catch (e) {
      AppLogger().log('Save profile error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save profile failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadProfile(String fileName) async {
    try {
      final file = File(fileName);
      if (!await file.exists()) throw Exception('File not found');

      final xml = await file.readAsString();
      final instr = await _getInstrument();
      if (instr == null) throw Exception('Device not connected');

      // Send the entire XML string as a SCPI command
      await instr.writeString(xml);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Profile "$fileName" loaded.')));
      }
      // Refresh screen dump after loading profile
      _scheduleRefresh();
    } catch (e) {
      AppLogger().log('Load profile error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Load profile failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteProfile(String fileName) async {
    try {
      final file = File(fileName);
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
      aiApiKey: _aiApiKey,
      aiApiToken: _aiApiToken,
      llmModel: _llmModel,
      saveWithParams: _saveWithParams,
      isRunningDiagnostic: _isRunningDiagnostic,
      diagnosticResults: _diagnosticResults,
      callbacks: SettingsPanelCallbacks(
        onSave: (newIp, newKey, newToken, newModel) {
          bool criticalConfigChanged =
              _ipAddress != newIp ||
              _aiApiKey != newKey ||
              _aiApiToken != newToken ||
              _llmModel != newModel;

          setState(() {
            _ipAddress = newIp;
            _aiApiKey = newKey;
            _aiApiToken = newToken;
            _llmModel = newModel;
            _deviceName = null;
            _showSettings = false;
          });
          _saveConfig();
          _startPingTimer();

          if (_aiApiKey.trim().length >= 8 && _aiApiToken.trim().length >= 8) {
            _configureAiService();
          }
        },
        onClose: () => setState(() => _showSettings = false),
        onDrag: (delta) => setState(() => _settingsOffset += delta),
      ),
      onSaveWithParamsChanged: (v) async {
        setState(() => _saveWithParams = v);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('save_with_params', v);
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
      final instr = Vxi11Instrument(_ipAddress, sourceLabel: 'updateWindowTitle');
      await instr.open(timeoutSeconds: 3.0);
      await instr.writeString('*IDN?');
      final idn = (await instr.readString()).trim();
      await instr.close();
      await instr.destroy();
      final parts = idn.split(',');
      final name = parts.length >= 2
          ? '${parts[0].trim()} ${parts[1].trim()}'
          : idn;
      if (mounted) {
        _deviceName = name;
        windowManager.setTitle(name);
      }
    } catch (_) {
      windowManager.setTitle('SDS-Remote — $_ipAddress');
    }
  }

  Future<void> _acquireScreenDump({bool keepPanels = false}) async {
    if (_isAcquiring) return;

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
      if (mounted) {
        setState(() {
          _isAcquiring = false;
        });
      }
    }
  }

  void _acquireWaveform() async {
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

      final result = await compute(_convertRawData, raw);

      setState(() {
        _waveformCh1 = result.$1;
        _waveformCh2 = result.$2;
        _deviceParams = result.$3;
        _screenDump = null;
        _isOnline = true;
        _waveformAcquired = true;
      });
    } catch (e) {
      AppLogger().log('Acquire waveform error: $e');
      if (mounted) {
        final reason = e is AcquisitionException ? e.reason : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Waveform error: $reason'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAcquiringWaveform = false;
        });
      }
    }
  }

  Future<void> _saveCurrentView() async {
    if (_screenDump != null) {
      await _saveScreenDump();
    } else if (_waveformCh1 != null || _waveformCh2 != null) {
      await _saveWaveform();
    }
  }

  Future<void> _saveScreenDump() async {
    try {
      final file = File('screen_dump.png');
      await file.writeAsBytes(_screenDump!);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved screen_dump.png')));
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

      final file = File('waveform.png');
      await file.writeAsBytes(pngBytes);

      // If "Save with parameters" is enabled, also save waveform data as CSV
      if (_saveWithParams) {
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
        csvBuffer.writeln(
          '# Cursors X Enabled: ${_cursorState.cursorsXEnabled}',
        );
        csvBuffer.writeln(
          '# Cursors Y Enabled: ${_cursorState.cursorsYEnabled}',
        );
        csvBuffer.writeln('#');
        csvBuffer.writeln('Time (s),CH1 (V),CH2 (V)');

        // Determine the maximum number of points across both channels
        final int maxPoints = [
          if (_waveformCh1 != null) _waveformCh1!.points.length,
          if (_waveformCh2 != null) _waveformCh2!.points.length,
        ].fold(0, (a, b) => a > b ? a : b);

        for (int i = 0; i < maxPoints; i++) {
          final time = _waveformCh1 != null && i < _waveformCh1!.points.length
              ? _waveformCh1!.points[i].$1
              : _waveformCh2 != null && i < _waveformCh2!.points.length
              ? _waveformCh2!.points[i].$1
              : 0.0;
          final ch1V = _waveformCh1 != null && i < _waveformCh1!.points.length
              ? _waveformCh1!.points[i].$2.toStringAsFixed(6)
              : '';
          final ch2V = _waveformCh2 != null && i < _waveformCh2!.points.length
              ? _waveformCh2!.points[i].$2.toStringAsFixed(6)
              : '';
          csvBuffer.writeln('$time,$ch1V,$ch2V');
        }

        final csvFile = File('waveform_data.csv');
        await csvFile.writeAsString(csvBuffer.toString());
      }

      if (mounted) {
        final msg = _saveWithParams
            ? 'Saved waveform.png + waveform_data.csv'
            : 'Saved waveform.png';
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

  // =========================================================================
  // Initialization & Config
  // =========================================================================

  Future<void> _initialize() async {
    await _loadConfig();
    await _checkNewsNotification();
    _loadProfileFiles();
    _startPingTimer();
    // Configure AI agent on startup if keys are already set/valid
    bool keysValid =
        _aiApiKey.trim().length >= 8 && _aiApiToken.trim().length >= 8;
    if (keysValid) {
      _configureAiService();
    }
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipAddress = prefs.getString('osci_ip') ?? '192.168.1.100';
      _aiApiKey = prefs.getString('ai_api_key') ?? '';
      _aiApiToken = prefs.getString('ai_api_token') ?? '';
      _llmModel = prefs.getString('llm_model') ?? '';
      _saveWithParams = prefs.getBool('save_with_params') ?? false;
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('osci_ip', _ipAddress);
    await prefs.setString('ai_api_key', _aiApiKey);
    await prefs.setString('ai_api_token', _aiApiToken);
    await prefs.setString('llm_model', _llmModel);
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

  void _toggleHelp() {
    _togglePanel(ActivePanel.help);
  }

  // =========================================================================
  // AI Operations
  // =========================================================================

  /// Configures the [AiChatService] with the current API keys, model, and
  /// device IP. This replaces the previous Docker-based backend.
  void _configureAiService() {
    if (_aiApiKey.trim().length < 8 || _aiApiToken.trim().length < 8) {
      AppLogger(agentName: 'main', toolName: '_configureAiService').log(
        'AI keys not valid, skipping configuration',
      );
      return;
    }

    AppLogger(agentName: 'main', toolName: '_configureAiService').log(
      'Configuring AI service: model=$_llmModel, ip=$_ipAddress',
    );

    _aiChatService.configure(
      apiKey: _aiApiKey,
      apiToken: _aiApiToken,
      model: _llmModel.isNotEmpty
          ? _llmModel
          : 'deepseek:deepseek-v4-flash',
      vxi11Host: _ipAddress,
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

    void addResult(String msg) {
      setState(() => _diagnosticResults.add(msg));
    }

    // Test 1: Ping the device
    addResult('Testing TCP connection to $_ipAddress:111...');
    try {
      final socket = await Socket.connect(
        _ipAddress,
        111,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      addResult('SUCCESS: TCP connection established');
    } catch (e) {
      addResult('FAILURE: TCP connection failed: $e');
      setState(() => _isRunningDiagnostic = false);
      return;
    }

    // Test 2: VXI-11 open
    addResult('Testing VXI-11 open...');
    try {
      final instr = Vxi11Instrument(_ipAddress, sourceLabel: 'diag-open');
      await instr.open(timeoutSeconds: 3.0);
      addResult('SUCCESS: VXI-11 link opened');
      await instr.close();
      await instr.destroy();
    } catch (e) {
      addResult('FAILURE: VXI-11 open failed: $e');
      setState(() => _isRunningDiagnostic = false);
      return;
    }

    // Test 3: *IDN?
    addResult('Querying *IDN?...');
    try {
      final instr = Vxi11Instrument(_ipAddress, sourceLabel: 'diag-idn');
      await instr.open(timeoutSeconds: 3.0);
      await instr.writeString('*IDN?');
      final idn = (await instr.readString()).trim();
      await instr.close();
      await instr.destroy();
      addResult('SUCCESS: Device identity: $idn');
    } catch (e) {
      addResult('FAILURE: *IDN? query failed: $e');
      setState(() => _isRunningDiagnostic = false);
      return;
    }

    // Test 4: Screen dump
    addResult('Testing screen dump...');
    try {
      final instr = Vxi11Instrument(_ipAddress, sourceLabel: 'diag-screendump');
      await instr.open(timeoutSeconds: 5.0);
      final data = await instr.getScreenDump();
      await instr.close();
      await instr.destroy();
      addResult('SUCCESS: Screen dump received (${data.length} bytes)');
    } catch (e) {
      addResult('FAILURE: Screen dump failed: $e');
    }

    addResult('Diagnostic complete.');
    setState(() => _isRunningDiagnostic = false);
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
        await instr.destroy();
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
  Future<bool> _sendCommand(String command) async {
    if (!_isOnline) {
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send command: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  /// Handles soft key button press (M1-M6).
  /// Sends $$SY_FP X,1 command where X is button number, then refreshes screen.
  void _handleSoftKeyPress(int buttonNumber) async {
    // Block if already processing a soft key or acquiring a screen dump
    if (_isProcessingSoftKey || !_isOnline) {
      return;
    }

    setState(() {
      _isProcessingSoftKey = true;
    });

    try {
      // Send the SCPI command
      final command = '\$\$SY_FP $buttonNumber,1';
      final success = await _sendCommand(command);

      if (success) {
        // Refresh screen dump after successful command
        _scheduleRefresh();
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
      if (mounted) {
        setState(() {
          _isProcessingSoftKey = false;
        });
      }
    }
  }

  /// Handles MENU button press.
  /// Sends $$SY_FP 0,1 command (VXI special SPCI command for MENU button),
  /// then immediately requests a screen dump image.
  void _handleMenuPress() async {
    // Block if already processing a soft key or acquiring a screen dump
    if (_isProcessingSoftKey || !_isOnline) {
      return;
    }

    setState(() {
      _isProcessingSoftKey = true;
    });

    try {
      // Send the VXI special SPCI command for MENU button
      final command = '\$\$SY_FP 0,1';
      final success = await _sendCommand(command);

      if (success) {
        // Immediately request screen dump image (reusing M1 button functionality)
        _scheduleRefresh();
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
      if (mounted) {
        setState(() {
          _isProcessingSoftKey = false;
        });
      }
    }
  }

  /// Handles Intensity/Adjust knob turned right or left.
  /// Sends $$SY_FP 15,1 command when turned right (value increases)
  /// Sends $$SY_FP 15,-1 command when turned left (value decreases)
  /// then immediately requests a screen dump image.
  /// Reuses functionality from button M1.
  double _previousIntensityValue = 0.5;
  void _handleIntensityAdjustChanged(double newValue) async {
    // Check if knob is turned (value changes) and device is ready
    // Block if already processing a soft key or acquiring a screen dump
    if (newValue != _previousIntensityValue &&
        _isOnline &&
        !_isProcessingSoftKey) {
      setState(() {
        _isProcessingSoftKey = true;
      });

      try {
        // Determine direction and send appropriate command
        final String command;
        if (newValue > _previousIntensityValue) {
          // Knob turned right (value increases)
          command = '\$\$SY_FP 15,1';
        } else {
          // Knob turned left (value decreases)
          command = '\$\$SY_FP 15,-1';
        }

        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } catch (e) {
        AppLogger().log('Intensity/Adjust knob handler error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error processing Intensity/Adjust knob: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isProcessingSoftKey = false;
          });
        }
      }
    }

    // Update previous value for next comparison
    _previousIntensityValue = newValue;
  }

  /// Handles Intensity/Adjust knob tap/click.
  /// Sends $$SY_FP 15,0 command (special SPCI command for Intensity/Adjust knob click),
  /// then immediately requests a screen dump image update.
  /// Reuses functionality from button M1.
  void _handleIntensityAdjustTapped() async {
    // Block if already processing a soft key or acquiring a screen dump
    if (!_isOnline || _isProcessingSoftKey) {
      return;
    }

    setState(() {
      _isProcessingSoftKey = true;
    });

    try {
      // Send the special SPCI command for Intensity/Adjust knob click
      final command = '\$\$SY_FP 15,0';
      final success = await _sendCommand(command);

      if (success) {
        // Immediately request screen dump image (reusing M1 button functionality)
        _scheduleRefresh();
      }
    } catch (e) {
      AppLogger().log('Intensity/Adjust knob tap handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing Intensity/Adjust knob tap: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSoftKey = false;
        });
      }
    }
  }

  /// Handles Channel 1 Voltage knob tap/click.
  /// Sends $$SY_FP 35,0 command (special SPCI command for CH1 Voltage knob click),
  /// then immediately requests a screen dump image update.
  /// Reuses functionality from button M1.
  void _handleCh1VoltageKnobTapped() async {
    // Block if already processing a soft key or acquiring a screen dump
    if (!_isOnline || _isProcessingSoftKey) {
      return;
    }

    setState(() {
      _isProcessingSoftKey = true;
    });

    try {
      // Send the special SPCI command for CH1 Voltage knob click
      final command = '\$\$SY_FP 35,0';
      final success = await _sendCommand(command);

      if (success) {
        // Immediately request screen dump image (reusing M1 button functionality)
        _scheduleRefresh();
      }
    } catch (e) {
      AppLogger().log('CH1 Voltage knob tap handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing CH1 Voltage knob tap: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSoftKey = false;
        });
      }
    }
  }

  /// Handles Channel 1 Voltage knob turned right or left.
  /// Sends $$SY_FP 35,1 command when turned right (value increases)
  /// Sends $$SY_FP 35,-1 command when turned left (value decreases)
  /// then immediately requests a screen dump image.
  /// Reuses functionality from button M1.
  double _previousCh1VoltageValue = 0.5;
  void _handleCh1VoltageKnobChanged(double newValue) async {
    // Check if knob is turned (value changes) and device is ready
    // Block if already processing a soft key or acquiring a screen dump
    if (newValue != _previousCh1VoltageValue &&
        _isOnline &&
        !_isProcessingSoftKey) {
      setState(() {
        _isProcessingSoftKey = true;
      });

      try {
        // Determine direction and send appropriate command
        final String command;
        if (newValue > _previousCh1VoltageValue) {
          // Knob turned right (value increases)
          command = '\$\$SY_FP 35,1';
        } else {
          // Knob turned left (value decreases)
          command = '\$\$SY_FP 35,-1';
        }

        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } catch (e) {
        AppLogger().log('CH1 Voltage knob handler error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error processing CH1 Voltage knob: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isProcessingSoftKey = false;
          });
        }
      }
    }

    // Update previous value for next comparison
    _previousCh1VoltageValue = newValue;
  }

  /// Handles Channel 2 Voltage knob turned right or left.
  /// Sends $$SY_FP 36,1 command when turned right (value increases)
  /// Sends $$SY_FP 36,-1 command when turned left (value decreases)
  /// then immediately requests a screen dump image.
  /// Reuses functionality from button M1.
  double _previousCh2VoltageValue = 0.5;
  void _handleCh2VoltageKnobChanged(double newValue) async {
    // Check if knob is turned (value changes) and device is ready
    // Block if already processing a soft key or acquiring a screen dump
    if (newValue != _previousCh2VoltageValue &&
        _isOnline &&
        !_isProcessingSoftKey) {
      setState(() {
        _isProcessingSoftKey = true;
      });

      try {
        // Determine direction and send appropriate command
        final String command;
        if (newValue > _previousCh2VoltageValue) {
          // Knob turned right (value increases)
          command = '\$\$SY_FP 36,1';
        } else {
          // Knob turned left (value decreases)
          command = '\$\$SY_FP 36,-1';
        }

        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } catch (e) {
        AppLogger().log('CH2 Voltage knob handler error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error processing CH2 Voltage knob: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isProcessingSoftKey = false;
          });
        }
      }
    }

    // Update previous value for next comparison
    _previousCh2VoltageValue = newValue;
  }

  /// Handles Channel 2 Voltage knob tap/click.
  /// Sends $$SY_FP 36,0 command (special SPCI command for CH2 Voltage knob click),
  /// then immediately requests a screen dump image update.
  /// Reuses functionality from button M1.
  void _handleCh2VoltageKnobTapped() async {
    // Block if already processing a soft key or acquiring a screen dump
    if (!_isOnline || _isProcessingSoftKey) {
      return;
    }

    setState(() {
      _isProcessingSoftKey = true;
    });

    try {
      // Send the special SPCI command for CH2 Voltage knob click
      final command = '\$\$SY_FP 36,0';
      final success = await _sendCommand(command);

      if (success) {
        // Immediately request screen dump image (reusing M1 button functionality)
        _scheduleRefresh();
      }
    } catch (e) {
      AppLogger().log('CH2 Voltage knob tap handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing CH2 Voltage knob tap: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSoftKey = false;
        });
      }
    }
  }

  /// Handles Channel 1 Position knob turned right or left.
  /// Sends $$SY_FP 43,1 command when turned right (value increases)
  /// Sends $$SY_FP 43,-1 command when turned left (value decreases)
  /// then immediately requests a screen dump image.
  /// Reuses functionality from button M1.
  double _previousCh1PositionValue = 0.5;
  void _handleCh1PositionKnobChanged(double newValue) async {
    // Check if knob is turned (value changes) and device is ready
    // Block if already processing a soft key or acquiring a screen dump
    if (newValue != _previousCh1PositionValue &&
        _isOnline &&
        !_isProcessingSoftKey) {
      setState(() {
        _isProcessingSoftKey = true;
      });

      try {
        // Determine direction and send appropriate command
        final String command;
        if (newValue > _previousCh1PositionValue) {
          // Knob turned right (value increases)
          command = '\$\$SY_FP 43,1';
        } else {
          // Knob turned left (value decreases)
          command = '\$\$SY_FP 43,-1';
        }

        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } catch (e) {
        AppLogger().log('CH1 Position knob handler error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error processing CH1 Position knob: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isProcessingSoftKey = false;
          });
        }
      }
    }

    // Update previous value for next comparison
    _previousCh1PositionValue = newValue;
  }

  /// Handles Channel 1 Position knob tap/click.
  /// Sends $$SY_FP 43,0 command (special SPCI command for CH1 Position knob click),
  /// then immediately requests a screen dump image update.
  /// Reuses functionality from button M1.
  void _handleCh1PositionKnobTapped() async {
    // Block if already processing a soft key or acquiring a screen dump
    if (!_isOnline || _isProcessingSoftKey) {
      return;
    }

    setState(() {
      _isProcessingSoftKey = true;
    });

    try {
      // Send the special SPCI command for CH1 Position knob click
      final command = '\$\$SY_FP 43,0';
      final success = await _sendCommand(command);

      if (success) {
        // Immediately request screen dump image (reusing M1 button functionality)
        _scheduleRefresh();
      }
    } catch (e) {
      AppLogger().log('CH1 Position knob tap handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing CH1 Position knob tap: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSoftKey = false;
        });
      }
    }
  }

  /// Handles Channel 2 Position knob turned right or left.
  /// Sends $$SY_FP 44,1 command when turned right (value increases)
  /// Sends $$SY_FP 44,-1 command when turned left (value decreases)
  /// then immediately requests a screen dump image.
  /// Reuses functionality from button M1.
  double _previousCh2PositionValue = 0.5;
  void _handleCh2PositionKnobChanged(double newValue) async {
    // Check if knob is turned (value changes) and device is ready
    // Block if already processing a soft key or acquiring a screen dump
    if (newValue != _previousCh2PositionValue &&
        _isOnline &&
        !_isProcessingSoftKey) {
      setState(() {
        _isProcessingSoftKey = true;
      });

      try {
        // Determine direction and send appropriate command
        final String command;
        if (newValue > _previousCh2PositionValue) {
          // Knob turned right (value increases)
          command = '\$\$SY_FP 44,1';
        } else {
          // Knob turned left (value decreases)
          command = '\$\$SY_FP 44,-1';
        }

        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } catch (e) {
        AppLogger().log('CH2 Position knob handler error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error processing CH2 Position knob: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isProcessingSoftKey = false;
          });
        }
      }
    }

    // Update previous value for next comparison
    _previousCh2PositionValue = newValue;
  }

  /// Handles Channel 2 Position knob tap/click.
  /// Sends $$SY_FP 44,0 command (special SPCI command for CH2 Position knob click),
  /// then immediately requests a screen dump image update.
  /// Reuses functionality from button M1.
  void _handleCh2PositionKnobTapped() async {
    // Block if already processing a soft key or acquiring a screen dump
    if (!_isOnline || _isProcessingSoftKey) {
      return;
    }

    setState(() {
      _isProcessingSoftKey = true;
    });

    try {
      // Send the special SPCI command for CH2 Position knob click
      final command = '\$\$SY_FP 44,0';
      final success = await _sendCommand(command);

      if (success) {
        // Immediately request screen dump image (reusing M1 button functionality)
        _scheduleRefresh();
      }
    } catch (e) {
      AppLogger().log('CH2 Position knob tap handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing CH2 Position knob tap: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSoftKey = false;
        });
      }
    }
  }

  /// Handles Horizontal Time knob turned right or left.
  /// Sends $$SY_FP 7,1 command when turned right (value increases)
  /// Sends $$SY_FP 7,-1 command when turned left (value decreases)
  /// then immediately requests a screen dump image.
  /// Reuses functionality from button M1.
  double _previousHorizontalTimeValue = 0.5;
  void _handleHorizontalTimeKnobChanged(double newValue) async {
    // Check if knob is turned (value changes) and device is ready
    // Block if already processing a soft key or acquiring a screen dump
    if (newValue != _previousHorizontalTimeValue &&
        _isOnline &&
        !_isProcessingSoftKey) {
      setState(() {
        _isProcessingSoftKey = true;
      });

      try {
        // Determine direction and send appropriate command
        final String command;
        if (newValue > _previousHorizontalTimeValue) {
          // Knob turned right (value increases)
          command = '\$\$SY_FP 7,1';
        } else {
          // Knob turned left (value decreases)
          command = '\$\$SY_FP 7,-1';
        }

        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } catch (e) {
        AppLogger().log('Horizontal Time knob handler error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error processing Horizontal Time knob: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isProcessingSoftKey = false;
          });
        }
      }
    }

    // Update previous value for next comparison
    _previousHorizontalTimeValue = newValue;
  }

  /// Handles Horizontal Time knob tap/click.
  /// Sends $$SY_FP 7,0 command (special SPCI command for Horizontal Time knob click),
  /// then immediately requests a screen dump image update.
  /// Reuses functionality from button M1.
  void _handleHorizontalTimeKnobTapped() async {
    // Block if already processing a soft key or acquiring a screen dump
    if (!_isOnline || _isProcessingSoftKey) {
      return;
    }

    setState(() {
      _isProcessingSoftKey = true;
    });

    try {
      // Send the special SPCI command for Horizontal Time knob click
      final command = '\$\$SY_FP 7,0';
      final success = await _sendCommand(command);

      if (success) {
        // Immediately request screen dump image (reusing M1 button functionality)
        _scheduleRefresh();
      }
    } catch (e) {
      AppLogger().log('Horizontal Time knob tap handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing Horizontal Time knob tap: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSoftKey = false;
        });
      }
    }
  }

  /// Handles Horizontal Position knob tap/click.
  /// Sends $$SY_FP 10,0 command (special SPCI command for Horizontal Position knob click),
  /// then immediately requests a screen dump image update.
  /// Reuses functionality from button M1.
  void _handleHorizontalPositionKnobTapped() async {
    // Block if already processing a soft key or acquiring a screen dump
    if (!_isOnline || _isProcessingSoftKey) {
      return;
    }

    setState(() {
      _isProcessingSoftKey = true;
    });

    try {
      // Send the special SPCI command for Horizontal Position knob click
      final command = '\$\$SY_FP 10,0';
      final success = await _sendCommand(command);

      if (success) {
        // Immediately request screen dump image (reusing M1 button functionality)
        _scheduleRefresh();
      }
    } catch (e) {
      AppLogger().log('Horizontal Position knob tap handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing Horizontal Position knob tap: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSoftKey = false;
        });
      }
    }
  }

  /// Handles Trigger Level knob turned right or left.
  /// Sends $$SY_FP 16,1 command when turned right (value increases)
  /// Sends $$SY_FP 16,-1 command when turned left (value decreases)
  /// then immediately requests a screen dump image.
  /// Reuses functionality from button M1.
  double _previousTriggerLevelValue = 0.5;
  void _handleTriggerLevelKnobChanged(double newValue) async {
    // Check if knob is turned (value changes) and device is ready
    // Block if already processing a soft key or acquiring a screen dump
    if (newValue != _previousTriggerLevelValue &&
        _isOnline &&
        !_isProcessingSoftKey) {
      setState(() {
        _isProcessingSoftKey = true;
      });

      try {
        // Determine direction and send appropriate command
        final String command;
        if (newValue > _previousTriggerLevelValue) {
          // Knob turned right (value increases)
          command = '\$\$SY_FP 16,1';
        } else {
          // Knob turned left (value decreases)
          command = '\$\$SY_FP 16,-1';
        }

        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } catch (e) {
        AppLogger().log('Trigger Level knob handler error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error processing Trigger Level knob: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isProcessingSoftKey = false;
          });
        }
      }
    }

    // Update previous value for next comparison
    _previousTriggerLevelValue = newValue;
  }

  /// Handles Trigger Level knob tap/click.
  /// Sends $$SY_FP 16,0 command (special SPCI command for Trigger Level knob click),
  /// then immediately requests a screen dump image update.
  /// Reuses functionality from button M1.
  void _handleTriggerLevelKnobTapped() async {
    // Block if already processing a soft key or acquiring a screen dump
    if (!_isOnline || _isProcessingSoftKey) {
      return;
    }

    setState(() {
      _isProcessingSoftKey = true;
    });

    try {
      // Send the special SPCI command for Trigger Level knob click
      final command = '\$\$SY_FP 16,0';
      final success = await _sendCommand(command);

      if (success) {
        // Immediately request screen dump image (reusing M1 button functionality)
        _scheduleRefresh();
      }
    } catch (e) {
      AppLogger().log('Trigger Level knob tap handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing Trigger Level knob tap: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSoftKey = false;
        });
      }
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

  void _onDeviceParamChannelToggle(String channel) {
    setState(() {
      if (channel == 'CH1') {
        _ch1Enabled = !_ch1Enabled;
      } else if (channel == 'CH2') {
        _ch2Enabled = !_ch2Enabled;
      }
    });
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

  /// Returns the bounding rectangle of the cursor info panel in local widget
  /// coordinates, or null if cursors are not enabled.
  Rect? _getCursorInfoPanelRect(Size size) {
    if (!_cursorState.cursorsXEnabled && !_cursorState.cursorsYEnabled) {
      return null;
    }
    const double panelWidth = 200.0;
    const double panelPadding = 12.0;
    const double rowHeight = 20.0;
    const double headerHeight = 24.0;
    const double sectionGap = 8.0;
    final int yRows = _cursorState.cursorsYEnabled ? 3 : 0;
    final int xRows = _cursorState.cursorsXEnabled ? 2 : 0;
    final double sectionsGap = (yRows > 0 && xRows > 0) ? sectionGap : 0;
    final double panelHeight =
        headerHeight +
        (yRows + xRows) * rowHeight +
        sectionsGap +
        panelPadding * 2;
    final double panelX =
        size.width - panelWidth - 12 + _cursorState.cursorInfoOffset.dx;
    final double panelY = 12 + _cursorState.cursorInfoOffset.dy;
    return Rect.fromLTWH(panelX, panelY, panelWidth, panelHeight);
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
    const double panelWidth = 200.0;
    const double panelPadding = 12.0;
    const double rowHeight = 20.0;
    const double headerHeight = 24.0;
    const double sectionGap = 8.0;
    final int yRows = _cursorState.cursorsYEnabled ? 3 : 0;
    final int xRows = _cursorState.cursorsXEnabled ? 2 : 0;
    final double sectionsGap = (yRows > 0 && xRows > 0) ? sectionGap : 0;
    final double panelHeight =
        headerHeight +
        (yRows + xRows) * rowHeight +
        sectionsGap +
        panelPadding * 2;

    const double margin = 12.0;

    // Constrain panelX within [margin, size.width - panelWidth - margin]
    // panelX = size.width - panelWidth - 12 + dx
    // => dx = panelX - (size.width - panelWidth - 12)
    // min dx: panelX = margin => dx = margin - (size.width - panelWidth - 12)
    // max dx: panelX = size.width - panelWidth - margin => dx = margin - 12
    final double minDx = margin - (size.width - panelWidth - margin);
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

  /// Handles menu button press (Cursors, Acquire, Save/Recall, etc.).
  /// For Cursors button: sends $$SY_FP 22,1 command then refreshes screen.
  /// For Acquire button: sends $$SY_FP 27,1 command then refreshes screen.
  /// For Save/Recall button: sends $$SY_FP 28,1 command then refreshes screen.
  /// For Measure button: sends $$SY_FP 26,1 command then refreshes screen.
  /// For Clear Sweeps button: sends $$SY_FP 47,1 command then refreshes screen.
  /// For Utility button: sends $$SY_FP 24,1 command then refreshes screen.
  /// For Default button: sends $$SY_FP 13,1 command then refreshes screen.
  /// For Display/Persist button: sends $$SY_FP 23,1 command then refreshes screen.
  /// For Print button: sends $$SY_FP 25,1 command then refreshes screen.
  /// Reuses M1 button functionality for screen dump acquisition.
  void _handleMenuButtonPress(String buttonLabel) async {
    // Block if already processing a soft key or acquiring a screen dump
    if (_isProcessingSoftKey || !_isOnline) {
      return;
    }

    setState(() {
      _isProcessingSoftKey = true;
    });

    try {
      // Handle different menu buttons
      if (buttonLabel == 'Cursors') {
        // Send the special SCPI command for Cursors button
        final command = '\$\$SY_FP 22,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'Acquire') {
        // Send the special SCPI command for Acquire button
        final command = '\$\$SY_FP 27,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'Save/Recall') {
        // Send the special SCPI command for Save/Recall button
        final command = '\$\$SY_FP 28,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'Measure') {
        // Send the special SCPI command for Measure button
        final command = '\$\$SY_FP 26,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'Clear Sweeps') {
        // Send the special SCPI command for Clear Sweeps button
        final command = '\$\$SY_FP 47,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'Utility') {
        // Send the special SCPI command for Utility button
        final command = '\$\$SY_FP 24,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'Default') {
        // Send the special SCPI command for Default button
        final command = '\$\$SY_FP 13,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'Display/Persist') {
        // Send the special SCPI command for Display/Persist button
        final command = '\$\$SY_FP 23,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'Print') {
        // Send the special SCPI command for Print button
        final command = '\$\$SY_FP 25,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else {
        // For other menu buttons, just log for now
        AppLogger().log(
          'Menu button pressed: $buttonLabel (not implemented yet)',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Button "$buttonLabel" not implemented yet'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger().log('Menu button handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing $buttonLabel button: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSoftKey = false;
        });
      }
    }
  }

  /// Handles vertical button press (Math, Ref, History, Decode, Run/Stop, Auto Setup).
  /// For Math button: sends $$SY_FP 31,1 command then refreshes screen.
  /// For Ref button: sends $$SY_FP 32,1 command then refreshes screen.
  /// For History button: sends $$SY_FP 48,1 command then refreshes screen.
  /// For Decode button: sends $$SY_FP 29,1 command then refreshes screen.
  /// For Run/Stop button: sends $$SY_FP 12,1 command then refreshes screen.
  /// For Auto Setup button: sends $$SY_FP 11,1 command then refreshes screen.
  /// Reuses M1 button functionality for screen dump acquisition.
  void _handleVerticalButtonPress(String buttonLabel) async {
    // Block if already processing a soft key or acquiring a screen dump
    if (_isProcessingSoftKey || !_isOnline) {
      return;
    }

    setState(() {
      _isProcessingSoftKey = true;
    });

    try {
      // Handle different vertical buttons
      if (buttonLabel == 'Math') {
        // Send the special SCPI command for Math button
        final command = '\$\$SY_FP 31,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'Ref') {
        // Send the special SCPI command for Ref button
        final command = '\$\$SY_FP 32,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'History') {
        // Send the special SCPI command for History button
        final command = '\$\$SY_FP 48,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'Decode') {
        // Send the special SCPI command for Decode button
        final command = '\$\$SY_FP 29,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'Run/Stop') {
        // Send the special SCPI command for Run/Stop button
        final command = '\$\$SY_FP 12,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'Auto\nSetup') {
        // Send the special SCPI command for Auto Setup button
        final command = '\$\$SY_FP 11,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else {
        // For other vertical buttons, just log for now
        AppLogger().log(
          'Vertical button pressed: $buttonLabel (not implemented yet)',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Button "$buttonLabel" not implemented yet'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger().log('Vertical button handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing $buttonLabel button: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSoftKey = false;
        });
      }
    }
  }

  /// Handles channel toggle button press (CH1, CH2).
  /// For CH1 button: sends $$SY_FP 39,1 command then refreshes screen.
  /// For CH2 button: sends $$SY_FP 40,1 command then refreshes screen.
  /// Also toggles the channel state in the UI.
  /// Reuses M1 button functionality for screen dump acquisition.
  void _handleChannelToggle(String channel) async {
    // Block if already processing a soft key or acquiring a screen dump
    if (_isProcessingSoftKey || !_isOnline) {
      return;
    }

    setState(() {
      _isProcessingSoftKey = true;
    });

    try {
      // CH1 and CH2 buttons are always activated - no state change
      // Send the appropriate SCPI command based on channel
      final String command;
      if (channel == 'CH1') {
        command = '\$\$SY_FP 39,1';
      } else {
        command = '\$\$SY_FP 40,1';
      }

      final success = await _sendCommand(command);

      if (success) {
        // Immediately request screen dump image (reusing M1 button functionality)
        _scheduleRefresh();
      }
    } catch (e) {
      AppLogger().log('Channel toggle handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing $channel button: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSoftKey = false;
        });
      }
    }
  }

  /// Handles horizontal button press (Roll).
  /// For Roll button: sends $$SY_FP 49,1 command then refreshes screen.
  /// Reuses M1 button functionality for screen dump acquisition.
  void _handleHorizontalButtonPress(String buttonLabel) async {
    // Block if already processing a soft key or acquiring a screen dump
    if (_isProcessingSoftKey || !_isOnline) {
      return;
    }

    setState(() {
      _isProcessingSoftKey = true;
    });

    try {
      // Handle different horizontal buttons
      if (buttonLabel == 'Roll') {
        // Send the special SCPI command for Roll button
        final command = '\$\$SY_FP 49,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else {
        // For other horizontal buttons, just log for now
        AppLogger().log(
          'Horizontal button pressed: $buttonLabel (not implemented yet)',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Button "$buttonLabel" not implemented yet'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger().log('Horizontal button handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing $buttonLabel button: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSoftKey = false;
        });
      }
    }
  }

  /// Handles trigger button press (Setup, Auto, Normal, Single).
  /// For Setup button: sends $$SY_FP 18,1 command then refreshes screen.
  /// For Auto button: sends $$SY_FP 17,1 command then refreshes screen.
  /// For Normal button: sends $$SY_FP 19,1 command then refreshes screen.
  /// For Single button: sends $$SY_FP 20,1 command then refreshes screen.
  /// Reuses M1 button functionality for screen dump acquisition.
  void _handleTriggerButtonPress(String buttonLabel) async {
    // Block if already processing a soft key or acquiring a screen dump
    if (_isProcessingSoftKey || !_isOnline) {
      return;
    }

    setState(() {
      _isProcessingSoftKey = true;
    });

    try {
      // Handle different trigger buttons
      if (buttonLabel == 'Setup') {
        // Send the special SCPI command for Setup button
        final command = '\$\$SY_FP 18,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'Auto') {
        // Send the special SCPI command for Auto button
        final command = '\$\$SY_FP 17,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'Normal') {
        // Send the special SCPI command for Normal button
        final command = '\$\$SY_FP 19,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else if (buttonLabel == 'Single') {
        // Send the special SCPI command for Single button
        final command = '\$\$SY_FP 20,1';
        final success = await _sendCommand(command);

        if (success) {
          // Immediately request screen dump image (reusing M1 button functionality)
          _scheduleRefresh();
        }
      } else {
        // For other trigger buttons, just log for now
        AppLogger().log(
          'Trigger button pressed: $buttonLabel (not implemented yet)',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Button "$buttonLabel" not implemented yet'),
              backgroundColor: Colors.blue,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger().log('Trigger button handler error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing $buttonLabel button: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingSoftKey = false;
        });
      }
    }
  }
}
