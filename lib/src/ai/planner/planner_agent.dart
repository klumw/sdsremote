/// PlannerAgent: the LLM boundary in front of the deterministic pipeline.
///
/// The model has exactly one tool, `plan_measurement`. Its `onCall` runs the
/// full pipeline, stores the typed result and stops the model stream. The
/// agent returns the captured result verbatim; the model never edits,
/// reorders or summarizes a plan, form, classification or abort.
library;

import 'dart:async';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../agents/systemprompts.dart';
import '../cancellation.dart';
import 'catalog/param_spec.dart';
import 'catalog/param_validation.dart';
import 'catalog/planner_catalog.dart';
import 'models/action_plan.dart';
import 'models/input_form.dart';
import 'models/json_value.dart';
import 'models/measurement_request.dart';
import 'models/planner_result.dart';
import 'pipeline/equipment_probe.dart';
import 'pipeline/planner_pipeline.dart';
import 'planner_config.dart';
import 'planner_ids.dart';
import 'planner_request_normalizer.dart';
import 'planner_schemas.dart';
import 'planner_session.dart';

/// Runs one PlannerAgent model turn with the given tools and yields text
/// chunks. The seam lets unit tests drive the tool without a network call.
typedef PlannerModelRunner =
    Stream<String> Function({
      required String model,
      required String systemPrompt,
      required String prompt,
      required List<Tool<Map<String, dynamic>>> tools,
      required int maxToolCalls,
    });

/// Production model runner backed by dartantic.
Stream<String> defaultPlannerModelRunner({
  required String model,
  required String systemPrompt,
  required String prompt,
  required List<Tool<Map<String, dynamic>>> tools,
  required int maxToolCalls,
}) {
  final agent = Agent(
    model,
    displayName: 'PlannerAgent',
    maxToolCalls: maxToolCalls,
    tools: tools,
  );
  return agent
      .sendStream(
        prompt,
        history: <ChatMessage>[ChatMessage.system(systemPrompt)],
      )
      .map((result) => result.output);
}

/// Converts free text into a strict measurement request and runs the
/// deterministic planner pipeline.
class PlannerAgent {
  PlannerAgent({
    String model = defaultModel,
    PlannerModelRunner? modelRunner,
    PlannerPipeline? pipeline,
    PlannerSessionStore? sessionStore,
    int maxToolCalls = defaultMaxToolCalls,
    PlannerCatalog catalog = PlannerCatalog.standard,
    PlannerConfig config = PlannerConfig.defaults,
    PlannerIdSource? idSource,
  }) : _model = model,
       _modelRunner = modelRunner ?? defaultPlannerModelRunner,
       _pipeline =
           pipeline ??
           PlannerPipeline(
             catalog: catalog,
             config: config,
             idSource: idSource ?? SequentialIdSource(),
           ),
       _sessionStore = sessionStore ?? PlannerSessionStore(),
       _maxToolCalls = maxToolCalls,
       _catalog = catalog;

  /// Default model of the planner.
  static const String defaultModel = 'deepseek:deepseek-v4-flash';

  /// Default internal call limit of the `plan_measurement` tool.
  static const int defaultMaxToolCalls = 6;

  final String _model;
  final PlannerModelRunner _modelRunner;
  final PlannerPipeline _pipeline;
  final PlannerSessionStore _sessionStore;
  final int _maxToolCalls;
  final PlannerCatalog _catalog;

  PlannerOutcome? _captured;
  int _toolCalls = 0;

  /// Values collected in this chat session.
  ///
  /// A new measurement reuses them so the same safety, channel and setup
  /// questions are not asked again. Values stated in the new request always
  /// take precedence.
  final Map<String, Object?> _sessionValues = <String, Object?>{};

  /// Values remembered for the current chat session.
  Map<String, Object?> get sessionValues =>
      Map<String, Object?>.unmodifiable(_sessionValues);

  /// Parameter specifications indexed by key, used to normalize values that
  /// the model supplied as `knownParameters`.
  late final Map<String, ParamSpec> _specsByKey = <String, ParamSpec>{
    for (final recipe in _catalog.recipes)
      for (final parameter in recipe.parameters) parameter.key: parameter,
    for (final parameter in _catalog.safetyParameters) parameter.key: parameter,
  };

