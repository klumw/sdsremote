/// Remote-control UI for the configured signal generator (JDS6600 or FY6900).
///
/// Pure presentation: all state, validation and device access live in
/// [SignalGeneratorPanelController]. No menu button is provided; the window is
/// opened with Ctrl+J from the main application.
library;

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../instrument/measurement.dart' show formatMeasurementValue;
import '../signal_generator/models.dart';
import '../signal_generator/siggen_window_controller.dart';

class SignalGeneratorPanel extends StatefulWidget {
  const SignalGeneratorPanel({super.key, required this.controller});

  final SignalGeneratorPanelController controller;

  @override
  State<SignalGeneratorPanel> createState() => _SignalGeneratorPanelState();
}

class _SignalGeneratorPanelState extends State<SignalGeneratorPanel> {
  final _frequency = TextEditingController();
  final _amplitude = TextEditingController();
  final _offset = TextEditingController();
  final _duty = TextEditingController();
  final _phase = TextEditingController();

  final _frequencyFocus = FocusNode();
  final _amplitudeFocus = FocusNode();
  final _offsetFocus = FocusNode();
  final _dutyFocus = FocusNode();
  final _phaseFocus = FocusNode();

  int _lastChannel = 1;

  SignalGeneratorPanelController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _fillTextFields(force: true);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    for (final controller in [_frequency, _amplitude, _offset, _duty, _phase]) {
      controller.dispose();
    }
    for (final focus in [
      _frequencyFocus,
      _amplitudeFocus,
      _offsetFocus,
      _dutyFocus,
      _phaseFocus,
    ]) {
      focus.dispose();
    }
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    _fillTextFields();
  }

  /// Copies draft values into the text fields unless the user is typing there.
  void _fillTextFields({bool force = false}) {
    final draft = _controller.draft;
    final channelChanged = _lastChannel != _controller.selectedChannel;
    _lastChannel = _controller.selectedChannel;
    final syncAll = force || channelChanged;
    _setText(_frequency, _frequencyFocus, draft.frequencyText, syncAll);
    _setText(_amplitude, _amplitudeFocus, draft.amplitudeText, syncAll);
    _setText(_offset, _offsetFocus, draft.offsetText, syncAll);
    _setText(_duty, _dutyFocus, draft.dutyText, syncAll);
    _setText(_phase, _phaseFocus, draft.phaseText, syncAll);
  }

  void _setText(
    TextEditingController controller,
    FocusNode focus,
    String text,
    bool force,
  ) {
    if (!force && focus.hasFocus) return;
    if (controller.text == text) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.panelBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border, width: 1.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _buildHeader(),
                _buildDeviceSelector(),
                const Divider(height: 1, color: AppColors.border),
                Expanded(child: _buildEditor()),
                _buildStatusBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Header / selector / footer
  // -------------------------------------------------------------------------

  Widget _buildHeader() {
    final generator = _controller.generator;
    final connected = generator.connected;
    final subtitle = generator.configured
        ? [
            if (generator.modelName != null) generator.modelName!,
            if (generator.port != null) generator.port!,
          ].join(' · ')
        : 'Not configured';
    return Container(
      color: const Color(0xFF172A45),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.waves, color: Colors.cyanAccent, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SIGNAL GENERATOR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          if (connected)
            const Icon(Icons.link, color: Colors.greenAccent, size: 18)
          else
            const Icon(Icons.link_off, color: Colors.redAccent, size: 18),
          const SizedBox(width: 6),
          Text(
            connected ? 'CONNECTED' : 'OFFLINE',
            style: TextStyle(
              color: connected ? Colors.greenAccent : Colors.redAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          if (_controller.busy) ...[
            const SizedBox(width: 12),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.cyanAccent,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceSelector() {
    final generator = _controller.generator;
    return Container(
      color: const Color(0xFF0F1D33),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final selection in SigGenDeviceSelection.values)
                  _deviceChip(selection),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _outputChip(1, generator.ch1Output, Colors.yellow),
          const SizedBox(width: 8),
          _outputChip(2, generator.ch2Output, const Color(0xFFFF20FF)),
        ],
      ),
    );
  }

  Widget _deviceChip(SigGenDeviceSelection selection) {
    final selected = _controller.selection == selection;
    final color = switch (selection) {
      SigGenDeviceSelection.ch1 => Colors.yellow,
      SigGenDeviceSelection.ch2 => const Color(0xFFFF20FF),
    };
    return InkWell(
      onTap: () => _controller.selectDevice(selection),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1E3A5F) : const Color(0xFF172A45),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 6),
            Text(
              selection.label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outputChip(int channel, bool enabled, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF172A45),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 9, color: color),
          const SizedBox(width: 6),
          Text(
            'CH$channel OUT',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(width: 6),
          Text(
            enabled ? 'ON' : 'OFF',
            style: TextStyle(
              color: enabled ? Colors.greenAccent : Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Channel editor
  // -------------------------------------------------------------------------

  Widget _buildEditor() {
    final generator = _controller.generator;
    final channel = _controller.selectedChannel;
    final color = channel == 1 ? Colors.yellow : const Color(0xFFFF20FF);
    final enabled = _controller.directEditingAllowed;
    final draft = _controller.draft;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!generator.connected && generator.configured)
            _banner(
              'Signal generator offline — controls are disabled.',
              Colors.redAccent,
            ),
          if (generator.connected && !generator.mutable)
            _banner(
              'Bode sweep running — settings cannot be changed.',
              Colors.orangeAccent,
            ),
          Row(
            children: [
              Icon(Icons.circle, size: 11, color: color),
              const SizedBox(width: 8),
              Text(
                'CH$channel',
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _confirmedSummary(channel),
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ),
              const Text(
                'OUTPUT',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(width: 6),
              Text(
                'OFF',
                key: const Key('output-off-label'),
                style: TextStyle(
                  color: generator.outputFor(channel)
                      ? Colors.white38
                      : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Switch(
                value: generator.outputFor(channel),
                activeThumbColor: color,
                onChanged: enabled ? _controller.setOutput : null,
              ),
              Text(
                'ON',
                key: const Key('output-on-label'),
                style: TextStyle(
                  color: generator.outputFor(channel)
                      ? Colors.greenAccent
                      : Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Output switching is immediate; all other values need Apply.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: _buildWaveformField(enabled, draft)),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: _buildFrequencyField(enabled, draft)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildAmplitudeField(enabled, draft)),
              const SizedBox(width: 12),
              Expanded(child: _buildOffsetField(enabled, draft)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildDutyField(enabled, draft)),
              const SizedBox(width: 12),
              Expanded(child: _buildPhaseField(enabled, draft)),
            ],
          ),
          const SizedBox(height: 12),
          if (_controller.validationError != null)
            Text(
              _controller.validationError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _controller.canApply
                    ? () => _controller.applyChanges()
                    : null,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('APPLY CHANGES'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan.shade800,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF334155),
                  disabledForegroundColor: Colors.white38,
                ),
              ),
              OutlinedButton.icon(
                onPressed: enabled && !_controller.busy
                    ? () => _controller.refreshFromDevice()
                    : null,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('REFRESH FROM DEVICE'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  side: const BorderSide(color: Colors.cyanAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWaveformField(bool enabled, SigGenChannelDraft draft) {
    return DropdownButtonFormField<Jds6600Waveform>(
      // Recreate when the value is changed externally (refresh/revert).
      key: ValueKey(
        'waveform-${_controller.selectedChannel}-${draft.waveform.name}',
      ),
      initialValue: draft.waveform,
      isExpanded: true,
      dropdownColor: const Color(0xFF1E1E1E),
      decoration: _decoration('Waveform'),
      items: _controller.selectableWaveforms
          .map(
            (waveform) => DropdownMenuItem(
              value: waveform,
              child: Text(waveform.displayName),
            ),
          )
          .toList(),
      onChanged: enabled
          ? (value) {
              if (value != null) _controller.updateWaveform(value);
            }
          : null,
    );
  }

  Widget _buildFrequencyField(bool enabled, SigGenChannelDraft draft) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _frequency,
                focusNode: _frequencyFocus,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _decoration('Frequency'),
                onChanged: _controller.updateFrequencyText,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 110,
              child: DropdownButtonFormField<String>(
                key: ValueKey('unit-${draft.frequencyUnit}'),
                initialValue: draft.frequencyUnit,
                isExpanded: true,
                dropdownColor: const Color(0xFF1E1E1E),
                decoration: _decoration('Unit'),
                items: const ['Hz', 'kHz', 'MHz']
                    .map(
                      (unit) =>
                          DropdownMenuItem(value: unit, child: Text(unit)),
                    )
                    .toList(),
                onChanged: enabled
                    ? (value) {
                        if (value != null) {
                          _controller.updateFrequencyUnit(value);
                        }
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 4),
            _spinner(
              enabled: enabled,
              label: 'Frequency',
              onUp: () => _stepFrequency(1),
              onDown: () => _stepFrequency(-1),
            ),
          ],
        ),
        _hint(_frequencyHint(draft)),
      ],
    );
  }

  Widget _buildAmplitudeField(bool enabled, SigGenChannelDraft draft) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _amplitude,
                focusNode: _amplitudeFocus,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _decoration('Amplitude', suffix: 'Vpp'),
                onChanged: _controller.updateAmplitudeText,
              ),
            ),
            const SizedBox(width: 4),
            _spinner(
              enabled: enabled,
              label: 'Amplitude',
              onUp: () => _stepAmplitude(1),
              onDown: () => _stepAmplitude(-1),
            ),
          ],
        ),
        _hint(_amplitudeHint(draft)),
      ],
    );
  }

  Widget _buildOffsetField(bool enabled, SigGenChannelDraft draft) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _offset,
                focusNode: _offsetFocus,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: _decoration('DC Offset', suffix: 'V'),
                onChanged: _controller.updateOffsetText,
              ),
            ),
            const SizedBox(width: 4),
            _spinner(
              enabled: enabled,
              label: 'DC Offset',
              onUp: () => _stepOffset(1),
              onDown: () => _stepOffset(-1),
            ),
          ],
        ),
        _hint(_offsetHint(draft)),
      ],
    );
  }

  Widget _buildDutyField(bool enabled, SigGenChannelDraft draft) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _duty,
                focusNode: _dutyFocus,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _decoration('Duty Cycle', suffix: '%'),
                onChanged: _controller.updateDutyText,
              ),
            ),
            const SizedBox(width: 4),
            _spinner(
              enabled: enabled,
              label: 'Duty Cycle',
              onUp: () => _stepDuty(1),
              onDown: () => _stepDuty(-1),
            ),
          ],
        ),
        _hint(_dutyHint),
      ],
    );
  }

  Widget _buildPhaseField(bool enabled, SigGenChannelDraft draft) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _phase,
                focusNode: _phaseFocus,
                enabled: enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _decoration(_phaseLabel, suffix: '°'),
                onChanged: _controller.updatePhaseText,
              ),
            ),
            const SizedBox(width: 4),
            _spinner(
              enabled: enabled,
              label: 'Phase',
              onUp: () => _stepPhase(1),
              onDown: () => _stepPhase(-1),
            ),
          ],
        ),
        _hint(_phaseHint),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Numeric spinners
  // -------------------------------------------------------------------------

  Widget _spinner({
    required bool enabled,
    required String label,
    required VoidCallback onUp,
    required VoidCallback onDown,
  }) {
    return SizedBox(
      width: 30,
      height: 46,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _spinnerButton(
            Icons.keyboard_arrow_up,
            'Increase $label',
            enabled ? onUp : null,
          ),
          _spinnerButton(
            Icons.keyboard_arrow_down,
            'Decrease $label',
            enabled ? onDown : null,
          ),
        ],
      ),
    );
  }

  Widget _spinnerButton(
    IconData icon,
    String tooltip,
    VoidCallback? onPressed,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 15,
        child: SizedBox(
          width: 30,
          height: 23,
          child: Icon(
            icon,
            size: 18,
            color: onPressed == null ? Colors.white24 : Colors.white54,
          ),
        ),
      ),
    );
  }

  void _stepFrequency(int direction) {
    final draft = _controller.draft;
    final factor = switch (draft.frequencyUnit) {
      'MHz' => 1e6,
      'kHz' => 1e3,
      _ => 1.0,
    };
    final info = _controller.deviceInfo;
    final current =
        draft.frequencyHz ?? _controller.confirmedChannel.frequencyHz;
    final next = (current + direction * factor)
        .clamp(info.limits.minFrequencyHz, info.maxFrequencyHz(draft.waveform))
        .toDouble();
    _applySpinner(
      _frequency,
      _fmtNumber(next / factor),
      _controller.updateFrequencyText,
    );
  }

  void _stepAmplitude(int direction) {
    final draft = _controller.draft;
    final info = _controller.deviceInfo;
    final confirmed = _controller.confirmedChannel;
    final frequency = draft.frequencyHz ?? confirmed.frequencyHz;
    final current = draft.amplitudeVpp ?? confirmed.amplitudeVpp;
    final next = (current + direction * 0.1)
        .clamp(0.0, info.maxAmplitudeVpp(frequency))
        .toDouble();
    _applySpinner(
      _amplitude,
      _fmtNumber(next),
      _controller.updateAmplitudeText,
    );
  }

  void _stepOffset(int direction) {
    final draft = _controller.draft;
    final info = _controller.deviceInfo;
    final frequency =
        draft.frequencyHz ?? _controller.confirmedChannel.frequencyHz;
    final current = draft.offsetV ?? _controller.confirmedChannel.offsetV;
    final next = (current + direction * 0.1)
        .clamp(info.minOffsetVAt(frequency), info.maxOffsetVAt(frequency))
        .toDouble();
    _applySpinner(_offset, _fmtNumber(next), _controller.updateOffsetText);
  }

  void _stepDuty(int direction) {
    final draft = _controller.draft;
    final limits = _controller.limits;
    final current =
        draft.dutyPercent ?? _controller.confirmedChannel.dutyPercent;
    final next = (current + direction * 1.0)
        .clamp(limits.minDutyPercent, limits.maxDutyPercent)
        .toDouble();
    _applySpinner(_duty, _fmtNumber(next), _controller.updateDutyText);
  }

  void _stepPhase(int direction) {
    final draft = _controller.draft;
    final limits = _controller.limits;
    final current = draft.phaseDeg ?? _controller.confirmedChannel.phaseDeg;
    final next = (current + direction * 1.0)
        .clamp(limits.minPhaseDegrees, limits.maxPhaseDegrees)
        .toDouble();
    _applySpinner(_phase, _fmtNumber(next), _controller.updatePhaseText);
  }

  void _applySpinner(
    TextEditingController textController,
    String text,
    void Function(String) update,
  ) {
    FocusManager.instance.primaryFocus?.unfocus();
    update(text);
    textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  String _frequencyHint(SigGenChannelDraft draft) {
    final info = _controller.deviceInfo;
    final max = info.maxFrequencyHz(draft.waveform);
    return 'Range: ${_fmtNumber(info.limits.minFrequencyHz)} Hz … '
        '${formatMeasurementValue(max, 'Hz')} '
        '(${draft.waveform.displayName})';
  }

  String _amplitudeHint(SigGenChannelDraft draft) {
    final info = _controller.deviceInfo;
    final frequency = draft.frequencyHz ?? 1000;
    final max = info.maxAmplitudeVpp(frequency);
    return 'Range: 0 … ${_fmtNumber(max)} Vpp at '
        '${formatMeasurementValue(frequency, 'Hz')}';
  }

  String _offsetHint(SigGenChannelDraft draft) {
    final info = _controller.deviceInfo;
    final frequency =
        draft.frequencyHz ?? _controller.confirmedChannel.frequencyHz;
    final min = info.minOffsetVAt(frequency);
    final max = info.maxOffsetVAt(frequency);
    final maxText = max >= 0 ? '+${_fmtNumber(max)}' : _fmtNumber(max);
    return 'Range: ${_fmtNumber(min)} … $maxText V at '
        '${formatMeasurementValue(frequency, 'Hz')}';
  }

  String get _dutyHint {
    final limits = _controller.limits;
    final applies = _controller.generator.family == SiggenFamily.fy6900
        ? 'square/rectangle'
        : 'square/pulse';
    return 'Range: ${_fmtNumber(limits.minDutyPercent)} … '
        '${_fmtNumber(limits.maxDutyPercent)} % '
        '(effective for $applies)';
  }

  String get _phaseLabel {
    if (_controller.generator.family == SiggenFamily.fy6900) {
      return 'Phase (CH${_controller.selectedChannel})';
    }
    return 'Phase (CH2 vs CH1)';
  }

  String get _phaseHint {
    final limits = _controller.limits;
    final description = _controller.generator.family == SiggenFamily.fy6900
        ? 'CH${_controller.selectedChannel} phase'
        : 'global device phase';
    return 'Range: ${_fmtNumber(limits.minPhaseDegrees)} … '
        '${_fmtNumber(limits.maxPhaseDegrees)}° ($description)';
  }

  String _confirmedSummary(int channel) {
    final confirmed = _controller.generator.channel(channel);
    final parts = [
      confirmed.waveform.displayName,
      formatMeasurementValue(confirmed.frequencyHz, 'Hz'),
      '${_fmtNumber(confirmed.amplitudeVpp)} Vpp',
      '${_fmtNumber(confirmed.offsetV)} V offset',
      if (dutyAppliesTo(confirmed.waveform))
        '${_fmtNumber(confirmed.dutyPercent)} % duty',
      if (channel == 2 || _controller.generator.family == SiggenFamily.fy6900)
        '${_fmtNumber(confirmed.phaseDeg)}° phase',
    ];
    return '${_controller.generator.lastRefresh == null ? 'Last known' : 'Device'}: '
        '${parts.join(' · ')}';
  }

  // -------------------------------------------------------------------------
  // Shared widgets and formatting
  // -------------------------------------------------------------------------

  Widget _buildStatusBar() {
    final message = _controller.message;
    final Color color;
    final IconData icon;
    final String text;
    if (message != null) {
      final error = _controller.messageIsError;
      color = error ? Colors.redAccent : Colors.greenAccent;
      icon = error ? Icons.error_outline : Icons.check_circle_outline;
      text = message;
    } else if (_controller.isDirty) {
      color = Colors.orangeAccent;
      icon = Icons.edit;
      text = 'Press APPLY CHANGES when finished';
    } else {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border(top: BorderSide(color: color.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _banner(String text, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11)),
    );
  }

  Widget _hint(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white38, fontSize: 10),
      ),
    );
  }

  InputDecoration _decoration(String label, {String? suffix}) {
    return InputDecoration(
      labelText: label,
      suffixText: suffix,
      suffixStyle: const TextStyle(color: Colors.white54, fontSize: 12),
      labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white24),
      ),
      disabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white12),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.cyanAccent),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    );
  }

  static String _fmtNumber(double value) {
    var text = value.toStringAsFixed(6);
    if (text.contains('.')) {
      text = text.replaceAll(RegExp(r'0+$'), '');
      if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    }
    return text;
  }
}
