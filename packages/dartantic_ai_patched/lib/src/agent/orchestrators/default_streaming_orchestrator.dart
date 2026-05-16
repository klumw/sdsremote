import 'dart:async';
import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import '../streaming_state.dart';
import '../tool_executor.dart';
import 'streaming_orchestrator.dart';

/// Default implementation of the streaming orchestrator.
///
/// This class implements the standard agent streaming pattern and exposes
/// overridable hooks so specialised orchestrators can customise behaviour
/// without duplicating the control flow.
class DefaultStreamingOrchestrator implements StreamingOrchestrator {
  /// Creates a default streaming orchestrator.
  const DefaultStreamingOrchestrator();

  static final _logger = Logger('dartantic.orchestrator.default');

  @override
  String get providerHint => 'default';

  @override
  void initialize(StreamingState state) {
    _logger.fine('Initializing streaming orchestrator');
    state.resetForNewMessage();
  }

  @override
  void finalize(StreamingState state) {
    _logger.fine('Finalizing streaming orchestrator');
  }

  @override
  Stream<StreamingIterationResult> processIteration(
    ChatModel<ChatModelOptions> model,
    StreamingState state, {
    Schema? outputSchema,
  }) async* {
    state.resetForNewMessage();
    await beforeModelStream(state, model, outputSchema: outputSchema);

    await for (final result in model.sendStream(
      List.unmodifiable(state.conversationHistory),
      outputSchema: outputSchema,
    )) {
      yield* onModelChunk(result, state);
      state.accumulatedMessage = state.accumulator.accumulate(
        state.accumulatedMessage,
        selectMessageForAccumulation(result),
      );
      state.lastResult = result;
    }

    final consolidatedMessage = state.accumulator.consolidate(
      state.accumulatedMessage,
    );

    yield* onConsolidatedMessage(
      consolidatedMessage,
      state,
      model,
      outputSchema: outputSchema,
    );
  }

  /// Hook invoked before the model stream begins.
  @protected
  Future<void> beforeModelStream(
    StreamingState state,
    ChatModel<ChatModelOptions> model, {
    Schema? outputSchema,
  }) async {}

  /// Handles a single streaming chunk from the model response.
  @protected
  Stream<StreamingIterationResult> onModelChunk(
    ChatResult<ChatMessage> result,
    StreamingState state,
  ) async* {
    final textOutput = _extractText(result);
    final thinkingOutput = _extractThinking(result);
    final hasMetadata = result.metadata.isNotEmpty;

    final streamText =
        textOutput.isNotEmpty && allowTextStreaming(state, result);
    final hasThinking = thinkingOutput.isNotEmpty;

    if (!streamText && !hasMetadata && !hasThinking) {
      return;
    }

    var streamOutput = '';
    if (streamText) {
      streamOutput = _shouldPrefixNewline(state) ? '\n$textOutput' : textOutput;
      state.markMessageStarted();
    }

    _logger.fine(
      'Streaming chunk: text=${streamOutput.length} chars, '
      'metadata=${result.metadata.keys}, '
      'thinking=${thinkingOutput.length} chars',
    );

    // NOTE: ThinkingPart content is NOT yielded in messages[] to avoid
    // polluting the caller's message history with duplicates. The thinking
    // content will be consolidated into the final model message via
    // MessageAccumulator. Instead, thinking is streamed via the `thinking`
    // field for real-time display.

    yield StreamingIterationResult(
      output: streamOutput,
      messages: const [],
      shouldContinue: true,
      finishReason: result.finishReason,
      thinking: hasThinking ? thinkingOutput : null,
      metadata: result.metadata,
      usage: null, // Usage only in final result
    );
  }

  /// Whether this orchestrator should stream text chunks for the current
  /// result. Subclasses can override to suppress raw text streaming while still
  /// allowing metadata to flow.
  @protected
  bool allowTextStreaming(
    StreamingState state,
    ChatResult<ChatMessage> result,
  ) => true;

  /// Selects which message should be accumulated for the consolidated result.
  @protected
  ChatMessage selectMessageForAccumulation(ChatResult<ChatMessage> result) =>
      result.output.parts.isEmpty && result.messages.isNotEmpty
      ? result.messages.first
      : result.output;

  /// Handles the final consolidated message after the model stream completes.
  @protected
  Stream<StreamingIterationResult> onConsolidatedMessage(
    ChatMessage consolidatedMessage,
    StreamingState state,
    ChatModel<ChatModelOptions> model, {
    Schema? outputSchema,
  }) async* {
    final emptyHandler = handleEmptyMessage(consolidatedMessage, state);
    if (emptyHandler != null) {
      yield* emptyHandler;
      return;
    }

    state.addToHistory(consolidatedMessage);

    yield StreamingIterationResult(
      output: '',
      messages: [consolidatedMessage],
      shouldContinue: true,
      finishReason: state.lastResult.finishReason,
      metadata: const {}, // Empty - metadata already streamed via onModelChunk
      usage: null, // Usage only in final chunk
    );

    final toolCalls = extractToolCalls(consolidatedMessage);
    if (toolCalls.isEmpty) {
      yield StreamingIterationResult(
        output: '',
        messages: const [],
        shouldContinue: false,
        finishReason: state.lastResult.finishReason,
        metadata:
            const {}, // Empty - metadata already streamed via onModelChunk
        usage: state.lastResult.usage, // Final usage here
      );
      return;
    }

    yield* executeToolCalls(toolCalls, state);
  }

