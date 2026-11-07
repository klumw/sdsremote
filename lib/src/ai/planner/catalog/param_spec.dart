/// One parameter of a measurement recipe.
library;

import '../models/input_form.dart';

/// Input control type of a parameter.
enum ParamType { number, boolean, text, singleChoice, multiChoice }

/// How a parameter value is obtained.
enum ParamSource {
  /// Stated by the user in the request.
  given,

  /// Read from the device at runtime; never asked.
  readable,

  /// Applied from a recorded default.
  defaulted,

  /// Computed from other parameters.
  derived,

  /// Only the user can answer this; it goes into the input form.
  userRequired,

  /// Derived when every dependency is known; otherwise asked in the form.
  ///
  /// Used for values that have a sensible derivation but must never be
  /// silently invented, such as the sweep frequency range.
  askedOrDerived,
}

/// Supported deterministic derivations.
enum Derivation {
  periodFromFrequency,
  vrmsFromVpp,
  vppFromVrms,
  frequencyFromPeriod,
  sweepStartFromCorner,
  sweepStopFromCorner,
}

/// When a parameter is required.
enum SafetyCondition {
  always,
  unknownVoltage,
  voltageAboveWarning,
  mainsReferenced,
  unknownMainsReference,
}

/// Device read that supplies a readable parameter.
class ReadingSpec {
  const ReadingSpec({required this.tool, required this.outputField});

  /// Name of the deterministic tool that returns the value.
  final String tool;

  /// Dot path in the tool result. `{key}` placeholders are substituted with
  /// resolved parameter values, for example `channels.{channel}.vppVolts`.
  final String outputField;
}

/// One parameter of a recipe.
class ParamSpec {
  const ParamSpec({
    required this.key,
    required this.type,
    required this.source,
    required this.priority,
    required this.question,
    this.unit,
    this.min,
    this.max,
    this.options,
    this.defaultValue,
    this.help,
    this.reading,
    this.derive,
    this.dependsOn = const <String>[],
    this.requiredWhen = SafetyCondition.always,
    this.required = true,
  });

  /// Machine key used in answers and plan inputs.
  final String key;

  /// Input control type.
  final ParamType type;

  /// How the value is obtained.
  final ParamSource source;

  /// Ordering hint inside the same question tier; lower comes first.
  final int priority;

  /// English question or label.
  final String question;

  /// Unit shown next to a number field.
  final String? unit;

  /// Inclusive minimum.
  final num? min;

  /// Inclusive maximum.
  final num? max;

  /// Options of a choice parameter.
  final List<InputOption>? options;

  /// Value applied when the parameter is not given.
  ///
  /// For [ParamSource.askedOrDerived] the value is only a form prefill; the
  /// user still confirms or replaces it.
  final Object? defaultValue;

  /// Optional English help text.
  final String? help;

  /// Device read that supplies a readable parameter.
  final ReadingSpec? reading;

  /// Derivation rule of a derived parameter.
  final Derivation? derive;

  /// Keys that must be resolved before a derivation can run.
  final List<String> dependsOn;

  /// Condition under which the parameter is required.
  final SafetyCondition requiredWhen;

  /// Whether a missing value for a `given` parameter is asked in the form.
  ///
  /// Optional parameters such as an expected cutoff are used when the user
  /// states them but never block the plan.
  final bool required;

  /// Converts this parameter into a form question.
  InputQuestion toInputQuestion({String? validationMessage}) {
    return InputQuestion(
      key: key,
      label: question,
      help: validationMessage ?? help,
      type: switch (type) {
        ParamType.number => InputQuestionType.number,
        ParamType.boolean => InputQuestionType.boolean,
        ParamType.text => InputQuestionType.text,
        ParamType.singleChoice => InputQuestionType.singleChoice,
        ParamType.multiChoice => InputQuestionType.multiChoice,
      },
      options: options,
      unit: unit,
      min: min,
      max: max,
      defaultValue: defaultValue,
      required: required,
    );
  }

  /// Returns validation errors of this specification.
  List<String> validate() {
    final errors = <String>[];
    if (key.isEmpty) errors.add('A parameter has an empty key.');
    if (question.trim().isEmpty) {
      errors.add('Parameter "$key" has an empty question.');
    }
    if (type == ParamType.singleChoice || type == ParamType.multiChoice) {
      if (options == null || options!.isEmpty) {
        errors.add('Choice parameter "$key" needs options.');
      }
    }
    switch (source) {
      case ParamSource.readable:
        if (reading == null) {
          errors.add('Readable parameter "$key" needs a reading spec.');
        }
      case ParamSource.defaulted:
        if (defaultValue == null) {
          errors.add('Default parameter "$key" needs a default value.');
        }
      case ParamSource.askedOrDerived:
        break;
      case ParamSource.derived:
        if (derive == null) {
          errors.add('Derived parameter "$key" needs a derivation rule.');
        }
      case ParamSource.given:
      case ParamSource.userRequired:
        break;
    }
    if (source != ParamSource.readable && reading != null) {
      errors.add('Parameter "$key" has a reading spec but is not readable.');
    }
    final derivationAllowed =
        source == ParamSource.derived ||
        (source == ParamSource.defaulted && derive != null) ||
        (source == ParamSource.askedOrDerived && derive != null);
    if (!derivationAllowed && derive != null) {
      errors.add(
        'Parameter "$key" has a derivation but is neither derived nor a '
        'derived default.',
      );
    }
    if (derive != null && dependsOn.isEmpty) {
      errors.add('Parameter "$key" has a derivation without dependencies.');
    }
    final minimum = min;
    final maximum = max;
    if (minimum != null && maximum != null && minimum > maximum) {
      errors.add('Parameter "$key" has min > max.');
    }
    return errors;
  }
}
