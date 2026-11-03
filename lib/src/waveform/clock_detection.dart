/// Clock-signal detection and timebase suggestion.
///
/// A waveform is considered a clock when it is periodic, has a duty cycle of
/// about 50 % and shows only small period jitter. The module proposes the
/// nearest standard 1-2-5 timebase that puts roughly four periods across the
/// 14-division graticule. Pure Dart, no I/O.
library;

import 'waveform_measurements.dart';

/// A suggested timebase for a detected clock signal.
class ClockSuggestion {
  final String channel;
  final double frequencyHz;
  final double dutyPercent;
  final double periodStdDevSeconds;

  /// Nearest standard timebase in seconds per division.
  final double suggestedTimebaseSeconds;

  /// Periods that fit across the 14 divisions with the suggested timebase.
  final double periodsOnScreen;

  const ClockSuggestion({
    required this.channel,
    required this.frequencyHz,
    required this.dutyPercent,
    required this.periodStdDevSeconds,
    required this.suggestedTimebaseSeconds,
    required this.periodsOnScreen,
  });
}

/// Target number of visible periods for the time-domain suggestion.
const int timeDomainTargetPeriodsOnScreen = 4;

/// Minimum number of visible periods for an effective FFT.
///
/// The spectrum transforms the largest power of two that fits the transferred
/// record, which is roughly half of the visible acquisition. Twenty visible
/// periods therefore leave about ten periods in the FFT window.
const int minFftPeriodsOnScreen = 20;

/// Target number of visible periods when optimizing the timebase for FFT.
const int fftTargetPeriodsOnScreen = 50;

/// Whether [periodsOnScreen] is too low for an effective FFT.
bool needsFftOptimization(double periodsOnScreen) =>
    periodsOnScreen < minFftPeriodsOnScreen;

/// Standard Siglent timebase steps from 1 ns/div to 50 s/div.
final List<double> _timebaseSteps = [
  for (var exponent = -9; exponent <= 1; exponent++)
    for (final multiplier in const [1.0, 2.0, 5.0])
      multiplier * _pow10(exponent),
];

double _pow10(int exponent) {
  var value = 1.0;
  if (exponent >= 0) {
    for (var i = 0; i < exponent; i++) {
      value *= 10;
    }
  } else {
    for (var i = 0; i < -exponent; i++) {
      value /= 10;
    }
  }
  return value;
}

/// Detects a clock on [measurement] and returns a timebase suggestion.
///
/// Returns `null` when the signal is not periodic, the duty cycle deviates by
/// more than [maxDutyDeviationPercent] from 50 %, or the relative period
/// jitter exceeds [maxRelativeJitter].
ClockSuggestion? detectClock(
  WaveformMeasurements measurement, {
  double maxDutyDeviationPercent = 5,
  double maxRelativeJitter = 0.02,
  int targetPeriods = timeDomainTargetPeriodsOnScreen,
}) {
  final frequency = measurement.frequencyHz;
  final duty = measurement.dutyPercent;
  final period = measurement.periodSeconds;
  final jitter = measurement.periodStdDevSeconds;
  if (frequency == null || !frequency.isFinite || frequency <= 0) return null;
  if (duty == null || !duty.isFinite) return null;
  if ((duty - 50).abs() > maxDutyDeviationPercent) return null;
  if (period == null || !period.isFinite || period <= 0) return null;
  if (jitter != null &&
      jitter.isFinite &&
      jitter / period > maxRelativeJitter) {
    return null;
  }

  final ideal = period * targetPeriods / 14;
  final best = nearestTimebase(ideal);
  final periodsOnScreen = 14 * best / period;
  return ClockSuggestion(
    channel: measurement.channel,
    frequencyHz: frequency,
    dutyPercent: duty,
    periodStdDevSeconds: jitter ?? 0,
    suggestedTimebaseSeconds: best,
    periodsOnScreen: periodsOnScreen,
  );
}

/// Nearest standard 1-2-5 timebase step (in seconds per division).
double nearestTimebase(double seconds) {
  if (!seconds.isFinite || seconds <= 0) return _timebaseSteps.first;
  var best = _timebaseSteps.first;
  var bestRatio = double.infinity;
  for (final step in _timebaseSteps) {
    final ratio = (step / seconds) >= 1 ? step / seconds : seconds / step;
    if (ratio < bestRatio) {
      bestRatio = ratio;
      best = step;
    }
  }
  return best;
}

/// Timebase in seconds per division that shows about [targetPeriods] periods
/// of a signal with [periodSeconds].
double timebaseForPeriods(
  double periodSeconds, {
  int targetPeriods = fftTargetPeriodsOnScreen,
}) {
  return nearestTimebase(periodSeconds * targetPeriods / 14);
}

/// Whether [measurement] contains at least [minFftPeriodsOnScreen] complete
/// periods for an effective FFT.
///
/// A signal without a measurable frequency is treated as usable because
/// non-periodic signals can still be analysed with an FFT.
bool hasEnoughFftPeriods(WaveformMeasurements measurement) {
  if (measurement.frequencyHz == null) return true;
  return measurement.periodCount >= minFftPeriodsOnScreen;
}

/// Formats a timebase with an SI prefix for banner display.
String formatTimebase(double seconds) {
  if (seconds >= 1) return '${_trim(seconds)} s/div';
  if (seconds >= 1e-3) return '${_trim(seconds * 1e3)} ms/div';
  if (seconds >= 1e-6) return '${_trim(seconds * 1e6)} µs/div';
  return '${_trim(seconds * 1e9)} ns/div';
}

String _trim(double value) {
  var text = value.toStringAsFixed(3);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}