  /// Handles empty assistant messages, optionally yielding results.
  @protected
  Stream<StreamingIterationResult>? handleEmptyMessage(
    ChatMessage message,
    StreamingState state,
  ) {
    if (message.parts.isEmpty) {
      if (hasRecentToolExecution(state)) {
        if (state.emptyAfterToolsContinuations < 1) {
          _logger.fine('Allowing one empty-after-tools continuation');
          state.noteEmptyAfterToolsContinuation();
          return Stream.value(
            StreamingIterationResult(
              output: '',
              messages: const [],
              shouldContinue: true,
              finishReason: state.lastResult.finishReason,
              metadata: const {}, // Empty - metadata already streamed
              usage: state.lastResult.usage,
            ),
          );
        }

        _logger.fine(
          'Second empty-after-tools message encountered; treating as final',
        );
        state.addToHistory(message);
        return Stream.value(
          StreamingIterationResult(
            output: '',
            messages: [message],
            shouldContinue: false,
            finishReason: state.lastResult.finishReason,
            metadata: const {}, // Empty - metadata already streamed
            usage: state.lastResult.usage,
          ),
        );
      }

      if (isLegitimateCompletion(state)) {
        _logger.fine('Empty message is legitimate completion, finishing');
        state.addToHistory(message);
        return Stream.value(
          StreamingIterationResult(
            output: '',
            messages: [message],
            shouldContinue: false,
            finishReason: state.lastResult.finishReason,
            metadata: const {}, // Empty - metadata already streamed
            usage: state.lastResult.usage,
          ),
        );
      }
    }

    return null;
  }

  /// Executes tool calls and yields their results.
  ///
  /// If [state.maxToolCalls] is set and executing these tool calls would
  /// exceed the limit, the excess calls are rejected with error results
  /// telling the model to respond with what it has so far.
  ///
  /// When the limit has already been triggered
  /// ([state.maxToolCallsTriggered]), all calls are rejected and the
  /// conversation loop ends immediately.
  @protected
  Stream<StreamingIterationResult> executeToolCalls(
    List<ToolPart> toolCalls,
    StreamingState state,
  ) async* {
    final toolNames = toolCalls.map((t) => t.toolName).join(', ');

    // Phase 1: If the limit was already triggered in a previous iteration,
    // reject everything and stop immediately to prevent infinite retry loops.
    // Yield a text fallback so the consumer receives SOMETHING even if the
    // model keeps making tool calls despite the error results.
    if (state.maxToolCallsTriggered) {
      final message = 'Maximum tool calls (${state.maxToolCalls}) reached. '
          'Please try rephrasing your request to be more specific.';
      _logger.info(
        'Max tool calls (${state.maxToolCalls}) already triggered; '
        'force-stopping with fallback message',
      );
      yield StreamingIterationResult(
        output: message,
        messages: const [],
        shouldContinue: false,
        finishReason: state.lastResult.finishReason,
        metadata: const {},
        usage: state.lastResult.usage,
      );
      return;
    }

    _logger.info(
      'Executing ${toolCalls.length} tool calls: [$toolNames]',
    );

    // Phase 2: Check if these tool calls would exceed the limit.
    final maxCalls = state.maxToolCalls;
    final wouldExceed = maxCalls != null &&
        (state.toolCallCount + toolCalls.length) > maxCalls;

    List<ToolPart> callsToExecute;
    List<ToolPart> callsToReject;

    if (wouldExceed) {
      final remaining = maxCalls - state.toolCallCount;
      callsToExecute = toolCalls.take(remaining > 0 ? remaining : 0).toList();
      callsToReject = toolCalls.skip(callsToExecute.length).toList();
      state.maxToolCallsTriggered = true;

      _logger.info(
        'Max tool calls ($maxCalls) limit: executing '
        '${callsToExecute.length}, rejecting ${callsToReject.length}',
      );
    } else {
      callsToExecute = toolCalls;
      callsToReject = const [];
    }

    // Execute calls within the limit
    if (callsToExecute.isNotEmpty) {
      state.toolCallCount += callsToExecute.length;

      registerToolCalls(callsToExecute, state);
      state.requestNextMessagePrefix();

      final executionResults = await executeToolBatch(state, callsToExecute);

      final toolResultParts = executionResults
          .map((result) => result.resultPart)
          .toList();

      if (toolResultParts.isNotEmpty) {
        // Copy provider-specific metadata (e.g., Google's thoughtSignatures)
        // from the model's tool call message to the tool result message
        final toolCallMessageMetadata = _findToolCallMessageMetadata(state);

        final toolResultMessage = ChatMessage(
          role: ChatMessageRole.user,
          parts: toolResultParts,
          metadata: toolCallMessageMetadata,
        );

        state.addToHistory(toolResultMessage);
        state.resetEmptyAfterToolsContinuation();

        yield StreamingIterationResult(
          output: '',
          messages: [toolResultMessage],
          shouldContinue: true,
          finishReason: state.lastResult.finishReason,
          metadata: const {},
          usage: state.lastResult.usage,
        );
      }
    }

    // Reject calls beyond the limit with error results.
    // After rejecting, yield shouldContinue: true so the model gets a
    // chance to respond to the "limit reached" errors in the next
    // processIteration call. The maxToolCallsTriggered flag prevents
    // infinite retry if the model keeps making tool calls.
    if (callsToReject.isNotEmpty) {
      final errorParts = callsToReject.map((tc) => ToolPart.result(
        callId: tc.callId,
        toolName: tc.toolName,
        result: jsonEncode({
          'error':
              'Maximum tool calls (${state.maxToolCalls}) reached. '
              'Please respond with what you have so far.',
        }),
      )).toList();

      final errorMessage = ChatMessage(
        role: ChatMessageRole.user,
        parts: errorParts,
      );

      state.addToHistory(errorMessage);

      yield StreamingIterationResult(
        output: '',
        messages: [errorMessage],
        shouldContinue: true,
        finishReason: state.lastResult.finishReason,
        metadata: const {},
        usage: state.lastResult.usage,
      );

      _logger.info(
        'Max tool calls (${state.maxToolCalls}) reached; '
        'rejected ${callsToReject.length} calls',
      );
    }

    // After executing tool calls, yield shouldContinue: true so the model
    // gets a chance to produce a follow-up text response based on the tool
    // results. The conversation loop ends naturally when the model responds
    // with text-only output (no further tool calls), which triggers
    // onConsolidatedMessage to yield shouldContinue: false.
    yield StreamingIterationResult(
      output: '',
      messages: const [],
      shouldContinue: true,
      finishReason: state.lastResult.finishReason,
      metadata: const {},
      usage: state.lastResult.usage,
    );
  }

