/// Narrow oscilloscope interface used by the Bode sweep.
///
/// The implementation owns all SCPI details; the service only sees measured
/// RMS voltages and an optional phase.
library;

import 'bode_models.dart';

class BodeReading {
  const BodeReading({
    this.vinRms,
    this.voutRms,
    this.vinVpp,
    this.voutVpp,
    this.phaseDeg,
    this.delaySeconds,
    this.phaseSource = BodePhaseSource.none,
    this.outOfRange = false,
    this.error,
  });

  final double? vinRms;
  final double? voutRms;

  /// Peak-to-peak voltages; only populated when the read requested them.
  final double? vinVpp;
  final double? voutVpp;

  final double? phaseDeg;
  final double? delaySeconds;
  final BodePhaseSource phaseSource;

  /// True when a PAVA response was `***` (signal outside the measurement
  /// range); the service may retry once after an auto-set.
  final bool outOfRange;
  final String? error;
}

class BodeScopeException implements Exception {
  const BodeScopeException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message (cause: $cause)';
}

abstract class BodeScope {
  /// Called once before the sweep. May perform an auto-setup and must leave
  /// both selected channels enabled/visible.
  Future<void> prepare({
    required int vinChannel,
    required int voutChannel,
    required bool measurePhase,
  });

  /// Measures one point. [frequencyHz] is used by the waveform fallback.
  ///
  /// Set [measureVpp] to also read the peak-to-peak voltages, which the
  /// amplitude sweep records alongside the RMS values. An amplitude sweep
  /// passes the generator setpoint as [expectedVinVpp] so the scope input is
  /// scaled before the reading instead of clipping at higher amplitudes.
  Future<BodeReading> read({
    required int vinChannel,
    required int voutChannel,
    required double frequencyHz,
    required bool measurePhase,
    bool measureVpp = false,
    double? expectedVinVpp,
  });

  /// Re-runs the scope auto-setup (used after an out-of-range reading).
  Future<void> autoSet();

  /// Restores any scope state changed by [prepare].
  Future<void> restore();
}
