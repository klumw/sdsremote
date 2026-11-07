import 'dart:async';

import 'package:flutter/foundation.dart';

/// One selectable option of a chat choice prompt.
class ChatChoiceOption {
  const ChatChoiceOption({
    required this.value,
    required this.label,
    this.description,
    this.rememberForSession = false,
  });

  /// Machine-readable value returned to the AI tool.
  final String value;

  /// Text shown next to the radio button.
  final String label;

  /// Optional explanation shown below the label.
  final String? description;

  /// Whether selecting this option remembers the answer for the rest of the
  /// chat session.
  ///
  /// Later requests with the same [ChatChoiceRequest.id] return this value
  /// immediately without showing the prompt again. This is how a session-wide
  /// permission grant is implemented without asking the user repeatedly.
  final bool rememberForSession;
}

/// A question shown as a radio-button prompt inside the chat.
class ChatChoiceRequest {
  const ChatChoiceRequest({
    required this.question,
    required this.options,
    this.id,
    this.allowCancel = true,
    this.allowText = false,
    this.textLabel,
    this.textHint,
    this.textSubmitLabel,
  });

  /// Stable identifier used to remember a session-wide answer.
  ///
  /// Required when one of [options] sets
  /// [ChatChoiceOption.rememberForSession].
  final String? id;

  /// Question shown above the radio buttons.
  final String question;

  /// Available choices; at least two are required.
  final List<ChatChoiceOption> options;

  /// Whether the user may dismiss the prompt without an answer.
  final bool allowCancel;

  /// Whether the prompt offers a free-text field in addition to the options.
  ///
  /// The field lets the user correct a value or give an answer that is not
  /// covered by the options. When it contains text, the prompt returns that
  /// text instead of the selected option; the field therefore takes precedence
  /// over a radio-button selection.
  final bool allowText;

  /// Label of the free-text field, already translated for the user.
  final String? textLabel;

  /// Placeholder of the free-text field, already translated for the user.
  final String? textHint;

  /// Label of the button that submits the free-text value.
  final String? textSubmitLabel;

  /// Returns the option with [value], or null when it does not exist.
  ChatChoiceOption? optionFor(String value) {
    for (final option in options) {
      if (option.value == value) return option;
    }
    return null;
  }

  /// Whether at least one option can be remembered for the session.
  bool get remembersSession =>
      id != null && options.any((option) => option.rememberForSession);
}

/// Answer of a [ChatChoiceRequest].
class ChatChoiceResult {
  const ChatChoiceResult({
    this.value,
    this.label,
    this.text,
    this.cancelled = false,
  });

  /// Selected option value, or null when the user cancelled or submitted text.
  final String? value;

  /// Selected option label, or null when the user cancelled or submitted text.
  final String? label;

  /// Free-text correction or answer, or null when no text was submitted.
  final String? text;

  /// Whether the user dismissed the prompt without an answer.
  final bool cancelled;
}

/// Owns the pending radio-button prompt and the session-wide answers.
///
/// The controller is reusable by any chat: the owning chat controller asks
/// [requestChoice] from an AI tool and renders the visible state in its panel
/// with the shared `ChatChoicePrompt` widget. [clearSession] discards the
/// remembered answers.
class ChatChoicePromptController extends ChangeNotifier {
  final Map<String, String> _sessionChoices = <String, String>{};

  ChatChoiceRequest? _request;
  String? _selectedValue;
  String _text = '';
  Completer<ChatChoiceResult>? _pending;
  bool _disposed = false;

  /// Whether a prompt is currently waiting for the user's answer.
  bool get isVisible => _request != null;

  /// The visible prompt, or null.
  ChatChoiceRequest? get request => _request;

  /// Value of the currently selected radio button, or null.
  String? get selectedValue => _selectedValue;

  /// Current free-text value, or an empty string.
  String get text => _text;

  /// Whether the user entered text or selected an option that can be
  /// submitted.
  bool get canSubmit =>
      _selectedValue != null ||
      (_request?.allowText == true && _text.trim().isNotEmpty);

