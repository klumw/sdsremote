/// JSON schemas of the planner tools.
///
/// The `measurements` enum is generated from the catalog so a new recipe
/// automatically appears in the tool schema. A sync test pins the two
/// together.
library;

import 'catalog/planner_catalog.dart';

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
    },
    'required': <String>['goal', 'measurements'],
  };
}
