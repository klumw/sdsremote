import 'package:flutter/material.dart';

import '../ai/measurement_form.dart';
import '../ai/planner/models/input_form.dart';
import 'scroll_hint.dart';

/// Bundled measurement form rendered above the chat input line.
///
/// The widget is presentation-only: it reads and writes the
/// [MeasurementFormController], which owns the pending form and its answers.
class MeasurementFormPrompt extends StatelessWidget {
  const MeasurementFormPrompt({super.key, required this.controller});

  /// Controller that owns the visible form.
  final MeasurementFormController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final form = controller.form;
        if (form == null) return const SizedBox.shrink();
        return Container(
          key: const ValueKey('measurement-form-prompt'),
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF10263D),
            border: Border.all(
              color: Colors.lightBlueAccent.withValues(alpha: 0.55),
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.lightBlueAccent.withValues(alpha: 0.12),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.assignment_outlined,
                      size: 18,
                      color: Colors.lightBlueAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        form.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cancel form',
                      onPressed: controller.cancel,
                      icon: const Icon(Icons.close, size: 16),
                      color: Colors.white54,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                ScrollHint(
                  maxHeight: 360,
                  background: const Color(0xFF10263D),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final question in form.questions)
                        _QuestionField(
                          controller: controller,
                          question: question,
                          formId: form.formId,
                        ),
                    ],
                  ),
                ),
                if (controller.validationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      controller.validationError!,
                      style: const TextStyle(
                        color: Color(0xFFFF8A80),
                        fontSize: 11,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      key: const ValueKey('measurement-form-cancel'),
                      onPressed: controller.cancel,
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey('measurement-form-submit'),
                      onPressed: controller.canSubmit
                          ? controller.submit
                          : null,
                      child: const Text(
                        'Submit',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuestionField extends StatelessWidget {
  const _QuestionField({
    required this.controller,
    required this.question,
    required this.formId,
  });

  final MeasurementFormController controller;
  final InputQuestion question;
  final String formId;

  @override
  Widget build(BuildContext context) {
    final key = question.key;
    final value = controller.valueFor(key);
    final unknown = controller.isUnknown(key);
    return Padding(
      key: ValueKey('measurement-form-question-$key'),
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            question.required ? '${question.label} *' : question.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          if (question.help != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                question.help!,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ),
          const SizedBox(height: 4),
          if (unknown)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Not known',
                style: TextStyle(
                  color: Colors.lightBlueAccent,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            _input(value),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('measurement-form-unknown-$key'),
              onPressed: () => controller.setUnknown(key, !unknown),
              icon: Icon(
                unknown ? Icons.undo : Icons.help_outline,
                size: 14,
                color: Colors.white54,
              ),
              label: Text(
                unknown ? 'Enter a value' : 'I do not know',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _input(Object? value) {
    switch (question.type) {
      case InputQuestionType.singleChoice:
        return RadioGroup<String>(
          groupValue: value is String ? value : null,
          onChanged: (selected) {
            if (selected != null) controller.setValue(question.key, selected);
          },
          child: Column(
            children: <Widget>[
              for (final option in question.options ?? const <InputOption>[])
                RadioListTile<String>(
                  key: ValueKey(
                    'measurement-form-option-${question.key}-${option.value}',
                  ),
                  value: option.value,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  activeColor: Colors.lightBlueAccent,
                  title: Text(
                    option.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ),
            ],
          ),
        );
      case InputQuestionType.multiChoice:
        final selected = value is List
            ? value.whereType<String>().toSet()
            : <String>{};
        return Column(
          children: <Widget>[
            for (final option in question.options ?? const <InputOption>[])
              CheckboxListTile(
                key: ValueKey(
                  'measurement-form-option-${question.key}-${option.value}',
                ),
                value: selected.contains(option.value),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Colors.lightBlueAccent,
                title: Text(
                  option.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
                onChanged: (checked) {
                  final current = <String>[...selected];
                  if (checked == true) {
                    if (!current.contains(option.value)) {
                      current.add(option.value);
                    }
                  } else {
                    current.remove(option.value);
                  }
                  controller.setValue(question.key, current);
                },
              ),
          ],
        );
      case InputQuestionType.number:
        return TextFormField(
          key: ValueKey('measurement-form-input-${question.key}-$formId'),
          initialValue: value is num
              ? _formatNumber(value)
              : value is String
              ? value
              : '',
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          style: const TextStyle(color: Colors.white, fontSize: 12.5),
          decoration: _decoration(
            unit: question.unit,
            hint: question.unit == null ? 'Value' : 'Value in ${question.unit}',
          ),
          onChanged: (text) {
            controller.setValue(question.key, double.tryParse(text.trim()));
          },
        );
      case InputQuestionType.text:
        return TextFormField(
          key: ValueKey('measurement-form-input-${question.key}-$formId'),
          initialValue: value is String ? value : '',
          style: const TextStyle(color: Colors.white, fontSize: 12.5),
          decoration: _decoration(),
          onChanged: (text) => controller.setValue(question.key, text),
        );
      case InputQuestionType.boolean:
        return SegmentedButton<bool>(
          key: ValueKey('measurement-form-input-${question.key}'),
          segments: const <ButtonSegment<bool>>[
            ButtonSegment<bool>(value: true, label: Text('Yes')),
            ButtonSegment<bool>(value: false, label: Text('No')),
          ],
          selected: <bool>{if (value is bool) value},
          emptySelectionAllowed: true,
          style: SegmentedButton.styleFrom(
            foregroundColor: Colors.white70,
            selectedForegroundColor: Colors.white,
            selectedBackgroundColor: Colors.lightBlueAccent.withValues(
              alpha: 0.35,
            ),
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 11.5),
          ),
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              controller.setValue(question.key, selection.first);
            }
          },
        );
    }
  }

  static InputDecoration _decoration({String? unit, String? hint}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: const BorderSide(color: Colors.white24),
    );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: const Color(0xFF0B1B2B),
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
      suffixText: unit,
      suffixStyle: const TextStyle(color: Colors.white54, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: Colors.lightBlueAccent),
      ),
    );
  }

  static String _formatNumber(num value) {
    if (value == value.roundToDouble() && value.abs() < 1e15) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}
