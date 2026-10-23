/// Configuration dialog for the Data Logger.
///
/// Allows the user to select measurements (Vpp / Mean / Rms / Duty / Freq per
/// channel, plus the cross-channel Gain (dB)), sampling interval (10s–60s),
/// and recording duration (1min–24h).
/// Provides Start and Cancel buttons. Once the logger is running,
/// shows Stop / New / Restart controls instead.
library;

import 'package:flutter/material.dart';

import '../data_logger/data_logger_models.dart';

// =============================================================================
// Data Logger Dialog
// =============================================================================

/// A dialog/widget for configuring and controlling the Data Logger.
///
/// When the logger is not running, displays configuration controls and a
/// Start button. When running, shows a Stop button. When stopped, shows
/// New (new configuration) and Restart (same config) buttons.
class DataLoggerDialog extends StatefulWidget {
  final DataLoggerConfig? currentConfig;
  final DataLoggerStatus status;

  /// Analog channel count of the connected instrument (2 or 4).
  final int channelCount;
  final int pointCount;
  final int totalPoints;
  final int elapsedSeconds;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final VoidCallback? onNew;
  final VoidCallback? onRestart;
  final ValueChanged<DataLoggerConfig>? onConfigChanged;

  const DataLoggerDialog({
    super.key,
    this.currentConfig,
    required this.status,
    this.channelCount = 2,
    this.pointCount = 0,
    this.totalPoints = 0,
    this.elapsedSeconds = 0,
    this.onStart,
    this.onStop,
    this.onNew,
    this.onRestart,
    this.onConfigChanged,
  });

  @override
  State<DataLoggerDialog> createState() => _DataLoggerDialogState();
}

/// Preset recording durations in minutes — non-linear steps so short
/// durations (1, 5, 10, 20 min) are easy to select, while longer ones
/// use coarser granularity up to 24 hours.
const List<int> _durationPresetsMinutes = [
  1,
  5,
  10,
  20,
  30,
  60,
  120,
  360,
  720,
  1440,
];

