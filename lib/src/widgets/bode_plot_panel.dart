import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../bode/bode_analysis.dart';
import '../bode/bode_math.dart';
import '../bode/bode_models.dart';
import '../bode/bode_plot_service.dart';
import '../bode/vxi11_bode_scope.dart';
import '../instrument/dart_vxi11.dart';
import '../signal_generator/models.dart';
import '../signal_generator/signal_generator_service.dart';
import 'animated_sync_icon.dart';

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
  final Set<String> _hiddenAmplitudeLines = <String>{};
  double? _hoverAmplitudeVpp;
  double _hoverX = 0;
  double _hoverY = 0;

  late final TextEditingController _startController;
  late final TextEditingController _stopController;
  late final TextEditingController _sweepFrequencyController;
  late final TextEditingController _pointsController;
  late final TextEditingController _amplitudeController;
  late final TextEditingController _startAmplitudeController;
  late final TextEditingController _stopAmplitudeController;
  late final TextEditingController _offsetController;
  late final TextEditingController _settleController;
  late final TextEditingController _reportNameController;
  String _startUnit = 'Hz';
  String _stopUnit = 'kHz';
  String _sweepFrequencyUnit = 'kHz';

  @override
  void initState() {
    super.initState();
    _draft = widget.savedConfig ?? const BodeConfig();
    _runConfig = widget.savedConfig;
    _points = List<BodePoint>.of(widget.savedPoints ?? const []);
    _status = widget.savedStatus ?? BodeStatus.configuring;
    _startController = TextEditingController();
    _stopController = TextEditingController();
    _sweepFrequencyController = TextEditingController();
    _pointsController = TextEditingController();
    _amplitudeController = TextEditingController();
    _startAmplitudeController = TextEditingController();
    _stopAmplitudeController = TextEditingController();
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
      _sweepFrequencyController,
      _pointsController,
      _amplitudeController,
      _startAmplitudeController,
      _stopAmplitudeController,
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
    _sweepFrequencyController.text = _trim(
      _draft.sweepFrequencyHz / _unitFactor(_sweepFrequencyUnit),
    );
    _pointsController.text = '${_draft.pointCount}';
    _amplitudeController.text = _trim(_draft.amplitudeVpp);
    _startAmplitudeController.text = _trim(_draft.startAmplitudeVpp);
    _stopAmplitudeController.text = _trim(_draft.stopAmplitudeVpp);
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
    final sweepFrequency =
        _parse(_sweepFrequencyController.text) *
        _unitFactor(_sweepFrequencyUnit);
    final points = int.tryParse(_pointsController.text.trim()) ?? 0;
    final amplitude = _parse(_amplitudeController.text);
    final startAmplitude = _parse(_startAmplitudeController.text);
    final stopAmplitude = _parse(_stopAmplitudeController.text);
    final offset = _parse(_offsetController.text);
    final settle = int.tryParse(_settleController.text.trim()) ?? -1;
    setState(() {
      _draft = _draft.copyWith(
        startFrequencyHz: start,
        stopFrequencyHz: stop,
        sweepFrequencyHz: sweepFrequency,
        pointCount: points,
        amplitudeVpp: amplitude,
        startAmplitudeVpp: startAmplitude,
        stopAmplitudeVpp: stopAmplitude,
        offsetV: offset,
        settling: Duration(milliseconds: settle),
        reportName: _reportNameController.text.trim(),
      );
    });
  }

  /// Switches the measurement method and keeps the form consistent.
  void _setMode(BodeMode mode) {
    setState(() {
      _draft = _draft.copyWith(
        mode: mode,
        // Phase is frequency-response data and has no meaning for an
        // amplitude sweep at a fixed frequency.
        measurePhase: mode == BodeMode.amplitudeSweep
            ? false
            : _draft.measurePhase,
        voutChannel:
            mode == BodeMode.amplitudeSweep &&
                _draft.vinChannel == _draft.voutChannel
            ? (_draft.vinChannel == 1 ? 2 : 1)
            : _draft.voutChannel,
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
    // On error the panel returns to the configuration form so the message
    // is shown there instead of staying on the chart.
    final showConfig =
        _status == BodeStatus.configuring ||
        _status == BodeStatus.idle ||
        _status == BodeStatus.error;
    final displayConfig = _runConfig ?? _draft;
    // The peak/-3 dB analysis is defined on the frequency axis and would be
    // misleading for an amplitude sweep.
    final analysis = displayConfig.mode == BodeMode.frequencySweep
        ? analyzeBode(_points)
        : const BodeAnalysisSummary();
    return Container(
      width: showConfig ? 700 : double.infinity,
      height: showConfig ? null : double.infinity,
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.panelBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _buildHeader(),
          if (!showConfig)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final amplitudeSweep =
                        displayConfig.mode == BodeMode.amplitudeSweep;
                    return Stack(
                      children: [
                        MouseRegion(
                          onHover: amplitudeSweep
                              ? (event) => _onAmplitudeHover(
                                  event.localPosition,
                                  constraints,
                                  displayConfig,
                                )
                              : null,
                          onExit: amplitudeSweep
                              ? (_) => _clearAmplitudeHover()
                              : null,
                          child: RepaintBoundary(
                            key: widget.plotKey,
                            child: CustomPaint(
                              painter: _BodePlotPainter(
                                points: _points,
                                config: displayConfig,
                                status: _status,
                                analysis: analysis,
                                hiddenLines: Set<String>.of(
                                  _hiddenAmplitudeLines,
                                ),
                              ),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ),
                        if (amplitudeSweep &&
                            _hoverAmplitudeVpp != null &&
                            _points.isNotEmpty)
                          _buildAmplitudeHoverTooltip(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          _buildBottom(showConfig, analysis),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final running = _status == BodeStatus.running;
    final mode = (_runConfig ?? _draft).mode;
    final title = mode == BodeMode.amplitudeSweep
        ? 'Bode Plot — Amplitude Sweep'
        : 'Bode Plot — Frequency Sweep';
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
            mode == BodeMode.amplitudeSweep
                ? Icons.stacked_line_chart
                : Icons.analytics_outlined,
            color: running ? Colors.greenAccent : Colors.cyanAccent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    _status == BodeStatus.completed
                        ? '$title — Complete'
                        : title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // The title already conveys completion, so no extra status
                // label is shown then.
                if (_status != BodeStatus.completed)
                  Text(
                    _statusLabel(_status),
                    style: TextStyle(
                      color: running ? Colors.greenAccent : Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          if (running)
            const AnimatedSyncIcon(size: 18, color: Colors.cyanAccent),
          IconButton(
            onPressed: widget.onClose,
            icon: const Icon(Icons.close, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildBottom(bool showConfig, BodeAnalysisSummary analysis) {
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
          if (showConfig) _buildConfigForm() else _buildRunningState(analysis),
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
              child: Row(
                children: [
                  Expanded(
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
                  IconButton(
                    tooltip: 'Dismiss',
                    onPressed: () => setState(() {
                      _message = null;
                      _messageIsError = false;
                    }),
                    icon: const Icon(Icons.close, size: 16),
                    color: _messageIsError
                        ? Colors.redAccent
                        : Colors.greenAccent,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Measurement-method dropdown at the top of the configuration form.
  Widget _buildModeDropdown() {
    return DropdownButtonFormField<BodeMode>(
      key: const ValueKey('bode-mode'),
      initialValue: _draft.mode,
      isExpanded: true,
      dropdownColor: const Color(0xFF1E1E1E),
      decoration: _decoration('Measurement method'),
      items: const [
        DropdownMenuItem(
          value: BodeMode.frequencySweep,
          child: Text('Frequency Sweep'),
        ),
        DropdownMenuItem(
          value: BodeMode.amplitudeSweep,
          child: Text('Amplitude Sweep'),
        ),
      ],
      onChanged: (value) {
        if (value == null) return;
        _setMode(value);
      },
    );
  }

  Widget _buildPointsField() {
    return TextField(
      controller: _pointsController,
      onChanged: (_) => _updateDraft(),
      keyboardType: TextInputType.number,
      decoration: _decoration('Points'),
    );
  }

  Widget _buildSettleField() {
    return TextField(
      controller: _settleController,
      onChanged: (_) => _updateDraft(),
      keyboardType: TextInputType.number,
      decoration: _decoration('Settle (ms)'),
    );
  }

  Widget _numberField(
    String label,
    TextEditingController controller, {
    bool signed = false,
  }) {
    return TextField(
      controller: controller,
      onChanged: (_) => _updateDraft(),
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: signed,
      ),
      decoration: _decoration(label),
    );
  }

  /// Spacing dropdown for the frequency or the amplitude sweep.
  ///
  /// Both modes keep their own value so switching the measurement method does
  /// not overwrite the other configuration.
  Widget _buildSpacingDropdown({required bool amplitude}) {
    return DropdownButtonFormField<BodeSpacing>(
      key: ValueKey(
        amplitude ? 'bode-spacing-amplitude' : 'bode-spacing-frequency',
      ),
      initialValue: amplitude ? _draft.amplitudeSpacing : _draft.spacing,
      isExpanded: true,
      dropdownColor: const Color(0xFF1E1E1E),
      decoration: _decoration('Spacing'),
      items: const [
        DropdownMenuItem(
          value: BodeSpacing.logarithmic,
          child: Text('Logarithmic'),
        ),
        DropdownMenuItem(value: BodeSpacing.linear, child: Text('Linear')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _draft = amplitude
              ? _draft.copyWith(amplitudeSpacing: value)
              : _draft.copyWith(spacing: value);
        });
      },
    );
  }

  /// Scope input channel for the amplitude sweep.
  ///
  /// The other channel is used as the output, so only one channel needs to be
  /// selected.
  Widget _buildScopeInputDropdown() {
    return DropdownButtonFormField<int>(
      key: const ValueKey('bode-scope-input'),
      initialValue: _draft.vinChannel,
      isExpanded: true,
      dropdownColor: const Color(0xFF1E1E1E),
      decoration: _decoration('Vin channel'),
      items: const [
        DropdownMenuItem(value: 1, child: Text('CH1')),
        DropdownMenuItem(value: 2, child: Text('CH2')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          _draft = _draft.copyWith(
            vinChannel: value,
            voutChannel: value == 1 ? 2 : 1,
          );
        });
      },
    );
  }

  /// Read-only display of the scope output channel paired with the input.
  Widget _buildVoutDisplay() {
    return InputDecorator(
      decoration: _decoration('Vout channel'),
      child: Text(
        'CH${_draft.voutChannel}',
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
    );
  }

  /// Waveform dropdown restricted to the connected generator family.
  Widget _buildWaveformDropdown() {
    final info = widget.signalGenerator.deviceInfo;
    final family = info?.family ?? SiggenFamily.jds6600;
    final waveforms = Jds6600Waveform.selectableFor(
      family,
      channel: _draft.generatorChannel,
    );
    // A saved config can contain a waveform the connected family does not
    // offer; show the first supported entry instead of asserting.
    final selected = waveforms.contains(_draft.waveform)
        ? _draft.waveform
        : waveforms.first;
    return DropdownButtonFormField<Jds6600Waveform>(
      // Recreate when the generator output or the draft waveform changes;
      // FY6900 CH2 does not offer the same waveform set as CH1.
      key: ValueKey(
        'bode-waveform-${_draft.generatorChannel}-${_draft.waveform.name}',
      ),
      initialValue: selected,
      isExpanded: true,
      dropdownColor: const Color(0xFF1E1E1E),
      decoration: _decoration('Waveform'),
      items: waveforms
          .map(
            (value) => DropdownMenuItem(
              value: value,
              child: Text(value.displayNameFor(family)),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() => _draft = _draft.copyWith(waveform: value));
      },
    );
  }

  /// Generator output driven by the sweep.
  ///
  /// Only the selected output is configured and switched on; the other
  /// output keeps its state.
  Widget _buildGeneratorChannelDropdown() {
    return DropdownButtonFormField<int>(
      key: const ValueKey('bode-generator-channel'),
      initialValue: _draft.generatorChannel,
      isExpanded: true,
      dropdownColor: const Color(0xFF1E1E1E),
      decoration: _decoration('Generator output'),
      items: const [
        DropdownMenuItem(value: 1, child: Text('CH1')),
        DropdownMenuItem(value: 2, child: Text('CH2')),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          final info = widget.signalGenerator.deviceInfo;
          final family = info?.family ?? SiggenFamily.jds6600;
          final waveforms = Jds6600Waveform.selectableFor(
            family,
            channel: value,
          );
          // FY6900 CH2 has no Adj-Pulse entry; fall back to the first
          // waveform the new output supports instead of keeping a value
          // that fails validation.
          _draft = _draft.copyWith(
            generatorChannel: value,
            waveform: waveforms.contains(_draft.waveform)
                ? _draft.waveform
                : waveforms.first,
          );
        });
      },
    );
  }

  /// Shows the limits of the connected generator model for the current
  /// waveform. The same limits are enforced by [validateBodeConfig].
  Widget _buildModelLimits() {
    final info = widget.signalGenerator.deviceInfo;
    if (info == null) {
      return const Text(
        'Connect the signal generator to load the model limits.',
        style: TextStyle(color: Colors.white38, fontSize: 11),
      );
    }
    final maxFrequency = info.maxFrequencyHz(_draft.waveform);
    final referenceFrequency = _draft.mode == BodeMode.amplitudeSweep
        ? _draft.sweepFrequencyHz
        : _draft.stopFrequencyHz;
    final maxAmplitude = info.maxAmplitudeVpp(referenceFrequency);
    final maxOffset = info.maxOffsetVAt(referenceFrequency);
    return Text(
      'Model ${info.modelName}: '
      '${_draft.waveform.displayNameFor(info.family)} up to '
      '${formatFrequencyHz(maxFrequency)} · amplitude up to '
      '${_trim(maxAmplitude)} Vpp · offset ±${_trim(maxOffset)} V',
      key: const Key('bode-model-limits'),
      style: const TextStyle(color: Colors.white54, fontSize: 11),
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

          // ---- Measurement Method ----
          _buildModeDropdown(),
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

          if (_draft.mode == BodeMode.frequencySweep) ...[
            Row(
              children: [
                Expanded(
                  child: _frequencyField(
                    'Start',
                    _startController,
                    _startUnit,
                    (value) => _startUnit = value,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _frequencyField(
                    'Stop',
                    _stopController,
                    _stopUnit,
                    (value) => _stopUnit = value,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 110, child: _buildPointsField()),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _numberField('Amplitude (Vpp)', _amplitudeController),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numberField(
                    'Offset (V)',
                    _offsetController,
                    signed: true,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 130, child: _buildSettleField()),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildSpacingDropdown(amplitude: false)),
                const SizedBox(width: 8),
                Expanded(child: _buildGeneratorChannelDropdown()),
                const SizedBox(width: 8),
                Expanded(child: _buildWaveformDropdown()),
              ],
            ),
            const SizedBox(height: 6),
            _buildModelLimits(),
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
                      setState(
                        () => _draft = _draft.copyWith(vinChannel: value),
                      );
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
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _frequencyField(
                    'Frequency',
                    _sweepFrequencyController,
                    _sweepFrequencyUnit,
                    (value) => _sweepFrequencyUnit = value,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 110, child: _buildPointsField()),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _numberField(
                    'Amplitude Start (Vpp)',
                    _startAmplitudeController,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numberField(
                    'Amplitude Stop (Vpp)',
                    _stopAmplitudeController,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numberField(
                    'Offset (V)',
                    _offsetController,
                    signed: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(width: 130, child: _buildSettleField()),
                const SizedBox(width: 8),
                Expanded(child: _buildSpacingDropdown(amplitude: true)),
                const SizedBox(width: 8),
                Expanded(child: _buildGeneratorChannelDropdown()),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildWaveformDropdown()),
                const SizedBox(width: 8),
                Expanded(child: _buildScopeInputDropdown()),
                const SizedBox(width: 8),
                Expanded(child: _buildVoutDisplay()),
              ],
            ),
            const SizedBox(height: 6),
            _buildModelLimits(),
          ],
          if (validation != null) ...[
            const SizedBox(height: 6),
            Text(
              validation,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                key: const ValueKey('bode_output_off_toggle'),
                onPressed: () => setState(
                  () => _draft = _draft.copyWith(
                    turnOffOutputsAfterSweep: !_draft.turnOffOutputsAfterSweep,
                  ),
                ),
                icon: Icon(
                  _draft.turnOffOutputsAfterSweep
                      ? Icons.power_settings_new
                      : Icons.power,
                  size: 16,
                ),
                label: Text(
                  _draft.turnOffOutputsAfterSweep
                      ? 'Outputs off after sweep'
                      : 'Outputs stay on after sweep',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _draft.turnOffOutputsAfterSweep
                      ? Colors.cyanAccent
                      : Colors.orangeAccent,
                  side: BorderSide(
                    color: _draft.turnOffOutputsAfterSweep
                        ? Colors.cyanAccent
                        : Colors.orangeAccent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: ready && validation == null ? _start : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('START SWEEP'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
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
          _buildPurposeNote(),
        ],
      ),
    );
  }

  /// Short explanation of the selected measurement method.
  Widget _buildPurposeNote() {
    final amplitude = _draft.mode == BodeMode.amplitudeSweep;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 14, color: Colors.white38),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            amplitude
                ? 'An amplitude sweep drives a circuit at a fixed frequency '
                      'and varies the generator level. Use it to check gain '
                      'linearity, find compression or clipping limits and '
                      'verify the usable amplitude range of amplifiers and '
                      'signal generators.'
                : 'A Bode frequency sweep measures how a circuit responds '
                      'across frequency: gain, bandwidth, resonance and '
                      'phase. Use it to verify filters, amplifiers, speakers '
                      'or control loops.',
            key: Key(
              amplitude ? 'bode-amplitude-sweep-purpose' : 'bode-sweep-purpose',
            ),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ),
      ],
    );
  }

  /// Maps the mouse position onto the amplitude axis and stores the hovered
  /// amplitude for the cursor tooltip.
  void _onAmplitudeHover(
    Offset local,
    BoxConstraints constraints,
    BodeConfig config,
  ) {
    final plotWidth = constraints.maxWidth - _ampPlotLeft - _ampPlotRight;
    final plotHeight = constraints.maxHeight - _ampPlotTop - _ampPlotBottom;
    if (plotWidth <= 0 || plotHeight <= 0) return;
    final inside =
        local.dx >= _ampPlotLeft &&
        local.dx <= _ampPlotLeft + plotWidth &&
        local.dy >= _ampPlotTop &&
        local.dy <= _ampPlotTop + plotHeight;
    if (!inside) {
      _clearAmplitudeHover();
      return;
    }

    final fraction = ((local.dx - _ampPlotLeft) / plotWidth).clamp(0.0, 1.0);
    final start = config.startAmplitudeVpp;
    final stop = config.stopAmplitudeVpp;
    final amplitude =
        config.amplitudeSpacing == BodeSpacing.logarithmic && start > 0
        ? start * math.pow(stop / start, fraction)
        : start + (stop - start) * fraction;
    setState(() {
      _hoverAmplitudeVpp = amplitude.toDouble();
      _hoverX = local.dx;
      _hoverY = local.dy;
    });
  }

  void _clearAmplitudeHover() {
    if (_hoverAmplitudeVpp == null) return;
    setState(() => _hoverAmplitudeVpp = null);
  }

  /// Tooltip showing the measured values of the nearest point at the cursor.
  Widget _buildAmplitudeHoverTooltip(double width, double height) {
    final hovered = _hoverAmplitudeVpp!;
    BodePoint? nearest;
    for (final point in _points) {
      final amplitude = point.amplitudeVpp;
      if (amplitude == null || !amplitude.isFinite) continue;
      if (nearest == null ||
          (amplitude - hovered).abs() <
              (nearest.amplitudeVpp! - hovered).abs()) {
        nearest = point;
      }
    }
    if (nearest == null) return const SizedBox.shrink();

    Widget row(String label, String value, Color color) =>
        Text('$label: $value', style: TextStyle(color: color, fontSize: 11));

    final rows = <Widget>[
      Text(
        'Amplitude: ${formatAmplitudeVpp(nearest.amplitudeVpp!)}',
        style: const TextStyle(color: Colors.white70, fontSize: 10),
      ),
    ];
    if (!_hiddenAmplitudeLines.contains('gain')) {
      rows.add(
        row(
          'Gain',
          '${nearest.gainDb?.toStringAsFixed(2) ?? '—'} dB',
          Colors.cyanAccent,
        ),
      );
    }
    if (!_hiddenAmplitudeLines.contains('vout_vpp')) {
      rows.add(
        row(
          'Vout Vpp',
          '${_formatVoltage(nearest.voutVpp)} V',
          Colors.greenAccent,
        ),
      );
    }
    if (!_hiddenAmplitudeLines.contains('vout_vrms')) {
      rows.add(
        row(
          'Vout Vrms',
          '${_formatVoltage(nearest.voutRms)} V',
          Colors.orangeAccent,
        ),
      );
    }
    if (!_hiddenAmplitudeLines.contains('vpp_vrms')) {
      rows.add(
        row(
          'Vpp/Vrms',
          nearest.voutVppRmsRatio?.toStringAsFixed(2) ?? '—',
          Colors.yellowAccent,
        ),
      );
    }

    const tooltipWidth = 190.0;
    const tooltipHeight = 112.0;
    const gap = 10.0;
    final maxLeft = math.max(0.0, width - tooltipWidth);
    final maxTop = math.max(0.0, height - tooltipHeight - 8);
    final left = _hoverX >= width / 2
        ? (_hoverX - tooltipWidth - gap).clamp(0.0, maxLeft)
        : (_hoverX + gap).clamp(0.0, maxLeft);
    final top = (_hoverY - tooltipHeight - 8).clamp(0.0, maxTop);
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

  /// Clickable chip that hides or shows one amplitude-sweep curve.
  Widget _amplitudeChip(String label, String id, Color color) {
    final hidden = _hiddenAmplitudeLines.contains(id);
    return GestureDetector(
      key: ValueKey('bode-chip-$id'),
      onTap: () {
        setState(() {
          if (hidden) {
            _hiddenAmplitudeLines.remove(id);
          } else {
            _hiddenAmplitudeLines.add(id);
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

  Widget _buildRunningState(BodeAnalysisSummary analysis) {
    final service = _service;
    final config = _runConfig ?? _draft;
    final amplitudeSweep = config.mode == BodeMode.amplitudeSweep;
    final last = _points.isNotEmpty ? _points.last : null;
    final progress = service == null
        ? '0 / 0'
        : '${service.completedPoints} / ${service.totalPoints}';
    final currentFrequency = service?.currentFrequencyHz;
    final currentAmplitude = service?.currentAmplitudeVpp;
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
              if (amplitudeSweep) ...[
                if (currentAmplitude != null)
                  Text(
                    'Current: ${formatAmplitudeVpp(currentAmplitude)} @ '
                    '${formatFrequencyHz(currentFrequency ?? config.sweepFrequencyHz)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                if (last != null)
                  Text(
                    'Last: ${last.amplitudeVpp == null ? '—' : formatAmplitudeVpp(last.amplitudeVpp!)} · '
                    '${last.gainDb?.toStringAsFixed(2) ?? '—'} dB · '
                    'Vout ${_formatVoltage(last.voutVpp)} Vpp / '
                    '${_formatVoltage(last.voutRms)} Vrms · '
                    'Vpp/Vrms ${last.voutVppRmsRatio?.toStringAsFixed(2) ?? '—'}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
              ] else ...[
                if (currentFrequency != null)
                  Text(
                    'Current: ${formatFrequencyHz(currentFrequency)}',
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
              if (amplitudeSweep) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _amplitudeChip('Gain (dB)', 'gain', Colors.cyanAccent),
                    _amplitudeChip('Vout Vpp', 'vout_vpp', Colors.greenAccent),
                    _amplitudeChip(
                      'Vout Vrms',
                      'vout_vrms',
                      Colors.orangeAccent,
                    ),
                    _amplitudeChip('Vpp/Vrms', 'vpp_vrms', Colors.yellowAccent),
                  ],
                ),
              ],
              if (analysis.hasData) _buildAnalysisSummary(analysis),
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

  /// Compact analysis result shown below the sweep status.
  Widget _buildAnalysisSummary(BodeAnalysisSummary analysis) {
    Widget item(String label, String value) => Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 9),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              if (analysis.peakGainDb != null &&
                  analysis.peakFrequencyHz != null)
                item(
                  'Peak',
                  '${analysis.peakGainDb!.toStringAsFixed(2)} dB @ '
                      '${formatFrequencyHz(analysis.peakFrequencyHz!)}',
                ),
              if (analysis.minus3DbFrequencyHz != null)
                item('−3 dB', formatFrequencyHz(analysis.minus3DbFrequencyHz!)),
              if (analysis.bandwidthHz != null)
                item('Bandwidth', formatFrequencyHz(analysis.bandwidthHz!)),
              if (analysis.qFactor != null)
                item('Q factor', analysis.qFactor!.toStringAsFixed(2)),
              if (analysis.unityCrossoverHz != null)
                item('0 dB', formatFrequencyHz(analysis.unityCrossoverHz!)),
            ],
          ),
          if (analysis.notes.isNotEmpty)
            Text(
              analysis.notes.join(' · '),
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
        ],
      ),
    );
  }

  Widget _frequencyField(
    String label,
    TextEditingController controller,
    String unit,
    ValueChanged<String> onUnitChanged,
  ) {
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
            // Recreate with the active unit so the field always shows the
            // value that belongs to the selected unit.
            key: ValueKey('bode-unit-$label-$unit'),
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
              onUnitChanged(value);
              _updateDraft();
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

  String _formatVoltage(double? value) {
    if (value == null || !value.isFinite) return '—';
    final abs = value.abs();
    if (abs >= 1) return value.toStringAsFixed(3);
    if (abs >= 0.001) return value.toStringAsFixed(4);
    return value.toStringAsExponential(2);
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

/// Plot margins of the single amplitude-sweep chart. Shared with the hover
/// mapping in the panel so the cursor position matches the painted axis.
const double _ampPlotLeft = 75;
const double _ampPlotRight = 75;
const double _ampPlotTop = 34;
const double _ampPlotBottom = 42;

enum _AmplitudeAxis { voltage, ratio, gain }

/// One curve of the amplitude-sweep chart.
class _AmplitudeSeries {
  const _AmplitudeSeries({
    required this.id,
    required this.label,
    required this.color,
    required this.value,
    required this.axis,
  });

  /// Identifier used for hiding the curve and in the legend.
  final String id;

  final String label;
  final Color color;
  final double? Function(BodePoint point) value;
  final _AmplitudeAxis axis;
}

class _BodePlotPainter extends CustomPainter {
  _BodePlotPainter({
    required this.points,
    required this.config,
    required this.status,
    required this.analysis,
    required this.hiddenLines,
  });

  final List<BodePoint> points;
  final BodeConfig config;
  final BodeStatus status;
  final BodeAnalysisSummary analysis;
  final Set<String> hiddenLines;

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

    if (config.mode == BodeMode.amplitudeSweep) {
      _paintAmplitudeChart(canvas, size);
      return;
    }

    final chartWidth = size.width - _left - _right;
    final showPhase = config.measurePhase;
    // Without a phase measurement the gain chart uses the full height and
    // carries the frequency axis itself.
    final chartHeight = showPhase
        ? (size.height - _top - _bottom - _gap) / 2
        : size.height - _top - _bottom;
    if (chartWidth <= 0 || chartHeight <= 0) return;
    final magnitudeRect = Rect.fromLTWH(_left, _top, chartWidth, chartHeight);

    _drawChart(
      canvas,
      magnitudeRect,
      'Gain (dB)',
      isPhase: false,
      showFrequencyAxis: !showPhase,
    );
    if (showPhase) {
      final phaseRect = Rect.fromLTWH(
        _left,
        _top + chartHeight + _gap,
        chartWidth,
        chartHeight,
      );
      _drawChart(
        canvas,
        phaseRect,
        'Phase (deg)',
        isPhase: true,
        showFrequencyAxis: true,
      );
    }

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

  /// Draws all amplitude-sweep curves in one chart, Data-Logger style.
  ///
  /// Voout Vpp and Vout Vrms use the left voltage axis, Vpp/Vrms the right
  /// axis and Gain (dB) an inner-left axis. Curves whose id is in
  /// [hiddenLines] are skipped.
  void _paintAmplitudeChart(Canvas canvas, Size size) {
    final plotRect = Rect.fromLTWH(
      _ampPlotLeft,
      _ampPlotTop,
      size.width - _ampPlotLeft - _ampPlotRight,
      size.height - _ampPlotTop - _ampPlotBottom,
    );
    if (plotRect.width <= 0 || plotRect.height <= 0) return;

    final start = config.startAmplitudeVpp;
    final stop = config.stopAmplitudeVpp;
    final axisValid = config.amplitudeSpacing == BodeSpacing.logarithmic
        ? start > 0 && stop > start
        : start >= 0 && stop > start;
    if (!axisValid) return;

    final series = <_AmplitudeSeries>[
      _AmplitudeSeries(
        id: 'gain',
        label: 'Gain (dB)',
        color: Colors.cyanAccent,
        value: (point) => point.gainDb,
        axis: _AmplitudeAxis.gain,
      ),
      _AmplitudeSeries(
        id: 'vout_vpp',
        label: 'Vout Vpp',
        color: Colors.greenAccent,
        value: (point) => point.voutVpp,
        axis: _AmplitudeAxis.voltage,
      ),
      _AmplitudeSeries(
        id: 'vout_vrms',
        label: 'Vout Vrms',
        color: Colors.orangeAccent,
        value: (point) => point.voutRms,
        axis: _AmplitudeAxis.voltage,
      ),
      _AmplitudeSeries(
        id: 'vpp_vrms',
        label: 'Vpp/Vrms',
        color: Colors.yellowAccent,
        value: (point) => point.voutVppRmsRatio,
        axis: _AmplitudeAxis.ratio,
      ),
    ];

    final voltageValues = points
        .where((point) => point.valid)
        .expand((point) => [point.voutVpp, point.voutRms])
        .whereType<double>()
        .where((value) => value.isFinite)
        .toList();
    final ratioValues = points
        .where((point) => point.valid)
        .map((point) => point.voutVppRmsRatio)
        .whereType<double>()
        .where((value) => value.isFinite)
        .toList();
    final gainValues = points
        .where((point) => point.valid)
        .map((point) => point.gainDb)
        .whereType<double>()
        .where((value) => value.isFinite)
        .toList();

    final voltageRange = _amplitudeAxisRange(voltageValues, minSpan: 0.1);
    final ratioRange = _amplitudeAxisRange(ratioValues, minSpan: 1.0);
    final gainRange = _amplitudeAxisRange(gainValues, minSpan: 2.0);
    final voltageTicks = _ticksForRange(voltageRange);
    final ratioTicks = _ticksForRange(ratioRange);
    final gainTicks = _ticksForRange(gainRange);

    canvas.drawRect(plotRect, Paint()..color = const Color(0xFF0A192F));
    final gridPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    // Horizontal grid follows the left voltage axis.
    for (final tick in voltageTicks) {
      final y = _yFor(tick, voltageRange.$1, voltageRange.$2, plotRect);
      canvas.drawLine(
        Offset(plotRect.left, y),
        Offset(plotRect.right, y),
        gridPaint,
      );
    }
    // Vertical grid and labels follow the shared amplitude axis.
    for (final tick in _amplitudeTicks(start, stop)) {
      final x = _xFor(tick, start, stop, plotRect);
      canvas.drawLine(
        Offset(x, plotRect.top),
        Offset(x, plotRect.bottom),
        gridPaint,
      );
      _drawText(
        canvas,
        _formatAmplitudeTick(tick),
        Offset(x - 22, plotRect.bottom + 8),
        Colors.white54,
        10,
      );
    }

    for (final entry in series) {
      if (hiddenLines.contains(entry.id)) continue;
      final range = switch (entry.axis) {
        _AmplitudeAxis.voltage => voltageRange,
        _AmplitudeAxis.ratio => ratioRange,
        _AmplitudeAxis.gain => gainRange,
      };
      _drawSeriesValues(
        canvas,
        plotRect,
        start,
        stop,
        range.$1,
        range.$2,
        entry.value,
        entry.color,
      );
    }

    // Left voltage axis labels.
    for (final tick in voltageTicks) {
      final y = _yFor(tick, voltageRange.$1, voltageRange.$2, plotRect);
      _drawTextRightAligned(
        canvas,
        _formatValueTick(tick),
        Offset(plotRect.left - 4, y - 6),
        Colors.white54,
        10,
      );
    }
    // Right Vpp/Vrms axis labels.
    for (final tick in ratioTicks) {
      final y = _yFor(tick, ratioRange.$1, ratioRange.$2, plotRect);
      _drawText(
        canvas,
        _formatValueTick(tick),
        Offset(plotRect.right + 4, y - 6),
        Colors.white54,
        10,
      );
    }
    // Inner-left gain axis labels.
    for (final tick in gainTicks) {
      final y = _yFor(tick, gainRange.$1, gainRange.$2, plotRect);
      _drawText(
        canvas,
        '${_formatDbTick(tick)}dB',
        Offset(plotRect.left + 4, y - 6),
        Colors.cyanAccent.withValues(alpha: 0.8),
        10,
      );
    }

    // Axis titles.
    _drawText(
      canvas,
      'Voltage (V)',
      Offset(4, plotRect.center.dy - 6),
      Colors.white70,
      10,
    );
    _drawTextRightAligned(
      canvas,
      'Vpp/Vrms',
      Offset(size.width - 4, plotRect.center.dy - 6),
      Colors.white70,
      10,
    );
    _drawCenteredText(
      canvas,
      'Generator amplitude (Vpp)',
      center: Offset(plotRect.center.dx, plotRect.bottom + 32),
      color: Colors.white70,
      fontSize: 11,
    );

    _drawAmplitudeLegend(canvas, plotRect, series);

    final border = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke;
    canvas.drawRect(plotRect, border);

    if (points.every((point) => point.gainDb == null)) {
      _drawCenteredText(
        canvas,
        'Waiting for sweep data',
        center: plotRect.center,
        color: Colors.yellow,
        fontSize: 12,
      );
    }
  }

  /// Pads the measured values into a usable axis range.
  (double, double) _amplitudeAxisRange(
    List<double> values, {
    required double minSpan,
  }) {
    var min = values.isEmpty ? 0.0 : values.reduce(math.min);
    var max = values.isEmpty ? 1.0 : values.reduce(math.max);
    min = math.min(min, 0);
    max = math.max(max, 0);
    if (max - min < minSpan) {
      final center = (min + max) / 2;
      min = center - minSpan / 2;
      max = center + minSpan / 2;
    }
    final padding = (max - min) * 0.2;
    if (min >= 0) return (0.0, max + padding);
    return (min - padding, max + padding);
  }

  List<double> _ticksForRange((double, double) range) {
    final ticks = _niceTicks(range.$1, range.$2)
        .where((value) => value >= range.$1 - 1e-9 && value <= range.$2 + 1e-9)
        .toList();
    return ticks.length < 2 ? [range.$1, range.$2] : ticks;
  }

  String _formatDbTick(double value) {
    if (value == 0) return '0';
    final abs = value.abs();
    if (abs >= 100) return value.toStringAsFixed(0);
    if (abs >= 1) return value.toStringAsFixed(1);
    return value.toStringAsFixed(2);
  }

  void _drawAmplitudeLegend(
    Canvas canvas,
    Rect plotRect,
    List<_AmplitudeSeries> series,
  ) {
    const itemHeight = 16.0;
    const padding = 8.0;
    const width = 120.0;
    final height = series.length * itemHeight + padding * 2;
    final legendRect = Rect.fromLTWH(
      plotRect.right - width - 8,
      plotRect.top + 8,
      width,
      height,
    );
    final radius = RRect.fromRectAndRadius(
      legendRect,
      const Radius.circular(4),
    );
    canvas.drawRRect(radius, Paint()..color = const Color(0xB00A192F));
    canvas.drawRRect(
      radius,
      Paint()
        ..color = AppColors.border.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    for (var index = 0; index < series.length; index++) {
      final entry = series[index];
      final hidden = hiddenLines.contains(entry.id);
      final y =
          legendRect.top + padding + index * itemHeight + itemHeight / 2 - 1;
      canvas.drawLine(
        Offset(legendRect.left + 8, y),
        Offset(legendRect.left + 28, y),
        Paint()
          ..color = hidden ? entry.color.withValues(alpha: 0.25) : entry.color
          ..strokeWidth = 2,
      );
      final painter = TextPainter(
        text: TextSpan(
          text: entry.label,
          style: TextStyle(
            color: hidden ? Colors.white30 : Colors.white70,
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(legendRect.left + 34, y - painter.height / 2),
      );
    }
  }

  void _drawTextRightAligned(
    Canvas canvas,
    String text,
    Offset rightTop,
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
    painter.paint(canvas, Offset(rightTop.dx - painter.width, rightTop.dy));
  }

  String _formatValueTick(double value) {
    if (!value.isFinite) return '—';
    final abs = value.abs();
    var text = value.toStringAsFixed(
      abs >= 10
          ? 0
          : abs >= 1
          ? 1
          : 2,
    );
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text == '-0' ? '0' : text;
  }

  void _drawChart(
    Canvas canvas,
    Rect rect,
    String yLabel, {
    required bool isPhase,
    required bool showFrequencyAxis,
  }) {
    final border = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF0A192F));
    canvas.drawRect(rect, border);

    final start = config.startFrequencyHz;
    final stop = config.stopFrequencyHz;
    if (start <= 0 || stop <= start) return;

    final xTicks = _frequencyTicks(start, stop);
    final gainTicks = isPhase
        ? const [-180.0, -90.0, 0.0, 90.0, 180.0]
        : _gainTicks();
    final yMin = isPhase ? -180.0 : gainTicks.first;
    final yMax = isPhase ? 180.0 : gainTicks.last;

    final gridPaint = Paint()
      ..color = Colors.white12
      ..strokeWidth = 1;
    for (final tick in xTicks) {
      final x = _xFor(tick, start, stop, rect);
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
      if (showFrequencyAxis) {
        _drawText(
          canvas,
          formatFrequencyHz(tick),
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

    if (showFrequencyAxis) {
      _drawCenteredText(
        canvas,
        'Frequency (Hz)',
        center: Offset(rect.center.dx, rect.bottom + 32),
        color: Colors.white70,
        fontSize: 11,
      );
    }

    _drawSeries(canvas, rect, start, stop, yMin, yMax, isPhase: isPhase);
    if (!isPhase) {
      _drawAnalysisMarkers(canvas, rect, start, stop);
    }
  }

  /// Draws dashed vertical markers for the analysis frequencies.
  void _drawAnalysisMarkers(
    Canvas canvas,
    Rect rect,
    double start,
    double stop,
  ) {
    final markers = <(String, double, Color)>[
      if (analysis.peakFrequencyHz != null)
        ('Peak', analysis.peakFrequencyHz!, Colors.greenAccent),
      if (analysis.minus3DbFrequencyHz != null)
        ('−3 dB', analysis.minus3DbFrequencyHz!, Colors.yellowAccent),
      if (analysis.lowerMinus3DbFrequencyHz != null)
        (
          '−3 dB',
          analysis.lowerMinus3DbFrequencyHz!,
          Colors.yellowAccent.withValues(alpha: 0.6),
        ),
      if (analysis.unityCrossoverHz != null)
        ('0 dB', analysis.unityCrossoverHz!, Colors.white70),
    ];
    if (markers.isEmpty) return;

    var labelY = rect.top + 4;
    for (final (label, frequency, color) in markers) {
      if (frequency < start || frequency > stop) continue;
      final x = _xFor(frequency, start, stop, rect);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..strokeWidth = 1.0;
      _drawDashedVertical(canvas, x, rect.top, rect.bottom, paint);
      _drawText(
        canvas,
        '$label ${formatFrequencyHz(frequency)}',
        Offset(x + 3, labelY),
        color,
        10,
      );
      labelY += 13;
    }
  }

  void _drawDashedVertical(
    Canvas canvas,
    double x,
    double top,
    double bottom,
    Paint paint,
  ) {
    const dash = 6.0;
    const gap = 4.0;
    var y = top;
    while (y < bottom) {
      final end = math.min(y + dash, bottom);
      canvas.drawLine(Offset(x, y), Offset(x, end), paint);
      y += dash + gap;
    }
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
    _drawSeriesValues(
      canvas,
      rect,
      start,
      stop,
      yMin,
      yMax,
      (point) => isPhase ? point.phaseDeg : point.gainDb,
      isPhase ? Colors.orangeAccent : Colors.cyanAccent,
    );
  }

  void _drawSeriesValues(
    Canvas canvas,
    Rect rect,
    double start,
    double stop,
    double yMin,
    double yMax,
    double? Function(BodePoint point) valueOf,
    Color color,
  ) {
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final pointPaint = Paint()..color = color;

    Path? path;
    var lastValid = false;
    for (final point in points) {
      final value = valueOf(point);
      final xValue = config.mode == BodeMode.amplitudeSweep
          ? point.amplitudeVpp
          : point.frequencyHz;
      if (!point.valid ||
          value == null ||
          !value.isFinite ||
          xValue == null ||
          !xValue.isFinite) {
        lastValid = false;
        if (path != null) {
          canvas.drawPath(path, linePaint);
          path = null;
        }
        continue;
      }
      final offset = Offset(
        _xFor(xValue, start, stop, rect),
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

  List<double> _amplitudeTicks(double start, double stop) {
    if (config.amplitudeSpacing == BodeSpacing.logarithmic) {
      return _frequencyTicks(start, stop);
    }
    final ticks = _niceTicks(
      start,
      stop,
    ).where((value) => value >= start && value <= stop).toList();
    return ticks.length < 2 ? [start, stop] : ticks;
  }

  String _formatAmplitudeTick(double value) {
    if (!value.isFinite) return '—';
    var text = value.toStringAsFixed(value.abs() >= 10 ? 0 : 2);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      text = text.replaceFirst(RegExp(r'\.$'), '');
    }
    return text == '-0' ? '0' : text;
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

  double _xFor(double value, double start, double stop, Rect rect) {
    final logarithmic =
        config.mode == BodeMode.frequencySweep ||
        config.amplitudeSpacing == BodeSpacing.logarithmic;
    final fraction = logarithmic
        ? (math.log(value) - math.log(start)) /
              (math.log(stop) - math.log(start))
        : (value - start) / (stop - start);
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
        oldDelegate.status != status ||
        oldDelegate.hiddenLines.length != hiddenLines.length ||
        !oldDelegate.hiddenLines.containsAll(hiddenLines) ||
        oldDelegate.analysis.peakFrequencyHz != analysis.peakFrequencyHz ||
        oldDelegate.analysis.peakGainDb != analysis.peakGainDb ||
        oldDelegate.analysis.minus3DbFrequencyHz !=
            analysis.minus3DbFrequencyHz ||
        oldDelegate.analysis.lowerMinus3DbFrequencyHz !=
            analysis.lowerMinus3DbFrequencyHz ||
        oldDelegate.analysis.unityCrossoverHz != analysis.unityCrossoverHz;
  }
}
