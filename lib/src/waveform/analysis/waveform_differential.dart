/// Differential sign statistics for waveform classification.
///
/// Implements the feature representation proposed by Xiao, Chen and Lv,
/// "A Lightweight Waveform Recognition Algorithm Based on Differential
/// Features and Its FPGA Implementation", Electronics 2026, 15(17), 4044:
/// the signs of the first and second discrete differences are counted, and
/// the number of sign reversals in the second difference is used to separate
/// smooth waveforms under noise.
///
/// The sign threshold is not an absolute voltage. It is derived from a robust
/// MAD estimate of the second-difference noise of the capture, so the same
/// representation works at every vertical scale. A contiguous window of up to
/// eight periods is block-averaged to [samplesPerPeriod] points per period
/// before the differences are formed; this suppresses broadband noise, which
/// matters because the second difference amplifies noise by sqrt(6).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'waveform_analysis_models.dart';

/// Default number of points per period in the differential window.
///
/// The paper uses 128 points per period with a 12-bit ADC. Oscilloscope
/// captures are 8-bit, and block averaging over the eight-period window only
/// recovers part of the resolution: at 64 points per period the second
/// difference of a 1 kHz sine is comparable to the residual quantisation
/// noise, which makes sine and triangle indistinguishable. At 16 points per
/// period the sine curvature is an order of magnitude above the noise while a
/// triangle still consists of linear segments between two vertices.
const int defaultDifferentialSamplesPerPeriod = 16;

/// Maximum number of periods in the differential window.
const int defaultDifferentialPeriods = 8;