  /// Tool names exposed to the model.
  List<String> get toolNames => const <String>['plan_measurement'];

  /// Input schema of the `plan_measurement` tool.
  Map<String, dynamic> get measurementSchema =>
      buildPlanMeasurementSchema(_catalog);

  /// Pending sessions, exposed for tests and diagnostics.
  PlannerSessionStore get sessions => _sessionStore;

  /// Converts [request] into exactly one `plan_measurement` call and returns
  /// the captured result verbatim.
  Future<Map<String, dynamic>> plan(
    String request, {
    required EquipmentProbe probe,
    CancellationToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      return _abort(
        AbortReason.userCancelled,
        'The planning request was cancelled.',
      );
    }
    final trimmed = request.trim();
    if (trimmed.isEmpty) {
      return _abort(
        AbortReason.inputIncomplete,
        'The planning request is empty.',
        const <String, Object?>{'reason': 'EMPTY_REQUEST'},
      );
    }

    _captured = null;
    _toolCalls = 0;
    final done = Completer<void>();
    StreamSubscription<String>? subscription;

    void cancel() {
      if (!done.isCompleted) done.complete();
      unawaited(subscription?.cancel());
    }

    final tool = Tool<Map<String, dynamic>>(
      name: 'plan_measurement',
      description:
          'Runs the deterministic planning pipeline for one measurement '
          'request. Call it exactly once. Use exact catalog ids in '
          '`measurements`; for an unlisted quantity use "other:<short name>". '
          'Fill `knownParameters` and `safetyHints` only with facts stated by '
          'the user. Always include `classification` with the category and '
          'your honest confidence; the user is asked when it is low or no '
          'catalog recipe matches. The tool returns a JSON result with status '
          'plan_ready, needs_input, classified or aborted; the application '
          'returns it verbatim. Never paraphrase or edit the result in prose.',
      inputSchema: Schema.fromMap(measurementSchema),
      onCall: (args) async {
        _toolCalls++;
        if (_toolCalls > _maxToolCalls) {
          return <String, dynamic>{
            'error_code': 'PLANNER_TOOL_LIMIT',
            'error':
                'The plan_measurement call limit ($_maxToolCalls) was reached.',
          };
        }
        if (_captured != null) {
          return <String, dynamic>{
            'error_code': 'ALREADY_PLANNED',
            'error': 'A planner result was already produced for this request.',
          };
        }
        final MeasurementRequest parsed;
        try {
          parsed = MeasurementRequest.fromMap(args);
        } on PlannerFormatException catch (error) {
          return <String, dynamic>{
            'error_code': 'INVALID_PLANNER_INPUT',
            'field': error.field,
            'error': error.toString(),
          };
        }
        final sanitized = _sanitizeRequest(parsed, trimmed);
        final enriched = enforceStatedGeneratorSettingsMode(
          enrichStatedCornerFrequency(sanitized, trimmed),
          trimmed,
        );
        _rememberValues(sanitized.answers ?? const <String, Object?>{});
        _rememberRequestValues(enriched);
        final seeded = _seedWithSessionValues(enriched);
        final logger = AppLogger(
          agentName: 'PlannerAgent',
          toolName: 'plan_measurement',
        );
        final rejected = <String>[
          for (final entry in parsed.knownParameters.entries)
            if (entry.value != null &&
                !sanitized.knownParameters.containsKey(entry.key))
              entry.key,
        ];
        final trustedHints = _hintValues(sanitized.safetyHints);
        final droppedHints = <String>[
          for (final key in _hintValues(parsed.safetyHints).keys)
            if (!trustedHints.containsKey(key)) key,
        ];
        logger.log(
          'Planner request ids=${seeded.measurements.join(',')} '
          'known=${seeded.knownParameters.keys.join(',')} '
          'remembered=${_sessionValues.length} '
          'classification=${seeded.classification == null ? '-' : '${seeded.classification!.category.wireName}/${seeded.classification!.confidence.wireName}'} '
          'hints=${_formatHintValues(sanitized.safetyHints)}'
          '${rejected.isEmpty ? '' : ' ignored=${rejected.join(',')}'}'
          '${droppedHints.isEmpty ? '' : ' ignoredHints=${droppedHints.join(',')}'}',
        );
        if (!parsed.knownParameters.containsKey(
              PlannerKeys.expectedCornerFrequencyHz,
            ) &&
            enriched.knownParameters.containsKey(
              PlannerKeys.expectedCornerFrequencyHz,
            )) {
          logger.log(
            'Derived expectedCornerFrequencyHz='
            '${enriched.knownParameters[PlannerKeys.expectedCornerFrequencyHz]} '
            'from the request text',
          );
        }
        final outcome = await _pipeline.run(
          seeded,
          const <String, Object?>{},
          0,
          probe,
        );
        _rememberOutcome(outcome);
        _captured = outcome;
        final result = outcome.result;
        if (result is NeedsInputResult) {
          _sessionStore.save(
            PlannerSession(
              stateRef: result.stateRef,
              request: outcome.request,
              answers: const <String, Object?>{},
              form: result.form,
              round: outcome.nextRound,
              requestText: trimmed,
            ),
          );
        }
        if (!done.isCompleted) done.complete();
        return result.toJson();
      },
    );

    cancelToken?.addListener(cancel);
    try {
      subscription =
          _modelRunner(
            model: _model,
            systemPrompt: plannerAgentSystemPrompt,
            prompt: 'MEASUREMENT REQUEST FROM THE WAVEFORM AGENT:\n$trimmed',
            tools: <Tool<Map<String, dynamic>>>[tool],
            maxToolCalls: _maxToolCalls,
          ).listen(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              if (!done.isCompleted) done.completeError(error, stackTrace);
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: true,
          );
      await done.future;
    } on Object catch (error) {
      if (_captured == null) {
        if (cancelToken?.isCancelled == true) {
          return _abort(
            AbortReason.userCancelled,
            'The planning request was cancelled.',
          );
        }
        return _abort(
          AbortReason.notFeasible,
          'The planner could not produce a structured result.',
          <String, Object?>{'reason': 'PLANNER_FAILURE', 'error': '$error'},
        );
      }
    } finally {
      cancelToken?.removeListener(cancel);
      unawaited(subscription?.cancel());
    }

    final captured = _captured;
    if (captured == null) {
      if (cancelToken?.isCancelled == true) {
        return _abort(
          AbortReason.userCancelled,
          'The planning request was cancelled.',
        );
      }
      return _abort(
        AbortReason.notFeasible,
        'The planner did not produce a valid measurement request. Rephrase '
        'the request with the quantities to measure.',
        const <String, Object?>{'reason': 'PLANNER_NO_STRUCTURED_REQUEST'},
      );
    }
    return captured.result.toJson();
  }

