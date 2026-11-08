/// Deterministic extraction of a stated -3 dB corner frequency.
///
/// The PlannerAgent model is supposed to fill `knownParameters`, but the
/// small/fast models sometimes omit a clearly stated cutoff. This pass reads
/// the original request text and fills `expectedCornerFrequencyHz` with the
/// lower bound of a stated range, so the sweep range is derived instead of
/// falling back to 20 Hz-20 kHz.
library;

import 'dart:math' as math;

import 'models/measurement_request.dart';
import 'planner_config.dart';

/// Wording that marks a request as a cutoff/corner-frequency measurement.
final RegExp _cornerHint = RegExp(
  r'(-?\s*3\s*db|-?\s*db\s*(?:punkt|point)|eckfrequenz|grenzfrequenz|'
  r'cutoff|corner|tiefpass|low[- ]?pass)',
  caseSensitive: false,
);

/// "1 kHz to 2 kHz" / "1 kHz - 2 kHz".
final RegExp _rangeWithBothUnits = RegExp(
  r'(\d+(?:[.,]\d+)?)\s*(hz|khz|mhz)\s*(?:-|–|—|bis|to|and|und)\s*'
  r'(\d+(?:[.,]\d+)?)\s*(hz|khz|mhz)',
  caseSensitive: false,
);

/// "1-2 kHz" / "1 bis 2 kHz" (shared unit).
final RegExp _rangeWithSharedUnit = RegExp(
  r'(\d+(?:[.,]\d+)?)\s*(?:-|–|—|bis|to|and|und)\s*'
  r'(\d+(?:[.,]\d+)?)\s*(hz|khz|mhz)',
  caseSensitive: false,
);

/// "bei 1 kHz" / "at 1 kHz" / "around 1 kHz".
final RegExp _singleWithContext = RegExp(
  r'(?:bei|at|around|etwa|ca\.?|approximately|near)\s+'
  r'(\d+(?:[.,]\d+)?)\s*(hz|khz|mhz)',
  caseSensitive: false,
);

/// Returns [request] with a stated sweep range or corner filled when missing.
///
/// A stated frequency range ("1000-2000 Hz", "1 kHz bis 2 kHz") is used
/// literally as the sweep start and stop. A single frequency with context
/// ("at about 1 kHz") becomes the expected corner, from which the planner
/// derives a decade-wide sweep. Explicit start/stop values always win.
MeasurementRequest enrichStatedCornerFrequency(
  MeasurementRequest request,
  String originalText,
) {
  if (!request.measurements.contains('audio.frequency_response')) {
    return request;
  }

  final known = Map<String, Object?>.of(request.knownParameters);
  var changed = false;

  // The gain recipe uses outputChannel; the frequency-response recipe uses
  // channel. Map the former when the model picked the wrong recipe keys.
  if (!known.containsKey(PlannerKeys.channel) &&
      known.containsKey('outputChannel')) {
    known[PlannerKeys.channel] = known['outputChannel'];
    changed = true;
  }

  if (known.containsKey(PlannerKeys.startFrequencyHz) ||
      known.containsKey(PlannerKeys.stopFrequencyHz) ||
      known.containsKey(PlannerKeys.expectedCornerFrequencyHz)) {
    return changed ? request.merged(knownParameters: known) : request;
  }

  final text = '$originalText ${request.goal}';
  final range = _parseRange(text);
  if (range != null) {
    known[PlannerKeys.startFrequencyHz] = range.start;
    known[PlannerKeys.stopFrequencyHz] = range.stop;
    return request.merged(knownParameters: known);
  }

  if (!_cornerHint.hasMatch(text)) {
    return changed ? request.merged(knownParameters: known) : request;
  }
  final single = _singleWithContext.firstMatch(text);
  if (single == null) {
    return changed ? request.merged(knownParameters: known) : request;
  }
  final corner = _parseValue(single.group(1)!) * _multiplier(single.group(2)!);
  if (!corner.isFinite || corner <= 0) {
    return changed ? request.merged(knownParameters: known) : request;
  }
  known[PlannerKeys.expectedCornerFrequencyHz] = corner;
  return request.merged(knownParameters: known);
}

/// Wording that explicitly asks to keep the current generator settings.
final RegExp _currentSettingsHint = RegExp(
  r'(1\s*:\s*1|aktuell|unverändert|unveraendert|beibehalten|'
  r'current settings|keep the|unchanged|as is|wie eingestellt)',
  caseSensitive: false,
);

/// Wording that explicitly asks to configure new generator settings.
final RegExp _configureSettingsHint = RegExp(
  r'(neu(e|en)?\s+(einstellung|parameter)|konfigurier|einstellen|'
  r'configure|set new|new settings|waveform|amplitude|'
  r'ausgangsspannung|vpp)',
  caseSensitive: false,
);

/// Drops a model-supplied generator settings mode without text evidence.
///
/// The mode must be asked for every generator measurement. A small model
/// sometimes fills `current` or `configure` without the user saying so; in
/// that case the value is removed so the planner form asks the question.
MeasurementRequest enforceStatedGeneratorSettingsMode(
  MeasurementRequest request,
  String originalText,
) {
  final mode = request.knownParameters[PlannerKeys.generatorSettingsMode];
  if (mode is! String) return request;
  // Only the user's own words count as evidence. The model-generated goal is
  // not evidence: a model that wants to keep a mode it invented could
  // otherwise write the matching words into the goal and legitimize itself.
  final text = originalText;
  final hasEvidence = switch (mode) {
    'current' => _currentSettingsHint.hasMatch(text),
    'configure' => _configureSettingsHint.hasMatch(text),
    _ => false,
  };
  if (hasEvidence) return request;
  final known = Map<String, Object?>.of(request.knownParameters)
    ..remove(PlannerKeys.generatorSettingsMode);
  return MeasurementRequest(
    goal: request.goal,
    measurements: request.measurements,
    knownParameters: known,
    safetyHints: request.safetyHints,
    classification: request.classification,
    stateRef: request.stateRef,
    answers: request.answers,
  );
}

({double start, double stop})? _parseRange(String text) {
  final bothUnits = _rangeWithBothUnits.firstMatch(text);
  if (bothUnits != null) {
    final first =
        _parseValue(bothUnits.group(1)!) * _multiplier(bothUnits.group(2)!);
    final second =
        _parseValue(bothUnits.group(3)!) * _multiplier(bothUnits.group(4)!);
    return (start: math.min(first, second), stop: math.max(first, second));
  }
  final sharedUnit = _rangeWithSharedUnit.firstMatch(text);
  if (sharedUnit != null) {
    final unit = _multiplier(sharedUnit.group(3)!);
    final first = _parseValue(sharedUnit.group(1)!) * unit;
    final second = _parseValue(sharedUnit.group(2)!) * unit;
    return (start: math.min(first, second), stop: math.max(first, second));
  }
  return null;
}

double _parseValue(String text) => double.parse(text.replaceAll(',', '.'));

double _multiplier(String unit) {
  return switch (unit.toLowerCase()) {
    'khz' => 1e3,
    'mhz' => 1e6,
    _ => 1,
  };
}
