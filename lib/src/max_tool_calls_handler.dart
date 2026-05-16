import 'package:dartantic_ai/dartantic_ai.dart';

/// A reusable mixin that provides max tool calls handling for agents.
///
/// When the number of tool calls in a single user input exceeds
/// [maxToolCalls], this mixin provides a method that creates a tool result
/// message telling the LLM that the limit was reached, so the LLM can respond
/// with whatever it has gathered so far instead of the stream silently ending.
///
/// The mixin returns the tool result message and a message string to yield,
/// leaving it to the caller to add the message to history and yield the string.
///
/// Usage:
/// ```dart
/// class MyAgent with MaxToolCallsHandler {
///   @override
///   final int maxToolCalls;
///   // ...
/// }
/// ```
mixin MaxToolCallsHandler {
  /// Maximum number of tool calls allowed per user input.
  int get maxToolCalls;

  /// Checks whether the tool call limit has been reached or exceeded.
  ///
  /// Returns `true` if [toolCallCount] >= [maxToolCalls], `false` otherwise.
  bool isMaxToolCallsExceeded(int toolCallCount) =>
      toolCallCount >= maxToolCalls;

  /// Creates a tool result [ChatMessage] that tells the LLM the maximum number
  /// of tool calls was reached.
  ///
  /// The caller should add this message to the conversation history and yield
  /// the returned [message] string to the stream consumer.
  ///
  /// Returns a record with:
  /// - [message]: A string to yield to the stream (the error message).
  /// - [toolResultMessage]: A [ChatMessage] to add to the conversation history.
  ({String message, ChatMessage toolResultMessage}) buildMaxToolCallsMessage() {
    final message =
        'Maximum tool calls ($maxToolCalls) reached. '
        'Please respond with what you have so far.';

    final toolResultPart = ToolPart.result(
      callId: 'max_tool_calls_reached',
      toolName: '_max_tool_calls_handler',
      result: '{"error": "$message"}',
    );

    final toolResultMessage = ChatMessage(
      role: ChatMessageRole.user,
      parts: [toolResultPart],
    );

    return (message: message, toolResultMessage: toolResultMessage);
  }
}
