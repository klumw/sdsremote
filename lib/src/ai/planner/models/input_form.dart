/// Bundled input form returned by a `needs_input` planner result.
library;

import 'json_value.dart';

/// Reserved value the user interface sends for a question the user cannot
/// answer. The planner turns it into a `user_input_unknown` abort.
const String unknownAnswerValue = '__unknown__';

/// Reserved key the user interface sends when the user cancels the form.
const String cancelledAnswerKey = '__cancelled__';

/// Hard upper bound of questions in one form.
///
/// `PlannerConfig.maxFormQuestions` defaults to this value; a test asserts
/// that both stay in sync.
const int hardMaxFormQuestions = 5;

/// Input control type of a form question.
enum InputQuestionType {
  singleChoice('single_choice'),
  multiChoice('multi_choice'),
  number('number'),
  text('text'),
  boolean('boolean');

  const InputQuestionType(this.wireName);

  /// Wire value used by the tool schema and the UI.
  final String wireName;

  static InputQuestionType fromWire(Object? value) {
    for (final type in values) {
      if (type.wireName == value) return type;
    }
    throw PlannerFormatException(
      'type',
      'single_choice|multi_choice|number|text|boolean',
      value,
    );
  }
}

/// One selectable option of a choice question.
class InputOption {
  const InputOption({required this.value, required this.label});

  /// Machine-readable value returned to the planner.
  final String value;

  /// Human-readable label translated by the WaveformAgent.
  final String label;

  factory InputOption.fromMap(Map<String, dynamic> map, String field) {
    return InputOption(
      value: requireJsonString(map['value'], '$field.value'),
      label: requireJsonString(map['label'], '$field.label'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'value': value,
    'label': label,
  };
}

/// One question of an [InputForm].
class InputQuestion {
  const InputQuestion({
    required this.key,
    required this.label,
    required this.type,
    this.help,
    this.options,
    this.unit,
    this.min,
    this.max,
    this.defaultValue,
    this.required = true,
  });

  /// Stable machine key used in the answers map.
  final String key;

  /// English question text; translated by the WaveformAgent.
  final String label;

  /// Optional English help text; translated by the WaveformAgent.
  final String? help;

  /// UI control type.
  final InputQuestionType type;

  /// Options for the two choice types.
  final List<InputOption>? options;

  /// Unit shown next to a number field.
  final String? unit;

  /// Inclusive minimum of a number answer.
  final num? min;

  /// Inclusive maximum of a number answer.
  final num? max;

  /// Value prefilled by the UI.
  final Object? defaultValue;

  /// Whether an answer is required before submission.
  final bool required;

  factory InputQuestion.fromMap(Map<String, dynamic> map, String field) {
    final type = InputQuestionType.fromWire(map['type']);
    final rawOptions = optionalJsonList(map['options'], '$field.options');
    final options = rawOptions == null
        ? null
        : <InputOption>[
            for (var index = 0; index < rawOptions.length; index++)
              InputOption.fromMap(
                requireJsonMap(rawOptions[index], '$field.options[$index]'),
                '$field.options[$index]',
              ),
          ];
    if ((type == InputQuestionType.singleChoice ||
            type == InputQuestionType.multiChoice) &&
        (options == null || options.isEmpty)) {
      throw PlannerFormatException(
        '$field.options',
        'non-empty array for a choice question',
        rawOptions,
      );
    }
    return InputQuestion(
      key: requireJsonString(map['key'], '$field.key'),
      label: requireJsonString(map['label'], '$field.label'),
      help: optionalJsonString(map['help'], '$field.help'),
      type: type,
      options: options,
      unit: optionalJsonString(map['unit'], '$field.unit'),
      min: optionalJsonDouble(map['min'], '$field.min'),
      max: optionalJsonDouble(map['max'], '$field.max'),
      defaultValue: jsonSafe(map['defaultValue'], '$field.defaultValue'),
      required: optionalJsonBool(map['required'], '$field.required') ?? true,
    );
  }

  /// Validates one answer value and returns an English error, or `null`.
  ///
  /// The unknown sentinel is accepted here: the pipeline converts it into the
  /// `user_input_unknown` abort, not a validation failure.
  String? validateAnswer(Object? value) {
    if (value == null) {
      return required ? 'This answer is required.' : null;
    }
    if (value == unknownAnswerValue) return null;
    switch (type) {
      case InputQuestionType.singleChoice:
        if (value is! String) return 'Choose one of the listed options.';
        final options = this.options ?? const <InputOption>[];
        if (!options.any((option) => option.value == value)) {
          return 'Choose one of the listed options.';
        }
        return null;
      case InputQuestionType.multiChoice:
        if (value is! List) return 'Choose at least one listed option.';
        final options = this.options ?? const <InputOption>[];
        final allowed = options.map((option) => option.value).toSet();
        for (final entry in value) {
          if (entry is! String || !allowed.contains(entry)) {
            return 'Choose only listed options.';
          }
        }
        if (required && value.isEmpty) return 'Choose at least one option.';
        return null;
      case InputQuestionType.number:
        if (value is! num) return 'Enter a number.';
        if (!value.isFinite) return 'Enter a finite number.';
        final minimum = min;
        if (minimum != null && value < minimum) {
          return 'Enter a value of at least $minimum.';
        }
        final maximum = max;
        if (maximum != null && value > maximum) {
          return 'Enter a value of at most $maximum.';
        }
        return null;
      case InputQuestionType.text:
        if (value is! String) return 'Enter text.';
        if (required && value.trim().isEmpty) return 'This answer is required.';
        return null;
      case InputQuestionType.boolean:
        if (value is! bool) return 'Choose yes or no.';
        return null;
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'label': label,
    if (help != null) 'help': help,
    'type': type.wireName,
    if (options != null)
      'options': [for (final option in options!) option.toJson()],
    if (unit != null) 'unit': unit,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
    if (defaultValue != null) 'defaultValue': defaultValue,
    'required': required,
  };
}

/// One bundled form shown by the chat UI.
class InputForm {
  InputForm({
    required this.formId,
    required this.title,
    required this.questions,
  }) {
    if (questions.isEmpty) {
      throw ArgumentError.value(
        questions,
        'questions',
        'A form needs questions',
      );
    }
    if (questions.length > hardMaxFormQuestions) {
      throw ArgumentError.value(
        questions.length,
        'questions',
        'At most $hardMaxFormQuestions questions are allowed',
      );
    }
    final keys = <String>{};
    for (final question in questions) {
      if (!keys.add(question.key)) {
        throw ArgumentError.value(question.key, 'questions', 'Duplicate key');
      }
    }
  }

  /// Stable identifier of this form.
  final String formId;

  /// English title; translated by the WaveformAgent.
  final String title;

  /// Questions in display order.
  final List<InputQuestion> questions;

  factory InputForm.fromMap(Map<String, dynamic> map) {
    final rawQuestions = requireJsonList(map['questions'], 'questions');
    return InputForm(
      formId: requireJsonString(map['formId'], 'formId'),
      title: requireJsonString(map['title'], 'title'),
      questions: <InputQuestion>[
        for (var index = 0; index < rawQuestions.length; index++)
          InputQuestion.fromMap(
            requireJsonMap(rawQuestions[index], 'questions[$index]'),
            'questions[$index]',
          ),
      ],
    );
  }

  /// Returns the question with [key], or `null`.
  InputQuestion? questionFor(String key) {
    for (final question in questions) {
      if (question.key == key) return question;
    }
    return null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'formId': formId,
    'title': title,
    'questions': [for (final question in questions) question.toJson()],
  };
}
