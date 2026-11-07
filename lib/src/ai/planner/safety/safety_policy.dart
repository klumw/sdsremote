/// Deterministic electrical-safety policy for planned measurements.
///
/// The policy fails closed: an unknown maximum voltage is never safe, and
/// unparseable or non-finite values are treated as unknown instead of zero.
/// All numeric thresholds are placeholders pending human review.
library;

import 'dart:math' as math;

import '../models/measurement_request.dart';
import '../models/units.dart';
import '../planner_config.dart';
import 'danger_assessment.dart';

/// Generator settings that will be applied during the measurement.
class PlannedGeneratorSettings {
  const PlannedGeneratorSettings({this.amplitudeVpp, this.offsetV});

  /// Planned peak-to-peak amplitude in volts.
  final double? amplitudeVpp;

  /// Planned DC offset in volts.
  final double? offsetV;

  /// Peak voltage seen at the generator output, including the offset.
  double? get peakVoltageV {
    final amplitude = amplitudeVpp;
    if (amplitude == null || !amplitude.isFinite) return null;
    final offset = offsetV;
    final absoluteOffset = offset != null && offset.isFinite
        ? offset.abs()
        : 0.0;
    return amplitude.abs() / 2 + absoluteOffset;
  }
}

/// Typed safety limits of the planner.
///
/// PENDING HUMAN REVIEW: every voltage threshold and probe rating below is a
/// placeholder and must be confirmed against the oscilloscope and probe
/// documentation before release.
class SafetyPolicy {
  const SafetyPolicy({
    this.scopeMaxInputV = 70.0,
    this.warningAcRmsV = 30.0,
    this.warningAcPeakV = 42.4,
    this.warningDcV = 60.0,
    this.probeRatingByAttenuation = const <String, double>{
      '1x': 50.0,
      '10x': 300.0,
      '100x': 600.0,
    },
    this.safetyQuestionOrder = const <String>[
      PlannerKeys.maxVoltageV,
      PlannerKeys.coupling,
      PlannerKeys.mainsReferenced,
      PlannerKeys.probeAttenuation,
      PlannerKeys.differentialOrIsolated,
      PlannerKeys.floatingDut,
    ],
  });

  /// Default policy used in production.
  static const SafetyPolicy defaults = SafetyPolicy();

  /// Marks the numeric defaults as pending human review.
  static const bool pendingHumanReview = true;

  /// Maximum input voltage of the oscilloscope in volts.
  final double scopeMaxInputV;

  /// Warning threshold for AC RMS voltage in volts.
  final double warningAcRmsV;

  /// Warning threshold for AC peak voltage in volts.
  final double warningAcPeakV;

  /// Warning threshold for DC voltage in volts.
  final double warningDcV;

  /// Probe ratings in volts, keyed by attenuation (`1x`, `10x`, `100x`).
  final Map<String, double> probeRatingByAttenuation;

  /// Order in which safety questions are asked.
  final List<String> safetyQuestionOrder;

  /// Effective input limit for a probe attenuation key.
  double effectiveLimitFor(String? attenuationKey) {
    final probeRating = attenuationKey == null
        ? null
        : probeRatingByAttenuation[attenuationKey];
    return math.min(scopeMaxInputV, probeRating ?? scopeMaxInputV);
  }

