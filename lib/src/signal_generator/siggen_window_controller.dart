/// State, drafts and validation for the signal-generator window.
///
/// The controller is presentation-agnostic and depends only on the
/// [SigGenWindowClient] interface, so it can be unit-tested with a fake client.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'jds6600_protocol.dart';
import 'models.dart';
import 'siggen_window_client.dart';
import 'siggen_window_protocol.dart';

/// Device selector entries of the window.
enum SigGenDeviceSelection { ch1, ch2 }

extension SigGenDeviceSelectionX on SigGenDeviceSelection {
  int get channel => this == SigGenDeviceSelection.ch2 ? 2 : 1;

  String get label => switch (this) {
    SigGenDeviceSelection.ch1 => 'CH1',
    SigGenDeviceSelection.ch2 => 'CH2',
  };
}

/// Parses a decimal number, accepting a comma as decimal separator.
double? _parseNumber(String text) {
  final normalized = text.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  final value = double.tryParse(normalized);
  return value == null || !value.isFinite ? null : value;
}

/// Formats a number without insignificant trailing zeros.
String _formatNumber(double value) {
  var text = value.toStringAsFixed(6);
  if (text.contains('.')) {
    text = text.replaceAll(RegExp(r'0+$'), '');
    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }
  }
  return text;
}

/// Chooses a readable frequency unit and mantissa.
({String text, String unit}) _formatFrequency(double hz) {
  if (hz.abs() >= 1e6) {
    return (text: _formatNumber(hz / 1e6), unit: 'MHz');
  }
  if (hz.abs() >= 1e3) {
    return (text: _formatNumber(hz / 1e3), unit: 'kHz');
  }
  return (text: _formatNumber(hz), unit: 'Hz');
}

/// Editable text values for one channel.
class SigGenChannelDraft {
  const SigGenChannelDraft({
    required this.waveform,
    required this.frequencyText,
    required this.frequencyUnit,
    required this.amplitudeText,
    required this.offsetText,
    required this.dutyText,
    required this.phaseText,
  });

  factory SigGenChannelDraft.defaults() => SigGenChannelDraft.fromSnapshot(
    const SigGenChannelSnapshot.defaults(),
    phaseDeg: 0,
  );

  factory SigGenChannelDraft.fromSnapshot(
    SigGenChannelSnapshot snapshot, {
    required double phaseDeg,
  }) {
    final frequency = _formatFrequency(snapshot.frequencyHz);
    return SigGenChannelDraft(
      waveform: snapshot.waveform,
      frequencyText: frequency.text,
      frequencyUnit: frequency.unit,
      amplitudeText: _formatNumber(snapshot.amplitudeVpp),
      offsetText: _formatNumber(snapshot.offsetV),
      dutyText: _formatNumber(snapshot.dutyPercent),
      phaseText: _formatNumber(phaseDeg),
    );
  }

  final Jds6600Waveform waveform;
  final String frequencyText;
  final String frequencyUnit;
  final String amplitudeText;
  final String offsetText;
  final String dutyText;
  final String phaseText;

  double? get frequencyHz {
    final value = _parseNumber(frequencyText);
    if (value == null) return null;
    return switch (frequencyUnit) {
      'MHz' => value * 1e6,
      'kHz' => value * 1e3,
      _ => value,
    };
  }

  double? get amplitudeVpp => _parseNumber(amplitudeText);
  double? get offsetV => _parseNumber(offsetText);
  double? get dutyPercent => _parseNumber(dutyText);
  double? get phaseDeg => _parseNumber(phaseText);

  SigGenChannelDraft copyWith({
    Jds6600Waveform? waveform,
    String? frequencyText,
    String? frequencyUnit,
    String? amplitudeText,
    String? offsetText,
    String? dutyText,
    String? phaseText,
  }) {
    return SigGenChannelDraft(
      waveform: waveform ?? this.waveform,
      frequencyText: frequencyText ?? this.frequencyText,
      frequencyUnit: frequencyUnit ?? this.frequencyUnit,
      amplitudeText: amplitudeText ?? this.amplitudeText,
      offsetText: offsetText ?? this.offsetText,
      dutyText: dutyText ?? this.dutyText,
      phaseText: phaseText ?? this.phaseText,
    );
  }
}