  /// Shows [request] and completes with the user's answer.
  ///
  /// When a session-wide answer was remembered for [ChatChoiceRequest.id],
  /// the future completes immediately and no prompt is shown.
  Future<ChatChoiceResult> requestChoice(ChatChoiceRequest request) async {
    if (_disposed) return const ChatChoiceResult(cancelled: true);

    final id = request.id;
    if (id != null) {
      final remembered = _sessionChoices[id];
      if (remembered != null) {
        final option = request.optionFor(remembered);
        if (option != null) {
          return ChatChoiceResult(value: option.value, label: option.label);
        }
      }
    }

    // A new request replaces a prompt that is still open. Tool calls are
    // normally sequential, so this only guards against a concurrent call.
    if (_request != null) {
      _complete(cancelled: true, value: null, label: null);
    }

    final completer = Completer<ChatChoiceResult>();
    _pending = completer;
    _request = request;
    _selectedValue = null;
    _text = '';
    notifyListeners();
    return completer.future;
  }

  /// Selects [value] as the current radio-button answer.
  void select(String value) {
    final request = _request;
    if (_disposed || request == null || request.optionFor(value) == null) {
      return;
    }
    if (_selectedValue == value) return;
    _selectedValue = value;
    notifyListeners();
  }

  /// Updates the free-text field of a prompt that allows text.
  void setText(String value) {
    final request = _request;
    if (_disposed || request == null || !request.allowText) return;
    if (_text == value) return;
    _text = value;
    notifyListeners();
  }

  /// Submits the free text or the current selection.
  ///
  /// Text takes precedence over a selected option so a correction is never
  /// lost when the user also left an option selected. When the selected option
  /// sets [ChatChoiceOption.rememberForSession], the answer is stored for the
  /// rest of the session.
  void submit() {
    final request = _request;
    if (_disposed || request == null) return;
    final text = _text.trim();
    if (request.allowText && text.isNotEmpty) {
      _complete(cancelled: false, value: null, label: null, text: text);
      return;
    }
    final value = _selectedValue;
    if (value == null) return;
    final option = request.optionFor(value);
    if (option == null) return;

    final id = request.id;
    if (option.rememberForSession && id != null) {
      _sessionChoices[id] = option.value;
    }
    _complete(cancelled: false, value: option.value, label: option.label);
  }

  /// Selects [value] and submits it immediately.
  ///
  /// Radio-button prompts confirm on selection, so the chat panels call this
  /// from the radio callback instead of offering a separate confirm action.
  /// While a free-text correction is pending, the selection is only recorded:
  /// the user submits the correction with the submit button, so a tap on an
  /// option cannot discard the typed correction.
  void selectAndSubmit(String value) {
    select(value);
    if (_request?.allowText == true && _text.trim().isNotEmpty) return;
    submit();
  }

  /// Dismisses the prompt if the request allows cancellation.
  void cancel() {
    final request = _request;
    if (_disposed || request == null || !request.allowCancel) return;
    _complete(cancelled: true, value: null, label: null);
  }

  /// Cancels a pending prompt regardless of [ChatChoiceRequest.allowCancel].
  ///
  /// Used when the chat session is cleared or the controller is disposed so a
  /// waiting AI tool does not block forever.
  void dismissPending() {
    if (_request == null) return;
    _complete(cancelled: true, value: null, label: null);
  }

  /// Forgets all session-wide answers.
  void clearSession() {
    if (_disposed || _sessionChoices.isEmpty) return;
    _sessionChoices.clear();
  }

  void _complete({
    required bool cancelled,
    required String? value,
    required String? label,
    String? text,
  }) {
    final completer = _pending;
    _pending = null;
    _request = null;
    _selectedValue = null;
    _text = '';
    if (!_disposed) notifyListeners();
    if (completer != null && !completer.isCompleted) {
      completer.complete(
        ChatChoiceResult(
          value: value,
          label: label,
          text: text,
          cancelled: cancelled,
        ),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final completer = _pending;
    _pending = null;
    _request = null;
    _selectedValue = null;
    _text = '';
    if (completer != null && !completer.isCompleted) {
      completer.complete(const ChatChoiceResult(cancelled: true));
    }
    super.dispose();
  }
}
