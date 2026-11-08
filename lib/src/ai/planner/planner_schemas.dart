/// JSON schemas of the planner tools.
///
/// The `measurements` enum is generated from the catalog so a new recipe
/// automatically appears in the tool schema. A sync test pins the two
/// together.
library;

import 'catalog/planner_catalog.dart';
import 'models/measurement_classification.dart';

/// One catalog entry as shown in the tool-schema description.
String _catalogLine(PlannerCatalog catalog) {
  return catalog.recipes
      .map((recipe) {
        final aliases = recipe.aliases.isEmpty
            ? ''
            : '; also: ${recipe.aliases.join(', ')}';
        return '${recipe.id} — ${recipe.title}$aliases';
      })
      .join('; ');
}

/// Builds the input schema of the `plan_measurement` tool.
Map<String, dynamic> buildPlanMeasurementSchema(PlannerCatalog catalog) {
  return <String, dynamic>{
    'type': 'object',
    'additionalProperties': false,
    'properties': <String, dynamic>{
      'goal': <String, dynamic>{
        'type': 'string',
        'description': 'Short English description of the measurement goal.',
      },
      'measurements': <String, dynamic>{
        'type': 'array',
        'minItems': 1,
        'items': <String, dynamic>{
          'anyOf': <Object?>[
            <String, dynamic>{'type': 'string', 'enum': catalog.measurementIds},
            <String, dynamic>{'type': 'string', 'pattern': '^other:.+'},
          ],
        },
        'description':
            'Exact catalog ids for the requested quantities. Catalog: '
            '${_catalogLine(catalog)}. Use audio.frequency_response for a '
            'frequency response, Bode sweep, gain/phase curve, -3 dB cutoff, '
            'corner frequency or bandwidth. For a quantity that is not in the '
            'catalog, use "other:<short name>". Never invent ids.',
      },
      'knownParameters': <String, dynamic>{
        'type': 'object',
        'additionalProperties': true,
        'description':
            'Values the user stated, with camelCase keys and SI units '
            '(frequencyHz, amplitudeVpp, offsetV, channel). Do not invent '
            'values.',
      },
      'safetyHints': <String, dynamic>{
        'type': 'object',
        'additionalProperties': false,
        'properties': <String, dynamic>{
          'maxVoltageV': <String, dynamic>{'type': 'number'},
          'coupling': <String, dynamic>{
            'type': 'string',
            'enum': <String>['dc', 'ac', 'unknown'],
          },
          'mainsReferenced': <String, dynamic>{'type': 'boolean'},
          'floatingDut': <String, dynamic>{'type': 'boolean'},
        },
      },
      'classification': <String, dynamic>{
        'type': 'object',
        'additionalProperties': false,
        'properties': <String, dynamic>{
          'type': <String, dynamic>{
            'type': 'string',
            'enum': <String>[
              for (final category in MeasurementCategory.values)
                category.wireName,
            ],
          },
          'confidence': <String, dynamic>{
            'type': 'string',
            'enum': <String>[
              for (final confidence in ClassificationConfidence.values)
                confidence.wireName,
            ],
          },
        },
        'required': <String>['type', 'confidence'],
        'description':
            'Your own classification of the request. simple_signal is a '
            'direct scope reading; complex_audio is audio, distortion, level '
            'or frequency-response work; complex_digital is timing, logic and '
            'signal-integrity work; other means no catalog category fits. '
            'Confidence high means the request clearly matches, medium means '
            'it probably matches, low means you are unsure. The application '
            'asks the user when the confidence is low or the catalog has no '
            'matching recipe. Never guess a high confidence.',
      },
    },
    'required': <String>['goal', 'measurements', 'classification'],
  };
}