  /// Finds provider-specific metadata from the model message containing
  /// tool calls. This allows providers like Google to pass through thought
  /// signatures required by Gemini 3+ models.
  Map<String, dynamic> _findToolCallMessageMetadata(StreamingState state) {
    // Find the most recent model message with tool calls
    for (var i = state.conversationHistory.length - 1; i >= 0; i--) {
      final message = state.conversationHistory[i];
      if (message.role == ChatMessageRole.model && message.hasToolCalls) {
        // Return metadata that should be passed to tool results
        // Currently supports Google's thought signatures
        final thoughtSigs = message.metadata['_google_thought_signatures'];
        if (thoughtSigs != null) {
          return {'_google_thought_signatures': thoughtSigs};
        }
        break;
      }
    }
    return const {};
  }

  /// Executes the batch of tools via the shared tool executor.
  @protected
  Future<List<ToolExecutionResult>> executeToolBatch(
    StreamingState state,
    List<ToolPart> toolCalls,
  ) => state.executor.executeBatch(toolCalls, state.toolMap);

  /// Registers tool calls with the tool ID coordinator.
  @protected
  void registerToolCalls(List<ToolPart> toolCalls, StreamingState state) {
    for (final toolCall in toolCalls) {
      state.registerToolCall(
        id: toolCall.callId,
        name: toolCall.toolName,
        arguments: toolCall.arguments,
      );
    }
  }

  /// Extracts tool call parts from a message.
  @protected
  List<ToolPart> extractToolCalls(ChatMessage message) => message.parts
      .whereType<ToolPart>()
      .where((p) => p.kind == ToolPartKind.call)
      .toList();

  /// Whether the conversation recently executed tools.
  @protected
  bool hasRecentToolExecution(StreamingState state) {
    if (state.conversationHistory.length < 2) {
      return false;
    }

    return state.conversationHistory
        .skip(state.conversationHistory.length - 2)
        .any(
          (message) => message.parts
              .whereType<ToolPart>()
              .where((p) => p.kind == ToolPartKind.result)
              .isNotEmpty,
        );
  }

  /// Whether the model's finish reason indicates a legitimate completion.
  @protected
  bool isLegitimateCompletion(StreamingState state) =>
      state.lastResult.finishReason == FinishReason.stop ||
      state.lastResult.finishReason == FinishReason.length;
}

String _extractText(ChatResult<ChatMessage> result) =>
    result.output.parts.whereType<TextPart>().map((p) => p.text).join();

String _extractThinking(ChatResult<ChatMessage> result) =>
    result.output.parts.whereType<ThinkingPart>().map((p) => p.text).join();

bool _shouldPrefixNewline(StreamingState state) =>
    state.shouldPrefixNextMessage && state.isFirstChunkOfMessage;
