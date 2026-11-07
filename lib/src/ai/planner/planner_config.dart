/// Budgets, limits and reserved parameter keys of the planner.
///
/// All values are typed constants so the pipeline behaviour is reviewable in
/// one place. The numeric defaults are covered by tests and documented in
/// `PLANNER.md`.
library;

import 'models/action_plan.dart';
import 'models/input_form.dart';

/// Budgets and limits used by every planner stage.
class PlannerConfig {
  const PlannerConfig({
    this.maxFormQuestions = hardMaxFormQuestions,
    this.maxFormRounds = 3,
    this.maxStepsPerSubAgent = 2,
    this.maxChannels = 4,
    this.callLimitMargin = 4,
    this.totalToolCallBudget = 60,
    this.stepOverheadToolCalls = 2,
    this.maxPlanSteps = 24,
    this.plannerInvocationsPerTurn = 8,
    this.plannerModelToolCalls = 6,
    this.maxStoredPlans = 2,
    this.agentCallLimits = const <PlanAgent, int>{
      PlanAgent.scopeAnalysis: 24,
      PlanAgent.audioAnalysis: 22,
      PlanAgent.digitalAnalysis: 26,
      PlanAgent.scpiInstrument: 8,
    },
  });

  /// Default configuration used in production and tests.
  static const PlannerConfig defaults = PlannerConfig();

  /// Maximum number of questions in one bundled form.
  final int maxFormQuestions;

  /// Maximum number of form rounds before `input_incomplete`.
  final int maxFormRounds;

  /// Maximum number of steps per executing sub-agent.
  final int maxStepsPerSubAgent;

  /// Maximum number of distinct scope channels in one plan.
  final int maxChannels;

  /// Tool calls reserved inside each sub-agent for reasoning and submission.
  final int callLimitMargin;

  /// Upper bound for the summed tool-call estimates of one request.
  final int totalToolCallBudget;

  /// Tool-call overhead of one delegation step.
  final int stepOverheadToolCalls;

  /// Maximum number of steps in one action plan.
  final int maxPlanSteps;

  /// Maximum number of planner invocations per user request.
  final int plannerInvocationsPerTurn;

  /// Maximum number of tool calls inside the PlannerAgent model.
  final int plannerModelToolCalls;

  /// Number of stored plans kept for execution.
  final int maxStoredPlans;

  /// Tool-call limits of the executing sub-agents.
  ///
  /// The instrument value is 8 because that is the limit `WaveformAgent`
  /// passes to its `InstrumentAgent`; a test pins this against
  /// `WaveformAgent.defaultInstrumentToolCalls`.
  final Map<PlanAgent, int> agentCallLimits;

  /// Tool-call limit of [agent], or 0 when the agent is not a sub-agent.
  int callLimitFor(PlanAgent agent) => agentCallLimits[agent] ?? 0;

  /// Usable tool-call budget of [agent] after reserving [callLimitMargin].
  int usableCallBudgetFor(PlanAgent agent) {
    final limit = callLimitFor(agent);
    if (limit <= 0) return 0;
    final usable = limit - callLimitMargin;
    return usable > 0 ? usable : 1;
  }

  /// Returns configuration errors; an empty list means the config is valid.
  List<String> validate() {
    final errors = <String>[];
    if (maxFormQuestions < 1 || maxFormQuestions > hardMaxFormQuestions) {
      errors.add(
        'maxFormQuestions must be between 1 and $hardMaxFormQuestions.',
      );
    }
    if (maxFormRounds < 1) errors.add('maxFormRounds must be positive.');
    if (maxStepsPerSubAgent < 1) {
      errors.add('maxStepsPerSubAgent must be positive.');
    }
    if (maxChannels < 1 || maxChannels > 4) {
      errors.add('maxChannels must be between 1 and 4.');
    }
    if (callLimitMargin < 0) {
      errors.add('callLimitMargin must not be negative.');
    }
    if (stepOverheadToolCalls < 0) {
      errors.add('stepOverheadToolCalls must not be negative.');
    }
    if (totalToolCallBudget < 1) {
      errors.add('totalToolCallBudget must be positive.');
    }
    if (maxPlanSteps < 1) errors.add('maxPlanSteps must be positive.');
    if (plannerInvocationsPerTurn < 1) {
      errors.add('plannerInvocationsPerTurn must be positive.');
    }
    if (plannerModelToolCalls < 1) {
      errors.add('plannerModelToolCalls must be positive.');
    }
    if (maxStoredPlans < 1) errors.add('maxStoredPlans must be positive.');
    for (final entry in agentCallLimits.entries) {
      if (entry.value < 1) {
        errors.add('Agent ${entry.key.wireName} needs a positive call limit.');
      }
    }
    return errors;
  }
}

/// Reserved parameter keys shared by the catalog, form and plan builder.
abstract final class PlannerKeys {
  static const String maxVoltageV = 'maxVoltageV';
  static const String coupling = 'coupling';
  static const String mainsReferenced = 'mainsReferenced';
  static const String floatingDut = 'floatingDut';
  static const String probeAttenuation = 'probeAttenuation';
  static const String differentialOrIsolated = 'differentialOrIsolated';
  static const String channel = 'channel';
  static const String channelB = 'channelB';
  static const String generatorChannel = 'generatorChannel';
  static const String generatorWaveform = 'generatorWaveform';
  static const String frequencyHz = 'frequencyHz';
  static const String amplitudeVpp = 'amplitudeVpp';
  static const String offsetV = 'offsetV';
  static const String dutyPercent = 'dutyPercent';
  static const String phaseDeg = 'phaseDeg';
  static const String startFrequencyHz = 'startFrequencyHz';
  static const String stopFrequencyHz = 'stopFrequencyHz';
  static const String expectedCornerFrequencyHz = 'expectedCornerFrequencyHz';
  static const String pointCount = 'pointCount';
  static const String loadImpedanceOhm = 'loadImpedanceOhm';
  static const String logicFamily = 'logicFamily';
}

/// Wire name of the `other:<text>` escape hatch for uncatalogued measurements.
const String otherMeasurementPrefix = 'other:';