  /// Resumes a pending session with submitted [answers], without a model call.
  Future<Map<String, dynamic>> resume(
    String stateRef,
    Map<String, Object?> answers, {
    required EquipmentProbe probe,
    CancellationToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      return _abort(
        AbortReason.userCancelled,
        'The planning request was cancelled.',
      );
    }
    final session = _sessionStore.load(stateRef);
    if (session == null) {
      return _abort(
        AbortReason.notFeasible,
        'The planner session is unknown or expired.',
        <String, Object?>{'reason': 'UNKNOWN_STATE_REF', 'stateRef': stateRef},
      );
    }
    final merged = <String, Object?>{...session.answers, ...answers};
    if (merged.containsKey(cancelledAnswerKey)) {
      _sessionStore.remove(stateRef);
      return _abort(
        AbortReason.userCancelled,
        'The user cancelled the input form.',
        const <String, Object?>{'reason': 'FORM_CANCELLED'},
      );
    }
    // Keep every accepted answer, even when the pipeline later aborts. A
    // second measurement in the same chat must not ask for them again.
    _rememberValues(answers);

    final outcome = await _pipeline.run(
      session.request,
      merged,
      session.round,
      probe,
      stateRef: stateRef,
    );
    _rememberOutcome(outcome);
    final result = outcome.result;
    if (result is NeedsInputResult) {
      _sessionStore.save(
        PlannerSession(
          stateRef: stateRef,
          request: outcome.request,
          answers: merged,
          form: result.form,
          round: outcome.nextRound,
          requestText: session.requestText,
        ),
      );
    } else {
      _sessionStore.remove(stateRef);
    }
    return result.toJson();
  }

  /// Clears every pending session and the remembered session values.
  void clearSession() {
    _sessionStore.clear();
    _sessionValues.clear();
  }

