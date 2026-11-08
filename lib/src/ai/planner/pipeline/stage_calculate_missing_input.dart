/// BPMN stage 6: decide the source of every parameter and detect missing
/// user data and generator-limit violations.
library;

import 'dart:math' as math;

import '../catalog/param_spec.dart';
import '../catalog/param_validation.dart';
import '../catalog/planner_catalog.dart';
import '../models/action_plan.dart';
import '../models/input_form.dart';
import '../models/measurement_request.dart';
import '../models/planner_result.dart';
import '../models/units.dart';
import '../planner_config.dart';
import '../safety/safety_policy.dart';
import 'equipment_report.dart';
import 'missing_input.dart';
import 'plan_draft.dart';
import 'plan_rendering.dart';
import 'stage_result.dart';

/// Resolves every parameter of [draft] to a value or a missing-input record.
///
/// Sources, in order: given value, readable value (cached device value or a
/// read step that later steps reference; never asked), default, derivation,
/// and user-required. Generator limits are validated here and abort
/// `not_feasible`.
StageResult<MissingInputPlan> calculateMissingInput({
  required MeasurementRequest request,
  required Map<String, Object?> answers,
  required PlanDraft draft,
  required EquipmentReport equipment,
  required PlannerConfig config,
  required SafetyPolicy safetyPolicy,
  required PlannerCatalog catalog,
}) {
  final merged = <String, Object?>{
    ...request.knownParameters,
    ...?request.answers,
    ...answers,
  };
  // Values that are already resolved in this pass. Readable output paths may
  // reference defaults resolved earlier, for example
  // `channels.{inputChannel}.frequencyHz`.
  final effectiveValues = <String, Object?>{...merged};
  final danger = safetyPolicy.evaluate(request: request, mergedInputs: merged);
  final requiredSafety = danger.missingSafetyInputs.toSet();

  final resolved = <String, ResolvedInput>{};
  final missing = <MissingInput>[];
  final references = <String, StepReferenceParameter>{};
  final readSteps = <PlanReadStep>[];
  final unknownKeys = <String>[];
  // The session stores the cancel sentinel as a top-level answer key, not as
  // a value of a parameter spec.
  var cancelled = merged.containsKey(cancelledAnswerKey);

  final specs = <ParamSpec>[];
  final seen = <String>{};
  for (final recipe in draft.recipes) {
    for (final parameter in recipe.parameters) {
      if (seen.add(parameter.key)) specs.add(parameter);
    }
  }
  for (final parameter in catalog.safetyParameters) {
    if (seen.add(parameter.key)) specs.add(parameter);
  }

  for (final spec in specs) {
    final condition = spec.activeWhen;
    if (condition != null) {
      final conditionValue =
          effectiveValues[condition.key] ?? resolved[condition.key]?.value;
      if (conditionValue == null) {
        // The controlling question (for example the generator settings mode)
        // is not answered yet. Ask it first and evaluate this parameter in the
        // next round.
        continue;
      }
      if (conditionValue != condition.equals) {
        final current = _currentGeneratorSetting(
          spec,
          effectiveValues,
          equipment,
        );
        if (current != null) {
          resolved[spec.key] = ResolvedInput(
            key: spec.key,
            value: current,
            source: InputSource.device,
          );
          effectiveValues[spec.key] = current;
        } else {
          missing.add(
            MissingInput(
              key: spec.key,
              spec: spec,
              reason: MissingInputReason.absent,
              validationMessage:
                  'The current generator setting could not be read. Enter '
                  'the value explicitly.',
            ),
          );
        }
        continue;
      }
    }

    final raw = merged[spec.key];
    final hasRaw = merged.containsKey(spec.key);
    if (raw == unknownAnswerValue) {
      // An optional question answered with "I do not know" is simply skipped;
      // only a required unknown value aborts the plan.
      if (!spec.required) continue;
      unknownKeys.add(spec.key);
      continue;
    }
    if (raw == cancelledAnswerKey) {
      cancelled = true;
      continue;
    }
    if (hasRaw && raw == null && !spec.required) {
      // The form was shown and the optional question was left blank.
      continue;
    }

    final isSafety = catalog.safetyParameterFor(spec.key) != null;
    if (raw != null) {
      final validation = validateParameterValue(spec, raw);
      if (validation.error != null) {
        missing.add(
          MissingInput(
            key: spec.key,
            spec: spec,
            reason: MissingInputReason.invalid,
            validationMessage: validation.error,
            originalValue: raw,
          ),
        );
      } else {
        resolved[spec.key] = ResolvedInput(
          key: spec.key,
          value: validation.value,
          source: InputSource.user,
        );
        effectiveValues[spec.key] = validation.value;
      }
      continue;
    }

    if (isSafety) {
      if (requiredSafety.contains(spec.key)) {
        missing.add(
          MissingInput(
            key: spec.key,
            spec: spec,
            reason: MissingInputReason.absent,
          ),
        );
      }
      continue;
    }

    switch (spec.source) {
      case ParamSource.given:
        if (!spec.required) break;
        missing.add(
          MissingInput(
            key: spec.key,
            spec: spec,
            reason: MissingInputReason.absent,
          ),
        );
      case ParamSource.userRequired:
        missing.add(
          MissingInput(
            key: spec.key,
            spec: spec,
            reason: MissingInputReason.absent,
          ),
        );
      case ParamSource.defaulted:
        // A derived default is used when its dependency is known; otherwise
        // the recorded default applies. Example: the sweep range is derived
        // from a stated expected cutoff, but stays 20 Hz-20 kHz when no
        // cutoff was given.
        final derivedFromCorner = spec.derive == null
            ? null
            : _derive(spec, resolved);
        final value = derivedFromCorner == null
            ? spec.defaultValue
            : _clampToSpec(spec, derivedFromCorner);
        resolved[spec.key] = ResolvedInput(
          key: spec.key,
          value: value,
          source: derivedFromCorner == null
              ? InputSource.defaulted
              : InputSource.derived,
        );
        effectiveValues[spec.key] = value;
      case ParamSource.askedOrDerived:
        // Ask the user unless the value can be derived from values that are
        // already known. The sweep range is the main use: a stated corner
        // frequency derives a decade-wide range, otherwise the form asks for
        // the start and stop frequency.
        final derived = spec.derive == null ? null : _derive(spec, resolved);
        if (derived == null) {
          missing.add(
            MissingInput(
              key: spec.key,
              spec: spec,
              reason: MissingInputReason.absent,
            ),
          );
        } else {
          final value = _clampToSpec(spec, derived);
          resolved[spec.key] = ResolvedInput(
            key: spec.key,
            value: value,
            source: InputSource.derived,
          );
          effectiveValues[spec.key] = value;
        }
      case ParamSource.derived:
        final derived = _derive(spec, resolved);
        if (derived == null) {
          missing.add(
            MissingInput(
              key: spec.key,
              spec: spec,
              reason: MissingInputReason.absent,
              validationMessage:
                  'This value depends on another value that is still unknown.',
            ),
          );
        } else {
          final value = _clampToSpec(spec, derived);
          resolved[spec.key] = ResolvedInput(
            key: spec.key,
            value: value,
            source: InputSource.derived,
          );
          effectiveValues[spec.key] = value;
        }
      case ParamSource.readable:
        final cached = _readCached(spec, effectiveValues, equipment);
        if (cached != null) {
          resolved[spec.key] = ResolvedInput(
            key: spec.key,
            value: cached,
            source: InputSource.device,
          );
          effectiveValues[spec.key] = cached;
          break;
        }
        final reading = spec.reading;
        if (reading == null) {
          missing.add(
            MissingInput(
              key: spec.key,
              spec: spec,
              reason: MissingInputReason.absent,
            ),
          );
          break;
        }
        final field = _substitute(reading.outputField, effectiveValues);
        final stepId = 'read-${readSteps.length + 1}';
        final step = PlanStepDraft(
          id: stepId,
          kind: ActionStepKind.read,
          agent: PlanAgent.scopeAnalysis,
          focus: 'measurement',
          template:
              'Read the current waveform summary and return $field for the '
              'next step.',
          parameterKeys: const <String>[],
          dependsOn: const <String>[],
          requiresUserConfirmation: false,
          expectedOutput: field,
          estimatedToolCalls: 1,
        );
        readSteps.add(
          PlanReadStep(
            step: step,
            beforeStepId: _consumingStepId(draft, spec.key),
            parameterKey: spec.key,
          ),
        );
        references[spec.key] = StepReferenceParameter(
          fromStep: stepId,
          field: field,
        );
    }
  }

  final safetyNotes = List<String>.of(danger.safetyNotes);
  final violationResult = _checkGeneratorLimits(
    draft: draft,
    equipment: equipment,
    resolved: resolved,
    safetyNotes: safetyNotes,
  );
  if (violationResult != null) return violationResult;

  return StageResult.ok(
    MissingInputPlan(
      resolved: resolved,
      missing: missing,
      readSteps: readSteps,
      references: references,
      safetyNotes: safetyNotes,
      cancelled: cancelled,
      hasUnknownSentinel: unknownKeys.isNotEmpty,
      unknownKeys: unknownKeys,
    ),
  );
}

