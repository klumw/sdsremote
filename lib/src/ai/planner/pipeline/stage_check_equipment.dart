/// BPMN stage 2: check that the required equipment is available.
library;

import '../catalog/recipe.dart';
import '../models/json_value.dart';
import '../models/measurement_request.dart';
import '../models/planner_result.dart';
import 'equipment_probe.dart';
import 'equipment_report.dart';
import 'stage_result.dart';
import '../catalog/planner_catalog.dart';

/// Checks scope reachability and, only when a selected recipe needs it, the
/// signal generator.
///
/// The generator is never probed for a request that does not need it, so a
/// simple scope reading works with the generator disconnected.
Future<StageResult<EquipmentReport>> checkEquipment({
  required MeasurementRequest request,
  required PlannerCatalog catalog,
  required EquipmentProbe probe,
}) async {
  ScopeEquipment scope;
  try {
    scope = await probe.probeScope();
  } on Object catch (error) {
    scope = ScopeEquipment(
      reachable: false,
      error: 'The oscilloscope probe failed ($error).',
    );
  }
  if (!scope.reachable) {
    return StageResult.abort(
      AbortReason.noScope,
      message:
          'No oscilloscope is configured, so a measurement plan cannot be '
          'created.',
      details: <String, Object?>{
        if (scope.host != null) 'host': scope.host,
        if (scope.error != null) 'error': scope.error,
      },
    );
  }

  // Unknown ids are handled by the classification stage. Resolving them
  // here must not turn into a misleading no_generator abort.
  List<Recipe> selected;
  try {
    selected = catalog.resolve(request.measurements);
  } on PlannerFormatException {
    selected = const <Recipe>[];
  }
  final needsGenerator = selected.any((recipe) => recipe.needsGenerator);

  // The generator is always probed so every plan records whether one is
  // connected. A missing generator only blocks recipes that need it.
  GeneratorEquipment generator;
  try {
    generator = await probe.probeGenerator();
  } on Object catch (error) {
    generator = GeneratorEquipment(
      configured: false,
      connected: false,
      supported: false,
      error: 'The signal generator probe failed ($error).',
    );
  }
  if (needsGenerator && !generator.available) {
    return StageResult.abort(
      AbortReason.noGenerator,
      message:
          'The selected measurement needs the signal generator, but it is not '
          'configured or not connected.',
      details: generator.toJson(),
    );
  }
  return StageResult.ok(
    EquipmentReport(scope: scope, generator: generator, generatorProbed: true),
  );
}
