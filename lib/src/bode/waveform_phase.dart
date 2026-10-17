/// Phase estimation from two acquired waveforms.
///
/// Uses the full-resolution raw samples (not the display path, which skips
/// samples and downsamples). The sign convention matches the Bode sweep:
/// `phase = -360 * f * (tVout - tVin)`, so a lagging output gives a negative
/// phase and a leading output a positive one.
library;

import '../waveform/waveform_converter.dart';
import '../waveform/waveform_models.dart';
import 'bode_math.dart';

/// Estimates the phase between Vin and Vout from raw JDS/Siglent waveform
/// data, or returns null when the record does not contain enough information.
double? estimatePhaseFromRaw({
  required WaveformRawData raw,
  required double frequencyHz,
  required int vinChannel,
  required int voutChannel,
}) {
  final vin = _channelPoints(raw, vinChannel);
  final vout = _channelPoints(raw, voutChannel);
  if (vin.length < 3 || vout.length < 3) return null;

  final times = vin.map((point) => point.$1).toList(growable: false);
  final vinVolts = vin.map((point) => point.$2).toList(growable: false);
  final voutVolts = vout.map((point) => point.$2).toList(growable: false);
  return estimatePhaseFromSamples(
    frequencyHz: frequencyHz,
    times: times,
    vin: vinVolts,
    vout: voutVolts,
  );
}

/// Pure phase estimator for tests and the raw-data adapter.
double? estimatePhaseFromSamples({
  required double frequencyHz,
  required List<double> times,
  required List<double> vin,
  required List<double> vout,
}) {
  if (!frequencyHz.isFinite || frequencyHz <= 0) return null;
  if (times.length != vin.length ||
      times.length != vout.length ||
      times.length < 3) {
    return null;
  }

  final span = times.last - times.first;
  if (!span.isFinite || span < 1.0 / frequencyHz) return null;

  final vinLevel = _midLevel(vin);
  final voutLevel = _midLevel(vout);
  final vinCrossings = _risingCrossings(times, vin, vinLevel);
  final voutCrossings = _risingCrossings(times, vout, voutLevel);
  if (vinCrossings.isEmpty || voutCrossings.isEmpty) return null;

  // Pair the closest Vin/Vout rising crossings within half a period. This
  // also handles a leading output whose matching crossing lies before the
  // first Vin crossing in the record.
  final period = 1.0 / frequencyHz;
  double? bestVin;
  double? bestVout;
  var bestDistance = double.infinity;
  for (final vinCrossing in vinCrossings) {
    for (final voutCrossing in voutCrossings) {
      final distance = (voutCrossing - vinCrossing).abs();
      if (distance <= period * 0.5 && distance < bestDistance) {
        bestDistance = distance;
        bestVin = vinCrossing;
        bestVout = voutCrossing;
      }
    }
  }
  if (bestVin == null || bestVout == null) return null;

  return phaseFromDelay(frequencyHz, bestVout - bestVin);
}

List<(double, double)> _channelPoints(WaveformRawData raw, int channel) {
  final bytes = channel == 1 ? raw.ch1Raw : raw.ch2Raw;
  final vdiv = channel == 1 ? raw.vdivCh1 : raw.vdivCh2;
  final voffset = channel == 1 ? raw.voffsetCh1 : raw.voffsetCh2;
  if (bytes == null || vdiv == null || voffset == null || bytes.length < 3) {
    return const [];
  }

  final voltages = WaveformConverter.convertVoltages(bytes, vdiv, voffset);
  final times = WaveformConverter.computeTimeAxis(
    bytes.length,
    raw.trdl,
    raw.timebase,
    raw.sampleRate,
    triggerPosition: raw.triggerPosition,
  );
  return [
    for (var index = 0; index < bytes.length; index++)
      (times[index], voltages[index]),
  ];
}

double _midLevel(List<double> values) {
  var min = double.infinity;
  var max = double.negativeInfinity;
  for (final value in values) {
    if (value < min) min = value;
    if (value > max) max = value;
  }
  return (min + max) / 2.0;
}

List<double> _risingCrossings(
  List<double> times,
  List<double> values,
  double level,
) {
  final crossings = <double>[];
  for (var index = 1; index < values.length; index++) {
    final previous = values[index - 1];
    final current = values[index];
    if (previous <= level && current > level && current != previous) {
      final fraction = (level - previous) / (current - previous);
      crossings.add(
        times[index - 1] + fraction * (times[index] - times[index - 1]),
      );
    }
  }
  return crossings;
}