Object? _currentGeneratorSetting(
  ParamSpec spec,
  Map<String, Object?> effectiveValues,
  EquipmentReport equipment,
) {
  final channels = equipment.generator?.readableValues['channels'];
  if (channels is! Map) return null;
  final channel =
      effectiveValues[PlannerKeys.generatorChannel]?.toString() ?? '1';
  final channelRaw = channels[channel];
  if (channelRaw is! Map) return null;
  switch (spec.key) {
    case PlannerKeys.generatorWaveform:
      final value = channelRaw['waveform'];
      if (value is! String) return null;
      final mnemonic = value.trim().toUpperCase();
      return switch (mnemonic) {
        'SIN' || 'SINE' => 'sine',
        'SQU' || 'SQUARE' => 'square',
        'TRI' || 'TRIANGLE' => 'triangle',
        'PULS' || 'PULSE' => 'pulse',
        'RAMP' => 'ramp',
        _ => value.trim().toLowerCase(),
      };
    case PlannerKeys.amplitudeVpp:
      final value = channelRaw['amplitude_vpp'];
      return value is num && value.isFinite ? value.toDouble() : null;
    case PlannerKeys.offsetV:
      final value = channelRaw['offset_v'];
      return value is num && value.isFinite ? value.toDouble() : null;
    default:
      return null;
  }
}

