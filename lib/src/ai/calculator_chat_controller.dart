import 'dart:async';

import 'package:flutter/foundation.dart';

import 'agents/calculator_agent.dart';
import 'ai_settings.dart';
import 'calculator_ai_service.dart';

/// One structured result returned by the Calculator Agent's deterministic
/// calculator tool. The chat panel renders these as cards with explicit
/// "Insert" and "Store" actions.
class CalculatorChatResult {
  const CalculatorChatResult({
    required this.operation,
    required this.expression,
    required this.normalized,
    required this.result,
    required this.value,
    this.unit,
    this.formulaId,
    this.formulaName,
    this.formulaInputs = const {},
    this.assumptions = const [],
  });

  final String operation;
  final String expression;
  final String normalized;
  final String result;
  final String value;
  final String? unit;
  final String? formulaId;
  final String? formulaName;
  final Map<String, String> formulaInputs;
  final List<String> assumptions;

  bool get isUsable => value.isNotEmpty && result.isNotEmpty;

  /// Whether [other] would display the same result.
  bool matches(CalculatorChatResult other) =>
      result == other.result && value == other.value;

  factory CalculatorChatResult.fromToolResult(Map<String, dynamic> json) {
    final inputs = <String, String>{};
    final rawInputs = json['formula_inputs'];
    if (rawInputs is Map) {
      for (final entry in rawInputs.entries) {
        inputs['${entry.key}'] = '${entry.value}';
      }
    }
    final assumptions = <String>[];
    final rawAssumptions = json['assumptions'];
    if (rawAssumptions is List) {
      assumptions.addAll(rawAssumptions.whereType<String>());
    }
    return CalculatorChatResult(
      operation: '${json['operation'] ?? ''}',
      expression: '${json['expression'] ?? ''}',
      normalized: '${json['normalized'] ?? ''}',
      result: '${json['result'] ?? ''}',
      value: '${json['value'] ?? ''}',
      unit: json['unit'] as String?,
      formulaId: json['formula_id'] as String?,
      formulaName: json['formula_name'] as String?,
      formulaInputs: inputs,
      assumptions: assumptions,
    );
  }
}

/// Owns the calculator AI transcript, agent lifecycle and structured results.
class CalculatorChatController extends ChangeNotifier {
  CalculatorChatController({CalculatorAiService Function()? serviceFactory})
    : _serviceFactory = serviceFactory ?? CalculatorAiService.new;

  final CalculatorAiService Function() _serviceFactory;
  final List<Map<String, String>> _messages = [];
  final Map<int, List<CalculatorChatResult>> _results = {};

  CalculatorAiService? _service;
  AiSettings? _settings;

  bool _isOpen = false;
  bool _isChatting = false;
  bool _disposed = false;
  int _generation = 0;
  int? _currentAiIndex;

  StreamSubscription<String>? _subscription;
  Completer<void>? _sendCompleter;
  bool _cancelRequested = false;

  bool get isOpen => _isOpen;
  bool get isChatting => _isChatting;
  bool get isInitialized => _service?.isInitialized ?? false;
  bool get isAvailable => _settings?.isConfigured == true && isInitialized;
  List<Map<String, String>> get messages => _messages;

  List<CalculatorChatResult> resultsFor(int messageIndex) =>
      _results[messageIndex] ?? const [];

  String get statusLabel {
    if (!isAvailable) return 'AI not configured';
    if (_isChatting) return 'Working…';
    return 'Ready';
  }

  void configure(
    AiSettings? settings, {
    required CalculatorAgentContext context,
  }) {
    if (_disposed) return;
    final configured = settings != null && settings.isConfigured;
    if (!configured) {
      _cancelActiveRequest();
      _settings = null;
      _generation++;
      _isChatting = false;
      _service?.dispose();
      _service = null;
      notifyListeners();
      return;
    }
    if (_settings == settings && _service != null) return;

    _cancelActiveRequest();
    _settings = settings;
    _generation++;
    _isChatting = false;
    _service?.dispose();

    final service = _serviceFactory();
    service.configure(
      apiKey: settings.apiKeyName,
      apiToken: settings.apiToken,
      model: settings.model,
      context: context,
      onToolResult: _handleToolResult,
    );
    _service = service;
    notifyListeners();
  }

