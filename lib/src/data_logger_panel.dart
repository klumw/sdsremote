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

  const DataLoggerPanel({
    super.key,
    required this.getInstrument,
    required this.isOnline,
    required this.onClose,
    this.onRunningChanged,
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
    // Start in configuring state to show the dialog immediately
    _status = DataLoggerStatus.configuring;
    _config = const DataLoggerConfig();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _service?.dispose();
    _service = null;
    _pulseController.dispose();
    super.dispose();
  }

  // ---------- Service Management ----------

  void _ensureService() {
    if (_service != null) return;
    _service = DataLoggerService(widget.getInstrument);
    _subscription = _service!.pointStream.listen(_onDataPoint);
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
    return Container(
      width: 700,
      decoration: BoxDecoration(
        color: const Color(0xFF0A192F),
        border: Border.all(color: const Color(0xFF475569)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Header ----
          _buildHeader(),

          // ---- Plot Area ----
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        DataLoggerPlot(
                          points: _points,
                          ch1Enabled: _config?.ch1Enabled ?? true,
                          ch2Enabled: _config?.ch2Enabled ?? false,
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
                          _buildHoverTooltip(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Legend toggle chips
                  _buildLegendToggleRow(),
                ],
              ),
            ),
          ),

          // ---- Bottom Controls ----
          _buildBottomControls(),
        ],
      ),
    );
  }

  /// Tooltip overlay showing data values at the hovered time position.
  Widget _buildHoverTooltip() {
    final time = _hoveredTime!;
    // Find the nearest data point (or interpolate between two)
    DataLoggerPoint? before, after;
    for (final p in _points) {
      if (p.elapsedSeconds <= time) before = p;
      if (p.elapsedSeconds >= time && after == null) after = p;
    }
    final nearest = (before ?? after)!;
    final rows = <Widget>[
      Text(
        't = ${nearest.elapsedSeconds.toStringAsFixed(1)}s',
        style: const TextStyle(color: Colors.white70, fontSize: 10),
      ),
    ];
    if (_config?.ch1Enabled == true) {
      if (!_hiddenLines.contains('ch1_vpp') && nearest.ch1Vpp != null) {
        rows.add(Text('CH1 Vpp: ${nearest.ch1Vpp!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFFFFFF00), fontSize: 11)));
      }
      if (!_hiddenLines.contains('ch1_freq') && nearest.ch1Freq != null) {
        rows.add(Text('CH1 Freq: ${_fmtSi(nearest.ch1Freq!)}Hz',
            style: const TextStyle(color: Color(0xFFFFFF00), fontSize: 11)));
      }
    }
    if (_config?.ch2Enabled == true) {
      if (!_hiddenLines.contains('ch2_vpp') && nearest.ch2Vpp != null) {
        rows.add(Text('CH2 Vpp: ${nearest.ch2Vpp!.toStringAsFixed(3)}V',
            style: const TextStyle(color: Color(0xFFFF20FF), fontSize: 11)));
      }
      if (!_hiddenLines.contains('ch2_freq') && nearest.ch2Freq != null) {
        rows.add(Text('CH2 Freq: ${_fmtSi(nearest.ch2Freq!)}Hz',
            style: const TextStyle(color: Color(0xFFFF20FF), fontSize: 11)));
      }
    }
    // Position tooltip near the cursor, clamped within bounds.
    final tooltipH = 80.0;
    final left = (_hoverX + 16).clamp(0.0, 500.0);
    final top = (_hoverY - tooltipH - 8).clamp(0.0, 400.0);
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
    final ch1 = _config?.ch1Enabled ?? true;
    final ch2 = _config?.ch2Enabled ?? false;
    final items = <Widget>[];
    if (ch1) {
      items.add(_legendChip('CH1 Vpp', 'ch1_vpp',
          const Color(0xFFFFFF00), false));
      items.add(const SizedBox(width: 4));
      items.add(_legendChip('CH1 Freq', 'ch1_freq',
          const Color(0xFFFFFF00), true));
    }
    if (ch2) {
      items.add(const SizedBox(width: 8));
      items.add(_legendChip('CH2 Vpp', 'ch2_vpp',
          const Color(0xFFFF20FF), false));
      items.add(const SizedBox(width: 4));
      items.add(_legendChip('CH2 Freq', 'ch2_freq',
          const Color(0xFFFF20FF), true));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: items),
    );
  }

  Widget _legendChip(String label, String id, Color color, bool dashed) {
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Line preview
            Icon(
              dashed ? Icons.minimize : Icons.remove,
              size: 14,
              color: hidden ? Colors.white30 : color,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: hidden ? FontWeight.normal : FontWeight.bold,
                color: hidden ? Colors.white38 : Colors.white,
              ),
            ),
          ],
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
              if (_status == DataLoggerStatus.running)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${_points.length}/${_config?.totalPoints ?? 0} pts',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
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
    );
  }
}