StageResult<MissingInputPlan>? _checkGeneratorLimits({
  required PlanDraft draft,
  required EquipmentReport equipment,
  required Map<String, ResolvedInput> resolved,
  required List<String> safetyNotes,
}) {
  if (!draft.generatorEnabled) return null;
  final generator = equipment.generator;
  if (generator == null) return null;
  if (resolved.isEmpty) return null;
  final limits = generator.limits;
  if (limits == null) {
    safetyNotes.add(
      'The signal-generator limits are unknown, so frequency and amplitude '
      'limits could not be checked.',
    );
    return null;
  }

  final violations = <Map<String, Object?>>[];
  final device = generator.model ?? generator.device ?? 'signal generator';

  void violate(String parameter, Object? requested, Object? limit) {
    violations.add(<String, Object?>{
      'parameter': parameter,
      'requested': requested,
      'limit': limit,
      'device': device,
    });
  }

  double? number(String key) {
    final value = resolved[key]?.value;
    if (value is num && value.isFinite) return value.toDouble();
    return null;
  }

  final waveform = resolved[PlannerKeys.generatorWaveform]?.value;
  final waveformName = waveform is String ? waveform : 'sine';

  final frequency = number(PlannerKeys.frequencyHz);
  final start = number(PlannerKeys.startFrequencyHz);
  final stop = number(PlannerKeys.stopFrequencyHz);
  final amplitude = number(PlannerKeys.amplitudeVpp);
  final offset = number(PlannerKeys.offsetV);
  final channelText = resolved[PlannerKeys.generatorChannel]?.value;

  for (final entry in <String, double?>{
    PlannerKeys.frequencyHz: frequency,
    PlannerKeys.startFrequencyHz: start,
    PlannerKeys.stopFrequencyHz: stop,
  }.entries) {
    final value = entry.value;
    if (value == null) continue;
    if (value < limits.minFrequencyHz) {
      violate(entry.key, value, limits.minFrequencyHz);
    }
    final maximum = limits.maxFrequencyHz(waveformName);
    if (maximum != null && value > maximum) {
      violate(entry.key, value, maximum);
    }
  }

  if (start != null && stop != null && start >= stop) {
    violations.add(<String, Object?>{
      'parameter': PlannerKeys.startFrequencyHz,
      'requested': start,
      'limit': stop,
      'device': device,
      'reason': 'START_NOT_BELOW_STOP',
    });
  }

  final referenceFrequency = <double>[?frequency, ?start, ?stop].fold<double?>(
    null,
    (current, value) => current == null ? value : math.max(current, value),
  );
  final maxAmplitude = referenceFrequency == null
      ? null
      : limits.maxAmplitudeVpp(referenceFrequency);
  if (amplitude != null) {
    if (amplitude > 0 && maxAmplitude != null && amplitude > maxAmplitude) {
      violate(PlannerKeys.amplitudeVpp, amplitude, maxAmplitude);
    }
    if (amplitude <= 0) {
      violate(PlannerKeys.amplitudeVpp, amplitude, '> 0');
    }
    if (amplitude > 0 &&
        offset != null &&
        maxAmplitude != null &&
        amplitude / 2 + offset.abs() > maxAmplitude) {
      violate(PlannerKeys.offsetV, offset, maxAmplitude - amplitude / 2);
    }
    if (maxAmplitude == null) {
      safetyNotes.add(
        'The generator amplitude limit for the requested frequency is not '
        'reported, so the amplitude was not checked.',
      );
    }
  }
  if (offset != null) {
    final minimum = limits.minOffsetV;
    final maximum = limits.maxOffsetV;
    if (minimum != null && offset < minimum) {
      violate(PlannerKeys.offsetV, offset, minimum);
    }
    if (maximum != null && offset > maximum) {
      violate(PlannerKeys.offsetV, offset, maximum);
    }
  }
  if (channelText != null) {
    final channel = int.tryParse(channelText.toString());
    if (channel == null || channel < 1 || channel > generator.channelCount) {
      violate(
        PlannerKeys.generatorChannel,
        channelText,
        '1..${generator.channelCount}',
      );
    }
  }

  if (violations.isEmpty) return null;
  return StageResult.abort(
    AbortReason.notFeasible,
    message:
        'The requested generator settings exceed the device limits. Adjust '
        'the values or split the request.',
    details: <String, Object?>{
      'reason': 'GENERATOR_LIMIT',
      'violations': violations,
    },
  );
}

