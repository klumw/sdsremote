/// Classification of a measurement request.
///
/// The PlannerAgent model classifies every request into one of the categories
/// below. When the model is not confident, or when the catalog has no recipe
/// for the request, the planner asks the user to choose a category and returns
/// a `classified` result that the WaveformAgent routes to a specialist.
library;

import 'action_plan.dart';
import 'json_value.dart';

/// Category of a measurement request.
enum MeasurementCategory {
  simpleSignal(
    'simple_signal',
    'Simple signal measurement',
    PlanType.simpleReading,
    PlanAgent.scopeAnalysis,
  ),
  complexAudio(
    'complex_audio',
    'Complex audio measurement',
    PlanType.audio,
    PlanAgent.audioAnalysis,
  ),
  complexDigital(
    'complex_digital',
    'Complex digital measurement',
    PlanType.digital,
    PlanAgent.digitalAnalysis,
  ),
  other('other', 'Other measurement', null, null);

  const MeasurementCategory(
    this.wireName,
    this.label,
    this.planType,
    this.routeAgent,
  );

  /// Wire value used by the model, the user form and the result.
  final String wireName;

  /// English label shown in the classification form.
  final String label;

  /// Plan category of a deterministic plan, or `null` for [other].
  final PlanType? planType;

  /// Specialist agent that executes this category, or `null` for [other].
  final PlanAgent? routeAgent;

  /// Wire name of the specialist agent, or `null` for [other].
  String? get route => routeAgent?.wireName;

  /// Parses a wire value and throws for an unknown one.
  static MeasurementCategory fromWire(Object? value) {
    final category = tryFromWire(value);
    if (category != null) return category;
    throw PlannerFormatException(
      'classification.type',
      'simple_signal|complex_audio|complex_digital|other',
      value,
    );
  }

  /// Parses a wire value, returning `null` for an unknown one.
  static MeasurementCategory? tryFromWire(Object? value) {
    for (final category in values) {
      if (category.wireName == value) return category;
    }
    return null;
  }
}

/// Confidence the model assigns to its own classification.
enum ClassificationConfidence {
  high('high'),
  medium('medium'),
  low('low');

  const ClassificationConfidence(this.wireName);

  /// Wire value used by the model and the result.
  final String wireName;

  /// Parses a wire value and throws for an unknown one.
  static ClassificationConfidence fromWire(Object? value) {
    for (final confidence in values) {
      if (confidence.wireName == value) return confidence;
    }
    throw PlannerFormatException(
      'classification.confidence',
      'high|medium|low',
      value,
    );
  }
}

/// Provenance of a classification.
enum ClassificationSource {
  model('model'),
  user('user');

  const ClassificationSource(this.wireName);

  /// Wire value used by the result.
  final String wireName;

  /// Parses a wire value and throws for an unknown one.
  static ClassificationSource fromWire(Object? value) {
    for (final source in values) {
      if (source.wireName == value) return source;
    }
    throw PlannerFormatException('classification.source', 'model|user', value);
  }
}

/// Classification supplied by its source.
class MeasurementClassification {
  const MeasurementClassification({
    required this.category,
    required this.confidence,
  });

  /// Selected measurement category.
  final MeasurementCategory category;

  /// Confidence in the selected category.
  final ClassificationConfidence confidence;

  /// Whether the classification is not explicitly doubtful.
  bool get isConfident => confidence != ClassificationConfidence.low;

  factory MeasurementClassification.fromMap(Map<String, dynamic> map) {
    const allowed = <String>{'type', 'confidence'};
    for (final key in map.keys) {
      if (!allowed.contains(key)) {
        throw PlannerFormatException('classification.$key', 'known field', key);
      }
    }
    return MeasurementClassification(
      category: MeasurementCategory.fromWire(map['type']),
      confidence: ClassificationConfidence.fromWire(map['confidence']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'type': category.wireName,
    'confidence': confidence.wireName,
  };
}
