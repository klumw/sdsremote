/// Main Data Logger panel widget.
///
/// Combines the XY plot, configuration dialog, and control buttons into
/// a single panel that fits into the center area of the main window
/// (replacing the waveform display while the Data Logger is active).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'data_logger_models.dart';
import 'data_logger_service.dart';
import 'data_logger_plot.dart';
import 'data_logger_dialog.dart';
import '../dart_vxi11.dart';

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
  )? onSaveState;

  /// Called when the service is created so the parent can stop it
  /// when switching panels.
  final ValueChanged<DataLoggerService>? onServiceCreated;

  /// Called when recording finishes with the final points and config.
  /// Fires both on manual stop and when the configured duration elapses.
  final void Function(
    List<DataLoggerPoint> points,
    DataLoggerConfig? config,
  )? onRecordingFinished;

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
  int _elapsedSeconds = 0;
  Set<String> _hiddenLines = {};
  double? _hoveredTime;
  double _hoverX = 0;
  double _hoverY = 0;

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
    if (widget.savedStatus != null) {
      _status = widget.savedStatus!;
    } else {
      _status = DataLoggerStatus.configuring;
    }
    if (widget.savedHiddenLines != null) {
      _hiddenLines = Set<String>.of(widget.savedHiddenLines!);
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
    _service?.dispose();
    _service = null;
    _pulseController.dispose();
    // If the status is "running" but the service wasn't actually running
    // (stopped externally via _stopDataLoggerIfRunning), correct it.
    if (_status == DataLoggerStatus.running && !wasRunning) {
      _status = DataLoggerStatus.stopped;
    }
    // Notify parent to save current state before panel is destroyed
    widget.onSaveState?.call(
      _points,
      _config,
      _status,
      _hiddenLines,
    );
    super.dispose();
  }

  // ---------- Service Management ----------

  void _ensureService() {
    if (_service != null) return;
    _service = DataLoggerService(widget.getInstrument);
    _subscription = _service!.pointStream.listen(_onDataPoint);
    widget.onServiceCreated?.call(_service!);
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

  // ---------- Callbacks ----------

  void _onConfigChanged(DataLoggerConfig config) {
    setState(() {
      _config = config;
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
      _elapsedSeconds = 0;
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
      _elapsedSeconds = 0;
      _status = DataLoggerStatus.configuring;
      // Keep _config as-is so the form shows previously entered values
    });
  }

  void _onRestart() {
    if (_config == null) return;
    _ensureService();
    setState(() {
      _points.clear();
      _elapsedSeconds = 0;
      _status = DataLoggerStatus.running;
    });
    _pulseController.repeat();
    widget.onRunningChanged?.call(true);
    _service!.start(_config!);
  }

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final isExpanded = _status == DataLoggerStatus.running ||
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
                          (_config != null && _config!.description.isNotEmpty) ? 8 : 16,
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
                                        ch1VppEnabled: _config?.ch1VppEnabled ?? true,
                                        ch1FreqEnabled: _config?.ch1FreqEnabled ?? true,
                                        ch2VppEnabled: _config?.ch2VppEnabled ?? false,
                                        ch2FreqEnabled: _config?.ch2FreqEnabled ?? false,
                                        status: _status,
                                        totalDurationSeconds: (_config?.durationMinutes ?? 1) * 60.0,
                                        hiddenLines: _hiddenLines,
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
                                            _hoveredTime = time < 0 ? null : time;
                                            _hoverX = localX;
                                            _hoverY = localY;
                                          });
                                        },
                                      ),
                                      if (_hoveredTime != null && _points.isNotEmpty)
                                        _buildHoverTooltip(
                                          tooltipAreaWidth: constraints.maxWidth,
                                          tooltipAreaHeight: constraints.maxHeight,
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
                  // Legend toggle chips (outside RepaintBoundary, not captured)
                  if (_status == DataLoggerStatus.running ||
                      _status == DataLoggerStatus.stopped)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                      child: _buildLegendToggleRow(),
                    ),
                ],
              ),
            ),

          // ---- Bottom Controls ----
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
        rows.add(Text('CH1 Vpp: ${nearest.ch1Vpp!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFFFFFF00), fontSize: 11)));
      }
    }
    if (_config?.ch1FreqEnabled == true) {
      if (!_hiddenLines.contains('ch1_freq') && nearest.ch1Freq != null) {
        rows.add(Text('CH1 Freq: ${_fmtSi(nearest.ch1Freq!)}Hz',
            style: const TextStyle(color: Color(0xFFFFFF00), fontSize: 11)));
      }
    }
    if (_config?.ch2VppEnabled == true) {
      if (!_hiddenLines.contains('ch2_vpp') && nearest.ch2Vpp != null) {
        rows.add(Text('CH2 Vpp: ${nearest.ch2Vpp!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFFFF20FF), fontSize: 11)));
      }
    }
    if (_config?.ch2FreqEnabled == true) {
      if (!_hiddenLines.contains('ch2_freq') && nearest.ch2Freq != null) {
        rows.add(Text('CH2 Freq: ${_fmtSi(nearest.ch2Freq!)}Hz',
            style: const TextStyle(color: Color(0xFFFF20FF), fontSize: 11)));
      }
    }
    // Position tooltip near the cursor, clamped within the actual available area.
    const tooltipH = 80.0;
    const tooltipW = 180.0;
    final left = (_hoverX + 16).clamp(0.0, tooltipAreaWidth - tooltipW);
    final top = (_hoverY - tooltipH - 8).clamp(0.0, tooltipAreaHeight - tooltipH - 8);
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

  /// Row of clickable legend chips to toggle individual plot lines on/off.
  Widget _buildLegendToggleRow() {
    final items = <Widget>[];
    if (_config?.ch1VppEnabled == true) {
      if (items.isNotEmpty) items.add(const SizedBox(width: 8));
      items.add(_legendChip('CH1 Vpp', 'ch1_vpp',
          const Color(0xFFFFFF00)));
    }
    if (_config?.ch1FreqEnabled == true) {
      if (items.isNotEmpty) items.add(const SizedBox(width: 4));
      items.add(_legendChip('CH1 Freq', 'ch1_freq',
          const Color(0xFFFFFF00)));
    }
    if (_config?.ch2VppEnabled == true) {
      if (items.isNotEmpty) items.add(const SizedBox(width: 8));
      items.add(_legendChip('CH2 Vpp', 'ch2_vpp',
          const Color(0xFFFF20FF)));
    }
    if (_config?.ch2FreqEnabled == true) {
      if (items.isNotEmpty) items.add(const SizedBox(width: 4));
      items.add(_legendChip('CH2 Freq', 'ch2_freq',
          const Color(0xFFFF20FF)));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: items),
    );
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
    final isExpanded = _status == DataLoggerStatus.running ||
        _status == DataLoggerStatus.stopped;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1D33),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        border: const Border(
          top: BorderSide(color: Color(0xFF475569)),
        ),
      ),
      child: isExpanded
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: DataLoggerDialog(
                  currentConfig: _config,
                  status: _status,
                  pointCount: _points.length,
                  totalPoints: _config?.totalPoints ?? 0,
                  elapsedSeconds: _elapsedSeconds,
                  onStart: _onStart,
                  onStop: _onStop,
                  onNew: _onNew,
                  onRestart: _onRestart,
                  onConfigChanged: _onConfigChanged,
                ),
              ),
            )
          : DataLoggerDialog(
              currentConfig: _config,
              status: _status,
              pointCount: _points.length,
              totalPoints: _config?.totalPoints ?? 0,
              elapsedSeconds: _elapsedSeconds,
              onStart: _onStart,
              onStop: _onStop,
              onNew: _onNew,
              onRestart: _onRestart,
              onConfigChanged: _onConfigChanged,
            ),
    );
  }
}