  /// Evaluates the safety of a measurement setup.
  ///
  /// [mergedInputs] carries the current answers and planned generator values.
  /// Values in it take precedence over [MeasurementRequest.safetyHints].
  DangerAssessment evaluate({
    required MeasurementRequest request,
    Map<String, Object?> mergedInputs = const <String, Object?>{},
    PlannedGeneratorSettings? generator,
  }) {
    final merged = <String, Object?>{
      ...request.knownParameters,
      ...?request.answers,
      ...mergedInputs,
    };

    final peak = tryParsePeakVoltage(
      merged.containsKey(PlannerKeys.maxVoltageV)
          ? merged[PlannerKeys.maxVoltageV]
          : request.safetyHints.maxVoltageV,
    );
    final coupling = _coupling(
      merged.containsKey(PlannerKeys.coupling)
          ? merged[PlannerKeys.coupling]
          : request.safetyHints.coupling,
    );
    final mains = _optionalBool(
      merged.containsKey(PlannerKeys.mainsReferenced)
          ? merged[PlannerKeys.mainsReferenced]
          : request.safetyHints.mainsReferenced,
    );
    final floating = _optionalBool(
      merged.containsKey(PlannerKeys.floatingDut)
          ? merged[PlannerKeys.floatingDut]
          : request.safetyHints.floatingDut,
    );
    final attenuation = _attenuationKey(merged[PlannerKeys.probeAttenuation]);
    final differential = _optionalBool(
      merged[PlannerKeys.differentialOrIsolated],
    );
    final probeRating = attenuation == null
        ? null
        : probeRatingByAttenuation[attenuation];
    final effectiveLimit = math.min(
      scopeMaxInputV,
      probeRating ?? scopeMaxInputV,
    );

    final codes = <DangerCode>[];
    final reasons = <String>[];
    final notes = <String>[];
    var level = DangerLevel.safe;

    void block(DangerCode code, String reason) {
      codes.add(code);
      reasons.add(reason);
      level = DangerLevel.blocked;
    }

    void warn(DangerCode code, String reason, {bool inNotes = true}) {
      codes.add(code);
      reasons.add(reason);
      if (inNotes) notes.add(reason);
      if (level != DangerLevel.blocked) level = DangerLevel.warning;
    }

    final elevated = peak != null && peak > warningAcPeakV;

    if (peak != null && probeRating != null && peak > probeRating) {
      block(
        DangerCode.aboveProbeRating,
        'The expected voltage (${_volts(peak)}) exceeds the probe rating '
        '(${_volts(probeRating)}).',
      );
    }
    if (peak != null && peak > scopeMaxInputV) {
      block(
        DangerCode.aboveScopeInput,
        'The expected voltage (${_volts(peak)}) exceeds the oscilloscope input '
        'limit (${_volts(scopeMaxInputV)}).',
      );
    }
    if (mains == true && differential == false) {
      block(
        DangerCode.mainsReferencedNoIsolation,
        'The DUT is mains-referenced and no differential or isolated setup was '
        'stated.',
      );
    } else if (mains == true && differential == null) {
      block(
        DangerCode.mainsReferencedNoIsolation,
        'The DUT is mains-referenced; whether the setup is differential or '
        'isolated is unknown.',
      );
    }

    if (peak == null) {
      warn(
        DangerCode.unknownMaxVoltage,
        'The expected maximum voltage is unknown, so the setup cannot be '
        'confirmed safe.',
      );
    }
    if (coupling == Coupling.unknown) {
      warn(DangerCode.unknownCoupling, 'The input coupling is unknown.');
      if (elevated) {
        warn(
          DangerCode.unknownCouplingElevatedVoltage,
          'The coupling is unknown at an elevated voltage.',
        );
      }
    }
    if (coupling != Coupling.dc && peak != null && peak > warningAcPeakV) {
      warn(
        DangerCode.aboveAcPeakWarning,
        'The expected AC peak voltage exceeds ${_volts(warningAcPeakV)}.',
      );
    }
    if (coupling != Coupling.dc &&
        peak != null &&
        peak / math.sqrt2 > warningAcRmsV) {
      warn(
        DangerCode.aboveAcRmsWarning,
        'The expected AC RMS voltage exceeds ${_volts(warningAcRmsV)} RMS.',
      );
    }
    if (coupling == Coupling.dc && peak != null && peak > warningDcV) {
      warn(
        DangerCode.aboveDcWarning,
        'The expected DC voltage exceeds ${_volts(warningDcV)}.',
      );
    }
    if (floating == true && elevated) {
      warn(
        DangerCode.floatingDutElevatedVoltage,
        'The DUT is floating at an elevated voltage.',
      );
    }
    if (floating == true && coupling == Coupling.unknown) {
      warn(
        DangerCode.floatingDutUnknownCoupling,
        'The DUT is floating and the input coupling is unknown.',
      );
    }
    if (mains == null) {
      warn(
        DangerCode.unknownMainsReference,
        'It is unknown whether the DUT is referenced to mains potential.',
      );
    }
    if (elevated && attenuation == null) {
      warn(
        DangerCode.probeRatingUnknown,
        'The probe attenuation is unknown at an elevated voltage.',
      );
    }
    final generatorPeak = generator?.peakVoltageV;
    if (generatorPeak != null && generatorPeak > warningAcPeakV) {
      warn(
        DangerCode.generatorAmplitudeWarning,
        'The planned generator output reaches ${_volts(generatorPeak)} peak '
        'including the offset.',
      );
    }

    final correctable = level == DangerLevel.blocked
        ? mains == true && differential == null
        : peak == null ||
              coupling == Coupling.unknown ||
              mains == null ||
              (mains == true && differential == null) ||
              (elevated && attenuation == null);

    final missingSafetyInputs = <String>[];
    for (final key in safetyQuestionOrder) {
      switch (key) {
        case PlannerKeys.maxVoltageV:
          if (peak == null) missingSafetyInputs.add(key);
        case PlannerKeys.coupling:
          if (coupling == Coupling.unknown) missingSafetyInputs.add(key);
        case PlannerKeys.mainsReferenced:
          if (mains == null) missingSafetyInputs.add(key);
        case PlannerKeys.probeAttenuation:
          if (elevated && attenuation == null) missingSafetyInputs.add(key);
        case PlannerKeys.differentialOrIsolated:
          if (mains == true && differential == null) {
            missingSafetyInputs.add(key);
          }
        case PlannerKeys.floatingDut:
          if (floating == null && elevated) missingSafetyInputs.add(key);
      }
    }

    return DangerAssessment(
      level: level,
      codes: List<DangerCode>.unmodifiable(codes),
      reasons: List<String>.unmodifiable(reasons),
      safetyNotes: List<String>.unmodifiable(notes),
      correctable: correctable,
      missingSafetyInputs: List<String>.unmodifiable(missingSafetyInputs),
      peakVoltageV: peak,
      probeRatingV: probeRating,
      effectiveLimitV: effectiveLimit,
    );
  }

  static String _volts(double value) {
    final rounded = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$rounded V';
  }

  static Coupling _coupling(Object? value) {
    if (value is Coupling) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      for (final coupling in Coupling.values) {
        if (coupling.wireName == normalized) return coupling;
      }
    }
    return Coupling.unknown;
  }

  static bool? _optionalBool(Object? value) {
    if (value is bool) return value;
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true':
        case 'yes':
          return true;
        case 'false':
        case 'no':
          return false;
      }
    }
    return null;
  }

  static String? _attenuationKey(Object? value) {
    if (value is num) {
      return value.isFinite ? '${value.toInt()}x' : null;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized.endsWith('x')) return normalized;
      final number = double.tryParse(normalized);
      if (number != null && number.isFinite) return '${number.toInt()}x';
    }
    return null;
  }
}
