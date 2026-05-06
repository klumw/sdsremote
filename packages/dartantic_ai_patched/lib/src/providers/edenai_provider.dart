import 'package:dartantic_interface/dartantic_interface.dart';

import '../embeddings_models/openai_embeddings/openai_embeddings_model_options.dart';
import '../platform/platform.dart';
import 'openai_provider.dart';

/// Provider for EdenAI V3 OpenAI-compatible API.
///
/// EdenAI V3 provides an OpenAI-compatible chat completions endpoint at
/// [defaultBaseUrl]. It supports streaming, tool/function calling, and
/// various models including GPT-4o, Claude, and others.
class EdenAIProvider extends OpenAIProvider {
  /// Creates a new EdenAI provider instance.
  EdenAIProvider({String? apiKey, super.headers})
    : super(
        apiKey: apiKey ?? tryGetEnv(defaultApiKeyName),
        apiKeyName: defaultApiKeyName,
        name: providerName,
        displayName: providerDisplayName,
        defaultModelNames: const {ModelKind.chat: defaultChatModel},
        baseUrl: defaultBaseUrl,
      );

  /// Canonical provider name.
  static const providerName = 'edenai';

  /// Human-friendly provider name.
  static const providerDisplayName = 'EdenAI';

  /// Default chat model identifier.
  static const defaultChatModel = 'gpt-4o';

  /// Environment variable used to read the API key.
  static const defaultApiKeyName = 'EDENAI_API_KEY';

  /// Default base URL for the EdenAI V3 API.
  static final defaultBaseUrl = Uri.parse('https://api.edenai.run/v3/llm');

  @override
  EmbeddingsModel<OpenAIEmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    OpenAIEmbeddingsModelOptions? options,
  }) {
    throw UnsupportedError(
      '$providerDisplayName provider does not support embeddings in dartantic.',
    );
  }

  @override
  Stream<ModelInfo> listModels() async* {
    throw UnsupportedError(
      '$providerDisplayName provider does not support listing models.',
    );
  }
}
