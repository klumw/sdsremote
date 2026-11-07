/// The typed planner catalog and its lookup operations.
library;

import '../models/json_value.dart';
import '../planner_config.dart';
import 'catalog_recipes.dart';
import 'param_spec.dart';
import 'recipe.dart';

/// Catalog of measurement recipes and safety parameters.
class PlannerCatalog {
  const PlannerCatalog({
    required this.recipes,
    this.safetyParameters = standardSafetyParameters,
  });

  /// Standard catalog used in production.
  static const PlannerCatalog standard = PlannerCatalog(
    recipes: standardRecipes,
    safetyParameters: standardSafetyParameters,
  );

  /// Measurement recipes.
  final List<Recipe> recipes;

  /// Safety questions shared by every request.
  final List<ParamSpec> safetyParameters;

  /// Returns the recipe with [id], or `null`.
  Recipe? recipeFor(String id) {
    for (final recipe in recipes) {
      if (recipe.id == id) return recipe;
    }
    return null;
  }

  /// Sorted, unique catalog ids used as the tool-schema enum.
  List<String> get measurementIds {
    final ids = <String>{for (final recipe in recipes) recipe.id};
    final sorted = ids.toList()..sort();
    return List<String>.unmodifiable(sorted);
  }

  /// Resolves measurement ids to recipes in request order.
  ///
  /// `other:<text>` entries are ignored. An unknown id throws a
  /// [PlannerFormatException] so the tool wrapper can reject the request
  /// deterministically.
  List<Recipe> resolve(List<String> measurements) {
    final resolved = <Recipe>[];
    for (final id in measurements) {
      if (id.startsWith(otherMeasurementPrefix)) continue;
      final recipe = recipeFor(id);
      if (recipe == null) {
        throw PlannerFormatException(
          'measurements',
          'a catalog id or other:<text>',
          id,
        );
      }
      if (!resolved.any((existing) => existing.id == recipe.id)) {
        resolved.add(recipe);
      }
    }
    return resolved;
  }

  /// Free-text measurements outside the catalog.
  List<String> otherMeasurements(List<String> measurements) {
    return <String>[
      for (final id in measurements)
        if (id.startsWith(otherMeasurementPrefix))
          id.substring(otherMeasurementPrefix.length).trim(),
    ]..removeWhere((text) => text.isEmpty);
  }

  /// Finds a safety parameter by key.
  ParamSpec? safetyParameterFor(String key) {
    for (final parameter in safetyParameters) {
      if (parameter.key == key) return parameter;
    }
    return null;
  }

  /// Finds a parameter by [key] across the safety parameters and [selected].
  ParamSpec? parameterFor(String key, List<Recipe> selected) {
    final safety = safetyParameterFor(key);
    if (safety != null) return safety;
    for (final recipe in selected) {
      final parameter = recipe.parameterFor(key);
      if (parameter != null) return parameter;
    }
    return null;
  }

  /// Returns catalog validation errors; an empty list means the catalog is
  /// structurally valid.
  List<String> validationErrors() {
    final errors = <String>[];
    final ids = <String>{};
    for (final recipe in recipes) {
      if (!ids.add(recipe.id)) {
        errors.add('Duplicate recipe id "${recipe.id}".');
      }
      errors.addAll(recipe.validate());
    }
    if (recipes.isEmpty) errors.add('The catalog has no recipes.');
    final safetyKeys = <String>{};
    for (final parameter in safetyParameters) {
      if (!safetyKeys.add(parameter.key)) {
        errors.add('Duplicate safety parameter "${parameter.key}".');
      }
      errors.addAll(parameter.validate());
      if (parameter.source != ParamSource.userRequired &&
          parameter.source != ParamSource.given) {
        errors.add(
          'Safety parameter "${parameter.key}" must be user-required.',
        );
      }
    }
    return errors;
  }

  /// Throws when [validationErrors] is not empty.
  void assertValid() {
    final errors = validationErrors();
    if (errors.isNotEmpty) {
      throw StateError('Invalid planner catalog:\n${errors.join('\n')}');
    }
  }
}
