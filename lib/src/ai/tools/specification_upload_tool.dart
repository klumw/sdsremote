/// AI tool that reveals the specification upload control in the chat.
///
/// The tool blocks until the user selects a specification file or cancels the
/// upload. The chat panel observes the pending request, shows the upload
/// control and completes the provider with the locally extracted text.
library;

import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';
import '../specification_upload.dart';

/// Waits for the user to select a DUT specification file.
///
/// Completes with the extracted specification, or null when the user cancels.
typedef SpecificationUploadProvider = Future<UploadedSpecification?> Function();

/// Registers `request_specification_upload` for the Waveform Agent.
Tool<Map<String, dynamic>> createSpecificationUploadTool({
  SpecificationUploadProvider? requestUpload,
  String agentName = 'unknown',
}) {
  final provider = requestUpload;
  return Tool<Map<String, dynamic>>(
    name: 'request_specification_upload',
    description:
        'Shows the specification upload control in the chat and waits for '
        'the user to choose a PDF or plain-text specification file for the '
        'DUT. The app extracts the text locally and returns it in `specText` '
        'with the file name in `sourceName`. Call this tool only when the '
        'user has confirmed that a specification file is available and the '
        'specification is not already in the chat. The call returns once the '
        'user chooses a file or cancels; `cancelled` is true when the user '
        'cancels. Pass `specText` and `sourceName` unchanged to '
        'analyze_specification. Never claim to have read a file without this '
        'tool result.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, dynamic>{},
    }),
    onCall: (args) async {
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'request_specification_upload',
      );
      if (provider == null) {
        const result = <String, dynamic>{
          'error':
              'Specification upload is not available in this context. Ask '
              'the user to paste the electrical characteristics table.',
        };
        await logger.logToolCall(
          input: const <String, dynamic>{},
          output: {'error': result['error']},
        );
        return result;
      }

      logger.log('Specification upload requested');
      final uploaded = await provider();
      if (uploaded == null) {
        const result = <String, dynamic>{
          'cancelled': true,
          'error':
              'The user cancelled the specification upload. Ask whether '
              'another file is available, or continue with manual reference '
              'values.',
        };
        await logger.logToolCall(
          input: const <String, dynamic>{},
          output: {'cancelled': true},
        );
        return result;
      }

      await logger.logToolCall(
        input: const <String, dynamic>{},
        output: {
          'sourceName': uploaded.fileName,
          'characterCount': uploaded.characterCount,
          if (uploaded.pageCount != null) 'pageCount': uploaded.pageCount,
        },
      );
      return <String, dynamic>{
        'ok': true,
        'sourceName': uploaded.fileName,
        'specText': uploaded.text,
        'characterCount': uploaded.characterCount,
        if (uploaded.pageCount != null) 'pageCount': uploaded.pageCount,
      };
    },
  );
}
