import 'package:dartantic_interface/dartantic_interface.dart';

/// Google AI-specific embeddings model options.
class GoogleEmbeddingsModelOptions extends EmbeddingsModelOptions {
  /// Creates Google AI embeddings model options.
  const GoogleEmbeddingsModelOptions({super.dimensions, super.batchSize = 100});
}
