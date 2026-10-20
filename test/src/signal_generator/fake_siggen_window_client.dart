import 'dart:async';

import 'package:sdsremote/src/signal_generator/models.dart';
import 'package:sdsremote/src/signal_generator/siggen_window_client.dart';
import 'package:sdsremote/src/signal_generator/siggen_window_protocol.dart';

/// Builds a connected generator snapshot for window tests.
SigGenWindowState fakeWindowState({
  bool connected = true,
  bool mutable = true,
  bool configured = true,
  int modelMHz = 15,
  SiggenFamily family = SiggenFamily.jds6600,
  String? modelName,
  SigGenChannelSnapshot? ch1,
  SigGenChannelSnapshot? ch2,
  bool ch1Output = false,
  bool ch2Output = false,
  double phaseDeg = 0,
  double? ch1PhaseDeg,
  double? ch2PhaseDeg,
}) {
  final name =
      modelName ??
      (family == SiggenFamily.fy6900
          ? 'FY6900-${modelMHz}M'
          : (modelMHz <= 15 ? 'JDS6600-LITE' : 'JDS6600'));
  final first =
      ch1 ??
      const SigGenChannelSnapshot.defaults().copyWith(
        phaseDeg:
            ch1PhaseDeg ?? (family == SiggenFamily.fy6900 ? 0.0 : phaseDeg),
      );
  final second =
      ch2 ??
      const SigGenChannelSnapshot.defaults().copyWith(
        phaseDeg: ch2PhaseDeg ?? phaseDeg,
      );
  return SigGenWindowState(
    generator: SigGenGeneratorSnapshot(
      configured: configured,
      connected: connected,
      mutable: mutable,
      port: connected ? '/dev/ttyUSB0' : null,
      modelName: connected ? name : null,
      family: family,
      isLite: connected && family == SiggenFamily.jds6600 && modelMHz <= 15,
      modelMHz: connected ? modelMHz : null,
      ch1: first,
      ch2: second,
      ch1Output: ch1Output,
      ch2Output: ch2Output,
      phaseDeg: phaseDeg,
      lastRefresh: DateTime(2026, 10, 17, 12, 0, 0),
    ),
  );
}

/// In-memory [SigGenWindowClient] that records calls and mutates its state.
class FakeSigGenWindowClient implements SigGenWindowClient {
  FakeSigGenWindowClient([SigGenWindowState? initial])
    : state = initial ?? fakeWindowState();

  SigGenWindowState state;
  final List<String> calls = <String>[];
  final Set<String> failMethods = <String>{};
  String failureMessage = 'Command failed';
  bool disposed = false;

  final StreamController<SigGenWindowState> _states =
      StreamController<SigGenWindowState>.broadcast();

  @override
  Stream<SigGenWindowState> get states => _states.stream;

  void push(SigGenWindowState next) {
    state = next;
    _states.add(next);
  }

  SigGenCommandResult _success(String call) {
    calls.add(call);
    return SigGenCommandResult.success(state);
  }

  SigGenCommandResult? _failure(String call) {
    calls.add(call);
    if (!failMethods.remove(call)) return null;
    return SigGenCommandResult.failure(
      state,
      failureMessage,
      errorType: 'protocol',
    );
  }

  @override
  Future<SigGenCommandResult> getSnapshot() async => _success('getSnapshot');

  @override
  Future<SigGenCommandResult> refreshGenerator() async =>
      _failure('refreshGenerator') ?? _success('refreshGenerator');

  @override
  Future<SigGenCommandResult> setWaveform(
    int channel,
    Jds6600Waveform waveform,
  ) async {
    final call = 'setWaveform:$channel:${waveform.name}';
    final failure = _failure(call);
    if (failure != null) return failure;
    final current = state.generator.channel(channel);
    _replaceChannel(
      channel,
      SigGenChannelSnapshot(
        waveform: waveform,
        frequencyHz: current.frequencyHz,
        amplitudeVpp: current.amplitudeVpp,
        offsetV: current.offsetV,
        dutyPercent: current.dutyPercent,
        phaseDeg: current.phaseDeg,
      ),
    );
    return SigGenCommandResult.success(state);
  }

  @override
  Future<SigGenCommandResult> setFrequency(int channel, double hz) async {
    final call = 'setFrequency:$channel:$hz';
    final failure = _failure(call);
    if (failure != null) return failure;
    final current = state.generator.channel(channel);
    _replaceChannel(
      channel,
      SigGenChannelSnapshot(
        waveform: current.waveform,
        frequencyHz: hz,
        amplitudeVpp: current.amplitudeVpp,
        offsetV: current.offsetV,
        dutyPercent: current.dutyPercent,
        phaseDeg: current.phaseDeg,
      ),
    );
    return SigGenCommandResult.success(state);
  }