/// Extracts the differential sign statistics of [values].
///
/// Returns `null` when the record is too short or flat to carry shape
/// information.
DifferentialFeatures? extractDifferentialFeatures(
  Float64List values, {
  required double sampleIntervalSeconds,
  double? fundamentalHz,
  int samplesPerPeriod = defaultDifferentialSamplesPerPeriod,
  int maxPeriods = defaultDifferentialPeriods,
}) {
  final n = values.length;
  if (n < 16 || !sampleIntervalSeconds.isFinite || sampleIntervalSeconds <= 0) {
    return null;
  }
  final amplitude = _peakToPeak(values);
  if (!(amplitude > 0)) return null;

  final inputSamplesPerPeriod = fundamentalHz != null && fundamentalHz > 0
      ? 1 / (fundamentalHz * sampleIntervalSeconds)
      : null;

  final int windowLength;
  final int targetLength;
  final int periodsUsed;
  if (inputSamplesPerPeriod != null && inputSamplesPerPeriod >= 4) {
    final availablePeriods = (n - 1) / inputSamplesPerPeriod;
    periodsUsed = math.min(
      math.max(1, maxPeriods),
      math.max(1, availablePeriods.floor()),
    );
    targetLength = math.max(
      16,
      math.min(math.max(16, samplesPerPeriod), n) * periodsUsed,
    );
    windowLength = math.max(
      16,
      math.min(n, (periodsUsed * inputSamplesPerPeriod).round()),
    );
  } else {
    periodsUsed = 0;
    windowLength = n;
    targetLength = math.min(1024, math.max(64, n ~/ 4));
  }
  final target = math.max(8, math.min(targetLength, windowLength));

  final resampled = _blockAverage(values, windowLength, target);
  if (resampled.length < 16) return null;

  final first = Float64List(resampled.length - 1);
  for (var i = 0; i < first.length; i++) {
    first[i] = resampled[i + 1] - resampled[i];
  }
  final second = Float64List(resampled.length - 2);
  for (var i = 1; i < resampled.length - 1; i++) {
    second[i - 1] = resampled[i + 1] - 2 * resampled[i] + resampled[i - 1];
  }

  // Robust noise estimate on the un-averaged analysis grid. For white noise
  // the second difference has variance 6 sigma^2 (paper, Eq. 20); block
  // averaging with b samples per output reduces its standard deviation by
  // sqrt(b).
  final rawSecond = Float64List(n - 2);
  for (var i = 1; i < n - 1; i++) {
    rawSecond[i - 1] = values[i + 1] - 2 * values[i] + values[i - 1];
  }
  final blockSize = windowLength / target;
  final rawSigma = 1.4826 * _medianAbsoluteDeviation(rawSecond);
  var secondSigma = rawSigma / math.sqrt(math.max(1.0, blockSize));
  secondSigma = math.max(secondSigma, amplitude * 1e-6);

  // A capture with long exactly flat segments (square wave, clipped sine) has
  // a MAD of zero on those segments, which would set the threshold far below
  // the quantisation residual of the flat top. The scope is an 8-bit device
  // and the display always spans a few divisions, so half a percent of Vpp is
  // a safe quantisation floor at every vertical scale.
  final minimumEpsilon = amplitude * 0.005;
  final firstEpsilon = math.max(secondSigma / math.sqrt(3), minimumEpsilon);
  final secondEpsilon = math.max(0.75 * secondSigma, minimumEpsilon);

  var firstPositive = 0;
  var firstZero = 0;
  var firstNegative = 0;
  for (final value in first) {
    if (value > firstEpsilon) {
      firstPositive++;
    } else if (value < -firstEpsilon) {
      firstNegative++;
    } else {
      firstZero++;
    }
  }

  final secondSigns = Int8List(second.length);
  var secondPositive = 0;
  var secondZero = 0;
  var secondNegative = 0;
  for (var i = 0; i < second.length; i++) {
    final value = second[i];
    final sign = value > secondEpsilon
        ? 1
        : value < -secondEpsilon
        ? -1
        : 0;
    secondSigns[i] = sign;
    if (sign > 0) {
      secondPositive++;
    } else if (sign < 0) {
      secondNegative++;
    } else {
      secondZero++;
    }
  }
  var reversals = 0;
  for (var i = 1; i < secondSigns.length; i++) {
    final previous = secondSigns[i - 1];
    final current = secondSigns[i];
    if (previous != 0 && current != 0 && previous != current) {
      reversals++;
    }
  }

  final firstTotal = first.length;
  final secondTotal = second.length;
  return DifferentialFeatures(
    firstPositiveFraction: firstPositive / firstTotal,
    firstZeroFraction: firstZero / firstTotal,
    firstNegativeFraction: firstNegative / firstTotal,
    secondPositiveFraction: secondPositive / secondTotal,
    secondZeroFraction: secondZero / secondTotal,
    secondNegativeFraction: secondNegative / secondTotal,
    secondSignReversalFraction: secondSigns.length > 1
        ? reversals / (secondSigns.length - 1)
        : 0,
    sampleCount: resampled.length,
    periodsUsed: periodsUsed,
    pointsPerPeriod: periodsUsed > 0 ? target / periodsUsed : 0,
    firstThresholdVolts: firstEpsilon,
    secondThresholdVolts: secondEpsilon,
  );
}

/// Averages the first [length] samples into [target] blocks.
Float64List _blockAverage(Float64List values, int length, int target) {
  final result = Float64List(target);
  for (var j = 0; j < target; j++) {
    var start = (j * length / target).floor();
    var end = ((j + 1) * length / target).floor();
    if (end <= start) end = start + 1;
    if (start >= length) start = length - 1;
    if (end > length) end = length;
    var sum = 0.0;
    for (var i = start; i < end; i++) {
      sum += values[i];
    }
    result[j] = sum / (end - start);
  }
  return result;
}

double _medianAbsoluteDeviation(Float64List values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final median = _medianOfSorted(sorted);
  final deviations = Float64List(sorted.length);
  for (var i = 0; i < sorted.length; i++) {
    deviations[i] = (sorted[i] - median).abs();
  }
  final sortedDeviations = [...deviations]..sort();
  return _medianOfSorted(sortedDeviations);
}

double _medianOfSorted(List<double> sorted) {
  if (sorted.isEmpty) return 0;
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

double _peakToPeak(Float64List values) {
  if (values.isEmpty) return 0;
  var minimum = values.first;
  var maximum = values.first;
  for (final value in values) {
    if (value < minimum) minimum = value;
    if (value > maximum) maximum = value;
  }
  return maximum - minimum;
}
