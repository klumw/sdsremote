/// Checkbox (multi-select) prompt with a Confirm button.
///
/// The Waveform Agent uses this prompt for data collection when several
/// independent options can apply. It is separate from the radio-button
/// `ChatChoicePromptController`, which returns exactly one option.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// One selectable option of a checkbox prompt.
class ChatChecklistOption {
  const ChatChecklistOption({
    required this.value,
    required this.label,
    this.description,
    this.selected = false,
  });

  /// Machine-readable value returned to the AI tool.
  final String value;

  /// Text shown next to the checkbox.
  final String label;

  /// Optional explanation shown below the label.
  final String? description;

  /// Whether the option is checked when the prompt opens.
  final bool selected;
}

/// A question shown as a checkbox list inside the chat.
class ChatChecklistRequest {
  const ChatChecklistRequest({
    required this.question,
    required this.options,
    this.allowCancel = true,
  });

  /// Question shown above the checkbox list.
  final String question;

  /// Available options; at least two are required.
  final List<ChatChecklistOption> options;

  /// Whether the user may dismiss the prompt without confirming.
  final bool allowCancel;

  /// Returns the option with [value], or null when it does not exist.
  ChatChecklistOption? optionFor(String value) {
    for (final option in options) {
      if (option.value == value) return option;
    }
    return null;
  }
}

/// Answer of a [ChatChecklistRequest].
class ChatChecklistResult {
  const ChatChecklistResult({
    this.values = const [],
    this.labels = const [],
    this.cancelled = false,
  });

  /// Selected option values in option order.
  final List<String> values;

  /// Labels of the selected options in option order.
  final List<String> labels;

  /// Whether the user dismissed the prompt without confirming.
  final bool cancelled;
}

/// Owns the pending checkbox prompt and its selection.
///
/// The chat controller asks [requestChecklist] from an AI tool and renders the
/// visible state with the shared `ChatChecklistPrompt` widget.
class ChatChecklistPromptController extends ChangeNotifier {
  ChatChecklistRequest? _request;
  final Set<String> _selected = <String>{};
  Completer<ChatChecklistResult>? _pending;
  bool _disposed = false;

  /// Whether a prompt is currently waiting for the user's confirmation.
  bool get isVisible => _request != null;

  /// The visible request, or null.
  ChatChecklistRequest? get request => _request;

  /// Number of checked options.
  int get selectedCount => _selected.length;

  /// Whether at least one option is checked.
  bool get canSubmit => _selected.isNotEmpty;

  /// Whether [value] is currently checked.
  bool isSelected(String value) => _selected.contains(value);

  /// Shows [request] and completes with the user's confirmed selection.
  Future<ChatChecklistResult> requestChecklist(
    ChatChecklistRequest request,
  ) async {
    if (_disposed) return const ChatChecklistResult(cancelled: true);
    if (_pending != null) {
      _complete(const ChatChecklistResult(cancelled: true));
    }
    final completer = Completer<ChatChecklistResult>();
    _pending = completer;
    _request = request;
    _selected
      ..clear()
      ..addAll(
        request.options
            .where((option) => option.selected)
            .map((option) => option.value),
      );
    notifyListeners();
    return completer.future;
  }

  /// Toggles the checkbox for [value].
  void toggle(String value) {
    final request = _request;
    if (_disposed || request == null || request.optionFor(value) == null) {
      return;
    }
    if (!_selected.add(value)) {
      _selected.remove(value);
    }
    notifyListeners();
  }

  /// Confirms the current selection.
  ///
  /// The Confirm action is disabled while no option is checked; callers must
  /// use [cancel] to skip the prompt without a selection.
  void submit() {
    final request = _request;
    if (_disposed || request == null || _selected.isEmpty) return;
    final selected = <ChatChecklistOption>[
      for (final option in request.options)
        if (_selected.contains(option.value)) option,
    ];
    _complete(
      ChatChecklistResult(
        values: [for (final option in selected) option.value],
        labels: [for (final option in selected) option.label],
      ),
    );
  }

  /// Cancels the prompt without confirming a selection.
  void cancel() {
    final request = _request;
    if (_disposed || request == null || !request.allowCancel) return;
    _complete(const ChatChecklistResult(cancelled: true));
  }

  /// Cancels a pending prompt regardless of the current state.
  ///
  /// Used when the chat request is cancelled or the session is cleared.
  void dismissPending() {
    if (_request == null) return;
    _complete(const ChatChecklistResult(cancelled: true));
  }

  /// Forgets a pending prompt.
  void clearSession() => dismissPending();

  void _complete(ChatChecklistResult result) {
    final completer = _pending;
    _pending = null;
    _request = null;
    _selected.clear();
    if (!_disposed) notifyListeners();
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final completer = _pending;
    _pending = null;
    _request = null;
    _selected.clear();
    if (completer != null && !completer.isCompleted) {
      completer.complete(const ChatChecklistResult(cancelled: true));
    }
    super.dispose();
  }
}
