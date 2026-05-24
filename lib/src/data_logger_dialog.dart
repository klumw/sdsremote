/// Configuration dialog for the Data Logger.
///
/// Allows the user to select channels (CH1 / CH2), sampling interval
/// (10s–60s), recording duration (1min–24h), and probe divider factor.
/// Provides Start and Cancel buttons. Once the logger is running,
/// shows Stop / New / Restart controls instead.

import 'package:flutter/material.dart';

import 'data_logger_models.dart';

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
  1, 5, 10, 20, 30, 60, 120, 360, 720, 1440,
];

class _DataLoggerDialogState extends State<DataLoggerDialog> {
  bool _ch1Enabled = true;
  bool _ch2Enabled = false;
  double _intervalSeconds = 10; // Slider: 10–60
  int _durationIndex = 0; // Index into _durationPresetsMinutes
  double _probeDividerCh1 = 1; // Dropdown for CH1
  double _probeDividerCh2 = 1; // Dropdown for CH2

  @override
  void initState() {
    super.initState();
    if (widget.currentConfig != null) {
      _ch1Enabled = widget.currentConfig!.ch1Enabled;
      _ch2Enabled = widget.currentConfig!.ch2Enabled;
      _intervalSeconds = widget.currentConfig!.intervalSeconds.toDouble();
      final saved = widget.currentConfig!.durationMinutes;
      _durationIndex = _durationPresetsMinutes
          .indexOf(saved)
          .clamp(0, _durationPresetsMinutes.length - 1);
      _probeDividerCh1 = widget.currentConfig!.probeDividerCh1;
      _probeDividerCh2 = widget.currentConfig!.probeDividerCh2;
    }
  }

  bool get _isValid => (_ch1Enabled || _ch2Enabled);
  int get _durationMinutes => _durationPresetsMinutes[_durationIndex];

  void _emitConfig() {
    widget.onConfigChanged?.call(DataLoggerConfig(
      ch1Enabled: _ch1Enabled,
      ch2Enabled: _ch2Enabled,
      intervalSeconds: _intervalSeconds.round(),
      durationMinutes: _durationMinutes,
      probeDividerCh1: _probeDividerCh1,
      probeDividerCh2: _probeDividerCh2,
    ));
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
                const Row(
                  children: [
                    Icon(Icons.sync, color: Colors.cyanAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Data Logger Configuration',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ---- Channel Selection ----
          _buildSectionTitle('Channels'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildChannelCheckbox(
                  label: 'CH1',
                  value: _ch1Enabled,
                  activeColor: const Color(0xFFFFFF00),
                  onChanged: (v) => setState(() {
                    _ch1Enabled = v!;
                    _emitConfig();
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildChannelCheckbox(
                  label: 'CH2',
                  value: _ch2Enabled,
                  activeColor: const Color(0xFFFF20FF),
                  onChanged: (v) => setState(() {
                    _ch2Enabled = v!;
                    _emitConfig();
                  }),
                ),
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
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: Colors.cyanAccent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.cyanAccent,
                    valueIndicatorColor: const Color(0xFF172A45),
                    valueIndicatorTextStyle: const TextStyle(color: Colors.white),
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
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.bold),
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
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: Colors.cyanAccent,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.cyanAccent,
                    valueIndicatorColor: const Color(0xFF172A45),
                    valueIndicatorTextStyle: const TextStyle(color: Colors.white),
                  ),
                  child: Slider(
                    value: _durationIndex.toDouble(),
                    min: 0,
                    max: (_durationPresetsMinutes.length - 1).toDouble(),
                    divisions: _durationPresetsMinutes.length - 1,
                    label: _formatDuration(_durationPresetsMinutes[_durationIndex]),
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
                  style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ---- Probe Divider ----
          _buildSectionTitle('Probe Attenuation'),
          const SizedBox(height: 8),
          Row(
            children: [
              if (_ch1Enabled) ...[
                _buildProbeChip('CH1', _probeDividerCh1, (v) {
                  setState(() => _probeDividerCh1 = v);
                  _emitConfig();
                }),
                const SizedBox(width: 12),
              ],
              if (_ch2Enabled) ...[
                _buildProbeChip('CH2', _probeDividerCh2, (v) {
                  setState(() => _probeDividerCh2 = v);
                  _emitConfig();
                }),
              ],
              if (!_ch1Enabled && !_ch2Enabled)
                const Text('Enable a channel to set probe attenuation',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total data points:',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
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
          ElevatedButton.icon(
            onPressed: _isValid ? widget.onStart : null,
            icon: const Icon(Icons.play_arrow, size: 20),
            label: const Text(
              'Start Recording',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isValid ? Colors.cyan[800] : Colors.grey[800],
              foregroundColor: _isValid ? Colors.white : Colors.white38,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
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
        ? (widget.totalPoints - widget.pointCount) * widget.currentConfig!.intervalSeconds
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
                '${widget.pointCount}/${widget.totalPoints}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                ),
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
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onStop,
              icon: const Icon(Icons.stop, size: 18, color: Colors.redAccent),
              label: const Text(
                'Stop',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 10),
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onNew,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.cyanAccent,
                side: const BorderSide(color: Colors.cyanAccent),
                padding: const EdgeInsets.symmetric(vertical: 10),
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

  Widget _buildChannelCheckbox({
    required String label,
    required bool value,
    required Color activeColor,
    required ValueChanged<bool?> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: value
              ? activeColor.withValues(alpha: 0.1)
              : const Color(0xFF172A45).withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value ? activeColor.withValues(alpha: 0.6) : _axisColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              value ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: value ? activeColor : Colors.white38,
            ),
            const SizedBox(width: 10),
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

  Widget _buildProbeChip(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF172A45).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: _axisColor),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<double>(
              value: value,
              dropdownColor: const Color(0xFF252525),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              iconEnabledColor: Colors.cyanAccent,
              isDense: true,
              items: const [
                DropdownMenuItem(value: 1.0, child: Text('1x')),
                DropdownMenuItem(value: 10.0, child: Text('10x')),
                DropdownMenuItem(value: 100.0, child: Text('100x')),
                DropdownMenuItem(value: 1000.0, child: Text('1000x')),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
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
