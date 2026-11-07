/// Deterministic comparison of a translated input form with the canonical one.
///
/// The WaveformAgent may translate the title, question labels and help texts.
/// It may not change machine fields. This guard rejects any difference in
/// question count, keys, types, option values, ranges or units and rebuilds
/// the canonical form with only the translated texts applied.
library;

import '../models/input_form.dart';
import '../models/json_value.dart';

/// Result of the guard.
class GuardedForm {
  const GuardedForm.ok(InputForm this.form) : error = null, field = null;

  const GuardedForm.rejected(this.error, {this.field}) : form = null;

  /// Canonical form with translated texts, when the translation is valid.
  final InputForm? form;

  /// English rejection reason.
  final String? error;

  /// JSON field that was rejected.
  final String? field;

  /// Whether the translation was accepted.
  bool get isOk => form != null;
}

/// Validates [translated] against [canonical] and applies the translated
/// texts to the canonical machine fields.
GuardedForm guardTranslatedForm({
  required InputForm canonical,
  required Map<String, dynamic> translated,
}) {
  final formId = translated['formId'];
  if (formId != null && formId != canonical.formId) {
    return const GuardedForm.rejected(
      'The form id must not change.',
      field: 'formId',
    );
  }

  final rawQuestions = translated['questions'];
  if (rawQuestions is! List) {
    return const GuardedForm.rejected(
      'questions must be an array.',
      field: 'questions',
    );
  }
  if (rawQuestions.length != canonical.questions.length) {
    return GuardedForm.rejected(
      'The form must contain exactly ${canonical.questions.length} '
      'questions.',
      field: 'questions',
    );
  }

  final labels = <String, String>{};
  final helps = <String, String?>{};
  for (var index = 0; index < canonical.questions.length; index++) {
    final question = canonical.questions[index];
    final raw = rawQuestions[index];
    if (raw is! Map) {
      return GuardedForm.rejected(
        'Question ${index + 1} must be an object.',
        field: 'questions[$index]',
      );
    }
    final map = requireJsonMap(raw, 'questions[$index]');
    final field = 'questions[$index]';

    if (map['key'] != question.key) {
      return GuardedForm.rejected(
        'Question ${index + 1} must have the key "${question.key}".',
        field: '$field.key',
      );
    }

    final type = map['type'];
    if (type != null && type != question.type.wireName) {
      return GuardedForm.rejected(
        'The type of question "${question.key}" must not change.',
        field: '$field.type',
      );
    }

    final options = map['options'];
    if (options != null) {
      if (options is! List) {
        return GuardedForm.rejected(
          'The options of question "${question.key}" must be an array.',
          field: '$field.options',
        );
      }
      final expected = <String>[
        for (final option in question.options ?? const <InputOption>[])
          option.value,
      ];
      final actual = <String>[];
      for (final entry in options) {
        if (entry is! Map) {
          return GuardedForm.rejected(
            'Each option of question "${question.key}" must be an object.',
            field: '$field.options',
          );
        }
        final value = entry['value'];
        if (value is! String) {
          return GuardedForm.rejected(
            'Each option of question "${question.key}" needs a string value.',
            field: '$field.options',
          );
        }
        actual.add(value);
      }
      if (expected.join('\u0000') != actual.join('\u0000')) {
        return GuardedForm.rejected(
          'The option values of question "${question.key}" must not change.',
          field: '$field.options',
        );
      }
    }

    if (map.containsKey('unit') && map['unit'] != question.unit) {
      return GuardedForm.rejected(
        'The unit of question "${question.key}" must not change.',
        field: '$field.unit',
      );
    }
    if (map.containsKey('min') && !_sameNumber(map['min'], question.min)) {
      return GuardedForm.rejected(
        'The minimum of question "${question.key}" must not change.',
        field: '$field.min',
      );
    }
    if (map.containsKey('max') && !_sameNumber(map['max'], question.max)) {
      return GuardedForm.rejected(
        'The maximum of question "${question.key}" must not change.',
        field: '$field.max',
      );
    }
    if (map.containsKey('required') && map['required'] != question.required) {
      return GuardedForm.rejected(
        'The required flag of question "${question.key}" must not change.',
        field: '$field.required',
      );
    }

    final label = map['label'];
    if (label is! String || label.trim().isEmpty) {
      return GuardedForm.rejected(
        'Question "${question.key}" needs a translated label.',
        field: '$field.label',
      );
    }
    labels[question.key] = label.trim();

    final help = map['help'];
    if (help != null && help is! String) {
      return GuardedForm.rejected(
        'The help of question "${question.key}" must be a string.',
        field: '$field.help',
      );
    }
    helps[question.key] = help as String?;
  }

  final rawTitle = translated['title'];
  if (rawTitle != null && rawTitle is! String) {
    return const GuardedForm.rejected(
      'The title must be a string.',
      field: 'title',
    );
  }
  final title = rawTitle is String && rawTitle.trim().isNotEmpty
      ? rawTitle.trim()
      : canonical.title;

  return GuardedForm.ok(
    InputForm(
      formId: canonical.formId,
      title: title,
      questions: <InputQuestion>[
        for (final question in canonical.questions)
          InputQuestion(
            key: question.key,
            label: labels[question.key]!,
            help: helps[question.key] ?? question.help,
            type: question.type,
            options: question.options,
            unit: question.unit,
            min: question.min,
            max: question.max,
            defaultValue: question.defaultValue,
            required: question.required,
          ),
      ],
    ),
  );
}

bool _sameNumber(Object? actual, num? expected) {
  if (actual == null) return expected == null;
  if (actual is num) {
    return expected != null && actual.toDouble() == expected.toDouble();
  }
  return false;
}
