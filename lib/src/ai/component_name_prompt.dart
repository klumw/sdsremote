/// Text prompt used to request the component or family name before the
/// SpecAnalyst saves an IC reference document.
///
/// The tool asks the chat controller for a name; the controller owns the
/// pending request and the chat panel renders it with the shared
/// `ComponentNamePrompt` widget. The prompt is separate from
/// `ChatChoicePromptController`, which only supports radio-button options.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ic/ic_reference_writer.dart';

/// Question shown by the component-name prompt.
class ComponentNameRequest {
  const ComponentNameRequest({
    required this.question,
    required this.fileExists,
    this.initialName,
  });

  /// Question shown above the text field.
  final String question;

  /// Checks whether a reference file with the normalized id already exists.
  final Future<bool> Function(String id) fileExists;

  /// Optional initial text.
  final String? initialName;
}

/// Answer of a [ComponentNameRequest].
class ComponentNameResult {
  const ComponentNameResult({
    this.name,
    this.id,
    this.overwrite = false,
    this.cancelled = false,
  });

  /// The name exactly as entered.
  final String? name;

  /// The normalized reference id derived from [name].
  final String? id;

  /// Whether the user explicitly confirmed overwriting an existing file.
  final bool overwrite;

  /// Whether the user dismissed the prompt without a name.
  final bool cancelled;
}

/// Provider used by the specification-analysis tool.
typedef ComponentNameProvider =
    Future<ComponentNameResult> Function(ComponentNameRequest request);

/// Owns the pending component-name prompt and its text state.
class ComponentNamePromptController extends ChangeNotifier {
  ComponentNameRequest? _request;
  Completer<ComponentNameResult>? _pending;
  String _text = '';
  bool _checking = false;
  bool _fileExists = false;
  bool _overwriteConfirmed = false;
  String? _error;
  bool _disposed = false;

  /// Whether a prompt is currently waiting for the user's answer.
  bool get isVisible => _request != null;

  /// The visible request, or null.
  ComponentNameRequest? get request => _request;

  /// Current text field content.
  String get text => _text;

  /// Whether the file-existence check is running.
  bool get isChecking => _checking;

  /// Whether a file with the current normalized id already exists.
  bool get fileExists => _fileExists;

  /// Whether the user confirmed overwriting an existing file.
  bool get overwriteConfirmed => _overwriteConfirmed;

  /// Validation error shown in the prompt.
  String? get error => _error;

  /// Normalized id derived from the current text.
  String get normalizedId => normalizeIcReferenceId(_text);

  /// Whether the Save action can complete the prompt.
  bool get canSubmit =>
      !_disposed &&
      _request != null &&
      !_checking &&
      _text.trim().isNotEmpty &&
      normalizedId.isNotEmpty &&
      (!_fileExists || _overwriteConfirmed);

  /// Shows [request] and completes with the user's answer.
  Future<ComponentNameResult> requestName(ComponentNameRequest request) async {
    if (_disposed) return const ComponentNameResult(cancelled: true);
    if (_pending != null) {
      _complete(const ComponentNameResult(cancelled: true));
    }
    final completer = Completer<ComponentNameResult>();
    _pending = completer;
    _request = request;
    _text = request.initialName ?? '';
    _checking = false;
    _fileExists = false;
    _overwriteConfirmed = false;
    _error = null;
    notifyListeners();
    if (_text.trim().isNotEmpty) {
      await _checkExists();
    }
    return completer.future;
  }

  /// Updates the text and refreshes the file-existence check.
  Future<void> updateText(String value) async {
    if (_disposed || _request == null) return;
    _text = value;
    _fileExists = false;
    _overwriteConfirmed = false;
    _error = null;
    notifyListeners();
    await _checkExists();
  }

  Future<void> _checkExists() async {
    final request = _request;
    if (_disposed || request == null) return;
    final id = normalizedId;
    if (id.isEmpty) {
      _checking = false;
      _fileExists = false;
      notifyListeners();
      return;
    }
    _checking = true;
    notifyListeners();
    var exists = false;
    try {
      exists = await request.fileExists(id);
    } on Object {
      exists = false;
    }
    if (_disposed || !identical(_request, request)) return;
    _checking = false;
    if (normalizedId != id) return;
    _fileExists = exists;
    if (!exists) _overwriteConfirmed = false;
    notifyListeners();
  }

  /// Confirms or revokes the overwrite permission.
  void setOverwriteConfirmed(bool value) {
    if (_disposed || _request == null) return;
    if (_overwriteConfirmed == value) return;
    _overwriteConfirmed = value;
    notifyListeners();
  }

  /// Validates the name and completes the prompt.
  Future<void> submit() async {
    final request = _request;
    if (_disposed || request == null || _checking) return;
    final name = _text.trim();
    final id = normalizedId;
    if (name.isEmpty) {
      _error = 'Enter a component or family name.';
      notifyListeners();
      return;
    }
    if (id.isEmpty) {
      _error = 'The name does not contain any usable characters.';
      notifyListeners();
      return;
    }
    var exists = _fileExists;
    try {
      exists = await request.fileExists(id);
    } on Object {
      exists = _fileExists;
    }
    if (_disposed || !identical(_request, request)) return;
    _fileExists = exists;
    if (exists && !_overwriteConfirmed) {
      _error = null;
      notifyListeners();
      return;
    }
    _complete(ComponentNameResult(name: name, id: id, overwrite: exists));
  }

  /// Cancels the prompt without saving.
  void cancel() {
    if (_disposed || _request == null) return;
    _complete(const ComponentNameResult(cancelled: true));
  }

  /// Cancels a pending prompt regardless of the current state.
  ///
  /// Used when the chat request is cancelled or the session is cleared.
  void dismissPending() {
    if (_request == null) return;
    _complete(const ComponentNameResult(cancelled: true));
  }

  /// Forgets the pending prompt.
  void clearSession() => dismissPending();

  void _complete(ComponentNameResult result) {
    final completer = _pending;
    _pending = null;
    _request = null;
    _text = '';
    _checking = false;
    _fileExists = false;
    _overwriteConfirmed = false;
    _error = null;
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
    if (completer != null && !completer.isCompleted) {
      completer.complete(const ComponentNameResult(cancelled: true));
    }
    super.dispose();
  }
}
