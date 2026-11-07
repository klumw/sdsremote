/// Bundled measurement form shown inside the chat.
///
/// The controller owns one pending [InputForm] and one `Completer`, exactly
/// like `ChatChoicePromptController`. The `present_input_form` tool awaits the
/// future; the chat panel renders the visible state.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'planner/models/input_form.dart';

/// Answer of one bundled measurement form.
class MeasurementFormResult {
  const MeasurementFormResult.submitted(this.answers) : cancelled = false;

  const MeasurementFormResult.cancelled()
    : answers = const <String, Object?>{},
      cancelled = true;

  /// Answers keyed by question key.
  final Map<String, Object?> answers;

  /// Whether the user cancelled the form.
  final bool cancelled;
}

/// Waits for the user to fill [form].
typedef MeasurementFormProvider =
    Future<MeasurementFormResult> Function(InputForm form);

/// Owns the pending measurement form and its answers.
class MeasurementFormController extends ChangeNotifier {
  InputForm? _form;
  Completer<MeasurementFormResult>? _pending;
  final Map<String, Object?> _values = <String, Object?>{};
  final Set<String> _unknown = <String>{};
  String? _validationError;
  bool _disposed = false;

  /// Whether a form is currently waiting for the user.
  bool get isVisible => _form != null;

  /// The visible form, or `null`.
  InputForm? get form => _form;

  /// Current answers, including applied defaults.
  Map<String, Object?> get answers =>
      Map<String, Object?>.unmodifiable(_values);

  /// Whether [key] is marked as unknown.
  bool isUnknown(String key) => _unknown.contains(key);

  /// Current value of [key].
  Object? valueFor(String key) => _values[key];

  /// Validation message shown under the form, or `null`.
  String? get validationError => _validationError;

  /// Whether every required question has a valid answer.
  bool get canSubmit {
    final form = _form;
    if (form == null) return false;
    for (final question in form.questions) {
      if (!question.required) continue;
      if (_unknown.contains(question.key)) continue;
      if (question.validateAnswer(_values[question.key]) != null) {
        return false;
      }
    }
    return true;
  }

  /// Shows [form] and completes with the user's answers or a cancellation.
  Future<MeasurementFormResult> requestForm(InputForm form) {
    if (_disposed) {
      return Future<MeasurementFormResult>.value(
        const MeasurementFormResult.cancelled(),
      );
    }
    final current = _form;
    if (current != null && current.formId == form.formId && _pending != null) {
      return _pending!.future;
    }
    if (_pending != null) {
      _complete(const MeasurementFormResult.cancelled());
    }

    _form = form;
    _values.clear();
    _unknown.clear();
    _validationError = null;
    for (final question in form.questions) {
      if (question.defaultValue != null) {
        _values[question.key] = question.defaultValue;
      }
    }
    final completer = Completer<MeasurementFormResult>();
    _pending = completer;
    notifyListeners();
    return completer.future;
  }

  /// Sets the answer of [key] and clears an unknown marker.
  void setValue(String key, Object? value) {
    final form = _form;
    if (_disposed || form == null || form.questionFor(key) == null) return;
    _unknown.remove(key);
    _values[key] = value;
    _validationError = null;
    notifyListeners();
  }

  /// Marks [key] as known or unknown.
  void setUnknown(String key, bool unknown) {
    final form = _form;
    if (_disposed || form == null || form.questionFor(key) == null) return;
    if (unknown) {
      _unknown.add(key);
      _values[key] = unknownAnswerValue;
    } else {
      _unknown.remove(key);
      _values.remove(key);
    }
    _validationError = null;
    notifyListeners();
  }

  /// Validates and submits the form.
  void submit() {
    final form = _form;
    final pending = _pending;
    if (_disposed || form == null || pending == null) return;
    final submitted = <String, Object?>{};
    for (final question in form.questions) {
      if (_unknown.contains(question.key)) {
        submitted[question.key] = unknownAnswerValue;
        continue;
      }
      final value = _values[question.key];
      final error = question.validateAnswer(value);
      if (error != null) {
        _validationError = error;
        notifyListeners();
        return;
      }
      submitted[question.key] = value;
    }
    _complete(MeasurementFormResult.submitted(submitted));
  }

  /// Cancels the form.
  void cancel() {
    if (_disposed || _form == null) return;
    _complete(const MeasurementFormResult.cancelled());
  }

  /// Cancels a pending form regardless of how it was opened.
  ///
  /// Used when the chat is cleared, the request is cancelled or the controller
  /// is disposed, so a waiting tool never blocks forever.
  void dismissPending() => cancel();

  /// Forgets the answers of the current form.
  void clearSession() {
    if (_disposed || (_values.isEmpty && _unknown.isEmpty)) return;
    _values.clear();
    _unknown.clear();
    _validationError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final pending = _pending;
    _pending = null;
    _form = null;
    _values.clear();
    _unknown.clear();
    if (pending != null && !pending.isCompleted) {
      pending.complete(const MeasurementFormResult.cancelled());
    }
    super.dispose();
  }

  void _complete(MeasurementFormResult result) {
    final pending = _pending;
    _pending = null;
    _form = null;
    _values.clear();
    _unknown.clear();
    _validationError = null;
    if (!_disposed) notifyListeners();
    if (pending != null && !pending.isCompleted) {
      pending.complete(result);
    }
  }
}