/// Whether a waveform has a meaningful duty cycle.
bool dutyAppliesTo(Jds6600Waveform waveform) =>
    waveform == Jds6600Waveform.square || waveform == Jds6600Waveform.pulse;

/// Panel controller shared by the child window UI and its tests.
class SignalGeneratorPanelController extends ChangeNotifier {
  SignalGeneratorPanelController({
    required this.client,
    this.refreshInterval = const Duration(seconds: 2),
  });

  final SigGenWindowClient client;

  /// How often the child pulls a fresh snapshot from the main window.
  ///
  /// State pushes cover normal operation; the pull is a safety net so a lost
  /// push (for example when the generator is switched off) cannot leave the
  /// window showing a stale CONNECTED state. `Duration.zero` disables it.
  final Duration refreshInterval;

  StreamSubscription<SigGenWindowState>? _subscription;
  Timer? _refreshTimer;
  bool _snapshotInFlight = false;
  SigGenWindowState _state = const SigGenWindowState();
  SigGenDeviceSelection _selection = SigGenDeviceSelection.ch1;
  final Map<int, SigGenChannelDraft> _drafts = {
    1: SigGenChannelDraft.defaults(),
    2: SigGenChannelDraft.defaults(),
  };
  final Set<int> _editedChannels = <int>{};
  bool _busy = false;
  bool _disposed = false;
  String? _message;
  bool _messageIsError = false;

  SigGenWindowState get state => _state;
  SigGenGeneratorSnapshot get generator => _state.generator;
  SigGenDeviceSelection get selection => _selection;
  int get selectedChannel => _selection.channel;
  bool get busy => _busy;
  String? get message => _message;
  bool get messageIsError => _messageIsError;

  SigGenChannelDraft get draft => _drafts[selectedChannel]!;
  SigGenChannelSnapshot get confirmedChannel =>
      _state.generator.channel(selectedChannel);
  bool get dutyApplicable => dutyAppliesTo(draft.waveform);

  bool get directEditingAllowed =>
      generator.connected && generator.mutable && !_busy;

  bool get isDirty => isDirtyChannel(selectedChannel);

  bool get canApply =>
      directEditingAllowed && isDirty && validationError == null;

  /// Human-readable validation error for the selected draft, if any.
  String? get validationError => _validateDraft();

  List<Jds6600Waveform> get selectableWaveforms => Jds6600Waveform.values
      .where((waveform) => waveform != Jds6600Waveform.arbitrary)
      .toList();

  /// Starts listening and fetches the initial snapshot.
  Future<void> init() async {
    _subscription ??= client.states.listen(_onPushedState);
    final result = await client.getSnapshot();
    _applyResult(result, syncDrafts: false);
    if (result.ok) _syncDraftsFromConfirmed(force: true);
    _startRefreshTimer();
    notifyListeners();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    if (refreshInterval <= Duration.zero) return;
    _refreshTimer = Timer.periodic(
      refreshInterval,
      (_) => unawaited(_pullSnapshot()),
    );
  }

  /// Pulls a fresh snapshot, so a missed push cannot leave stale UI state.
  Future<void> _pullSnapshot() async {
    if (_disposed || _busy || _snapshotInFlight) return;
    _snapshotInFlight = true;
    try {
      final result = await client.getSnapshot();
      if (_disposed || !result.ok) return;
      _state = result.state;
      _syncDraftsFromConfirmed(force: false);
      notifyListeners();
    } catch (_) {
      // Keep the last known state; the next tick retries.
    } finally {
      _snapshotInFlight = false;
    }
  }

  void selectDevice(SigGenDeviceSelection selection) {
    if (_disposed || _selection == selection) return;
    _selection = selection;
    _message = null;
    notifyListeners();
  }

  void updateWaveform(Jds6600Waveform waveform) {
    _updateDraft(draft.copyWith(waveform: waveform));
  }

  void updateFrequencyText(String text) {
    _updateDraft(draft.copyWith(frequencyText: text));
  }

