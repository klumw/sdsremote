/// Main-window side of the signal-generator window bridge.
///
/// The host owns no hardware itself: all writes go through the existing
/// [SignalGeneratorService]. It is free of Flutter plugin imports so the
/// command dispatch can be unit-tested.
library;

import 'dart:async';

import 'models.dart';
import 'siggen_window_protocol.dart';
import 'signal_generator_service.dart';

/// Pushes snapshots to the child window (implemented with
/// `WindowController.invokeMethod` in the Flutter layer).
abstract class SigGenWindowEventSink {
  Future<void> pushState(SigGenWindowState state);
}

/// Dispatches child-window commands to the driver service.
class SigGenWindowHost {
  SigGenWindowHost({
    required this.service,
    required this.sink,
    bool Function()? canMutate,
  }) : _canMutate = canMutate ?? (() => true) {
    service.addListener(_onStateChanged);
  }

  final SignalGeneratorService service;
  final SigGenWindowEventSink sink;
  final bool Function() _canMutate;

  bool _active = false;
  bool _disposed = false;
  bool _pushScheduled = false;

  /// True while the child window is considered open.
  bool get isActive => _active;

  /// Enables snapshot pushes after the child window has opened.
  void activate() {
    if (_disposed) return;
    _active = true;
    _schedulePush();
  }

  /// Stops snapshot pushes when the child window closes.
  void deactivate() {
    _active = false;
  }

  /// Current complete state for the child window.
  SigGenWindowState buildSnapshot() {
    final info = service.deviceInfo;
    final outputs = service.outputs;
    return SigGenWindowState(
      generator: SigGenGeneratorSnapshot(
        configured: true,
        connected: service.isConnected,
        busy: service.busy,
        mutable: _canMutate() && service.isConnected,
        port: service.port,
        modelName: info?.modelName,
        family: info?.family ?? SiggenFamily.jds6600,
        isLite: info?.isLite,
        modelMHz: info?.modelMHz,
        ch1: SigGenChannelSnapshot.fromChannelState(service.ch1),
        ch2: SigGenChannelSnapshot.fromChannelState(service.ch2),
        ch1Output: outputs.ch1,
        ch2Output: outputs.ch2,
        phaseDeg: service.phaseDeg,
        lastError: service.lastError,
        lastRefresh: service.lastRefresh,
      ),
    );
  }

  /// Handles one bridge command and returns the resulting state.
  Future<SigGenCommandResult> handleCommand(
    String method,
    Map<String, dynamic> args,
  ) async {
    if (method == SigGenWindowMethods.getSnapshot) {
      return SigGenCommandResult.success(buildSnapshot());
    }

    if (_isMutation(method)) {
      if (!_canMutate()) {
        return SigGenCommandResult.failure(
          buildSnapshot(),
          'Generator is busy (Bode sweep running)',
          errorType: 'busy',
        );
      }
      if (!service.isConnected) {
        return SigGenCommandResult.failure(
          buildSnapshot(),
          'Signal generator is not connected',
          errorType: 'disconnected',
        );
      }
    }

    try {
      switch (method) {
        case SigGenWindowMethods.refreshGenerator:
          await service.refreshAll();
        case SigGenWindowMethods.setWaveform:
          await service.setWaveform(
            sigGenChannelFromArgs(args['channel']),
            sigGenWaveformFromArgs(args['waveform']),
          );
        case SigGenWindowMethods.setFrequency:
          await service.setFrequency(
            sigGenChannelFromArgs(args['channel']),
            _asDouble(args['value']),
          );
        case SigGenWindowMethods.setAmplitude:
          await service.setAmplitude(
            sigGenChannelFromArgs(args['channel']),
            _asDouble(args['value']),
          );
        case SigGenWindowMethods.setOffset:
          await service.setOffset(
            sigGenChannelFromArgs(args['channel']),
            _asDouble(args['value']),
          );
        case SigGenWindowMethods.setDuty:
          await service.setDuty(
            sigGenChannelFromArgs(args['channel']),
            _asDouble(args['value']),
          );
        case SigGenWindowMethods.setPhase:
          await service.setPhase(
            sigGenChannelFromArgs(args['channel']),
            _asDouble(args['value']),
          );
        case SigGenWindowMethods.setOutput:
          await service.setOutput(
            sigGenChannelFromArgs(args['channel']),
            args['enabled'] == true,
          );
        default:
          return SigGenCommandResult.failure(
            buildSnapshot(),
            'Unknown command: $method',
            errorType: 'protocol',
          );
      }
      return SigGenCommandResult.success(buildSnapshot());
    } catch (error) {
      return SigGenCommandResult.failure(
        buildSnapshot(),
        error.toString(),
        errorType: sigGenErrorType(error),
      );
    }
  }

  bool _isMutation(String method) {
    switch (method) {
      case SigGenWindowMethods.refreshGenerator:
      case SigGenWindowMethods.setWaveform:
      case SigGenWindowMethods.setFrequency:
      case SigGenWindowMethods.setAmplitude:
      case SigGenWindowMethods.setOffset:
      case SigGenWindowMethods.setDuty:
      case SigGenWindowMethods.setPhase:
      case SigGenWindowMethods.setOutput:
        return true;
      default:
        return false;
    }
  }

  void _onStateChanged() {
    if (_active) _schedulePush();
  }

  void _schedulePush() {
    if (!_active || _disposed || _pushScheduled) return;
    _pushScheduled = true;
    // Coalesce the notifications produced by one poll tick.
    scheduleMicrotask(() {
      _pushScheduled = false;
      if (!_active || _disposed) return;
      unawaited(_push());
    });
  }

  Future<void> _push() async {
    try {
      await sink.pushState(buildSnapshot());
    } catch (_) {
      // The child window may already be gone; the launcher handles closing.
    }
  }

  /// Removes listeners. The caller owns [service].
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _active = false;
    service.removeListener(_onStateChanged);
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.replaceAll(',', '.'));
      if (parsed != null && parsed.isFinite) return parsed;
    }
    throw ArgumentError.value(value, 'value', 'Expected a finite number');
  }
}

/// Convenience for tests and callers that only need the error classification.
String describeSigGenError(Object error) => sigGenErrorType(error);
