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
  return 'Approve executing plan ${plan.planId} for "${plan.goal}" with '
      '${plan.steps.length} steps ($steps)?$safety';
}

/// Question shown before one state-changing step runs.
String stepConfirmationQuestion(ActionStep step) {
  return 'May I proceed with step "${step.id}": ${step.instruction}?';
}
