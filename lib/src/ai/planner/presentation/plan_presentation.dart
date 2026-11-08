/// Deterministic English texts the executor returns to the WaveformAgent.
///
/// The WaveformAgent translates these strings into the user's language; the
/// machine fields (ids, kinds, statuses) stay untranslated.
library;

import '../models/action_plan.dart';

/// Question shown before the plan starts.
String planApprovalQuestion(ActionPlan plan) {
  final steps = plan.steps.map((step) => step.id).join(', ');
  final safety = plan.safetyNotes.isEmpty
      ? ''
      : ' Safety notes: ${plan.safetyNotes.join(' ')}';
  final equipment = plan.equipment == null
      ? ''
      : ' Equipment: ${_equipmentSummary(plan.equipment!)}.';
  return 'Approve executing plan ${plan.planId} for "${plan.goal}" with '
      '${plan.steps.length} steps ($steps)?$safety$equipment';
}

String _equipmentSummary(PlanEquipment equipment) {
  final scope = equipment.scope;
  final scopeType = <String>[
    if (scope.model != null && scope.model!.trim().isNotEmpty) scope.model!,
    if (scope.profile != null && scope.profile!.trim().isNotEmpty)
      scope.profile!,
  ].join(' / ');
  final generator = equipment.generator;
  final generatorText = generator.connected
      ? 'signal generator connected'
            '${generator.model == null ? '' : ' (${generator.model})'}'
      : 'no signal generator connected';
  return '${scopeType.isEmpty ? 'oscilloscope type unknown' : 'oscilloscope $scopeType'}, '
      '$generatorText';
}

/// Question shown before one state-changing step runs.
String stepConfirmationQuestion(ActionStep step) {
  return 'May I proceed with step "${step.id}": ${step.instruction}?';
}
