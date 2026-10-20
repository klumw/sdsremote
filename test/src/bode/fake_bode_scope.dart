import 'package:sdsremote/src/bode/bode_models.dart';
import 'package:sdsremote/src/bode/bode_scope.dart';

/// Scriptable [BodeScope] for service tests.
class FakeBodeScope implements BodeScope {
  int prepareCalls = 0;
  int readCalls = 0;
  int autoSetCalls = 0;
  int restoreCalls = 0;
  final List<double> frequencies = <double>[];

  double vinRms = 1.0;

  /// Optional per-read Vin values; consumed before [vinRms].
  final List<double> vinSequence = <double>[];
  double voutRms = 0.5;
  double? phaseDeg = -45;
  bool outOfRangeOnce = false;
  Duration readDelay = Duration.zero;

  @override
  Future<void> prepare({
    required int vinChannel,
    required int voutChannel,
    required bool measurePhase,
  }) async {
    prepareCalls++;
  }

  @override
  Future<BodeReading> read({
    required int vinChannel,
    required int voutChannel,
    required double frequencyHz,
    required bool measurePhase,
  }) async {
    readCalls++;
    frequencies.add(frequencyHz);
    if (readDelay > Duration.zero) {
      await Future<void>.delayed(readDelay);
    }
    if (outOfRangeOnce) {
      outOfRangeOnce = false;
      return const BodeReading(outOfRange: true, error: 'Signal outside range');
    }
    final phase = measurePhase ? phaseDeg : null;
    final vin = vinSequence.isNotEmpty ? vinSequence.removeAt(0) : vinRms;
    return BodeReading(
      vinRms: vin,
      voutRms: voutRms,
      phaseDeg: phase,
      delaySeconds: phase == null ? null : -phase / (360.0 * frequencyHz),
      phaseSource: phase == null ? BodePhaseSource.none : BodePhaseSource.mead,
    );
  }

  @override
  Future<void> autoSet() async {
    autoSetCalls++;
  }

  @override
  Future<void> restore() async {
    restoreCalls++;
  }
}
