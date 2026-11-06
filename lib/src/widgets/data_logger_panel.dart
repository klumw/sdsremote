/// Main Data Logger panel widget.
///
/// Combines the XY plot, configuration dialog, and control buttons into
/// a single panel that fits into the center area of the main window
/// (replacing the waveform display while the Data Logger is active).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../data_logger/data_logger_alarms.dart';
import '../data_logger/data_logger_models.dart';
import '../data_logger/data_logger_service.dart';
import '../data_logger/data_logger_statistics.dart';
import 'data_logger_plot.dart';
import 'data_logger_dialog.dart';
import '../instrument/dart_vxi11.dart';

/// Accent color for the Gain (dB) measurement, matching the plot line color.
const Color _gainColor = Color(0xFF00E5FF);

/// The main Data Logger panel widget.
///
/// Manages the logger lifecycle: idle → configuring → running → stopped.
/// Shows the XY plot during and after recording, and manages the
/// configuration dialog and control buttons.
class DataLoggerPanel extends StatefulWidget {
  /// Async function to obtain a connected instrument for SCPI queries.
  final Future<Vxi11Instrument?> Function() getInstrument;

  /// Whether the device is currently online.
  final bool isOnline;

  /// Analog channel count of the connected instrument (2 or 4).
  final int channelCount;

  /// Called when the panel should be closed.
  final VoidCallback onClose;

  /// Called when the running status changes (true = recording, false = not).
  final ValueChanged<bool>? onRunningChanged;

  /// Called when the panel is being closed, with the current state
  /// so it can be preserved and restored on reopen.
  final void Function(
    List<DataLoggerPoint> points,
    DataLoggerConfig? config,
    DataLoggerStatus status,
    Set<String> hiddenLines,
  )?
  onSaveState;

  /// Called when the service is created so the parent can stop it
  /// when switching panels.
  final ValueChanged<DataLoggerService>? onServiceCreated;

  /// Called when recording finishes with the final points and config.
  /// Fires both on manual stop and when the configured duration elapses.
  final void Function(List<DataLoggerPoint> points, DataLoggerConfig? config)?
  onRecordingFinished;

  /// Saved state to restore after panel is reopened.
  final List<DataLoggerPoint>? savedPoints;
  final DataLoggerConfig? savedConfig;
  final DataLoggerStatus? savedStatus;
  final Set<String>? savedHiddenLines;

  /// GlobalKey for the plot area's RepaintBoundary, used to capture
  /// the chart as an image for PDF report generation.
  final GlobalKey? plotKey;

  const DataLoggerPanel({
    super.key,
    required this.getInstrument,
    required this.isOnline,
    this.channelCount = 2,
    required this.onClose,
    this.plotKey,
    this.onRunningChanged,
    this.onSaveState,
    this.onServiceCreated,
    this.onRecordingFinished,
    this.savedPoints,
    this.savedConfig,
    this.savedStatus,
    this.savedHiddenLines,
  });

  @override
  State<DataLoggerPanel> createState() => _DataLoggerPanelState();
}