double? _derive(ParamSpec spec, Map<String, ResolvedInput> resolved) {
  double? dependency(int index) {
    if (index >= spec.dependsOn.length) return null;
    final value = resolved[spec.dependsOn[index]]?.value;
    return value is num ? value.toDouble() : null;
  }

  switch (spec.derive) {
    case Derivation.periodFromFrequency:
      final frequency = dependency(0);
      return frequency == null || frequency == 0 ? null : 1 / frequency;
    case Derivation.frequencyFromPeriod:
      final period = dependency(0);
      return period == null || period == 0 ? null : 1 / period;
    case Derivation.vrmsFromVpp:
      final vpp = dependency(0);
      return vpp == null ? null : vpp / (2 * math.sqrt2);
    case Derivation.vppFromVrms:
      final vrms = dependency(0);
      return vrms == null ? null : vrms * 2 * math.sqrt2;
    case Derivation.sweepStartFromCorner:
      final corner = dependency(0);
      return corner == null || corner <= 0 ? null : corner / 10;
    case Derivation.sweepStopFromCorner:
      final corner = dependency(0);
      return corner == null || corner <= 0 ? null : corner * 10;
    case null:
      return null;
  }
}

double _clampToSpec(ParamSpec spec, double value) {
  var result = value;
  final minimum = spec.min;
  final maximum = spec.max;
  if (minimum != null && result < minimum) result = minimum.toDouble();
  if (maximum != null && result > maximum) result = maximum.toDouble();
  return result;
}

Object? _readCached(
  ParamSpec spec,
  Map<String, Object?> values,
  EquipmentReport equipment,
) {
  final reading = spec.reading;
  if (reading == null) return null;
  if (reading.tool != 'read_waveform_summary') return null;
  final summary = equipment.scope.readableValues['waveformSummary'];
  if (summary is! Map) return null;
  final field = _substitute(reading.outputField, values);
  final raw = _lookup(summary, field);
  return _toSpecUnit(spec, raw);
}

double? _toSpecUnit(ParamSpec spec, Object? raw) {
  if (raw == null) return null;
  if (spec.unit == null) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString());
  }
  final expected = switch (spec.unit!.toLowerCase()) {
    'hz' => QuantityKind.frequency,
    'v' => QuantityKind.voltagePeak,
    'vpp' => QuantityKind.voltagePeakToPeak,
    _ => null,
  };
  if (expected == null) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString());
  }
  final quantity = tryParseQuantity(raw, expected: expected);
  if (quantity == null) return null;
  if (quantity.kind == QuantityKind.frequency) return quantity.siValue;
  return quantity.value;
}

Object? _lookup(Object? root, String path) {
  Object? current = root;
  for (final segment in path.split('.')) {
    if (current is Map) {
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) return null;
      current = current[index];
    } else {
      return null;
    }
    if (current == null) return null;
  }
  return current;
}

String _substitute(String template, Map<String, Object?> values) {
  return template.replaceAllMapped(RegExp(r'\{([a-zA-Z0-9_]+)\}'), (match) {
    final key = match.group(1)!;
    return values.containsKey(key)
        ? formatPlannerValue(values[key])
        : match.group(0)!;
  });
}

String _consumingStepId(PlanDraft draft, String key) {
  for (final step in draft.steps) {
    if (step.kind != ActionStepKind.manual &&
        step.parameterKeys.contains(key)) {
      return step.id;
    }
  }
  for (final step in draft.steps) {
    if (step.kind == ActionStepKind.measure) return step.id;
  }
  return draft.steps.isEmpty ? 'measure-1' : draft.steps.last.id;
}