  void toggleOpen() {
    if (_disposed) return;
    _isOpen = !_isOpen;
    notifyListeners();
  }

  void close() {
    if (!_isOpen) return;
    _isOpen = false;
    notifyListeners();
  }

  Future<void> send(String text) async {
    final service = _service;
    final trimmed = text.trim();
    if (_disposed ||
        service == null ||
        !service.isInitialized ||
        trimmed.isEmpty ||
        _isChatting) {
      return;
    }

    final generation = _generation;
    final aiMessage = <String, String>{'role': 'ai', 'content': ''};
    _messages.add({'role': 'user', 'content': trimmed});
    _messages.add(aiMessage);
    final aiIndex = _messages.length - 1;
    _currentAiIndex = aiIndex;
    _results[aiIndex] = [];
    _isChatting = true;
    _cancelRequested = false;
    final completer = Completer<void>();
    _sendCompleter = completer;

    var receivedChunk = false;
    var hadError = false;
    final subscription = service
        .sendMessageStream(text: trimmed)
        .listen(
          (chunk) {
            if (_disposed || generation != _generation || _cancelRequested) {
              return;
            }
            receivedChunk = true;
            aiMessage['content'] = (aiMessage['content'] ?? '') + chunk;
            notifyListeners();
          },
          onError: (Object error) {
            hadError = true;
            if (!_disposed && generation == _generation && !_cancelRequested) {
              aiMessage['content'] = 'Error: $error';
              notifyListeners();
            }
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );
    _subscription = subscription;
    notifyListeners();

    await completer.future;
    if (_subscription == subscription) _subscription = null;
    if (_sendCompleter == completer) _sendCompleter = null;
    if (_disposed || generation != _generation || _cancelRequested) return;
    if (!receivedChunk && !hadError) {
      aiMessage['content'] = 'No response from the AI provider.';
    }
    _isChatting = false;
    _currentAiIndex = null;
    notifyListeners();
  }

  Future<void> cancel() async {
    if (_disposed || !_isChatting) return;
    _cancelRequested = true;
    final subscription = _subscription;
    _subscription = null;
    final aiMessage = _messages.isNotEmpty && _messages.last['role'] == 'ai'
        ? _messages.last
        : null;
    aiMessage?['content'] = 'terminated by user';
    _isChatting = false;
    _currentAiIndex = null;
    final completer = _sendCompleter;
    _sendCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    notifyListeners();
    await subscription?.cancel();
  }

  void clearChat() {
    if (_isChatting) return;
    _messages.clear();
    _results.clear();
    notifyListeners();
  }

  /// Adds a structured result to the current answer and returns its 1-based
  /// footnote number. The number is passed back through calculator_tool so the
  /// agent can cite the same marker in its answer text.
  int? _handleToolResult(Map<String, dynamic> result) {
    if (_disposed || result['ok'] != true) return null;
    final operation = '${result['operation'] ?? ''}';
    if (!const {
      'evaluate',
      'run_formula',
      'convert',
      'define_variable',
    }.contains(operation)) {
      return null;
    }
    final index = _currentAiIndex;
    if (index == null) return null;
    final parsed = CalculatorChatResult.fromToolResult(result);
    if (!parsed.isUsable) return null;
    final existing = _results.putIfAbsent(index, () => []);
    final duplicate = existing.indexWhere(parsed.matches);
    if (duplicate >= 0) return duplicate + 1;
    existing.add(parsed);
    notifyListeners();
    return existing.length;
  }

  void _cancelActiveRequest() {
    _cancelRequested = true;
    final subscription = _subscription;
    _subscription = null;
    final completer = _sendCompleter;
    _sendCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
    if (subscription != null) unawaited(subscription.cancel());
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancelActiveRequest();
    _service?.dispose();
    _service = null;
    super.dispose();
  }
}