class _DataLoggerDialogState extends State<DataLoggerDialog> {
  // Individual measurement toggles — all start deselected.
  bool _ch1VppEnabled = false;
  bool _ch1MeanEnabled = false;
  bool _ch1RmsEnabled = false;
  bool _ch1DutyEnabled = false;
  bool _ch1FreqEnabled = false;
  bool _ch2VppEnabled = false;
  bool _ch2MeanEnabled = false;
  bool _ch2RmsEnabled = false;
  bool _ch2DutyEnabled = false;
  bool _ch2FreqEnabled = false;
  bool _ch3VppEnabled = false;
  bool _ch3MeanEnabled = false;
  bool _ch3RmsEnabled = false;
  bool _ch3DutyEnabled = false;
  bool _ch3FreqEnabled = false;
  bool _ch4VppEnabled = false;
  bool _ch4MeanEnabled = false;
  bool _ch4RmsEnabled = false;
  bool _ch4DutyEnabled = false;
  bool _ch4FreqEnabled = false;
  bool _gainDbEnabled = false;
  double _intervalSeconds = 10; // Slider: 10–60
  int _durationIndex = 0; // Index into _durationPresetsMinutes
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.currentConfig != null) {
      // Restore individual measurement flags from config.
      _ch1VppEnabled = widget.currentConfig!.ch1VppEnabled;
      _ch1MeanEnabled = widget.currentConfig!.ch1MeanEnabled;
      _ch1RmsEnabled = widget.currentConfig!.ch1RmsEnabled;
      _ch1DutyEnabled = widget.currentConfig!.ch1DutyEnabled;
      _ch1FreqEnabled = widget.currentConfig!.ch1FreqEnabled;
      _ch2VppEnabled = widget.currentConfig!.ch2VppEnabled;
      _ch2MeanEnabled = widget.currentConfig!.ch2MeanEnabled;
      _ch2RmsEnabled = widget.currentConfig!.ch2RmsEnabled;
      _ch2DutyEnabled = widget.currentConfig!.ch2DutyEnabled;
      _ch2FreqEnabled = widget.currentConfig!.ch2FreqEnabled;
      _ch3VppEnabled = widget.currentConfig!.ch3VppEnabled;
      _ch3MeanEnabled = widget.currentConfig!.ch3MeanEnabled;
      _ch3RmsEnabled = widget.currentConfig!.ch3RmsEnabled;
      _ch3DutyEnabled = widget.currentConfig!.ch3DutyEnabled;
      _ch3FreqEnabled = widget.currentConfig!.ch3FreqEnabled;
      _ch4VppEnabled = widget.currentConfig!.ch4VppEnabled;
      _ch4MeanEnabled = widget.currentConfig!.ch4MeanEnabled;
      _ch4RmsEnabled = widget.currentConfig!.ch4RmsEnabled;
      _ch4DutyEnabled = widget.currentConfig!.ch4DutyEnabled;
      _ch4FreqEnabled = widget.currentConfig!.ch4FreqEnabled;
      _gainDbEnabled = widget.currentConfig!.gainDbEnabled;
      if (widget.channelCount < 4) {
        // A configuration saved on a four-channel scope must not query CH3/CH4
        // when it is restored on a two-channel instrument.
        _ch3VppEnabled = false;
        _ch3MeanEnabled = false;
        _ch3RmsEnabled = false;
        _ch3DutyEnabled = false;
        _ch3FreqEnabled = false;
        _ch4VppEnabled = false;
        _ch4MeanEnabled = false;
        _ch4RmsEnabled = false;
        _ch4DutyEnabled = false;
        _ch4FreqEnabled = false;
      }
      _intervalSeconds = widget.currentConfig!.intervalSeconds.toDouble();
      final saved = widget.currentConfig!.durationMinutes;
      _durationIndex = _durationPresetsMinutes
          .indexOf(saved)
          .clamp(0, _durationPresetsMinutes.length - 1);
      _descriptionController.text = widget.currentConfig!.description;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  /// Count of currently selected measurement parameters.
  int get _selectedCount =>
      (_ch1VppEnabled ? 1 : 0) +
      (_ch1MeanEnabled ? 1 : 0) +
      (_ch1RmsEnabled ? 1 : 0) +
      (_ch1DutyEnabled ? 1 : 0) +
      (_ch1FreqEnabled ? 1 : 0) +
      (_ch2VppEnabled ? 1 : 0) +
      (_ch2MeanEnabled ? 1 : 0) +
      (_ch2RmsEnabled ? 1 : 0) +
      (_ch2DutyEnabled ? 1 : 0) +
      (_ch2FreqEnabled ? 1 : 0) +
      (_ch3VppEnabled ? 1 : 0) +
      (_ch3MeanEnabled ? 1 : 0) +
      (_ch3RmsEnabled ? 1 : 0) +
      (_ch3DutyEnabled ? 1 : 0) +
      (_ch3FreqEnabled ? 1 : 0) +
      (_ch4VppEnabled ? 1 : 0) +
      (_ch4MeanEnabled ? 1 : 0) +
      (_ch4RmsEnabled ? 1 : 0) +
      (_ch4DutyEnabled ? 1 : 0) +
      (_ch4FreqEnabled ? 1 : 0) +
      (_gainDbEnabled ? 1 : 0);

  /// Maximum number of measurement parameters that can be selected.
  static const int _maxSelected = 5;

  /// True if at least one measurement is enabled and at most 5.
  bool get _isValid => _selectedCount >= 1 && _selectedCount <= _maxSelected;
  int get _durationMinutes => _durationPresetsMinutes[_durationIndex];

  void _emitConfig() {
    widget.onConfigChanged?.call(
      DataLoggerConfig(
        ch1VppEnabled: _ch1VppEnabled,
        ch1MeanEnabled: _ch1MeanEnabled,
        ch1RmsEnabled: _ch1RmsEnabled,
        ch1DutyEnabled: _ch1DutyEnabled,
        ch1FreqEnabled: _ch1FreqEnabled,
        ch2VppEnabled: _ch2VppEnabled,
        ch2MeanEnabled: _ch2MeanEnabled,
        ch2RmsEnabled: _ch2RmsEnabled,
        ch2DutyEnabled: _ch2DutyEnabled,
        ch2FreqEnabled: _ch2FreqEnabled,
        ch3VppEnabled: _ch3VppEnabled,
        ch3MeanEnabled: _ch3MeanEnabled,
        ch3RmsEnabled: _ch3RmsEnabled,
        ch3DutyEnabled: _ch3DutyEnabled,
        ch3FreqEnabled: _ch3FreqEnabled,
        ch4VppEnabled: _ch4VppEnabled,
        ch4MeanEnabled: _ch4MeanEnabled,
        ch4RmsEnabled: _ch4RmsEnabled,
        ch4DutyEnabled: _ch4DutyEnabled,
        ch4FreqEnabled: _ch4FreqEnabled,
        gainDbEnabled: _gainDbEnabled,
        intervalSeconds: _intervalSeconds.round(),
        durationMinutes: _durationMinutes,
        description: _descriptionController.text.trim(),
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final rem = minutes % 60;
    if (rem == 0) return '${h}h';
    return '${h}h ${rem}min';
  }

  @override
  Widget build(BuildContext context) {
    // Running state: only show Stop + status info
    if (widget.status == DataLoggerStatus.running) {
      return _buildRunningState();
    }

    // Stopped state: show New / Restart buttons + config summary
    if (widget.status == DataLoggerStatus.stopped) {
      return _buildStoppedState();
    }

    // Idle / configuring state: show the full configuration form
    return _buildConfigForm();
  }

  Widget _buildConfigForm() {
    final totalPoints = (_durationMinutes * 60) ~/ _intervalSeconds.round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent, width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- Header ----
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Data Logger Configuration',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ---- Description ----
          TextField(
            controller: _descriptionController,
            maxLength: 150,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Report Name (optional)',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF172A45).withValues(alpha: 0.5),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF475569)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF475569)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.cyanAccent),
              ),
              counterStyle: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
              ),
            ),
            onChanged: (_) => _emitConfig(),
          ),
          const SizedBox(height: 16),

          // ---- Measurement Toggle Buttons ----
          Row(
            children: [
              _buildSectionTitle('Measurements'),
              if (_selectedCount >= _maxSelected) ...[
                const SizedBox(width: 8),
                Text(
                  'Select a maximum of $_maxSelected parameters',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // CH1 Vpp toggle with fixed-height probe label area underneath
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMeasurementToggle(
                    label: 'CH1 Vpp',
                    value: _ch1VppEnabled,
                    activeColor: const Color(0xFFFFFF00),
                    onChanged: (v) => setState(() {
                      _ch1VppEnabled = v;
                      _emitConfig();
                    }),
                  ),
                  // Fixed-height area so the dialog height doesn't change
                  // when the probe label appears/disappears.
                  SizedBox(
                    height: 30,
                    child:
                        (_ch1VppEnabled ||
                                _ch1MeanEnabled ||
                                _ch1RmsEnabled ||
                                // Gain (dB) reads the CH1 RMS voltage too.
                                _gainDbEnabled) &&
                            widget.currentConfig != null
                        ? Padding(
                            padding: const EdgeInsets.only(left: 4, top: 4),
                            child: _buildProbeChip(
                              'CH1-Probe: ${_fmtProbe(widget.currentConfig!.probeDividerCh1)}',
                              const Color(0xFFFFFF00),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
              _buildMeasurementToggle(
                label: 'CH1 Mean',
                value: _ch1MeanEnabled,
                activeColor: const Color(0xFF00E676),
                onChanged: (v) => setState(() {
                  _ch1MeanEnabled = v;
                  _emitConfig();
                }),
              ),
              _buildMeasurementToggle(
                label: 'CH1 Rms',
                value: _ch1RmsEnabled,
                activeColor: const Color(0xFF00E676),
                onChanged: (v) => setState(() {
                  _ch1RmsEnabled = v;
                  _emitConfig();
                }),
              ),
              _buildMeasurementToggle(
                label: 'CH1 Duty',
                value: _ch1DutyEnabled,
                activeColor: const Color(0xFFFFFF00),
                onChanged: (v) => setState(() {
                  _ch1DutyEnabled = v;
                  _emitConfig();
                }),
              ),
              _buildMeasurementToggle(
                label: 'CH1 Freq',
                value: _ch1FreqEnabled,
                activeColor: const Color(0xFFFFFF00),
                onChanged: (v) => setState(() {
                  _ch1FreqEnabled = v;
                  _emitConfig();
                }),
              ),
              // CH2 Vpp toggle with fixed-height probe label area underneath
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMeasurementToggle(
                    label: 'CH2 Vpp',
                    value: _ch2VppEnabled,
                    activeColor: const Color(0xFFFF20FF),
                    onChanged: (v) => setState(() {
                      _ch2VppEnabled = v;
                      _emitConfig();
                    }),
                  ),
                  // Fixed-height area so the dialog height doesn't change
                  // when the probe label appears/disappears.
                  SizedBox(
                    height: 30,
                    child:
                        (_ch2VppEnabled ||
                                _ch2MeanEnabled ||
                                _ch2RmsEnabled ||
                                // Gain (dB) reads the CH2 RMS voltage too.
                                _gainDbEnabled) &&
                            widget.currentConfig != null
                        ? Padding(
                            padding: const EdgeInsets.only(left: 4, top: 4),
                            child: _buildProbeChip(
                              'CH2-Probe: ${_fmtProbe(widget.currentConfig!.probeDividerCh2)}',
                              const Color(0xFFFF20FF),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
              _buildMeasurementToggle(
                label: 'CH2 Mean',
                value: _ch2MeanEnabled,
                activeColor: const Color(0xFFFF5252),
                onChanged: (v) => setState(() {
                  _ch2MeanEnabled = v;
                  _emitConfig();
                }),
              ),
              _buildMeasurementToggle(
                label: 'CH2 Rms',
                value: _ch2RmsEnabled,
                activeColor: const Color(0xFFFF5252),
                onChanged: (v) => setState(() {
                  _ch2RmsEnabled = v;
                  _emitConfig();
                }),
              ),
              _buildMeasurementToggle(
                label: 'CH2 Duty',
                value: _ch2DutyEnabled,
                activeColor: const Color(0xFFFF20FF),
                onChanged: (v) => setState(() {
                  _ch2DutyEnabled = v;
                  _emitConfig();
                }),
              ),
              _buildMeasurementToggle(
                label: 'CH2 Freq',
                value: _ch2FreqEnabled,
                activeColor: const Color(0xFFFF20FF),
                onChanged: (v) => setState(() {
                  _ch2FreqEnabled = v;
                  _emitConfig();
                }),
              ),
              if (widget.channelCount >= 4) ...[
                // CH3 Vpp toggle with fixed-height probe label area.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMeasurementToggle(
                      label: 'CH3 Vpp',
                      value: _ch3VppEnabled,
                      activeColor: const Color(0xFF4FC3F7),
                      onChanged: (v) => setState(() {
                        _ch3VppEnabled = v;
                        _emitConfig();
                      }),
                    ),
                    SizedBox(
                      height: 30,
                      child:
                          (_ch3VppEnabled ||
                                  _ch3MeanEnabled ||
                                  _ch3RmsEnabled) &&
                              widget.currentConfig != null
                          ? Padding(
                              padding: const EdgeInsets.only(left: 4, top: 4),
                              child: _buildProbeChip(
                                'CH3-Probe: ${_fmtProbe(widget.currentConfig!.probeDividerCh3)}',
                                const Color(0xFF4FC3F7),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
                _buildMeasurementToggle(
                  label: 'CH3 Mean',
                  value: _ch3MeanEnabled,
                  activeColor: const Color(0xFF00B0FF),
                  onChanged: (v) => setState(() {
                    _ch3MeanEnabled = v;
                    _emitConfig();
                  }),
                ),
                _buildMeasurementToggle(
                  label: 'CH3 Rms',
                  value: _ch3RmsEnabled,
                  activeColor: const Color(0xFF00B0FF),
                  onChanged: (v) => setState(() {
                    _ch3RmsEnabled = v;
                    _emitConfig();
                  }),
                ),
                _buildMeasurementToggle(
                  label: 'CH3 Duty',
                  value: _ch3DutyEnabled,
                  activeColor: const Color(0xFF4FC3F7),
                  onChanged: (v) => setState(() {
                    _ch3DutyEnabled = v;
                    _emitConfig();
                  }),
                ),
                _buildMeasurementToggle(
                  label: 'CH3 Freq',
                  value: _ch3FreqEnabled,
                  activeColor: const Color(0xFF4FC3F7),
                  onChanged: (v) => setState(() {
                    _ch3FreqEnabled = v;
                    _emitConfig();
                  }),
                ),
                // CH4 Vpp toggle with fixed-height probe label area.
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMeasurementToggle(
                      label: 'CH4 Vpp',
                      value: _ch4VppEnabled,
                      activeColor: const Color(0xFF66BB6A),
                      onChanged: (v) => setState(() {
                        _ch4VppEnabled = v;
                        _emitConfig();
                      }),
                    ),
                    SizedBox(
                      height: 30,
                      child:
                          (_ch4VppEnabled ||
                                  _ch4MeanEnabled ||
                                  _ch4RmsEnabled) &&
                              widget.currentConfig != null
                          ? Padding(
                              padding: const EdgeInsets.only(left: 4, top: 4),
                              child: _buildProbeChip(
                                'CH4-Probe: ${_fmtProbe(widget.currentConfig!.probeDividerCh4)}',
                                const Color(0xFF66BB6A),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
                _buildMeasurementToggle(
                  label: 'CH4 Mean',
                  value: _ch4MeanEnabled,
                  activeColor: const Color(0xFFFFA726),
                  onChanged: (v) => setState(() {
                    _ch4MeanEnabled = v;
                    _emitConfig();
                  }),
                ),
                _buildMeasurementToggle(
                  label: 'CH4 Rms',
                  value: _ch4RmsEnabled,
                  activeColor: const Color(0xFFFFA726),
                  onChanged: (v) => setState(() {
                    _ch4RmsEnabled = v;
                    _emitConfig();
                  }),
                ),
                _buildMeasurementToggle(
                  label: 'CH4 Duty',
                  value: _ch4DutyEnabled,
                  activeColor: const Color(0xFF66BB6A),
                  onChanged: (v) => setState(() {
                    _ch4DutyEnabled = v;
                    _emitConfig();
                  }),
                ),
                _buildMeasurementToggle(
                  label: 'CH4 Freq',
                  value: _ch4FreqEnabled,
                  activeColor: const Color(0xFF66BB6A),
                  onChanged: (v) => setState(() {
                    _ch4FreqEnabled = v;
                    _emitConfig();
                  }),
                ),
              ],
              // Gain (dB) is a cross-channel measurement: the RMS voltage on
              // CH2 (signal) divided by the RMS voltage on CH1 (reference).
              // It therefore has no per-channel toggle of its own.
              _buildMeasurementToggle(
                label: 'Gain (dB)',
                value: _gainDbEnabled,
                activeColor: _gainColor,
                onChanged: (v) => setState(() {
                  _gainDbEnabled = v;
                  _emitConfig();
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ---- Sampling Interval ----
          _buildSectionTitle('Sampling Interval'),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    activeTrackColor: Colors.cyanAccent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.cyanAccent,
                    valueIndicatorColor: const Color(0xFF172A45),
                    valueIndicatorTextStyle: const TextStyle(
                      color: Colors.white,
                    ),
                  ),
                  child: Slider(
                    value: _intervalSeconds,
                    min: 10,
                    max: 60,
                    divisions: 5,
                    label: '${_intervalSeconds.round()} s',
                    onChanged: (v) {
                      setState(() => _intervalSeconds = v);
                      _emitConfig();
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(
                  '${_intervalSeconds.round()} s',
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ---- Recording Duration ----
          _buildSectionTitle('Recording Duration'),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    activeTrackColor: Colors.cyanAccent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.cyanAccent,
                    valueIndicatorColor: const Color(0xFF172A45),
                    valueIndicatorTextStyle: const TextStyle(
                      color: Colors.white,
                    ),
                  ),
                  child: Slider(
                    value: _durationIndex.toDouble(),
                    min: 0,
                    max: (_durationPresetsMinutes.length - 1).toDouble(),
                    divisions: _durationPresetsMinutes.length - 1,
                    label: _formatDuration(
                      _durationPresetsMinutes[_durationIndex],
                    ),
                    onChanged: (v) {
                      setState(() => _durationIndex = v.round());
                      _emitConfig();
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 80,
                child: Text(
                  _formatDuration(_durationPresetsMinutes[_durationIndex]),
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ---- Total Points Info ----
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF172A45).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _axisColor),
            ),
            child: Row(
              children: [
                const Text(
                  'Total data points:',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(width: 8),
                Text(
                  '~$totalPoints',
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- Start Button ----
          Align(
            child: ElevatedButton.icon(
              onPressed: _isValid ? widget.onStart : null,
              icon: const Icon(Icons.play_arrow, size: 20),
              label: const Text(
                'Start Recording',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isValid ? Colors.cyan[800] : Colors.grey[800],
                foregroundColor: _isValid ? Colors.white : Colors.white38,
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 30,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunningState() {
    final elapsed = widget.elapsedSeconds;
    final remaining = widget.totalPoints > 0
        ? (widget.totalPoints - widget.pointCount) *
              widget.currentConfig!.intervalSeconds
        : 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.greenAccent, width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.greenAccent,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Recording...',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              Text(
                'Data Points: ${widget.pointCount}/${widget.totalPoints}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Elapsed: ${_fmtDuration(elapsed)}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              if (remaining > 0)
                Text(
                  'Remaining: ${_fmtDuration(remaining)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // ---- Probe Info (running) ----
          if (widget.currentConfig != null)
            _buildProbeLabelRow(widget.currentConfig!),
          const SizedBox(height: 8),
          Align(
            child: OutlinedButton.icon(
              onPressed: widget.onStop,
              icon: const Icon(Icons.stop, size: 18, color: Colors.redAccent),
              label: const Text(
                'Stop',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 30,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoppedState() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent, width: 1.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
              SizedBox(width: 8),
              Text(
                'Recording Complete',
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.pointCount} points collected in ${_fmtDuration(widget.elapsedSeconds)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 8),

          // ---- Probe Info (stopped) ----
          if (widget.currentConfig != null)
            _buildProbeLabelRow(widget.currentConfig!),
          const SizedBox(height: 12),
          Align(
            child: OutlinedButton.icon(
              onPressed: widget.onNew,
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('New'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.cyanAccent,
                side: const BorderSide(color: Colors.cyanAccent),
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 30,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build a probe label column for the running/stopped states.
  /// Labels are stacked vertically so both fit without wrapping issues.
  Widget _buildProbeLabelRow(DataLoggerConfig config) {
    final items = <Widget>[];
    if (config.ch1VppEnabled ||
        config.ch1MeanEnabled ||
        config.ch1RmsEnabled ||
        config.gainDbEnabled) {
      items.add(
        Text(
          'CH1-Probe: ${_fmtProbe(config.probeDividerCh1)}',
          style: const TextStyle(color: Color(0xFFFFFF00), fontSize: 11),
        ),
      );
    }
    if (config.ch2VppEnabled ||
        config.ch2MeanEnabled ||
        config.ch2RmsEnabled ||
        config.gainDbEnabled) {
      if (items.isNotEmpty) items.add(const SizedBox(height: 2));
      items.add(
        Text(
          'CH2-Probe: ${_fmtProbe(config.probeDividerCh2)}',
          style: const TextStyle(color: Color(0xFFFF20FF), fontSize: 11),
        ),
      );
    }
    if (config.ch3VppEnabled || config.ch3MeanEnabled || config.ch3RmsEnabled) {
      if (items.isNotEmpty) items.add(const SizedBox(height: 2));
      items.add(
        Text(
          'CH3-Probe: ${_fmtProbe(config.probeDividerCh3)}',
          style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 11),
        ),
      );
    }
    if (config.ch4VppEnabled || config.ch4MeanEnabled || config.ch4RmsEnabled) {
      if (items.isNotEmpty) items.add(const SizedBox(height: 2));
      items.add(
        Text(
          'CH4-Probe: ${_fmtProbe(config.probeDividerCh4)}',
          style: const TextStyle(color: Color(0xFF66BB6A), fontSize: 11),
        ),
      );
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: items,
      ),
    );
  }

  /// Format probe divider value (e.g. 10.0 → "10x", 1.0 → "1x").
  String _fmtProbe(double value) {
    if (value == value.roundToDouble()) {
      return '${value.round()}x';
    }
    return '${value.toStringAsFixed(1)}x';
  }

  /// A small chip displaying a probe label, matching the dialog's style.
  /// Uses the channel's color for the text and border.
  Widget _buildProbeChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildMeasurementToggle({
    required String label,
    required bool value,
    required Color activeColor,
    required ValueChanged<bool> onChanged,
  }) {
    final atLimit = !value && _selectedCount >= _maxSelected;
    return InkWell(
      onTap: atLimit ? null : () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value
              ? activeColor.withValues(alpha: 0.1)
              : const Color(0xFF172A45).withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value
                ? activeColor.withValues(alpha: 0.6)
                : _axisColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: value ? activeColor : Colors.white38,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: value ? activeColor : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  String _fmtDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) return '${h}h ${m}min';
    if (m > 0) return '${m}min ${s}s';
    return '${s}s';
  }
}

const Color _axisColor = Color(0xFF475569);

/// Accent color for the Gain (dB) measurement, matching the plot line color.
const Color _gainColor = Color(0xFF00E5FF);