  void _rememberRequestValues(MeasurementRequest request) {
    _rememberValues(request.knownParameters);
    _rememberValues(_hintValues(request.safetyHints));
  }

  Map<String, Object?> _hintValues(SafetyHints hints) {
    return <String, Object?>{
      if (hints.maxVoltageV != null) PlannerKeys.maxVoltageV: hints.maxVoltageV,
      if (hints.coupling != Coupling.unknown)
        PlannerKeys.coupling: hints.coupling.wireName,
      if (hints.mainsReferenced != null)
        PlannerKeys.mainsReferenced: hints.mainsReferenced,
      if (hints.floatingDut != null) PlannerKeys.floatingDut: hints.floatingDut,
    };
  }

  String _formatHintValues(SafetyHints hints) {
    final values = _hintValues(hints);
    if (values.isEmpty) return '-';
    return values.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(',');
  }

  /// Keeps validated values of a finished pipeline run for later measurements.
  ///
  /// Only user-provided values are remembered: defaults and derived values are
  /// recomputed by the next run, and readable values come from the device.
  /// Answers that the next form asks about again were not accepted and are
  /// therefore not remembered.
  void _rememberOutcome(PlannerOutcome outcome) {
    final result = outcome.result;
    if (result is PlanReadyResult) {
      _rememberValues(<String, Object?>{
        for (final input in result.plan.inputs)
          if (input.source == InputSource.user) input.key: input.value,
      });
      return;
    }
    if (result is NeedsInputResult) {
      final asked = <String>{
        for (final question in result.form.questions) question.key,
      };
      _rememberValues(<String, Object?>{
        for (final entry in outcome.answers.entries)
          if (!asked.contains(entry.key)) entry.key: entry.value,
      });
    }
  }

  void _rememberValues(Map<String, Object?> values) {
    for (final entry in values.entries) {
      final value = entry.value;
      if (entry.key.isEmpty ||
          entry.key == PlannerKeys.measurementCategory ||
          entry.key == PlannerKeys.frequenciesHz ||
          entry.key == PlannerKeys.generatorSettingsMode ||
          value == null ||
          value == unknownAnswerValue ||
          value == cancelledAnswerKey) {
        continue;
      }
      final spec = _specsByKey[entry.key];
      if (spec == null) {
        _sessionValues[entry.key] = value;
        continue;
      }
      // Only canonical values are remembered. A model-extracted value with a
      // wrong case or unit is normalized; an unusable value is dropped so it
      // cannot shadow a valid remembered answer.
      final validation = validateParameterValue(spec, value);
      if (validation.isValid && validation.value != null) {
        _sessionValues[entry.key] = validation.value;
      }
    }
  }

  /// Returns [request] with every known parameter normalized.
  ///
  /// Values that the model extracted but that do not validate against the
  /// catalog are dropped: they are not usable user statements, and keeping
  /// them would silently override a valid answer from an earlier form.
  ///
  /// Safety values additionally need evidence in the user's request text. The
  /// model must never invent a voltage or a safety condition, because an
  /// invented value would suppress the mandatory safety question.
  MeasurementRequest _sanitizeRequest(
    MeasurementRequest request,
    String requestText,
  ) {
    final evidence = _SafetyEvidence.fromText(requestText);
    return MeasurementRequest(
      goal: request.goal,
      measurements: request.measurements,
      knownParameters: _sanitizedValues(
        request.knownParameters,
        evidence: evidence,
      ),
      safetyHints: evidence.trustedHints(request.safetyHints),
      classification: request.classification,
      stateRef: request.stateRef,
      answers: request.answers == null
          ? null
          : _sanitizedValues(request.answers!),
    );
  }

  Map<String, Object?> _sanitizedValues(
    Map<String, Object?> values, {
    _SafetyEvidence? evidence,
  }) {
    final result = <String, Object?>{};
    for (final entry in values.entries) {
      final value = entry.value;
      if (value == null ||
          value == unknownAnswerValue ||
          value == cancelledAnswerKey) {
        result[entry.key] = value;
        continue;
      }
      if (evidence != null && !evidence.allows(entry.key)) continue;
      final spec = _specsByKey[entry.key];
      if (spec == null) {
        result[entry.key] = value;
        continue;
      }
      final validation = validateParameterValue(spec, value);
      if (validation.isValid) {
        result[entry.key] = validation.value;
      }
    }
    return result;
  }

