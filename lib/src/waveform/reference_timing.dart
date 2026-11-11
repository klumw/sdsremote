/// Compares the timing metadata of a loaded reference waveform with the
/// current instrument settings.
///
/// The module is pure Dart (no Flutter): it turns both value sets into a list
/// of mismatches that the UI renders as a warning banner.
library;

import 'dart:math' as math;

import 'waveform_csv_parser.dart' show WaveformCsvMetadata;

/// Timing setting that can differ between the reference and the live data.
enum ReferenceTimingField {
  timebase('Timebase'),
  triggerDelay('Trigger delay'),
  sampleRate('Sample rate');

  const ReferenceTimingField(this.label);

  /// Human-readable name used in the warning banner.
  final String label;
}

/// One setting whose reference value differs from the current instrument.
class ReferenceTimingMismatch {
  final ReferenceTimingField field;

  /// Value stored in the reference file.
  final double referenceValue;

  /// Value currently reported by the instrument.
  final double currentValue;

  const ReferenceTimingMismatch({
    required this.field,
    required this.referenceValue,
    required this.currentValue,
  });
}

/// Relative tolerance applied to timebase and sample rate comparisons.
const double referenceTimingRelativeTolerance = 0.001;

/// Absolute tolerance floor for the trigger delay (1 µs).
///
/// Trigger delays are often zero or very small, where a purely relative
/// tolerance would flag irrelevant differences.
const double referenceTimingTriggerDelayTolerance = 1e-6;

/// Lists the timing settings in [reference] that differ from the current
/// instrument values.
///
/// Settings missing from the reference file are skipped, so CSVs without
/// timing comments never produce a mismatch.
List<ReferenceTimingMismatch> compareReferenceTiming({
  required WaveformCsvMetadata reference,
  required double currentTimebase,
  required double currentTriggerDelay,
  required double currentSampleRate,
  double relativeTolerance = referenceTimingRelativeTolerance,
  double triggerDelayTolerance = referenceTimingTriggerDelayTolerance,
}) {
  final mismatches = <ReferenceTimingMismatch>[];

  void check(
    ReferenceTimingField field,
    double? referenceValue,
    double currentValue, {
    double absoluteTolerance = 0,
  }) {
    if (referenceValue == null) return;
    final scale = math.max(referenceValue.abs(), currentValue.abs());
    final tolerance = math.max(scale * relativeTolerance, absoluteTolerance);
    if ((referenceValue - currentValue).abs() > tolerance) {
      mismatches.add(
        ReferenceTimingMismatch(
          field: field,
          referenceValue: referenceValue,
          currentValue: currentValue,
        ),
      );
    }
  }

  check(
    ReferenceTimingField.timebase,
    reference.timebaseSecondsPerDiv,
    currentTimebase,
  );
  check(
    ReferenceTimingField.triggerDelay,
    reference.triggerDelaySeconds,
    currentTriggerDelay,
    absoluteTolerance: triggerDelayTolerance,
  );
  check(
    ReferenceTimingField.sampleRate,
    reference.sampleRateHz,
    currentSampleRate,
  );

  return mismatches;
}
