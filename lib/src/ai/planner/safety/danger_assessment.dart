/// Deterministic electrical-safety assessment of a planned measurement.
library;

/// Severity of a measurement setup.
enum DangerLevel {
  safe,
  warning,
  blocked;

  /// Wire value used in abort details and the session store.
  String get wireName => name;
}

/// Machine-readable reason for a danger level.
enum DangerCode {
  unknownMaxVoltage,
  unknownCoupling,
  unknownCouplingElevatedVoltage,
  aboveAcPeakWarning,
  aboveAcRmsWarning,
  aboveDcWarning,
  aboveScopeInput,
  aboveProbeRating,
  mainsReferencedNoIsolation,
  unknownMainsReference,
  floatingDutElevatedVoltage,
  floatingDutUnknownCoupling,
  probeRatingUnknown,
  generatorAmplitudeWarning;

  /// Wire value used in abort details.
  String get wireName => name;
}

/// Result of the safety evaluation.
class DangerAssessment {
  const DangerAssessment({
    required this.level,
    required this.codes,
    required this.reasons,
    required this.safetyNotes,
    required this.correctable,
    required this.missingSafetyInputs,
    this.peakVoltageV,
    this.probeRatingV,
    this.effectiveLimitV,
  });

  /// Overall severity.
  final DangerLevel level;

  /// Machine-readable codes, in evaluation order.
  final List<DangerCode> codes;

  /// English explanations, one per code.
  final List<String> reasons;

  /// English notes copied into the action plan.
  final List<String> safetyNotes;

  /// Whether further user answers could change the assessment.
  final bool correctable;

  /// Safety questions that are still unanswered, in policy order.
  final List<String> missingSafetyInputs;

  /// Expected peak voltage in volts, or `null` when unknown.
  final double? peakVoltageV;

  /// Rating of the selected probe attenuation, or `null` when unknown.
  final double? probeRatingV;

  /// Effective input limit: the lower of the scope and probe limits.
  final double? effectiveLimitV;

  /// Whether the setup is blocked.
  bool get isBlocked => level == DangerLevel.blocked;

  /// Whether the setup carries a warning but is executable.
  bool get isWarning => level == DangerLevel.warning;

  /// Whether the setup is safe.
  bool get isSafe => level == DangerLevel.safe;

  Map<String, Object?> toJson() => <String, Object?>{
    'level': level.wireName,
    'codes': <String>[for (final code in codes) code.wireName],
    'reasons': reasons,
    'safetyNotes': safetyNotes,
    'correctable': correctable,
    'missingSafetyInputs': missingSafetyInputs,
    if (peakVoltageV != null) 'peakVoltageV': peakVoltageV,
    if (probeRatingV != null) 'probeRatingV': probeRatingV,
    if (effectiveLimitV != null) 'effectiveLimitV': effectiveLimitV,
  };
}
