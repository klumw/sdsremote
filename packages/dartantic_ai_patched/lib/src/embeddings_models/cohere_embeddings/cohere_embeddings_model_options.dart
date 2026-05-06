import 'package:dartantic_interface/dartantic_interface.dart';

/// Options for Cohere embeddings models.
class CohereEmbeddingsModelOptions extends EmbeddingsModelOptions {
  /// Creates new Cohere embeddings model options.
  const CohereEmbeddingsModelOptions({
    super.dimensions,
    super.batchSize,
    this.inputType,
    this.embeddingTypes,
    this.truncate,
  });

  /// The input type for the embeddings.
  /// Can be 'search_document', 'search_query', 'classification', 'clustering'.
  final String? inputType;

  /// The embedding types to return.
  /// Can include 'float', 'int8', 'uint8', 'binary', 'ubinary'.
  final List<String>? embeddingTypes;

  /// How to handle inputs longer than the maximum token length.
  /// Can be 'NONE', 'START', 'END'.
  final String? truncate;
}