  void updateFrequencyUnit(String unit) {
    _updateDraft(draft.copyWith(frequencyUnit: unit));
  }

  void updateAmplitudeText(String text) {
    _updateDraft(draft.copyWith(amplitudeText: text));
  }

  void updateOffsetText(String text) {
    _updateDraft(draft.copyWith(offsetText: text));
  }

  void updateDutyText(String text) {
    _updateDraft(draft.copyWith(dutyText: text));
  }

  void updatePhaseText(String text) {
    _updateDraft(draft.copyWith(phaseText: text));
  }

  /// Discards pending edits and restores the confirmed device values.
  void revertDraft() {
    _editedChannels.remove(selectedChannel);
    _drafts[selectedChannel] = SigGenChannelDraft.fromSnapshot(
      confirmedChannel,
      phaseDeg: generator.phaseDeg,
    );
    _message = null;
    notifyListeners();
  }

  /// Sends all changed values of the selected channel in a safe order.
  Future<void> applyChanges() async {
    if (_busy) return;
    if (!generator.connected) {
      _setMessage('Signal generator is not connected', error: true);
      return;
    }
    if (!generator.mutable) {
      _setMessage('Generator is busy (Bode sweep running)', error: true);
      return;
    }
    final validation = _validateDraft();
    if (validation != null) {
      _setMessage(validation, error: true);
      return;
    }
    final changes = _collectChanges(selectedChannel);
    if (changes.isEmpty) {
      _setMessage('No changes to apply', error: false);
      return;
    }

    _busy = true;
    _message = null;
    notifyListeners();
    var failed = false;
    try {
      for (final command in changes) {
        final result = await command();
        _state = result.state;
        if (!result.ok) {
          failed = true;
          _setMessage(result.error ?? 'Command failed', error: true);
          break;
        }
      }
    } finally {
      _busy = false;
    }

    if (!failed) {
      _syncDraftsFromConfirmed(force: true);
      _setMessage('Settings applied', error: false);
    } else {
      await _refreshConfirmedSilently();
    }
    notifyListeners();
  }