class _DataLoggerPanelState extends State<DataLoggerPanel>
    with SingleTickerProviderStateMixin {
  // ---------- State ----------
  DataLoggerStatus _status = DataLoggerStatus.idle;
  DataLoggerConfig? _config;
  List<DataLoggerPoint> _points = [];
  DataLoggerService? _service;
  StreamSubscription<DataLoggerPoint>? _subscription;
  StreamSubscription<DataLoggerAlarmEvent>? _alarmSubscription;
  List<DataLoggerAlarmEvent> _alarmEvents = [];
  int _elapsedSeconds = 0;
  Set<String> _hiddenLines = {};
  double? _hoveredTime;
  double _hoverX = 0;
  double _hoverY = 0;

  // Collapsible detail panels; both start hidden and are toggled from the
  // buttons in the control box.
  bool _showAlarmsPanel = false;
  bool _showDeltasPanel = false;

  /// Whether the bottom controls box is collapsed to its slim header bar,
  /// leaving the plot the full panel height.
  bool _controlsCollapsed = false;

  void _toggleControls() {
    setState(() {
      _controlsCollapsed = !_controlsCollapsed;
    });
  }

  /// Whether the recording produced an alarm worth showing in the panel.
  bool get _hasAlarms =>
      _alarmEvents.isNotEmpty ||
      (_points.isNotEmpty && _points.last.activeAlarms.isNotEmpty);

  void _toggleAlarmsPanel() {
    setState(() {
      _showAlarmsPanel = !_showAlarmsPanel;
    });
  }

  void _toggleDeltasPanel() {
    setState(() {
      _showDeltasPanel = !_showDeltasPanel;
    });
  }

  // ---------- Animation for running indicator ----------
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    // Restore saved state if available (panel was reopened)
    if (widget.savedPoints != null) {
      _points = List<DataLoggerPoint>.of(widget.savedPoints!);
    }
    if (widget.savedConfig != null) {
      _config = widget.savedConfig;
    } else {
      _config = const DataLoggerConfig();
    }
    _config = _sanitizeConfig(_config!);
    // Restored recordings replay their alarm events from the stored samples
    // and rules; the live stream only feeds a running session.
    if (_points.isNotEmpty && _config!.hasActiveAlarms) {
      _alarmEvents = dataLoggerAlarmEvents(config: _config!, points: _points);
    }
    if (widget.savedStatus != null) {
      _status = widget.savedStatus!;
    } else {
      _status = DataLoggerStatus.configuring;
    }
    if (widget.savedHiddenLines != null) {
      _hiddenLines = Set<String>.of(widget.savedHiddenLines!);
    }

    // Query probe dividers early so the setup dialog shows real values.
    if (_status == DataLoggerStatus.configuring) {
      _queryProbeDividersEarly();
    }
  }

  @override
  void dispose() {
    // Stop recording but preserve data for when panel reopens.
    // Detect if we were stopped externally (e.g. panel switched away):
    // the service is no longer running but our status still says "running".
    final wasRunning = _service != null && _service!.isRunning;
    if (wasRunning) {
      _service?.stop();
    }
    _subscription?.cancel();
    _alarmSubscription?.cancel();
    _service?.dispose();
    _service = null;
    _pulseController.dispose();
    // If the status is "running" but the service wasn't actually running
    // (stopped externally via _stopDataLoggerIfRunning), correct it.
    if (_status == DataLoggerStatus.running && !wasRunning) {
      _status = DataLoggerStatus.stopped;
    }
    // Notify parent to save current state before panel is destroyed
    widget.onSaveState?.call(_points, _config, _status, _hiddenLines);
    super.dispose();
  }

  // ---------- Service Management ----------

  void _ensureService() {
    if (_service != null) return;
    _service = DataLoggerService(widget.getInstrument);
    _subscription = _service!.pointStream.listen(_onDataPoint);
    _alarmSubscription = _service!.alarmStream.listen(_onAlarmEvent);
    widget.onServiceCreated?.call(_service!);
    // Listen for probe divider updates from the service so we can
    // propagate them to _config and rebuild the dialog with real values.
    _service!.onProbeDividersUpdated = () {
      if (_service?.config != null && mounted) {
        setState(() {
          _config = _service!.config;
        });
      }
    };
  }

  /// Query probe divider values from the instrument while still in the
  /// configuring phase, so the setup dialog can display the actual probe
  /// attenuation factors before recording starts.
  Future<void> _queryProbeDividersEarly() async {
    if (_config == null) return;
    // Only query the channels that have any measurement enabled.
    final enabled = <int, bool>{
      1: _config!.ch1Enabled,
      2: _config!.ch2Enabled,
      3: _config!.ch3Enabled,
      4: _config!.ch4Enabled,
    };
    if (!enabled.values.any((value) => value)) return;

    try {
      final instr = await widget.getInstrument();
      if (instr == null) return;
      final dividers = <int, double>{};
      for (final entry in enabled.entries) {
        if (!entry.value) continue;
        final resp = (await instr.queryString('C${entry.key}:ATTN?')).trim();
        final m = RegExp(
          r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?',
        ).allMatches(resp).toList();
        if (m.isEmpty) continue;
        final value = double.tryParse(m.last.group(0)!);
        if (value != null && value > 0) dividers[entry.key] = value;
      }
      if (dividers.isNotEmpty) {
        setState(() {
          _config = _config!.copyWith(
            probeDividerCh1: dividers[1] ?? _config!.probeDividerCh1,
            probeDividerCh2: dividers[2] ?? _config!.probeDividerCh2,
            probeDividerCh3: dividers[3] ?? _config!.probeDividerCh3,
            probeDividerCh4: dividers[4] ?? _config!.probeDividerCh4,
          );
        });
      }
    } catch (_) {
      // Probe query is best-effort; silently ignore failures.
    }
  }

  void _onDataPoint(DataLoggerPoint point) {
    if (!mounted) return;
    setState(() {
      // Create a new list reference so CustomPainter's shouldRepaint
      // detects the change via != operator.
      _points = [..._points, point];
      _elapsedSeconds = point.elapsedSeconds.round();
      if (_service != null && !_service!.isRunning) {
        _status = DataLoggerStatus.stopped;
        _pulseController.stop();
        widget.onRunningChanged?.call(false);
        // Notify parent that recording finished with final data
        widget.onRecordingFinished?.call(_points, _config);
      }
    });
  }

  void _onAlarmEvent(DataLoggerAlarmEvent event) {
    if (!mounted) return;
    setState(() {
      _alarmEvents = [..._alarmEvents, event];
    });
  }

  // ---------- Callbacks ----------

  /// Clears CH3/CH4 selections when the connected instrument only has two
  /// channels, e.g. when a saved configuration from a four-channel scope is
  /// restored on a two-channel scope.
  DataLoggerConfig _sanitizeConfig(DataLoggerConfig config) {
    if (widget.channelCount >= 4) return config;
    return config.copyWith(
      ch3VppEnabled: false,
      ch3MeanEnabled: false,
      ch3RmsEnabled: false,
      ch3DutyEnabled: false,
      ch3FreqEnabled: false,
      ch4VppEnabled: false,
      ch4MeanEnabled: false,
      ch4RmsEnabled: false,
      ch4DutyEnabled: false,
      ch4FreqEnabled: false,
    );
  }

  void _onConfigChanged(DataLoggerConfig config) {
    setState(() {
      _config = _sanitizeConfig(config);
    });
  }

  void _onStart() {
    if (_config == null) return;
    _ensureService();
    // First update the UI to show "Running" state immediately,
    // then start the SCPI work on the next frame so the button
    // doesn't feel unresponsive.
    setState(() {
      _points.clear();
      _alarmEvents.clear();
      _elapsedSeconds = 0;
      _showAlarmsPanel = false;
      _showDeltasPanel = false;
      _status = DataLoggerStatus.running;
    });
    _pulseController.repeat();
    widget.onRunningChanged?.call(true);
    // Defer SCPI start to after the current frame has been painted
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _service!.start(_config!);
    });
  }

  void _onStop() {
    _service?.stop();
    _pulseController.stop();
    widget.onRunningChanged?.call(false);
    setState(() {
      _status = DataLoggerStatus.stopped;
    });
  }

  void _onNew() {
    _service?.stop();
    _service?.dispose();
    _service = null;
    _subscription?.cancel();
    _subscription = null;
    _pulseController.stop();
    widget.onRunningChanged?.call(false);
    setState(() {
      _points.clear();
      _alarmEvents.clear();
      _elapsedSeconds = 0;
      _showAlarmsPanel = false;
      _showDeltasPanel = false;
      _controlsCollapsed = false;
      _status = DataLoggerStatus.configuring;
      // Keep _config as-is so the form shows previously entered values
    });
    // Re-query probe dividers for the new configuration session.
    _queryProbeDividersEarly();
  }

  void _onRestart() {
    if (_config == null) return;
    _ensureService();
    setState(() {
      _points.clear();
      _alarmEvents.clear();
      _elapsedSeconds = 0;
      _showAlarmsPanel = false;
      _showDeltasPanel = false;
      _status = DataLoggerStatus.running;
    });
    _pulseController.repeat();
    widget.onRunningChanged?.call(true);
    _service!.start(_config!);
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final isExpanded =
        _status == DataLoggerStatus.running ||
        _status == DataLoggerStatus.stopped;
    return Container(
      width: isExpanded ? double.infinity : 700,
      height: isExpanded ? double.infinity : null,
      decoration: BoxDecoration(
        color: const Color(0xFF0A192F),
        border: Border.all(color: const Color(0xFF475569)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        // When configuring (plot hidden), shrink-wrap to fit the header +
        // config dialog. When running/stopped, allow Expanded plot to fill.
        mainAxisSize: _status == DataLoggerStatus.configuring
            ? MainAxisSize.min
            : MainAxisSize.max,
        children: [
          // ---- Header ----
          _buildHeader(),

          // ---- Plot Area ----
          // Only show the plot during running/stopped; hide the empty
          // container during the setup/configuring phase.
          if (_status != DataLoggerStatus.configuring)
            Expanded(
              child: Column(
                children: [
                  // Description banner (outside RepaintBoundary, not captured)
                  if (_config != null && _config!.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Text(
                        _config!.description,
                        style: const TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  // Plot + legend inside RepaintBoundary for image capture
                  Expanded(
                    child: RepaintBoundary(
                      key: widget.plotKey,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          (_config != null && _config!.description.isNotEmpty)
                              ? 8
                              : 16,
                          16,
                          0,
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return Stack(
                                    children: [
                                      DataLoggerPlot(
                                        points: _points,
                                        ch1VppEnabled:
                                            _config?.ch1VppEnabled ?? true,
                                        ch1MeanEnabled:
                                            _config?.ch1MeanEnabled ?? false,
                                        ch1RmsEnabled:
                                            _config?.ch1RmsEnabled ?? false,
                                        ch1DutyEnabled:
                                            _config?.ch1DutyEnabled ?? false,
                                        ch1FreqEnabled:
                                            _config?.ch1FreqEnabled ?? true,
                                        ch2VppEnabled:
                                            _config?.ch2VppEnabled ?? false,
                                        ch2MeanEnabled:
                                            _config?.ch2MeanEnabled ?? false,
                                        ch2RmsEnabled:
                                            _config?.ch2RmsEnabled ?? false,
                                        ch2DutyEnabled:
                                            _config?.ch2DutyEnabled ?? false,
                                        ch2FreqEnabled:
                                            _config?.ch2FreqEnabled ?? false,
                                        ch3VppEnabled:
                                            _config?.ch3VppEnabled ?? false,
                                        ch3MeanEnabled:
                                            _config?.ch3MeanEnabled ?? false,
                                        ch3RmsEnabled:
                                            _config?.ch3RmsEnabled ?? false,
                                        ch3DutyEnabled:
                                            _config?.ch3DutyEnabled ?? false,
                                        ch3FreqEnabled:
                                            _config?.ch3FreqEnabled ?? false,
                                        ch4VppEnabled:
                                            _config?.ch4VppEnabled ?? false,
                                        ch4MeanEnabled:
                                            _config?.ch4MeanEnabled ?? false,
                                        ch4RmsEnabled:
                                            _config?.ch4RmsEnabled ?? false,
                                        ch4DutyEnabled:
                                            _config?.ch4DutyEnabled ?? false,
                                        ch4FreqEnabled:
                                            _config?.ch4FreqEnabled ?? false,
                                        gainDbEnabled:
                                            _config?.gainDbEnabled ?? false,
                                        status: _status,
                                        totalDurationSeconds:
                                            (_config?.durationMinutes ?? 1) *
                                            60.0,
                                        hiddenLines: _hiddenLines,
                                        alarmRules:
                                            _config?.alarmRules ?? const {},
                                        alarmEvents: _alarmEvents,
                                        onToggleLine: (id) {
                                          setState(() {
                                            if (_hiddenLines.contains(id)) {
                                              _hiddenLines.remove(id);
                                            } else {
                                              _hiddenLines.add(id);
                                            }
                                          });
                                        },
                                        onHover: (time, localX, localY) {
                                          setState(() {
                                            _hoveredTime = time < 0
                                                ? null
                                                : time;
                                            _hoverX = localX;
                                            _hoverY = localY;
                                          });
                                        },
                                      ),
                                      if (_hoveredTime != null &&
                                          _points.isNotEmpty)
                                        _buildHoverTooltip(
                                          tooltipAreaWidth:
                                              constraints.maxWidth,
                                          tooltipAreaHeight:
                                              constraints.maxHeight,
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Collapsible detail panels, hidden by default and opened
                  // from the Alarms / Deltas buttons in the control box.
                  if (_showAlarmsPanel &&
                      (_status == DataLoggerStatus.running ||
                          _status == DataLoggerStatus.stopped))
                    _buildAlarmsPanel(),
                  if (_showDeltasPanel && _status == DataLoggerStatus.stopped)
                    _buildDeltasPanel(),
                ],
              ),
            ),

          // ---- Bottom Controls ----
          // The configuration form grows with the number of channels; keep it
          // scrollable when it exceeds the available height.
          if (_status == DataLoggerStatus.configuring)
            Flexible(
              child: SingleChildScrollView(child: _buildBottomControls()),
            )
          else
            _buildBottomControls(),
        ],
      ),
    );
  }

  /// Returns (conversionFactor, unitSuffix) matching the plot's X-axis time unit.
  (double, String) _timeUnitInfo() {
    final totalSeconds = (_config?.durationMinutes ?? 1) * 60.0;
    if (totalSeconds >= 7200) {
      return (3600.0, 'h');
    } else if (totalSeconds >= 120) {
      return (60.0, 'min');
    } else {
      return (1.0, 's');
    }
  }

  /// Tooltip overlay showing data values at the hovered time position.
  Widget _buildHoverTooltip({
    required double tooltipAreaWidth,
    required double tooltipAreaHeight,
  }) {
    final time = _hoveredTime!;
    // Find the nearest data point (or interpolate between two)
    DataLoggerPoint? before, after;
    for (final p in _points) {
      if (p.elapsedSeconds <= time) before = p;
      if (p.elapsedSeconds >= time && after == null) after = p;
    }
    final nearest = (before ?? after)!;
    final (timeFactor, timeUnit) = _timeUnitInfo();
    final displayTime = (nearest.elapsedSeconds / timeFactor).round();
    final rows = <Widget>[
      Text(
        't = $displayTime$timeUnit',
        style: const TextStyle(color: Colors.white70, fontSize: 10),
      ),
    ];
    if (_config?.ch1VppEnabled == true) {
      if (!_hiddenLines.contains('ch1_vpp') && nearest.ch1Vpp != null) {
        rows.add(
          Text(
            'CH1 Vpp: ${nearest.ch1Vpp!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFFFFFF00), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch1MeanEnabled == true) {
      if (!_hiddenLines.contains('ch1_mean') && nearest.ch1Mean != null) {
        rows.add(
          Text(
            'CH1 Mean: ${nearest.ch1Mean!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFF00E676), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch1RmsEnabled == true) {
      if (!_hiddenLines.contains('ch1_rms') && nearest.ch1Rms != null) {
        rows.add(
          Text(
            'CH1 Rms: ${nearest.ch1Rms!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFF00E676), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch1DutyEnabled == true) {
      if (!_hiddenLines.contains('ch1_duty') && nearest.ch1Duty != null) {
        rows.add(
          Text(
            'CH1 Duty: ${nearest.ch1Duty!.toStringAsFixed(1)}%',
            style: const TextStyle(color: Color(0xFFFFFF00), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch1FreqEnabled == true) {
      if (!_hiddenLines.contains('ch1_freq') && nearest.ch1Freq != null) {
        rows.add(
          Text(
            'CH1 Freq: ${_fmtSi(nearest.ch1Freq!)}Hz',
            style: const TextStyle(color: Color(0xFFFFFF00), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch2VppEnabled == true) {
      if (!_hiddenLines.contains('ch2_vpp') && nearest.ch2Vpp != null) {
        rows.add(
          Text(
            'CH2 Vpp: ${nearest.ch2Vpp!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFFFF20FF), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch2MeanEnabled == true) {
      if (!_hiddenLines.contains('ch2_mean') && nearest.ch2Mean != null) {
        rows.add(
          Text(
            'CH2 Mean: ${nearest.ch2Mean!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFFFF5252), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch2RmsEnabled == true) {
      if (!_hiddenLines.contains('ch2_rms') && nearest.ch2Rms != null) {
        rows.add(
          Text(
            'CH2 Rms: ${nearest.ch2Rms!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFFFF5252), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch2DutyEnabled == true) {
      if (!_hiddenLines.contains('ch2_duty') && nearest.ch2Duty != null) {
        rows.add(
          Text(
            'CH2 Duty: ${nearest.ch2Duty!.toStringAsFixed(1)}%',
            style: const TextStyle(color: Color(0xFFFF20FF), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch2FreqEnabled == true) {
      if (!_hiddenLines.contains('ch2_freq') && nearest.ch2Freq != null) {
        rows.add(
          Text(
            'CH2 Freq: ${_fmtSi(nearest.ch2Freq!)}Hz',
            style: const TextStyle(color: Color(0xFFFF20FF), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch3VppEnabled == true) {
      if (!_hiddenLines.contains('ch3_vpp') && nearest.ch3Vpp != null) {
        rows.add(
          Text(
            'CH3 Vpp: ${nearest.ch3Vpp!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch3MeanEnabled == true) {
      if (!_hiddenLines.contains('ch3_mean') && nearest.ch3Mean != null) {
        rows.add(
          Text(
            'CH3 Mean: ${nearest.ch3Mean!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFF00B0FF), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch3RmsEnabled == true) {
      if (!_hiddenLines.contains('ch3_rms') && nearest.ch3Rms != null) {
        rows.add(
          Text(
            'CH3 Rms: ${nearest.ch3Rms!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFF00B0FF), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch3DutyEnabled == true) {
      if (!_hiddenLines.contains('ch3_duty') && nearest.ch3Duty != null) {
        rows.add(
          Text(
            'CH3 Duty: ${nearest.ch3Duty!.toStringAsFixed(1)}%',
            style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch3FreqEnabled == true) {
      if (!_hiddenLines.contains('ch3_freq') && nearest.ch3Freq != null) {
        rows.add(
          Text(
            'CH3 Freq: ${_fmtSi(nearest.ch3Freq!)}Hz',
            style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch4VppEnabled == true) {
      if (!_hiddenLines.contains('ch4_vpp') && nearest.ch4Vpp != null) {
        rows.add(
          Text(
            'CH4 Vpp: ${nearest.ch4Vpp!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFF66BB6A), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch4MeanEnabled == true) {
      if (!_hiddenLines.contains('ch4_mean') && nearest.ch4Mean != null) {
        rows.add(
          Text(
            'CH4 Mean: ${nearest.ch4Mean!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFFFFA726), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch4RmsEnabled == true) {
      if (!_hiddenLines.contains('ch4_rms') && nearest.ch4Rms != null) {
        rows.add(
          Text(
            'CH4 Rms: ${nearest.ch4Rms!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFFFFA726), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch4DutyEnabled == true) {
      if (!_hiddenLines.contains('ch4_duty') && nearest.ch4Duty != null) {
        rows.add(
          Text(
            'CH4 Duty: ${nearest.ch4Duty!.toStringAsFixed(1)}%',
            style: const TextStyle(color: Color(0xFF66BB6A), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.ch4FreqEnabled == true) {
      if (!_hiddenLines.contains('ch4_freq') && nearest.ch4Freq != null) {
        rows.add(
          Text(
            'CH4 Freq: ${_fmtSi(nearest.ch4Freq!)}Hz',
            style: const TextStyle(color: Color(0xFF66BB6A), fontSize: 11),
          ),
        );
      }
    }
    if (_config?.gainDbEnabled == true) {
      if (!_hiddenLines.contains('gain_db')) {
        // A silently missing row would hide that gain stopped being
        // measurable, so the popup says so where the value would be.
        rows.add(
          Text(
            'Gain: ${formatGainValue(nearest.gainDb)}',
            style: const TextStyle(color: _gainColor, fontSize: 11),
          ),
        );
      }
    }
    // Position tooltip near the cursor, clamped within the actual available area.
    // When cursor is past 50% of chart width, show tooltip to the left of cursor
    // to avoid overflowing off-screen.
    const tooltipH = 80.0;
    const tooltipW = 180.0;
    const tooltipGap = 10.0;
    final midX = tooltipAreaWidth * 0.5;
    // The tooltip is inside a Stack that covers the entire plot area.
    // _hoverX is the local coordinate within the plot area (including margins).
    // We want the tooltip to be relative to the cursor position within the plot.
    // When on the left, we want it to be at _hoverX + tooltipGap.
    // When on the right, we want it to be at _hoverX - tooltipW - tooltipGap.
    final left = _hoverX >= midX
        ? (_hoverX - tooltipW - tooltipGap + 60.0).clamp(
            0.0,
            tooltipAreaWidth - tooltipW,
          )
        : (_hoverX + tooltipGap).clamp(0.0, tooltipAreaWidth - tooltipW);
    final top = (_hoverY - tooltipH - 8).clamp(
      0.0,
      tooltipAreaHeight - tooltipH - 8,
    );
    return Positioned(
      left: left,
      top: top,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xDD0A192F),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF475569)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        ),
      ),
    );
  }

  String _fmtSi(double v) {
    final abs = v.abs();
    if (abs >= 1e6) return '${(v / 1e6).toStringAsFixed(2)}M';
    if (abs >= 1e3) return '${(v / 1e3).toStringAsFixed(2)}k';
    return v.toStringAsFixed(1);
  }

  /// Row of clickable measurement chips to toggle individual plot lines.
  ///
  /// Chips are grouped per channel; each channel's probe divider label sits
  /// directly underneath its chips. Gain has no channel of its own, so when
  /// CH1/CH2 have no chips of their own, their probe labels are shown under
  /// the Gain chip that reads them.
  Widget _buildMeasurementChips() {
    final config = _config;
    if (config == null) return const SizedBox.shrink();

    Widget probeLabel(int channel) {
      final divider = switch (channel) {
        1 => config.probeDividerCh1,
        2 => config.probeDividerCh2,
        3 => config.probeDividerCh3,
        _ => config.probeDividerCh4,
      };
      return Text(
        'CH$channel-Probe: ${_fmtProbe(divider)}',
        style: TextStyle(
          color: _parameterColor('ch$channel'),
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    final groups = <Widget>[];

    void addGroup(List<Widget> chips, List<Widget> probeLabels) {
      if (chips.isEmpty && probeLabels.isEmpty) return;
      if (groups.isNotEmpty) groups.add(const SizedBox(width: 8));
      groups.add(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (chips.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < chips.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    chips[i],
                  ],
                ],
              ),
            for (final label in probeLabels)
              Padding(
                padding: const EdgeInsets.only(left: 4, top: 2),
                child: label,
              ),
          ],
        ),
      );
    }

    final ch1Chips = <Widget>[
      if (config.ch1VppEnabled)
        _legendChip('CH1 Vpp', 'ch1_vpp', const Color(0xFFFFFF00)),
      if (config.ch1MeanEnabled)
        _legendChip('CH1 Mean', 'ch1_mean', const Color(0xFF00E676)),
      if (config.ch1RmsEnabled)
        _legendChip('CH1 Rms', 'ch1_rms', const Color(0xFF00E676)),
      if (config.ch1DutyEnabled)
        _legendChip('CH1 Duty', 'ch1_duty', const Color(0xFFFFFF00)),
      if (config.ch1FreqEnabled)
        _legendChip('CH1 Freq', 'ch1_freq', const Color(0xFFFFFF00)),
    ];
    final ch2Chips = <Widget>[
      if (config.ch2VppEnabled)
        _legendChip('CH2 Vpp', 'ch2_vpp', const Color(0xFFFF20FF)),
      if (config.ch2MeanEnabled)
        _legendChip('CH2 Mean', 'ch2_mean', const Color(0xFFFF5252)),
      if (config.ch2RmsEnabled)
        _legendChip('CH2 Rms', 'ch2_rms', const Color(0xFFFF5252)),
      if (config.ch2DutyEnabled)
        _legendChip('CH2 Duty', 'ch2_duty', const Color(0xFFFF20FF)),
      if (config.ch2FreqEnabled)
        _legendChip('CH2 Freq', 'ch2_freq', const Color(0xFFFF20FF)),
    ];
    final ch3Chips = <Widget>[
      if (config.ch3VppEnabled)
        _legendChip('CH3 Vpp', 'ch3_vpp', const Color(0xFF4FC3F7)),
      if (config.ch3MeanEnabled)
        _legendChip('CH3 Mean', 'ch3_mean', const Color(0xFF00B0FF)),
      if (config.ch3RmsEnabled)
        _legendChip('CH3 Rms', 'ch3_rms', const Color(0xFF00B0FF)),
      if (config.ch3DutyEnabled)
        _legendChip('CH3 Duty', 'ch3_duty', const Color(0xFF4FC3F7)),
      if (config.ch3FreqEnabled)
        _legendChip('CH3 Freq', 'ch3_freq', const Color(0xFF4FC3F7)),
    ];
    final ch4Chips = <Widget>[
      if (config.ch4VppEnabled)
        _legendChip('CH4 Vpp', 'ch4_vpp', const Color(0xFF66BB6A)),
      if (config.ch4MeanEnabled)
        _legendChip('CH4 Mean', 'ch4_mean', const Color(0xFFFFA726)),
      if (config.ch4RmsEnabled)
        _legendChip('CH4 Rms', 'ch4_rms', const Color(0xFFFFA726)),
      if (config.ch4DutyEnabled)
        _legendChip('CH4 Duty', 'ch4_duty', const Color(0xFF66BB6A)),
      if (config.ch4FreqEnabled)
        _legendChip('CH4 Freq', 'ch4_freq', const Color(0xFF66BB6A)),
    ];
    final gainChips = <Widget>[
      if (config.gainDbEnabled) _legendChip('Gain (dB)', 'gain_db', _gainColor),
    ];

    final showCh1Probe =
        config.ch1VppEnabled ||
        config.ch1MeanEnabled ||
        config.ch1RmsEnabled ||
        config.gainDbEnabled;
    final showCh2Probe =
        config.ch2VppEnabled ||
        config.ch2MeanEnabled ||
        config.ch2RmsEnabled ||
        config.gainDbEnabled;
    final showCh3Probe =
        config.ch3VppEnabled || config.ch3MeanEnabled || config.ch3RmsEnabled;
    final showCh4Probe =
        config.ch4VppEnabled || config.ch4MeanEnabled || config.ch4RmsEnabled;

    addGroup(ch1Chips, [
      if (showCh1Probe && ch1Chips.isNotEmpty) probeLabel(1),
    ]);
    addGroup(ch2Chips, [
      if (showCh2Probe && ch2Chips.isNotEmpty) probeLabel(2),
    ]);
    addGroup(ch3Chips, [
      if (showCh3Probe && ch3Chips.isNotEmpty) probeLabel(3),
    ]);
    addGroup(ch4Chips, [
      if (showCh4Probe && ch4Chips.isNotEmpty) probeLabel(4),
    ]);
    addGroup(gainChips, [
      if (config.gainDbEnabled && ch1Chips.isEmpty) probeLabel(1),
      if (config.gainDbEnabled && ch2Chips.isEmpty) probeLabel(2),
    ]);

    if (groups.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: groups),
    );
  }

  /// Format a probe divider value (10.0 → "10x", 1.0 → "1x").
  String _fmtProbe(double value) {
    if (value == value.roundToDouble()) return '${value.round()}x';
    return '${value.toStringAsFixed(1)}x';
  }

  Widget _legendChip(String label, String id, Color color) {
    final hidden = _hiddenLines.contains(id);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (hidden) {
            _hiddenLines.remove(id);
          } else {
            _hiddenLines.add(id);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: hidden
              ? const Color(0xFF172A45).withValues(alpha: 0.3)
              : color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: hidden
                ? const Color(0xFF475569).withValues(alpha: 0.3)
                : color.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: hidden ? FontWeight.normal : FontWeight.bold,
            color: hidden ? Colors.white38 : Colors.white,
          ),
        ),
      ),
    );
  }

  /// Collapsible panel listing the alarm messages of the current recording.
  ///
  /// Newest entry first; the list scrolls when it outgrows the panel.
  Widget _buildAlarmsPanel() {
    final active = _points.isNotEmpty
        ? _points.last.activeAlarms
        : const <String>{};
    final events = _alarmEvents;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF172A45).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.45)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Alarm Messages',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${events.length} events',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
                const Spacer(),
                _buildPanelCloseButton(_toggleAlarmsPanel),
              ],
            ),
            if (active.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final parameterId in active)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.6),
                        ),
                      ),
                      child: Text(
                        '${dataLoggerParameterLabel(parameterId)} active',
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            if (events.isEmpty)
              const Text(
                'No alarms during this recording.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    // Newest event first.
                    final event = events[events.length - 1 - index];
                    return _buildAlarmEventRow(event);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// One alarm message: recording time, parameter, value and breached bound.
  Widget _buildAlarmEventRow(DataLoggerAlarmEvent event) {
    final parameter = dataLoggerParameterById(event.parameterId);
    final unit = parameter?.unit ?? '';
    final bound = event.direction == DataLoggerAlarmDirection.belowLower
        ? event.lower
        : event.upper;
    final relation = event.direction == DataLoggerAlarmDirection.belowLower
        ? 'below lower'
        : 'above upper';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              't=${_fmtAlarmTime(event.elapsedSeconds)}',
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          ),
          const Icon(
            Icons.warning_amber_rounded,
            size: 12,
            color: Colors.redAccent,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '${event.parameterLabel} ${_fmtStat(event.value, unit)} '
              '$relation ${_fmtStat(bound, unit)}',
              style: TextStyle(
                color: parameter == null
                    ? Colors.white70
                    : _parameterColor(parameter.channel),
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Collapsible panel with the per-parameter statistics of the recording.
  ///
  /// Replaces the former always-visible statistics strip.
  Widget _buildDeltasPanel() {
    final config = _config;
    if (config == null) return const SizedBox.shrink();
    final statistics = computeDataLoggerStatistics(
      config: config,
      points: _points,
    );

    final rows = <Widget>[];
    for (final parameter in dataLoggerParameters) {
      final stats = statistics[parameter.id];
      if (stats == null) continue;
      rows.add(_buildDeltaRow(parameter, stats));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF172A45).withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.45)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.trending_up,
                  size: 16,
                  color: Colors.cyanAccent,
                ),
                const SizedBox(width: 6),
                const Text(
                  'Deltas',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Change per parameter',
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
                const Spacer(),
                _buildPanelCloseButton(_toggleDeltasPanel),
              ],
            ),
            const SizedBox(height: 4),
            if (rows.isEmpty)
              const Text(
                'No data recorded.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: ListView(shrinkWrap: true, children: rows),
              ),
          ],
        ),
      ),
    );
  }

  /// One parameter row inside the deltas panel.
  Widget _buildDeltaRow(
    DataLoggerParameter parameter,
    ParameterStatistics stats,
  ) {
    final mean = stats.mean;
    final deviation = stats.standardDeviation;
    final trend = stats.trendPerMinute;
    final drift = stats.driftPercent;
    final values =
        'μ ${_fmtStat(mean, stats.unit)}'
        '${deviation == null ? '' : ' · σ ${_fmtStat(deviation, stats.unit)}'}'
        '${trend == null ? '' : ' · ${_fmtSignedStat(trend, stats.unit)}/min'}'
        '${drift == null ? '' : ' · ${drift >= 0 ? '+' : ''}${drift.toStringAsFixed(1)}%'}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              parameter.label,
              style: TextStyle(
                color: _parameterColor(parameter.channel),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              values,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  /// Small close button shared by the collapsible panels.
  Widget _buildPanelCloseButton(VoidCallback onPressed) {
    return IconButton(
      onPressed: onPressed,
      icon: const Icon(Icons.close, size: 16, color: Colors.white54),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      tooltip: 'Hide panel',
    );
  }

  /// Channel color used by the delta rows, matching the plot lines.
  Color _parameterColor(String channel) => switch (channel) {
    'ch1' => const Color(0xFFFFFF00),
    'ch2' => const Color(0xFFFF20FF),
    'ch3' => const Color(0xFF4FC3F7),
    'ch4' => const Color(0xFF66BB6A),
    _ => _gainColor,
  };

  String _fmtStat(double? value, String unit) {
    if (value == null || !value.isFinite) return '—';
    switch (unit) {
      case 'Hz':
        return '${_fmtSi(value)}Hz';
      case '%':
        return '${value.toStringAsFixed(1)}%';
      case 'dB':
        return '${value.toStringAsFixed(2)}dB';
      default:
        return '${value.toStringAsFixed(3)}$unit';
    }
  }

  String _fmtSignedStat(double value, String unit) {
    final text = _fmtStat(value, unit);
    return value >= 0 ? '+$text' : text;
  }

  String _fmtAlarmTime(double seconds) {
    if (seconds < 120) return '${seconds.round()}s';
    final minutes = seconds ~/ 60;
    final rest = seconds.round() % 60;
    return rest == 0 ? '${minutes}min' : '${minutes}min ${rest}s';
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF172A45),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.sync,
                color: _status == DataLoggerStatus.running
                    ? Colors.greenAccent
                    : Colors.cyanAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _status == DataLoggerStatus.stopped
                    ? 'Data Logger — Complete'
                    : 'Data Logger',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                onPressed: () {
                  _service?.stop();
                  widget.onClose();
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final isExpanded =
        _status == DataLoggerStatus.running ||
        _status == DataLoggerStatus.stopped;
    final dialog = DataLoggerDialog(
      currentConfig: _config,
      status: _status,
      channelCount: widget.channelCount,
      pointCount: _points.length,
      totalPoints: _config?.totalPoints ?? 0,
      elapsedSeconds: _elapsedSeconds,
      onStart: _onStart,
      onStop: _onStop,
      onNew: _onNew,
      onRestart: _onRestart,
      onConfigChanged: _onConfigChanged,
      hasAlarms: _hasAlarms,
      alarmsPanelVisible: _showAlarmsPanel,
      onToggleAlarms: _toggleAlarmsPanel,
      deltasPanelVisible: _showDeltasPanel,
      onToggleDeltas: _toggleDeltasPanel,
      // The measurement chips live in the running/stopped status row.
      measureChips: isExpanded ? _buildMeasurementChips() : null,
    );
    // The configuration form must stay visible so the recording can be
    // started; only the running/stopped control box is collapsible.
    final isCollapsible = _status != DataLoggerStatus.configuring;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1D33),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        border: const Border(top: BorderSide(color: Color(0xFF475569))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCollapsible) _buildControlsHeaderBar(),
          if (!isCollapsible || !_controlsCollapsed)
            Padding(
              padding: isCollapsible
                  ? const EdgeInsets.fromLTRB(16, 0, 16, 16)
                  : const EdgeInsets.all(16),
              child: isExpanded
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 700),
                        child: dialog,
                      ),
                    )
                  : dialog,
            ),
        ],
      ),
    );
  }

  /// Slim header bar of the collapsible bottom controls panel.
  ///
  /// Collapsing it leaves the recording controls hidden and lets the plot
  /// fill the remaining panel height.
  Widget _buildControlsHeaderBar() {
    return Tooltip(
      message: _controlsCollapsed ? 'Show controls' : 'Hide controls',
      child: InkWell(
        onTap: _toggleControls,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
          child: Row(
            children: [
              const Icon(Icons.tune, size: 14, color: Colors.white54),
              const SizedBox(width: 6),
              const Text(
                'Controls',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.4,
                ),
              ),
              const Spacer(),
              Icon(
                _controlsCollapsed ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: Colors.white54,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
