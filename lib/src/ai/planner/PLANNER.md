# PlannerAgent — design record

Short design record for the deterministic measurement planner added to
`WaveformAgent`. The numeric safety defaults below are marked **pending human
review**.

## Purpose

`PlannerAgent` converts a free-text measurement request into exactly one of:

- a complete, executable `ActionPlan` (`plan_ready`),
- one bundled `InputForm` for missing user data (`needs_input`), or
- an abort with a machine-readable reason.

Planning is deterministic Dart. The LLM only fills the `MeasurementRequest`
schema and returns the captured tool result verbatim. The planner never
measures, never changes a device and never talks to the user.

## Layout

```
lib/src/ai/planner/
  planner_config.dart        budgets, limits, reserved keys
  planner_ids.dart           deterministic id source
  planner_schemas.dart       plan_measurement schema (enum from the catalog)
  planner_session.dart       host-owned pending sessions
  planner_agent.dart         PlannerAgent + injectable PlannerModelRunner
  models/                    request, result, form and plan contracts
  catalog/                   ParamSpec, Recipe, recipes, catalog lookups
  safety/                    SafetyPolicy and DangerAssessment
  pipeline/                  stage result, equipment probe/report, plan draft,
                             rendering, missing input, stages 1-8, pipeline
```

`models/` and `pipeline/` do not import Flutter or `dartantic_ai`. The only
device seam is `EquipmentProbe`.

## Wire conventions

- Canonical keys are camelCase, matching the existing sub-agent results
  (`formattedValue`, `needsInput`). Snake_case aliases are accepted at the tool
  boundary for robustness; `toJson` always emits camelCase.
- Enum wire values are snake_case (`too_dangerous`, `configure_generator`,
  `single_choice`).
- Every model has hand-written `toJson`/`fromMap`; the project has no code
  generation. Malformed input throws `PlannerFormatException`, which the tool
  wrapper converts to `INVALID_PLANNER_INPUT`.

## Pipeline

`PlannerPipeline.run(request, answers, round, probe, {stateRef})` re-runs the
whole pipeline on every invocation.

| Stage | Function | Abort reasons |
|---|---|---|
| 1 | `calculateDanger` (first pass) | `too_dangerous` (uncorrectable only) |
| 2 | `checkEquipment` | `no_scope`, `no_generator` |
| 3 | `classifyType` | `input_incomplete`, `unsupported_method`, `too_complex` |
| 4 | `classifyComplexity` | `too_complex` |
| 5 | `planSimple` / `planAudio` / `planDigital` | `not_feasible` (wrong planner) |
| 6 | `calculateMissingInput` | `not_feasible` (generator limits) |
| 7 | `askUser` | `user_cancelled`, `user_input_unknown`, `input_incomplete` |
| 8 | `createActionPlan` | `too_dangerous` (re-check), `not_feasible` |

Invariants checked in stage 8: unique step ids, acyclic `dependsOn`, at most
two steps per sub-agent (manual steps excluded), teardown when the planner
enabled the generator, and a rendered instruction for every placeholder.

## Catalog and parameter sources

The catalog is a typed Dart constant list in `catalog/catalog_recipes.dart`;
the `measurements` enum of the tool schema is generated from it and a test
pins both together. A parameter is resolved in this order:

1. `given` / user answer (validated against type, options and range),
2. `readable` — a cached device value, otherwise a `read` step whose output is
   referenced as `{fromStep, field}`; readable parameters are never asked,
3. `defaulted` — applied and recorded with `source: default`,
4. `derived` — computed from resolved dependencies,
5. `askedOrDerived` — derived when its dependencies are known, otherwise one
   question in the bundled form. The sweep start and stop frequencies use
   this: a stated expected cutoff derives a decade-wide range, while a sweep
   without a stated range asks the user for both bounds,
6. `userRequired` — one question in the bundled form.

