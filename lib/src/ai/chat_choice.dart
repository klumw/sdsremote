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
  const ChatChoiceResult({this.value, this.label, this.cancelled = false});

  /// Selected option value, or null when the user cancelled.
  final String? value;

  /// Selected option label, or null when the user cancelled.
  final String? label;

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
  Completer<ChatChoiceResult>? _pending;
  bool _disposed = false;

  /// Whether a prompt is currently waiting for the user's answer.
  bool get isVisible => _request != null;

  /// The visible prompt, or null.
  ChatChoiceRequest? get request => _request;

  /// Value of the currently selected radio button, or null.
  String? get selectedValue => _selectedValue;

  /// Whether the user selected an option that can be submitted.
  bool get canSubmit => _selectedValue != null;

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

  /// Submits the current selection.
  ///
  /// When the selected option sets [ChatChoiceOption.rememberForSession], the
  /// answer is stored for the rest of the session.
  void submit() {
    final request = _request;
    final value = _selectedValue;
    if (_disposed || request == null || value == null) return;
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
  void selectAndSubmit(String value) {
    select(value);
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
  }) {
    final completer = _pending;
    _pending = null;
    _request = null;
    _selectedValue = null;
    if (!_disposed) notifyListeners();
    if (completer != null && !completer.isCompleted) {
      completer.complete(
        ChatChoiceResult(value: value, label: label, cancelled: cancelled),
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
    if (completer != null && !completer.isCompleted) {
      completer.complete(const ChatChoiceResult(cancelled: true));
    }
    super.dispose();
  }
}
