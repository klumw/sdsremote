/// Device-independent driver seam for signal generators.
///
/// [SignalGeneratorService] owns connection lifecycle, caching, polling and
/// the SCPI layer. A [SiggenDriver] owns everything that is specific to one
/// device family: framing, value encoding, channel registers and readback.
library;

import 'models.dart';

/// Full device state as read back from a generator.
class SiggenStateSnapshot {
  const SiggenStateSnapshot({
    required this.outputs,
    required this.ch1,
    required this.ch2,
    required this.phaseDeg,
    required this.actionActive,
  });

  final Jds6600OutputState outputs;
  final Jds6600ChannelState ch1;
  final Jds6600ChannelState ch2;

  /// Aggregate phase (CH2). Prefer the per-channel
  /// [Jds6600ChannelState.phaseDeg] values; the JDS6600 uses one global
  /// CH2-vs-CH1 register, the FY6900 has per-channel phase.
  final double phaseDeg;

  final bool actionActive;
}

/// Hardware operations the service needs from a generator driver.
///
/// Implementations validate their own device limits and throw
/// [Jds6600RangeException] for out-of-range values so the shared SCPI layer
/// can map them to the usual `-222` errors.
abstract class SiggenDriver {
  bool get isOpen;

  Future<void> open();

  Future<void> close();

  Future<Jds6600DeviceInfo> readDeviceInfo();

  Future<SiggenStateSnapshot> readState();

  Future<void> setWaveform(int channel, Jds6600Waveform waveform);
  Future<Jds6600Waveform> readWaveform(int channel);

  Future<void> setFrequency(int channel, double hz);
  Future<double> readFrequency(int channel);

  Future<void> setAmplitude(int channel, double vpp);
  Future<double> readAmplitude(int channel);

  Future<void> setOffset(int channel, double volts);
  Future<double> readOffset(int channel);

  Future<void> setDuty(int channel, double percent);
  Future<double> readDuty(int channel);

  /// Sets the phase of [channel], exposed as `SOUR<channel>:PHAS`.
  ///
  /// The JDS6600 has one global CH2-vs-CH1 register, so both channels address
  /// the same value; the FY6900 has per-channel phase commands.
  Future<void> setPhase(int channel, double degrees);
  Future<double> readPhase(int channel);

  Future<void> setOutput(int channel, bool enabled);
  Future<bool> readOutput(int channel);

  /// Cancels any running modulation/sweep action; a no-op for devices
  /// without an action register.
  Future<void> stopActions();

  Future<void> resetSafeState();
}

typedef SiggenDriverFactory = SiggenDriver Function(String port);
