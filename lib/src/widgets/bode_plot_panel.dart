import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../bode/bode_math.dart';
import '../bode/bode_models.dart';
import '../bode/bode_plot_service.dart';
import '../bode/vxi11_bode_scope.dart';
import '../instrument/dart_vxi11.dart';
import '../signal_generator/models.dart';
import '../signal_generator/signal_generator_service.dart';

/// Bode Plot panel in the same visual language as the Data Logger.
class BodePlotPanel extends StatefulWidget {
  const BodePlotPanel({
    super.key,
    required this.getInstrument,
    required this.signalGenerator,
    required this.isOnline,
    required this.generatorDetected,
    required this.onClose,
    this.plotKey,
    this.onRunningChanged,
    this.onServiceCreated,
    this.onSaveState,
    this.savedPoints,
    this.savedConfig,
    this.savedStatus,
  });

  final Future<Vxi11Instrument?> Function() getInstrument;
  final SignalGeneratorService signalGenerator;
  final bool isOnline;
  final bool generatorDetected;
  final VoidCallback onClose;

  /// GlobalKey for the plot area's RepaintBoundary, used to capture
  /// the Bode plot as an image for PDF report generation.
  final GlobalKey? plotKey;

  final ValueChanged<bool>? onRunningChanged;
  final ValueChanged<BodePlotService>? onServiceCreated;
  final void Function(
    List<BodePoint> points,
    BodeConfig? config,
    BodeStatus status,
  )?
  onSaveState;
  final List<BodePoint>? savedPoints;
  final BodeConfig? savedConfig;
  final BodeStatus? savedStatus;

  @override
  State<BodePlotPanel> createState() => _BodePlotPanelState();
}

class _BodePlotPanelState extends State<BodePlotPanel> {
  late BodeConfig _draft;
  BodeConfig? _runConfig;
  late List<BodePoint> _points;
  late BodeStatus _status;
  BodePlotService? _service;
  bool _lastRunning = false;
  String? _message;
  bool _messageIsError = false;

  late final TextEditingController _startController;
  late final TextEditingController _stopController;
  late final TextEditingController _pointsController;
  late final TextEditingController _amplitudeController;
  late final TextEditingController _offsetController;
  late final TextEditingController _settleController;
  late final TextEditingController _reportNameController;
  String _startUnit = 'Hz';
  String _stopUnit = 'kHz';

  @override
  void initState() {
    super.initState();
    _draft = widget.savedConfig ?? const BodeConfig();
    _runConfig = widget.savedConfig;
    _points = List<BodePoint>.of(widget.savedPoints ?? const []);
    _status = widget.savedStatus ?? BodeStatus.configuring;
    _startController = TextEditingController();
    _stopController = TextEditingController();
    _pointsController = TextEditingController();
    _amplitudeController = TextEditingController();
    _offsetController = TextEditingController();
    _settleController = TextEditingController();
    _reportNameController = TextEditingController();
    _applyDraftToControllers();
  }