The form prefills `askedOrDerived` defaults but never applies them silently.
All raw values — form answers and model-supplied `knownParameters` — pass
through the same validator (`catalog/param_validation.dart`). Choice values
accept the option value or label in any letter case and numeric shorthand
(`CH2`, `2` and `Channel 2` all become `ch2`).

## Safety policy — PENDING HUMAN REVIEW

All voltage thresholds and probe ratings are placeholders and must be
confirmed against the oscilloscope and probe documentation before release.

- Scope maximum input: **70 V** (explicit product decision).
- Warning above 30 Vrms, 42.4 Vpk or 60 VDC.
- Probe ratings: 1x 50 V, 10x 300 V, 100x 600 V; effective limit is the lower
  of scope and probe.
- Blocked above the effective limit, or when the DUT is mains-referenced
  without a stated differential/isolated setup.
- Unknown maximum voltage is **never safe**; it is a warning and a mandatory
  top-priority question.
- Floating DUT, unknown coupling at elevated voltage, unknown mains reference
  and an unknown probe rating at elevated voltage are warnings.
- Warnings add safety notes and a manual `safety-confirmation` step. The plan
  approval presents the notes; the executor completes manual steps
  automatically, so no separate acknowledgement dialog is shown.

Device profiles contain command syntax only, so electrical limits come from
`SafetyPolicy` and user answers, not from the profile data.

## Session and stateRef

`WaveformAgent` keeps only the last 20 user/model texts; tool results are not
retained across turns. Pending planner sessions are therefore stored host-side
in `PlannerSessionStore` under the opaque `stateRef` from a `needs_input`
result. `PlannerAgent.resume(stateRef, answers)` re-runs the pipeline without a
model call. A submitted form never travels back through the model.

`PlannerAgent` also keeps a session-wide map of user-provided values. Every
submitted form answer is validated and remembered as soon as `resume` starts,
even when the pipeline later aborts, so a second measurement in the same chat
never asks for it again. After a run it also remembers every plan input with
source `user`; for a `needs_input` result it remembers the answers that the
next form does not ask again (so rejected values are not retained). The next
measurement in the same chat is seeded with these values as `knownParameters`,
so safety, coupling, channel and setup questions are not repeated. Values
stated in the new request always win over remembered ones, because seeding
only fills keys the request does not already contain.

Model-supplied `knownParameters` are normalized with the catalog validator
before they are remembered or seeded. An unusable value (for example a channel
that is neither an option value nor an option label) is dropped instead of
overriding a valid answer from an earlier form; this prevents a repeated
question loop when the model keeps extracting the same malformed value from
the chat history.

Safety values from `knownParameters` or `safetyHints` additionally need
evidence in the original request text: a numeric voltage for `maxVoltageV`,
an AC/DC wording for `coupling`, mains/grounded wording for
`mainsReferenced`, an attenuation for `probeAttenuation`,
differential/isolated wording for `differentialOrIsolated` and
floating/potential-free wording for `floatingDut`. Without evidence the value
is treated as unknown and the mandatory form question is asked. This prevents
the model from inventing a value such as `maxVoltageV: 0` and thereby
suppressing the safety question.

Defaults, derived values and device readings are not stored; they are
recomputed each run. `clearSession()` (called from
`WaveformAgent.clearHistory`) drops the map.

## WaveformAgent integration

`WaveformAgent` registers three tools beyond the five delegation paths:

- `planner_agent` — starts a plan, resumes a submitted form, or reports that a
  form is still open. It is capped at 8 invocations per user request by
  `PlannerInvocationBudget` (inside the global 16) and stores a `plan_ready`
  plan under its `planRef`.
- `present_input_form` — renders the canonical form with translated texts. The
  guard rejects any change to keys, types, option values, ranges, units or the
  question count. Answers are stored host-side in the session; the model only
  receives `{submitted, cancelled, stateRef, answerCount}`.
- `execute_plan` — advances a stored plan through `PlanExecutor`. The executor
  resolves `fromStep` values, pauses for approval and per-step confirmation,
  marks manual setup steps complete without a second prompt, delegates each
  measure step to the existing sub-agents, and runs teardown on failure or
  cancellation. Scope writes performed through the instrument agent refresh
  the waveform acquisition automatically before the next read or measure step.

