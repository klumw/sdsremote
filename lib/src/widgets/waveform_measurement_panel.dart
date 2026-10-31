import 'package:flutter/material.dart';

import '../instrument/measurement.dart' show formatMeasurementValue;
import '../waveform/waveform_mask.dart';
import '../waveform/waveform_measurements.dart';

/// Settings of the software mask test as edited in the measurement panel.
///
/// [toleranceValue] is a percentage of the reference Vpp when [usePercent] is
/// true, otherwise a voltage in volts. A [timeToleranceSeconds] of zero
/// disables the horizontal tolerance.
typedef MaskSettings = ({
  bool enabled,
  bool usePercent,
  double toleranceValue,
  double timeToleranceSeconds,
});

const MaskSettings defaultMaskSettings = (
  enabled: false,
  usePercent: true,
  toleranceValue: 5,
  timeToleranceSeconds: 0,
);

/// Measurement panel shown below the waveform chart.
///
/// It lists the automatic measurements of every acquired channel, switches
/// between the standard measurement set and the PWM/signal-integrity set, and
/// hosts the software mask test controls.
class WaveformMeasurementPanel extends StatefulWidget {
  /// Measurements keyed by channel (`'ch1'` … `'ch4'`).
  final Map<String, WaveformMeasurements> measurements;

  /// Statistics over the stored acquisition history, keyed by channel.
  final Map<String, WaveformChannelStatistics> statistics;

  /// Number of stored acquisitions used for [statistics].
  final int historyCount;

  /// Whether a reference waveform is available for the mask test.
  final bool maskAvailable;

  /// Peak-to-peak voltage of the loaded reference (for the volt tolerance).
  final double referenceVppVolts;

  /// Duration of the loaded reference (for the time tolerance slider).
  final double referenceDurationSeconds;

  final MaskSettings maskSettings;
  final MaskResult? maskResult;
  final ValueChanged<MaskSettings>? onMaskSettingsChanged;

  const WaveformMeasurementPanel({
    super.key,
    required this.measurements,
    this.statistics = const {},
    this.historyCount = 0,
    this.maskAvailable = false,
    this.referenceVppVolts = 0,
    this.referenceDurationSeconds = 0,
    this.maskSettings = defaultMaskSettings,
    this.maskResult,
    this.onMaskSettingsChanged,
  });

  @override
  State<WaveformMeasurementPanel> createState() =>
      _WaveformMeasurementPanelState();
}

class _WaveformMeasurementPanelState extends State<WaveformMeasurementPanel> {
  bool _pwmMode = false;
  bool _showDetails = false;
  bool _collapsed = false;

  late double _toleranceValue;
  late double _timeTolerance;

  static const double _percentMax = 20;
  static const double _timeFractionMax = 0.2; // 20 % of the reference duration

  @override
  void initState() {
    super.initState();
    _toleranceValue = widget.maskSettings.toleranceValue;
    _timeTolerance = widget.maskSettings.timeToleranceSeconds;
  }

