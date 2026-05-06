import 'package:dartantic_interface/dartantic_interface.dart';

/// Options for Mistral embeddings models.
class MistralEmbeddingsModelOptions extends EmbeddingsModelOptions {
  /// Creates new Mistral embeddings model options.
  const MistralEmbeddingsModelOptions({
    super.dimensions,
    super.batchSize,
    this.encodingFormat,
  });

  /// The encoding format for the embeddings.
  /// Can be 'float' or 'base64'.
  final String? encodingFormat;
}