  @override
  Future<SigGenCommandResult> setAmplitude(int channel, double vpp) async {
    final call = 'setAmplitude:$channel:$vpp';
    final failure = _failure(call);
    if (failure != null) return failure;
    final current = state.generator.channel(channel);
    _replaceChannel(
      channel,
      SigGenChannelSnapshot(
        waveform: current.waveform,
        frequencyHz: current.frequencyHz,
        amplitudeVpp: vpp,
        offsetV: current.offsetV,
        dutyPercent: current.dutyPercent,
        phaseDeg: current.phaseDeg,
      ),
    );
    return SigGenCommandResult.success(state);
  }

  @override
  Future<SigGenCommandResult> setOffset(int channel, double volts) async {
    final call = 'setOffset:$channel:$volts';
    final failure = _failure(call);
    if (failure != null) return failure;
    final current = state.generator.channel(channel);
    _replaceChannel(
      channel,
      SigGenChannelSnapshot(
        waveform: current.waveform,
        frequencyHz: current.frequencyHz,
        amplitudeVpp: current.amplitudeVpp,
        offsetV: volts,
        dutyPercent: current.dutyPercent,
        phaseDeg: current.phaseDeg,
      ),
    );
    return SigGenCommandResult.success(state);
  }

  @override
  Future<SigGenCommandResult> setDuty(int channel, double percent) async {
    final call = 'setDuty:$channel:$percent';
    final failure = _failure(call);
    if (failure != null) return failure;
    final current = state.generator.channel(channel);
    _replaceChannel(
      channel,
      SigGenChannelSnapshot(
        waveform: current.waveform,
        frequencyHz: current.frequencyHz,
        amplitudeVpp: current.amplitudeVpp,
        offsetV: current.offsetV,
        dutyPercent: percent,
        phaseDeg: current.phaseDeg,
      ),
    );
    return SigGenCommandResult.success(state);
  }

  @override
  Future<SigGenCommandResult> setPhase(int channel, double degrees) async {
    final call = 'setPhase:$channel:$degrees';
    final failure = _failure(call);
    if (failure != null) return failure;
    if (state.generator.family == SiggenFamily.jds6600) {
      // One global CH2-vs-CH1 register: both channels show the same value.
      state = SigGenWindowState(
        generator: _copyGenerator(
          ch1: state.generator.ch1.copyWith(phaseDeg: degrees),
          ch2: state.generator.ch2.copyWith(phaseDeg: degrees),
          phaseDeg: degrees,
        ),
      );
    } else {
      final current = state.generator.channel(channel);
      _replaceChannel(channel, current.copyWith(phaseDeg: degrees));
      state = SigGenWindowState(generator: _copyGenerator(phaseDeg: degrees));
    }
    return SigGenCommandResult.success(state);
  }

  @override
  Future<SigGenCommandResult> setOutput(int channel, bool enabled) async {
    final call = 'setOutput:$channel:$enabled';
    final failure = _failure(call);
    if (failure != null) return failure;
    state = SigGenWindowState(
      generator: _copyGenerator(
        ch1Output: channel == 1 ? enabled : state.generator.ch1Output,
        ch2Output: channel == 2 ? enabled : state.generator.ch2Output,
      ),
    );
    return SigGenCommandResult.success(state);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _states.close();
  }

  void _replaceChannel(int channel, SigGenChannelSnapshot next) {
    state = SigGenWindowState(
      generator: _copyGenerator(
        ch1: channel == 1 ? next : null,
        ch2: channel == 2 ? next : null,
      ),
    );
  }

  SigGenGeneratorSnapshot _copyGenerator({
    SigGenChannelSnapshot? ch1,
    SigGenChannelSnapshot? ch2,
    bool? ch1Output,
    bool? ch2Output,
    double? phaseDeg,
  }) {
    final generator = state.generator;
    return SigGenGeneratorSnapshot(
      configured: generator.configured,
      connected: generator.connected,
      busy: generator.busy,
      mutable: generator.mutable,
      port: generator.port,
      modelName: generator.modelName,
      family: generator.family,
      isLite: generator.isLite,
      modelMHz: generator.modelMHz,
      ch1: ch1 ?? generator.ch1,
      ch2: ch2 ?? generator.ch2,
      ch1Output: ch1Output ?? generator.ch1Output,
      ch2Output: ch2Output ?? generator.ch2Output,
      phaseDeg: phaseDeg ?? generator.phaseDeg,
      lastError: generator.lastError,
      lastRefresh: generator.lastRefresh,
    );
  }
}
