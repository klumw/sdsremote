import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:openai_dart/openai_dart.dart' as openai;

import '../openai_responses/openai_responses_event_mapper.dart';
import '../openai_responses/openai_responses_tool_event_recorder.dart';
import '../openai_responses/openai_responses_tool_types.dart';

/// Event mapper for xAI Responses streams.
///
/// Delegates standard OpenAI-compatible event handling to
/// [OpenAIResponsesEventMapper], and adds raw JSON MCP metadata emission so
/// MCP events are preserved even when the OpenAI SDK cannot deserialize them.
class XAIResponsesEventMapper {
  /// Creates a new mapper configured for a specific stream invocation.
  XAIResponsesEventMapper({
    required bool storeSession,
    required ContainerFileLoader downloadContainerFile,
  }) : _delegate = OpenAIResponsesEventMapper(
         storeSession: storeSession,
         downloadContainerFile: downloadContainerFile,
       );

  final OpenAIResponsesEventMapper _delegate;
  final OpenAIResponsesToolEventRecorder _toolRecorder =
      const OpenAIResponsesToolEventRecorder();

  /// The container ID extracted from raw SSE JSON.
  String? get containerId => _delegate.containerId;
  set containerId(String? value) {
    if (value == null) return;
    _delegate.containerId = value;
  }

  /// Handles typed events (OpenAI-compatible path).
  Stream<ChatResult<ChatMessage>> handleTyped(
    openai.ResponseStreamEvent event,
  ) => _delegate.handle(event);

  /// Emits MCP metadata chunks directly from raw SSE JSON.
  Stream<ChatResult<ChatMessage>> handleRawJson(
    Map<String, dynamic> json,
  ) async* {
    if (!_containsMcp(json)) return;
    yield* _toolRecorder.yieldToolMetadataChunk(
      OpenAIResponsesToolTypes.mcp,
      Map<String, Object?>.from(json),
    );
  }

  static bool _containsMcp(Object? value) {
    if (value is Map<String, dynamic>) {
      final type = value['type'];
      if (type is String && type.toLowerCase().contains('mcp')) return true;
      for (final entry in value.entries) {
        if (_containsMcp(entry.value)) return true;
      }
      return false;
    }

    if (value is List) {
      for (final item in value) {
        if (_containsMcp(item)) return true;
      }
      return false;
    }

    return false;
  }
}