  /// Switches one output on or off. Only the explicit switch triggers this.
  Future<void> setOutput(bool enabled) async {
    if (_busy) return;
    if (!generator.connected) {
      _setMessage('Signal generator is not connected', error: true);
      return;
    }
    if (!generator.mutable) {
      _setMessage('Generator is busy (Bode sweep running)', error: true);
      return;
    }
    final channel = selectedChannel;
    _busy = true;
    notifyListeners();
    try {
      final result = await client.setOutput(channel, enabled);
      _state = result.state;
      if (!result.ok) {
        _setMessage(result.error ?? 'Could not switch the output', error: true);
        await _refreshConfirmedSilently();
      } else {
        _message = null;
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Re-reads all generator registers.
  Future<void> refreshFromDevice() async {
    if (_busy || generator.busy) return;
    if (!generator.connected) {
      _setMessage('Signal generator is not connected', error: true);
      return;
    }
    _busy = true;
    notifyListeners();
    try {
      final result = await client.refreshGenerator();
      _applyResult(result, syncDrafts: !result.ok ? false : true);
      if (result.ok) {
        _syncDraftsFromConfirmed(force: true);
        _setMessage('Device state refreshed', error: false);
      } else {
        _setMessage(result.error ?? 'Refresh failed', error: true);
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// True when the draft differs from the confirmed device state.
  bool isDirtyChannel(int channel) {
    final draft = _drafts[channel]!;
    final confirmed = _state.generator.channel(channel);
    if (draft.waveform != confirmed.waveform) return true;
    if (_differs(draft.frequencyHz, confirmed.frequencyHz)) return true;
    if (_differs(draft.amplitudeVpp, confirmed.amplitudeVpp)) return true;
    if (_differs(draft.offsetV, confirmed.offsetV)) return true;
    if (_differs(draft.dutyPercent, confirmed.dutyPercent)) return true;
    if (_differs(draft.phaseDeg, _state.generator.phaseDeg)) return true;
    return false;
  }

  List<Future<SigGenCommandResult> Function()> _collectChanges(int channel) {
    final draft = _drafts[channel]!;
    final confirmed = _state.generator.channel(channel);
    final commands = <Future<SigGenCommandResult> Function()>[];

    // Waveform first: the frequency limit depends on it.
    if (draft.waveform != confirmed.waveform) {
      commands.add(() => client.setWaveform(channel, draft.waveform));
    }
    final frequency = draft.frequencyHz;
    if (frequency != null && _differs(frequency, confirmed.frequencyHz)) {
      commands.add(() => client.setFrequency(channel, frequency));
    }
    final amplitude = draft.amplitudeVpp;
    if (amplitude != null && _differs(amplitude, confirmed.amplitudeVpp)) {
      commands.add(() => client.setAmplitude(channel, amplitude));
    }
    final offset = draft.offsetV;
    if (offset != null && _differs(offset, confirmed.offsetV)) {
      commands.add(() => client.setOffset(channel, offset));
    }
    final duty = draft.dutyPercent;
    if (duty != null && _differs(duty, confirmed.dutyPercent)) {
      commands.add(() => client.setDuty(channel, duty));
    }
    final phase = draft.phaseDeg;
    if (phase != null && _differs(phase, _state.generator.phaseDeg)) {
      commands.add(() => client.setPhase(phase));
    }
    return commands;
  }

  String? _validateDraft() {
    final draft = this.draft;
    if (draft.frequencyHz == null) return 'Frequency: enter a valid number';
    if (draft.amplitudeVpp == null) return 'Amplitude: enter a valid number';
    if (draft.offsetV == null) return 'Offset: enter a valid number';
    if (draft.dutyPercent == null) {
      return 'Duty cycle: enter a valid number';
    }
    if (draft.phaseDeg == null) {
      return 'Phase: enter a valid number';
    }

    final info = Jds6600DeviceInfo(
      modelMHz: _state.generator.modelMHz ?? 15,
      serialNumber: 0,
    );
    try {
      Jds6600Protocol.validateFrequency(
        info,
        draft.waveform,
        draft.frequencyHz!,
      );
      Jds6600Protocol.validateAmplitude(
        info,
        draft.frequencyHz!,
        draft.amplitudeVpp!,
      );
      Jds6600Protocol.validateOffset(draft.offsetV!);
      Jds6600Protocol.validateDuty(draft.dutyPercent!);
      Jds6600Protocol.validatePhase(draft.phaseDeg!);
    } on Jds6600RangeException catch (error) {
      return error.message;
    }
    return null;
  }

  Future<void> _refreshConfirmedSilently() async {
    try {
      final result = await client.refreshGenerator();
      _state = result.state;
    } catch (_) {
      // Keep the last known state.
    }
  }

  void _onPushedState(SigGenWindowState state) {
    if (_disposed) return;
    _state = state;
    _syncDraftsFromConfirmed(force: false);
    notifyListeners();
  }

  void _syncDraftsFromConfirmed({required bool force}) {
    for (final channel in const [1, 2]) {
      if (force || !_editedChannels.contains(channel)) {
        _drafts[channel] = SigGenChannelDraft.fromSnapshot(
          _state.generator.channel(channel),
          phaseDeg: _state.generator.phaseDeg,
        );
        _editedChannels.remove(channel);
      }
    }
  }

  void _applyResult(SigGenCommandResult result, {required bool syncDrafts}) {
    _state = result.state;
    if (syncDrafts) _syncDraftsFromConfirmed(force: false);
    if (!result.ok) {
      _message = result.error ?? 'Command failed';
      _messageIsError = true;
    }
  }

  void _updateDraft(SigGenChannelDraft next) {
    _drafts[selectedChannel] = next;
    _editedChannels.add(selectedChannel);
    _message = null;
    notifyListeners();
  }

  void _setMessage(String message, {required bool error}) {
    _message = message;
    _messageIsError = error;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  static bool _differs(double? a, double b) {
    if (a == null) return true;
    final tolerance = 1e-6 * (b.abs() < 1 ? 1 : b.abs());
    return (a - b).abs() > tolerance;
  }
}
