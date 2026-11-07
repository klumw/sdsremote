/// One measurement recipe of the planner catalog.
library;

import '../models/action_plan.dart';
import 'param_spec.dart';

/// Measurement category of a recipe.
enum RecipeType {
  simpleReading(
    'simple_reading',
    PlanType.simpleReading,
    PlanAgent.scopeAnalysis,
  ),
  audio('audio', PlanType.audio, PlanAgent.audioAnalysis),
  digital('digital', PlanType.digital, PlanAgent.digitalAnalysis);

  const RecipeType(this.wireName, this.planType, this.agent);

  /// Wire value used by the plan result.
  final String wireName;

  /// Plan category produced when this recipe is selected.
  final PlanType planType;

  /// Sub-agent that executes the recipe.
  final PlanAgent agent;
}

/// One deterministic measurement recipe.
class Recipe {
  const Recipe({
    required this.id,
    required this.type,
    required this.title,
    required this.focus,
    required this.needsGenerator,
    required this.needsLiveScope,
    required this.parameters,
    required this.estimatedToolCalls,
    required this.requestTemplate,
    required this.manualInstructions,
    required this.expectedOutput,
    required this.setupId,
    this.aliases = const <String>[],
    this.hostManagesGenerator = false,
    this.requiresProtocolDecode = false,
  });

  /// Catalog id used in `MeasurementRequest.measurements`.
  final String id;

  /// Measurement category.
  final RecipeType type;

  /// Short English title.
  final String title;

  /// Focus block passed to the sub-agent.
  final String focus;

  /// Whether the recipe needs the signal generator.
  final bool needsGenerator;

  /// Whether the AudioAgent host sweep provider configures and restores the
  /// generator itself. Such recipes need the generator for the equipment
  /// check but produce no `configure_generator` or teardown step.
  final bool hostManagesGenerator;

  /// Whether a fresh acquisition or live scope state is needed.
  final bool needsLiveScope;

  /// Parameters of the recipe.
  final List<ParamSpec> parameters;

  /// Estimated tool calls inside the executing sub-agent.
  final int estimatedToolCalls;

  /// English instruction template; `{key}` placeholders are substituted from
  /// the recipe parameters.
  final String requestTemplate;

  /// English manual setup instructions; placeholders are allowed.
  final List<String> manualInstructions;

  /// English description of the produced result.
  final String expectedOutput;

  /// Physical setup group. Recipes with different ids cannot be combined in
  /// one plan.
  final String setupId;

  /// English synonyms that help the model map a free-text request to this
  /// recipe, for example `-3 db` and `cutoff` for the frequency response.
  final List<String> aliases;

  /// Whether the recipe needs protocol decoding, which the planner rejects.
  final bool requiresProtocolDecode;

  /// Executing sub-agent.
  PlanAgent get agent => type.agent;

  /// Keys of all parameters.
  List<String> get parameterKeys => <String>[
    for (final parameter in parameters) parameter.key,
  ];

  /// Returns the parameter with [key], or `null`.
  ParamSpec? parameterFor(String key) {
    for (final parameter in parameters) {
      if (parameter.key == key) return parameter;
    }
    return null;
  }

  /// Returns validation errors of this recipe.
  List<String> validate() {
    final errors = <String>[];
    if (id.isEmpty) errors.add('A recipe has an empty id.');
    if (!id.contains('.')) errors.add('Recipe id "$id" has no domain prefix.');
    if (title.trim().isEmpty) errors.add('Recipe "$id" has an empty title.');
    if (focus.trim().isEmpty) errors.add('Recipe "$id" has an empty focus.');
    if (estimatedToolCalls < 1) {
      errors.add('Recipe "$id" needs a positive tool-call estimate.');
    }
    if (requestTemplate.trim().isEmpty) {
      errors.add('Recipe "$id" has an empty request template.');
    }
    final keys = parameterKeys;
    if (keys.toSet().length != keys.length) {
      errors.add('Recipe "$id" has duplicate parameter keys.');
    }
    for (final parameter in parameters) {
      for (final error in parameter.validate()) {
        errors.add('Recipe "$id": $error');
      }
    }
    final declared = keys.toSet();
    for (final placeholder in _placeholders(requestTemplate)) {
      if (!declared.contains(placeholder)) {
        errors.add(
          'Recipe "$id" uses undeclared placeholder "{$placeholder}" in its '
          'request template.',
        );
      }
    }
    for (final instruction in manualInstructions) {
      for (final placeholder in _placeholders(instruction)) {
        if (!declared.contains(placeholder)) {
          errors.add(
            'Recipe "$id" uses undeclared placeholder "{$placeholder}" in a '
            'manual instruction.',
          );
        }
      }
    }
    return errors;
  }

  static Iterable<String> _placeholders(String template) {
    return RegExp(
      r'\{([a-zA-Z0-9_]+)\}',
    ).allMatches(template).map((match) => match.group(1)!);
  }
}