  @override
  void didUpdateWidget(WaveformMeasurementPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maskSettings != widget.maskSettings) {
      _toleranceValue = widget.maskSettings.toleranceValue;
      _timeTolerance = widget.maskSettings.timeToleranceSeconds;
    }
  }

  double get _toleranceMax => widget.maskSettings.usePercent
      ? _percentMax
      : (widget.referenceVppVolts > 0 ? widget.referenceVppVolts / 2 : 1.0);

  double get _timeToleranceMax => widget.referenceDurationSeconds > 0
      ? widget.referenceDurationSeconds * _timeFractionMax
      : 1.0;

  void _emitMaskSettings({
    bool? enabled,
    bool? usePercent,
    double? toleranceValue,
    double? timeToleranceSeconds,
  }) {
    final current = widget.maskSettings;
    widget.onMaskSettingsChanged?.call((
      enabled: enabled ?? current.enabled,
      usePercent: usePercent ?? current.usePercent,
      toleranceValue: toleranceValue ?? current.toleranceValue,
      timeToleranceSeconds:
          timeToleranceSeconds ?? current.timeToleranceSeconds,
    ));
  }

  /// Switches the tolerance unit while keeping the physical band width.
  void _switchToleranceMode(bool usePercent) {
    final current = widget.maskSettings;
    if (current.usePercent == usePercent) return;
    final vpp = widget.referenceVppVolts;
    final double value;
    if (usePercent) {
      value = vpp > 0
          ? (current.toleranceValue / vpp * 100)
                .clamp(0.0, _percentMax)
                .toDouble()
          : current.toleranceValue.clamp(0.0, _percentMax).toDouble();
    } else {
      final maxVolts = vpp > 0 ? vpp / 2 : 1.0;
      value = (vpp * current.toleranceValue / 100)
          .clamp(0.0, maxVolts)
          .toDouble();
    }
    _emitMaskSettings(usePercent: usePercent, toleranceValue: value);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // 46 = 44 px header + the 1 px border on each side.
      height: _collapsed ? 46 : (_showDetails ? 300 : 220),
      decoration: BoxDecoration(
        color: const Color(0xFF0A192F),
        border: Border.all(color: const Color(0xFF475569)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          if (!_collapsed) ...[
            Expanded(child: _buildChannelCards()),
            if (widget.maskAvailable) _buildMaskBar(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF172A45),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.straighten, size: 16, color: Colors.blueAccent),
          const SizedBox(width: 8),
          const Text(
            'Measurements',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 16),
          _ModeButton(
            label: 'Measurements',
            selected: !_pwmMode,
            onTap: () => setState(() => _pwmMode = false),
          ),
          const SizedBox(width: 6),
          _ModeButton(
            label: 'PWM',
            selected: _pwmMode,
            onTap: () => setState(() => _pwmMode = true),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => setState(() => _showDetails = !_showDetails),
            icon: Icon(
              _showDetails ? Icons.expand_less : Icons.expand_more,
              size: 16,
            ),
            label: Text(_showDetails ? 'Less' : 'Details'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: _collapsed
                ? 'Expand measurements'
                : 'Collapse measurements',
            onPressed: () => setState(() => _collapsed = !_collapsed),
            icon: Icon(
              _collapsed ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 18,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelCards() {
    if (widget.measurements.isEmpty) {
      return const Center(
        child: Text(
          'No measurements available',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in widget.measurements.entries) ...[
            _buildChannelCard(entry.key, entry.value),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildChannelCard(String channel, WaveformMeasurements measurement) {
    final color = _channelColor(channel);
    final stats = widget.statistics[channel];

    return Container(
      width: _showDetails ? 420 : 340,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF172A45).withValues(alpha: 0.35),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: color),
                const SizedBox(width: 6),
                Text(
                  channel.toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (measurement.notes.isNotEmpty)
                  Tooltip(
                    message: measurement.notes.join('\n'),
                    child: const Icon(
                      Icons.info_outline,
                      size: 13,
                      color: Colors.amberAccent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final metric
                    in _pwmMode
                        ? _pwmMetrics(measurement)
                        : _measurementMetrics(measurement))
                  _MetricCell(label: metric.$1, value: metric.$2),
              ],
            ),
            if (_showDetails) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final metric
                      in _pwmMode
                          ? _pwmDetailMetrics(measurement)
                          : _measurementDetailMetrics(measurement))
                    _MetricCell(label: metric.$1, value: metric.$2),
                ],
              ),
            ],
            if (widget.historyCount > 1 && stats != null) ...[
              const SizedBox(height: 6),
              Text(
                _buildStatisticsLine(stats),
                style: const TextStyle(color: Colors.white54, fontSize: 10),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<(String, String)> _measurementMetrics(WaveformMeasurements m) => [
    ('Vpp', _formatVoltage(m.vPp)),
    ('RMS', _formatVoltage(m.vRms)),
    ('Frequency', _formatFrequency(m.frequencyHz)),
    ('Duty', _formatPercent(m.dutyPercent)),
    ('Rise', _formatSeconds(m.riseTimeSeconds)),
    ('Fall', _formatSeconds(m.fallTimeSeconds)),
    ('Overshoot', _formatPercent(m.overshootPercent)),
  ];

  List<(String, String)> _measurementDetailMetrics(WaveformMeasurements m) => [
    ('Vmax', _formatVoltage(m.vMax)),
    ('Vmin', _formatVoltage(m.vMin)),
    ('Vmean', _formatVoltage(m.vMean)),
    ('Top', _formatVoltage(m.vTop)),
    ('Base', _formatVoltage(m.vBase)),
    ('Pulse', _formatSeconds(m.pulseWidthSeconds)),
    ('Periods', '${m.periodCount}'),
    ('Samples', '${m.sampleCount}'),
    ('Δt', _formatSeconds(m.sampleIntervalSeconds)),
  ];

  List<(String, String)> _pwmMetrics(WaveformMeasurements m) => [
    ('Frequency', _formatFrequency(m.frequencyHz)),
    ('Duty', _formatPercent(m.dutyPercent)),
    ('Pulse mean', _formatSeconds(m.pulseWidthSeconds)),
    ('Pulse min', _formatSeconds(m.pulseWidthMinSeconds)),
    ('Pulse max', _formatSeconds(m.pulseWidthMaxSeconds)),
    ('Pulse σ', _formatSeconds(m.pulseWidthStdDevSeconds)),
    ('Jitter σ', _formatSeconds(m.periodStdDevSeconds)),
  ];

  List<(String, String)> _pwmDetailMetrics(WaveformMeasurements m) => [
    ('Rise', _formatSeconds(m.riseTimeSeconds)),
    ('Fall', _formatSeconds(m.fallTimeSeconds)),
    ('Overshoot', _formatPercent(m.overshootPercent)),
    ('Undershoot', _formatPercent(m.undershootPercent)),
    ('Rising edges', '${m.risingEdgeCount}'),
    ('Falling edges', '${m.fallingEdgeCount}'),
    ('Periods', '${m.periodCount}'),
    ('Samples', '${m.sampleCount}'),
    ('Δt', _formatSeconds(m.sampleIntervalSeconds)),
  ];

  String _buildStatisticsLine(WaveformChannelStatistics stats) {
    String part(String key, String unit) {
      final metric = stats.metrics[key];
      if (metric == null || metric.mean == null) return '';
      final mean = _formatStatValue(metric.mean!, unit);
      final deviation = metric.standardDeviation;
      return deviation == null
          ? mean
          : '$mean ± ${_formatStatValue(deviation, unit)}';
    }

    final parts = <String>[
      if (part('vPp', 'V').isNotEmpty) 'Vpp ${part('vPp', 'V')}',
      if (part('vRms', 'V').isNotEmpty) 'RMS ${part('vRms', 'V')}',
      if (part('frequencyHz', 'Hz').isNotEmpty)
        'f ${part('frequencyHz', 'Hz')}',
      if (part('dutyPercent', '%').isNotEmpty)
        'Duty ${part('dutyPercent', '%')}',
    ];
    return 'History (${stats.measurementCount}): ${parts.join(' · ')}';
  }

  String _formatStatValue(double value, String unit) {
    if (unit == '%') return '${value.toStringAsFixed(1)} %';
    return formatMeasurementValue(value, unit);
  }

  Widget _buildMaskBar() {
    final settings = widget.maskSettings;
    final toleranceMax = _toleranceMax;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF172A45),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(
              Icons.verified_outlined,
              size: 15,
              color: Colors.redAccent,
            ),
            const SizedBox(width: 6),
            const Text(
              'Mask',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Switch(
              value: settings.enabled,
              onChanged: (value) => _emitMaskSettings(enabled: value),
              activeThumbColor: Colors.redAccent,
              activeTrackColor: Colors.redAccent.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 8),
            _ModeButton(
              label: '% Vpp',
              selected: settings.usePercent,
              onTap: () => _switchToleranceMode(true),
            ),
            const SizedBox(width: 4),
            _ModeButton(
              label: 'V',
              selected: !settings.usePercent,
              onTap: () => _switchToleranceMode(false),
            ),
            const SizedBox(width: 8),
            const Text(
              'Tolerance',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            SizedBox(
              width: 150,
              child: Slider(
                value: _toleranceValue.clamp(0.0, toleranceMax).toDouble(),
                min: 0,
                max: toleranceMax,
                activeColor: Colors.redAccent,
                inactiveColor: Colors.white24,
                onChanged: (value) => setState(() => _toleranceValue = value),
                onChangeEnd: (value) =>
                    _emitMaskSettings(toleranceValue: value),
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                settings.usePercent
                    ? '${_toleranceValue.toStringAsFixed(1)} %'
                    : '${_toleranceValue.toStringAsFixed(3)} V',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Time',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            SizedBox(
              width: 110,
              child: Slider(
                value: _timeTolerance.clamp(0.0, _timeToleranceMax).toDouble(),
                min: 0,
                max: _timeToleranceMax,
                activeColor: Colors.orangeAccent,
                inactiveColor: Colors.white24,
                onChanged: (value) => setState(() => _timeTolerance = value),
                onChangeEnd: (value) =>
                    _emitMaskSettings(timeToleranceSeconds: value),
              ),
            ),
            SizedBox(
              width: 52,
              child: Text(
                _timeTolerance <= 0 ? 'off' : formatTime(_timeTolerance),
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
            const SizedBox(width: 12),
            _buildMaskResult(widget.maskResult),
          ],
        ),
      ),
    );
  }

  Widget _buildMaskResult(MaskResult? result) {
    if (result == null || !result.hasData) {
      return const Text(
        'Mask: —',
        style: TextStyle(color: Colors.white54, fontSize: 12),
      );
    }
    if (result.passed) {
      return const Text(
        'PASS',
        style: TextStyle(
          color: Colors.greenAccent,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      );
    }
    final first = result.firstViolationTime;
    final last = result.lastViolationTime;
    return Text(
      'FAIL – ${result.violations} violations'
      '${first == null || last == null ? '' : ' (${formatTime(first)} … ${formatTime(last)})'}'
      ' · max ${result.maxViolationVolts.toStringAsFixed(3)} V',
      style: const TextStyle(
        color: Colors.redAccent,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Color _channelColor(String channel) => switch (channel) {
    'ch1' => const Color(0xFFFFEB3B),
    'ch2' => const Color(0xFFFF20FF),
    'ch3' => const Color(0xFF4FC3F7),
    'ch4' => const Color(0xFF66BB6A),
    _ => Colors.white,
  };
}

/// A compact metric label/value pair.
class _MetricCell extends StatelessWidget {
  final String label;
  final String value;

  const _MetricCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 9),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// A small selectable label used for the mode and tolerance switches.
class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ModeButton({required this.label, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? Colors.blueAccent.withValues(alpha: 0.2)
              : Colors.transparent,
          border: Border.all(
            color: selected ? Colors.blueAccent : Colors.white24,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.blueAccent : Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

String _formatVoltage(double? value) =>
    value == null ? '—' : formatMeasurementValue(value, 'V');

String _formatFrequency(double? value) =>
    value == null ? '—' : formatMeasurementValue(value, 'Hz');

String _formatSeconds(double? value) => value == null ? '—' : formatTime(value);

String _formatPercent(double? value) =>
    value == null ? '—' : '${value.toStringAsFixed(1)} %';