The plan approval uses `request_user_choice` with a free-text field
(`allow_text: true`). The choice prompt returns the text instead of the selected
option. `WaveformAgent` handles it host-side: the stored `PlanSession` keeps the
original request text, the correction is appended as a trailing "User
correction before the start" section, and `PlannerAgent.plan` runs again. On
`plan_ready` the new plan replaces the old one under a new `planRef` and the
choice result carries `replanned: true`; the model presents the corrected plan
and asks for approval again before `execute_plan` is called. A correction never
starts an execution on its own.

`WaveformAgent._history` keeps only the last 20 user/model texts, so plans and
form answers never rely on the message window. `sendStream` resets the planner
budget, and `clearHistory` clears both session stores and the remembered
session values.

The chat form is `MeasurementFormPrompt` in `lib/src/widgets`, backed by
`MeasurementFormController`. The panel renders it first in its input banner and
the controller suspends the response timeout while the user fills it.

## Decisions and deviations

- **Form submission uses the blocking-tool pattern** (approved). `present_input_form`
  awaits the user and stores answers host-side; no structured chat message type
  was added.
- **Plan execution is host-owned** (approved). `execute_plan` and a deterministic
  `PlanExecutor` drive the stored plan; every measure step still delegates to an
  existing sub-agent. This avoids the LLM re-reading a plan that may have left the
  20-message window.
- **Teardown does not require confirmation.** The spec says
  `requiresUserConfirmation` is always true for state changes; switching the
  generator off is safety-restoring, so teardown is planned with
  `requiresUserConfirmation: false`. All generator/scope *setup* changes still
  require confirmation.
- **Manual setup steps do not pause execution.** The plan approval already
  covers the wiring instructions and safety notes shown in the plan, so a
  separate acknowledgement dialog would be redundant. `PlanExecutor` records
  each manual step (including `safety-confirmation`) as complete and
  continues; there is no `awaiting_manual` status and no
  `manualStepComplete` tool argument.
- **Instrument call limit is 8 in the Waveform context**, matching
  `WaveformAgent.defaultInstrumentToolCalls`; the standalone `InstrumentAgent`
  default remains 3.
- **Amplitude bands were added to the generator status map** in
  `home_page.dart` (JSON-safe, no infinity) so `not_feasible` can validate the
  amplitude against the frequency band. Missing bands produce a limitation note
  instead of a silent skip.
- **`PLANNER.md` lives next to the code** as the brief asks; the repository
  otherwise keeps topic docs in `docs/` or `plans/`.
- **Planner-own quantity parser.** `models/units.dart` intentionally does not
  reuse the calculator registry: that registry is case-sensitive and has no
  Vpp/Vrms bases, while planner input is free text. Ambiguous input is rejected
  so the safety policy fails closed.

## Tests

Deterministic tests use fakes only; no LLM and no device I/O. They cover JSON
round trips, safety boundaries, equipment probing, classification, golden step
lists, missing-input sourcing, form ordering, plan construction, the mocked
PlannerAgent, the tool wrappers, the form controller and widget, plan
execution, and the end-to-end pipeline for every BPMN end event. The
`bpmn_coverage_test.dart` table maps each edge to a scenario and asserts that
every abort reason and execution status is covered.

Commands:

```bash
dart analyze lib/src/ai/planner test/src/ai/planner
flutter test test/src/ai/planner
flutter test test/src/ai/measurement_form_test.dart \
  test/src/widgets/measurement_form_prompt_test.dart
flutter test test/src            # full deterministic suite
```

## Open questions

- Confirm the safety thresholds and probe ratings with the hardware
  documentation.
- Decide whether `restore` steps for scope settings changed by an approved plan
  should be added in a later iteration.
- Decide whether the form should be translated by an app-side label table
  instead of the WaveformAgent.