  @override
  void dispose() {
    final service = _service;
    if (service != null) {
      service.removeListener(_onServiceChanged);
      unawaited(service.stop());
      service.dispose();
    }
    widget.onSaveState?.call(_points, _runConfig ?? _draft, _status);
    for (final controller in [
      _startController,
      _stopController,
      _pointsController,
      _amplitudeController,
      _offsetController,
      _settleController,
      _reportNameController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _applyDraftToControllers() {
    _startController.text = _trim(
      _draft.startFrequencyHz / _unitFactor(_startUnit),
    );
    _stopController.text = _trim(
      _draft.stopFrequencyHz / _unitFactor(_stopUnit),
    );
    _pointsController.text = '${_draft.pointCount}';
    _amplitudeController.text = _trim(_draft.amplitudeVpp);
    _offsetController.text = _trim(_draft.offsetV);
    _settleController.text = '${_draft.settling.inMilliseconds}';
    _reportNameController.text = _draft.reportName;
  }

  BodePlotService _ensureService() {
    final existing = _service;
    if (existing != null) return existing;
    final service = BodePlotService(
      signalGenerator: widget.signalGenerator,
      scope: Vxi11BodeScope(widget.getInstrument),
    );
    service.addListener(_onServiceChanged);
    _service = service;
    widget.onServiceCreated?.call(service);
    return service;
  }

  void _onServiceChanged() {
    final service = _service;
    if (service == null || !mounted) return;
    setState(() {
      _points = service.points;
      _runConfig = service.config ?? _runConfig;
      _status = service.status;
      if (service.errorMessage != null) {
        _message = service.errorMessage;
        _messageIsError = true;
      }
    });
    final running = service.isRunning;
    if (!running &&
        (_status == BodeStatus.completed ||
            _status == BodeStatus.cancelled ||
            _status == BodeStatus.error)) {
      widget.onSaveState?.call(
        service.points,
        service.config ?? _runConfig,
        service.status,
      );
    }
    if (running != _lastRunning) {
      _lastRunning = running;
      widget.onRunningChanged?.call(running);
    }
  }

  void _updateDraft() {
    final start = _parse(_startController.text) * _unitFactor(_startUnit);
    final stop = _parse(_stopController.text) * _unitFactor(_stopUnit);
    final points = int.tryParse(_pointsController.text.trim()) ?? 0;
    final amplitude = _parse(_amplitudeController.text);
    final offset = _parse(_offsetController.text);
    final settle = int.tryParse(_settleController.text.trim()) ?? -1;
    setState(() {
      _draft = _draft.copyWith(
        startFrequencyHz: start,
        stopFrequencyHz: stop,
        pointCount: points,
        amplitudeVpp: amplitude,
        offsetV: offset,
        settling: Duration(milliseconds: settle),
        reportName: _reportNameController.text.trim(),
      );
    });
  }

  Future<void> _start() async {
    final error = validateBodeConfig(_draft, widget.signalGenerator.deviceInfo);
    if (error != null) {
      setState(() {
        _message = error;
        _messageIsError = true;
      });
      return;
    }
    if (!widget.isOnline) {
      setState(() {
        _message = 'Oscilloscope is not detected.';
        _messageIsError = true;
      });
      return;
    }
    if (!widget.signalGenerator.isConnected) {
      setState(() {
        _message = 'Signal generator is not connected.';
        _messageIsError = true;
      });
      return;
    }
    final service = _ensureService();
    setState(() {
      _runConfig = _draft;
      _points = const [];
      _status = BodeStatus.running;
      _message = null;
    });
    await service.start(_draft);
  }

  void _stop() {
    unawaited(_service?.stop());
  }

  void _new() {
    _service?.clear();
    setState(() {
      _points = const [];
      _runConfig = null;
      _status = BodeStatus.configuring;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final configuring =
        _status == BodeStatus.configuring || _status == BodeStatus.idle;
    return Container(
      width: configuring ? 700 : double.infinity,
      height: configuring ? null : double.infinity,
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _buildHeader(),
          if (!configuring)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: RepaintBoundary(
                  key: widget.plotKey,
                  child: CustomPaint(
                    painter: _BodePlotPainter(
                      points: _points,
                      config: _runConfig ?? _draft,
                      status: _status,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          _buildBottom(configuring),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final running = _status == BodeStatus.running;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF172A45),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.analytics_outlined,
            color: running ? Colors.greenAccent : Colors.cyanAccent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Text(
            _status == BodeStatus.completed
                ? 'Bode Plot — Complete'
                : 'Bode Plot',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(width: 16),
          // The title already reads "Bode Plot — Complete" once the sweep
          // has finished, so no extra status label is shown then.
          if (_status != BodeStatus.completed)
            Text(
              _statusLabel(_status),
              style: TextStyle(
                color: running ? Colors.greenAccent : Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          const Spacer(),
          if (running)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildBottom(bool configuring) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F1D33),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (configuring || _status == BodeStatus.error)
            _buildConfigForm()
          else
            _buildRunningState(),
          if (_message != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (_messageIsError ? Colors.redAccent : Colors.greenAccent)
                    .withValues(alpha: 0.1),
                border: Border.all(
                  color: _messageIsError
                      ? Colors.redAccent
                      : Colors.greenAccent,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _message!,
                style: TextStyle(
                  color: _messageIsError
                      ? Colors.redAccent
                      : Colors.greenAccent,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfigForm() {
    final validation = validateBodeConfig(
      _draft,
      widget.signalGenerator.deviceInfo,
    );
    final ready =
        widget.isOnline &&
        widget.generatorDetected &&
        widget.signalGenerator.isConnected;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Bode Plot Configuration',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),

          // ---- Report Name ----
          TextField(
            controller: _reportNameController,
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
            onChanged: (_) => _updateDraft(),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(child: _frequencyField('Start', _startController, true)),
              const SizedBox(width: 8),
              Expanded(child: _frequencyField('Stop', _stopController, false)),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _pointsController,
                  onChanged: (_) => _updateDraft(),
                  keyboardType: TextInputType.number,
                  decoration: _decoration('Points'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amplitudeController,
                  onChanged: (_) => _updateDraft(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _decoration('Amplitude (Vpp)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _offsetController,
                  onChanged: (_) => _updateDraft(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: _decoration('Offset (V)'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _settleController,
                  onChanged: (_) => _updateDraft(),
                  keyboardType: TextInputType.number,
                  decoration: _decoration('Settle (ms)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<BodeSpacing>(
                  initialValue: _draft.spacing,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E1E1E),
                  decoration: _decoration('Spacing'),
                  items: const [
                    DropdownMenuItem(
                      value: BodeSpacing.logarithmic,
                      child: Text('Logarithmic'),
                    ),
                    DropdownMenuItem(
                      value: BodeSpacing.linear,
                      child: Text('Linear'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _draft = _draft.copyWith(spacing: value));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<Jds6600Waveform>(
                  initialValue: _draft.waveform,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E1E1E),
                  decoration: _decoration('Waveform'),
                  items: Jds6600Waveform.values
                      .where((value) => value != Jds6600Waveform.arbitrary)
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(value.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _draft = _draft.copyWith(waveform: value));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _draft.vinChannel,
                  dropdownColor: const Color(0xFF1E1E1E),
                  decoration: _decoration('Vin channel'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('CH1')),
                    DropdownMenuItem(value: 2, child: Text('CH2')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _draft = _draft.copyWith(vinChannel: value));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _draft.voutChannel,
                  dropdownColor: const Color(0xFF1E1E1E),
                  decoration: _decoration('Vout channel'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('CH1')),
                    DropdownMenuItem(value: 2, child: Text('CH2')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(
                      () => _draft = _draft.copyWith(voutChannel: value),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Measure phase',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Switch(
                value: _draft.measurePhase,
                activeThumbColor: Colors.cyanAccent,
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(measurePhase: value),
                ),
              ),
            ],
          ),
          if (validation != null) ...[
            const SizedBox(height: 6),
            Text(
              validation,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          if (!ready) ...[
            const SizedBox(height: 6),
            Text(
              !widget.isOnline
                  ? 'Oscilloscope not detected.'
                  : !widget.generatorDetected
                  ? 'Signal generator not detected.'
                  : 'Signal generator not connected.',
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: ready && validation == null ? _start : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('START SWEEP'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.cyan.shade800,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunningState() {
    final service = _service;
    final last = _points.isNotEmpty ? _points.last : null;
    final progress = service == null
        ? '0 / 0'
        : '${service.completedPoints} / ${service.totalPoints}';
    final current = service?.currentFrequencyHz;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _status == BodeStatus.running
                    ? 'Sweeping — point $progress'
                    : _status == BodeStatus.completed
                    ? 'Sweep complete — $progress points'
                    : _statusLabel(_status),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (current != null)
                Text(
                  'Current: ${formatFrequencyHz(current)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              if (last != null)
                Text(
                  'Last: ${formatFrequencyHz(last.frequencyHz)} · '
                  '${last.gainDb?.toStringAsFixed(2) ?? '—'} dB · '
                  '${last.phaseDeg?.toStringAsFixed(1) ?? '—'}°',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ),
        ),
        if (_status == BodeStatus.running)
          OutlinedButton.icon(
            onPressed: _stop,
            icon: const Icon(Icons.stop),
            label: const Text('STOP'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: _new,
            icon: const Icon(Icons.add),
            label: const Text('NEW'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.cyanAccent,
              side: const BorderSide(color: Colors.cyanAccent),
            ),
          ),
      ],
    );
  }

  Widget _frequencyField(
    String label,
    TextEditingController controller,
    bool isStart,
  ) {
    final unit = isStart ? _startUnit : _stopUnit;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: (_) => _updateDraft(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _decoration(label),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 110,
          child: DropdownButtonFormField<String>(
            initialValue: unit,
            isExpanded: true,
            dropdownColor: const Color(0xFF1E1E1E),
            decoration: _decoration('Unit'),
            items: const ['Hz', 'kHz', 'MHz']
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                if (isStart) {
                  _startUnit = value;
                } else {
                  _stopUnit = value;
                }
                _updateDraft();
              });
            },
          ),
        ),
      ],
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white24),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.cyanAccent),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  double _parse(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    return value == null || !value.isFinite ? double.nan : value;
  }

  double _unitFactor(String unit) {
    switch (unit) {
      case 'kHz':
        return 1e3;
      case 'MHz':
        return 1e6;
      default:
        return 1.0;
    }
  }

  String _trim(double value) {
    if (!value.isFinite) return '';
    var text = value.toStringAsFixed(6);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
    return text;
  }

  String _statusLabel(BodeStatus status) {
    switch (status) {
      case BodeStatus.idle:
      case BodeStatus.configuring:
        return 'CONFIGURING';
      case BodeStatus.running:
        return 'RUNNING';
      case BodeStatus.completed:
        // Completion is already conveyed by the "Bode Plot — Complete"
        // title, so no separate status label is rendered.
        return '';
      case BodeStatus.cancelled:
        return 'CANCELLED';
      case BodeStatus.error:
        return 'ERROR';
    }
  }
}

class _BodePlotPainter extends CustomPainter {
  _BodePlotPainter({
    required this.points,
    required this.config,
    required this.status,
  });

  final List<BodePoint> points;
  final BodeConfig config;
  final BodeStatus status;

  static const double _left = 72;
  static const double _right = 20;
  static const double _top = 34;
  static const double _bottom = 42;
  static const double _gap = 44;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppColors.panelBackground,
    );

    final chartWidth = size.width - _left - _right;
    final chartHeight = (size.height - _top - _bottom - _gap) / 2;
    if (chartWidth <= 0 || chartHeight <= 0) return;
    final magnitudeRect = Rect.fromLTWH(_left, _top, chartWidth, chartHeight);
    final phaseRect = Rect.fromLTWH(
      _left,
      _top + chartHeight + _gap,
      chartWidth,
      chartHeight,
    );

    _drawChart(canvas, magnitudeRect, 'Gain (dB)', isPhase: false);
    _drawChart(canvas, phaseRect, 'Phase (deg)', isPhase: true);

    if (points.every((point) => point.gainDb == null)) {
      _drawCenteredText(
        canvas,
        'Waiting for sweep data',
        center: Offset(_left + chartWidth / 2, _top + chartHeight * 0.45),
        color: Colors.yellow,
        fontSize: 12,
      );
    }
  }

  void _drawChart(
    Canvas canvas,
    Rect rect,
    String yLabel, {
    required bool isPhase,
  }) {
    final border = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF0A192F));
    canvas.drawRect(rect, border);

    final start = config.startFrequencyHz;
    final stop = config.stopFrequencyHz;
    if (start <= 0 || stop <= start) return;

    final frequencyTicks = _frequencyTicks(start, stop);
    final gainTicks = isPhase
        ? const [-180.0, -90.0, 0.0, 90.0, 180.0]
        : _gainTicks();
    final yMin = isPhase ? -180.0 : gainTicks.first;
    final yMax = isPhase ? 180.0 : gainTicks.last;

    final gridPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (final frequency in frequencyTicks) {
      final x = _xFor(frequency, start, stop, rect);
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
      if (isPhase) {
        _drawText(
          canvas,
          formatFrequencyHz(frequency),
          Offset(x - 22, rect.bottom + 8),
          Colors.white54,
          10,
        );
      }
    }
    for (final tick in gainTicks) {
      final y = _yFor(tick, yMin, yMax, rect);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
      _drawText(
        canvas,
        isPhase ? '${tick.toStringAsFixed(0)}°' : tick.toStringAsFixed(0),
        Offset(rect.left - 42, y - 6),
        Colors.white54,
        10,
      );
    }

    // Keep the axis title in the reserved band above the chart. Aligning it
    // with the plot's left edge avoids the top scale tick that sits to the
    // left of the plot.
    _drawText(
      canvas,
      yLabel,
      Offset(rect.left, rect.top - 20),
      Colors.white70,
      11,
    );

    if (isPhase) {
      _drawText(
        canvas,
        'Frequency (Hz)',
        Offset(rect.left + rect.width / 2 - 34, rect.bottom + 26),
        Colors.white70,
        11,
      );
    }

    _drawSeries(canvas, rect, start, stop, yMin, yMax, isPhase: isPhase);
  }

  void _drawSeries(
    Canvas canvas,
    Rect rect,
    double start,
    double stop,
    double yMin,
    double yMax, {
    required bool isPhase,
  }) {
    final linePaint = Paint()
      ..color = isPhase ? Colors.orangeAccent : Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final pointPaint = Paint()
      ..color = isPhase ? Colors.orangeAccent : Colors.cyanAccent;

    Path? path;
    var lastValid = false;
    for (final point in points) {
      final value = isPhase ? point.phaseDeg : point.gainDb;
      if (!point.valid || value == null || !value.isFinite) {
        lastValid = false;
        if (path != null) {
          canvas.drawPath(path, linePaint);
          path = null;
        }
        continue;
      }
      final offset = Offset(
        _xFor(point.frequencyHz, start, stop, rect),
        _yFor(value, yMin, yMax, rect),
      );
      if (!lastValid) {
        path = Path()..moveTo(offset.dx, offset.dy);
      } else {
        path?.lineTo(offset.dx, offset.dy);
      }
      canvas.drawCircle(offset, 2.2, pointPaint);
      lastValid = true;
    }
    if (path != null) canvas.drawPath(path, linePaint);
  }

  List<double> _gainTicks() {
    final gains = points
        .where((point) => point.valid)
        .map((point) => point.gainDb)
        .whereType<double>()
        .where((value) => value.isFinite)
        .toList();
    var min = gains.isEmpty ? -20.0 : gains.reduce(math.min);
    var max = gains.isEmpty ? 10.0 : gains.reduce(math.max);
    min = math.min(min, 0);
    max = math.max(max, 0);
    if (max - min < 20) {
      final center = (max + min) / 2;
      min = center - 10;
      max = center + 10;
    }
    return _niceTicks((min - 2).floorToDouble(), (max + 2).ceilToDouble());
  }

  List<double> _niceTicks(double min, double max) {
    const target = 5;
    final rawStep = (max - min) / target;
    final magnitude = math
        .pow(10, (math.log(rawStep) / math.ln10).floor())
        .toDouble();
    final step = [1.0, 2.0, 5.0, 10.0]
        .map((value) => value * magnitude)
        .firstWhere((value) => value >= rawStep, orElse: () => 10 * magnitude);
    final ticks = <double>[];
    for (
      var value = (min / step).floor() * step;
      value <= max + step / 2;
      value += step
    ) {
      ticks.add(value.toDouble());
    }
    return ticks.isEmpty ? [min, max] : ticks;
  }

  List<double> _frequencyTicks(double start, double stop) {
    final ticks = <double>[];
    final firstDecade = math
        .pow(10, (math.log(start) / math.ln10).floor())
        .toDouble();
    var decade = firstDecade;
    while (decade <= stop * 1.001) {
      for (final multiplier in const [1.0, 2.0, 5.0]) {
        final value = decade * multiplier;
        if (value >= start * 0.999 && value <= stop * 1.001) {
          ticks.add(value);
        }
      }
      decade *= 10;
    }
    return ticks.isEmpty ? [start, stop] : ticks;
  }

  double _xFor(double frequency, double start, double stop, Rect rect) {
    final fraction =
        (math.log(frequency) - math.log(start)) /
        (math.log(stop) - math.log(start));
    return rect.left + fraction.clamp(0.0, 1.0) * rect.width;
  }

  double _yFor(double value, double min, double max, Rect rect) {
    final fraction = (value - min) / (max - min);
    return rect.bottom - fraction.clamp(0.0, 1.0) * rect.height;
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  void _drawCenteredText(
    Canvas canvas,
    String text, {
    required Offset center,
    required Color color,
    required double fontSize,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _BodePlotPainter oldDelegate) {
    return oldDelegate.points.length != points.length ||
        !identical(oldDelegate.points, points) ||
        oldDelegate.config != config ||
        oldDelegate.status != status;
  }
}