  MeasurementRequest _seedWithSessionValues(MeasurementRequest request) {
    if (_sessionValues.isEmpty) return request;
    final hints = request.safetyHints;
    // Values stated in the new request win, whether they arrive as known
    // parameters or as safety hints.
    final explicit = <String>{
      ...request.knownParameters.keys,
      if (hints.maxVoltageV != null) PlannerKeys.maxVoltageV,
      if (hints.coupling != Coupling.unknown) PlannerKeys.coupling,
      if (hints.mainsReferenced != null) PlannerKeys.mainsReferenced,
      if (hints.floatingDut != null) PlannerKeys.floatingDut,
    };
    final additions = <String, Object?>{};
    for (final entry in _sessionValues.entries) {
      if (!explicit.contains(entry.key)) {
        additions[entry.key] = entry.value;
      }
    }
    if (additions.isEmpty) return request;
    return request.merged(knownParameters: additions);
  }

  Map<String, dynamic> _abort(
    AbortReason reason,
    String message, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {
    return AbortedResult(
      reason: reason,
      message: message,
      details: details,
    ).toJson();
  }
}

/// Wording that proves a user stated a safety fact.
///
/// Safety values without matching evidence are treated as unknown, so the
/// pipeline asks the mandatory question instead of trusting a model guess.
class _SafetyEvidence {
  const _SafetyEvidence({
    required this.maxVoltage,
    required this.coupling,
    required this.mainsReferenced,
    required this.probeAttenuation,
    required this.differentialOrIsolated,
    required this.floatingDut,
  });

  factory _SafetyEvidence.fromText(String text) {
    final lower = text.toLowerCase();
    return _SafetyEvidence(
      maxVoltage: _voltagePattern.hasMatch(lower),
      coupling: _couplingPattern.hasMatch(lower),
      mainsReferenced: _mainsPattern.hasMatch(lower),
      probeAttenuation: _probePattern.hasMatch(lower),
      differentialOrIsolated: _differentialPattern.hasMatch(lower),
      floatingDut: _floatingPattern.hasMatch(lower),
    );
  }

  final bool maxVoltage;
  final bool coupling;
  final bool mainsReferenced;
  final bool probeAttenuation;
  final bool differentialOrIsolated;
  final bool floatingDut;

  /// Whether a model-supplied value for [key] may be trusted.
  bool allows(String key) {
    return switch (key) {
      PlannerKeys.maxVoltageV => maxVoltage,
      PlannerKeys.coupling => coupling,
      PlannerKeys.mainsReferenced => mainsReferenced,
      PlannerKeys.probeAttenuation => probeAttenuation,
      PlannerKeys.differentialOrIsolated => differentialOrIsolated,
      PlannerKeys.floatingDut => floatingDut,
      _ => true,
    };
  }

  /// Returns only the hints that the request text supports.
  SafetyHints trustedHints(SafetyHints hints) {
    return SafetyHints(
      maxVoltageV: maxVoltage ? hints.maxVoltageV : null,
      coupling: coupling ? hints.coupling : Coupling.unknown,
      mainsReferenced: mainsReferenced ? hints.mainsReferenced : null,
      floatingDut: floatingDut ? hints.floatingDut : null,
    );
  }
}

final RegExp _voltagePattern = RegExp(
  r'\d+(?:[.,]\d+)?\s*(?:[µμunmk]?v(?:pp|pk|rms)?|volts?)\b',
);

final RegExp _couplingPattern = RegExp(r'\b(?:ac|dc)\b|koppl|coupl');

final RegExp _mainsPattern = RegExp(
  r'\bnetz\b|\bnetz(?:spannung|anschluss|referenz|gebunden)\b|\bmains\b|'
  r'geerdet|grounded|erdbezogen|mains[- ]referenced',
);

final RegExp _probePattern = RegExp(
  r'\b(?:1x|10x|100x)\b|\b(?:1|10|100)\s*:\s*1\b|tastkopf',
);

final RegExp _differentialPattern = RegExp(r'differential|isoliert|isolated');

final RegExp _floatingPattern = RegExp(r'floating|schwebend|potentialfrei');
