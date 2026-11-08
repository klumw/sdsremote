# PlannerAgent — design record

Short design record for the deterministic measurement planner added to
`WaveformAgent`. The numeric safety defaults below are marked **pending human
review**.

## Purpose

`PlannerAgent` converts a free-text measurement request into exactly one of:

- a complete, executable `ActionPlan` (`plan_ready`),
- one bundled `InputForm` for missing user data (`needs_input`),
- a measurement classification for the orchestrator to route (`classified`),
  or
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
| 2 | `checkEquipment` (scope + generator) | `no_scope`, `no_generator` (generator only when needed) |
| 3 | `classifyRequest` (uses `classifyType`) | `input_incomplete` (invalid category only), `user_input_unknown`, `too_complex` |
| 4 | `classifyComplexity` | `too_complex` |
| 5 | `planSimple` / `planAudio` / `planDigital` | `not_feasible` (wrong planner) |
| 6 | `calculateMissingInput` | `not_feasible` (generator limits) |
| 7 | `askUser` | `user_cancelled`, `user_input_unknown`, `input_incomplete` |
| 8 | `createActionPlan` | `too_dangerous` (re-check), `not_feasible` |

Invariants checked in stage 8: unique step ids, acyclic `dependsOn`, at most
two steps per sub-agent (manual steps excluded), teardown when the planner
enabled the generator, and a rendered instruction for every placeholder.

## Equipment record

Stage 2 always probes the oscilloscope and the signal generator. The generator
probe no longer depends on the selected recipes: a missing generator only
aborts `no_generator` when a recipe needs it, while a simple scope plan
continues. The resulting facts are recorded in every plan under `equipment`:

```json
"equipment": {
  "scope": {
    "reachable": true,
    "model": "SDS1202X-E",
    "profile": "Siglent SDS1000X-E",
    "host": "192.168.178.95"
  },
  "generator": {
    "configured": true,
    "connected": true,
    "supported": true,
    "detected": true,
    "model": "FY6900",
    "identity": "FY6900,SN123",
    "family": "fy6900",
    "port": "/dev/ttyUSB0"
  }
}
```

`scope.model` is the detected `*IDN?` designation; `scope.profile` is the
configured device profile name. Both are omitted when unknown. A generator that
is not connected is recorded with `connected: false` and the optional `error`;
the plan still proceeds when no recipe needs it. Plans parsed from a payload
without `equipment` remain valid, but plans built by the pipeline always carry
it. The WaveformAgent presents the recorded equipment together with the plan.

## User-driven classification fallback

The `plan_measurement` schema requires a `classification` object:

- `type` — `simple_signal`, `complex_audio`, `complex_digital` or `other`
  (`MeasurementCategory`),
- `confidence` — `high`, `medium` or `low` (`ClassificationConfidence`).

Stage 3 returns one of three decisions:

1. **Plan** — the catalog resolves every measurement and
   `classification.type` matches the derived `PlanType` (or the model omitted
   the classification).
2. **Classified** — the user chose a category in the form. The result carries
   `classification{type,confidence,source}` and, for every category except
   `other`, a `route` with the specialist agent wire name. The orchestrator
   routes the original request; the planner does not build a plan after a user
   classification.
3. **User form** — a single-choice `InputForm` with the question key
   `measurementCategory` and the four category options. It triggers when:
   - the model reports `confidence: low`,
   - the model category contradicts the resolvable recipes,
   - the catalog has no recipe (`input_incomplete` or `unsupported_method`),
   - the submitted answer is not one of the four category values.

A model classification of `other` with medium or high confidence and no
resolvable recipe returns `classified` directly. `too_complex` (mixed audio and
digital) stays an abort, because a category choice cannot split the request.

The submitted category is deliberately **not** remembered in
`PlannerAgent._sessionValues` and is not seeded into later requests: a category
chosen for one measurement must not classify the next measurement. The same
applies to the explicit `frequenciesHz` list of a frequency series.

## Multi-frequency level series

`audio.frequency_series` measures the level (Vpp or Vrms) at an explicit list
of discrete frequencies. It is host-managed (`hostManagesGenerator: true`), so
the plan contains no configure/teardown steps.

- `frequenciesHz` uses the `numberList` parameter type. The form shows a text
  field; the shared validator accepts a JSON list or comma/semicolon-separated
  text with units (`1 kHz, 10 kHz; 20000 Hz`) and normalizes it to a list of
  Hz values.
- `seriesQuantity` defaults to `vpp`; `amplitudeVpp` and `generatorChannel`
  use the existing generator parameters.
- The AudioAgent calls `measure_frequency_series` once. The host provider runs
  `FrequencySeriesService`: it configures the generator sine, switches the
  generator output on, enables the scope channel and runs Auto Setup (ASET)
  before the first point, sets a 1-2-5 vertical scale, sets the timebase to
  about three periods per screen for each point, reads `C<ch>:PAVA? PKPK` or
  `RMS`, and restores the generator, trace, V/div, timebase and trigger state
  afterwards. The generator outputs are switched off for safety.
- `Vxi11FrequencySeriesScope` owns the SCPI details; `FrequencySeriesService`
  is deterministic and is tested with a fake generator transport and a fake
  scope.

## Digital input-suitability series

`digital.frequency_series` checks logic levels, edge times and signal quality
at an explicit list of frequencies. It is host-managed
(`hostManagesGenerator: true`), so the plan contains one manual setup step and
one measure step, but no `configure_generator` or teardown step.

- Parameters: `channel`, `frequenciesHz`, `logicFamily`, `generatorChannel`.
- The DigitalAgent calls `measure_digital_frequency_series` once. The host
  provider runs `FrequencySeriesService.runQuantities`: it preserves the
  generator waveform, amplitude and offset, sets each frequency, switches the
  output on, prepares the scope channel, runs Auto Setup (ASET) before the
  first point, reads PKPK/TOP/BASE/MAX/MIN/RISE/FALL/FREQ/DUTY via `PAVA`,
  restores the generator and scope state and switches the generator outputs
  off.
- The DigitalAgent compares TOP with VIH min and BASE with VIL max of the
  selected logic family for every frequency and reports one verdict per
  frequency.
- The logic-family options use the ids of the bundled reference table
  (`ttl_5v`, `ttl_compatible_cmos_5v`, `cmos_5v`, `lvttl_3v3`, `cmos_2v5`,
  `cmos_1v8`), so the DigitalAgent can pass the value directly to
  `read_logic_level_reference`.

## Bode sweep channel preparation and ASET

`Vxi11BodeScope.prepare` now enables a disabled CH1/CH2 trace instead of
throwing `BodeScopeException`. It remembers which traces were off and
`restore()` turns them off again. This removes the most common manual
prerequisite of a frequency-response sweep; a missing generator or unavailable
sweep provider is still reported.

`BodePlotService` now always runs Auto Setup (ASET) after it has configured the
generator, switched its output on and prepared the scope channels, and before
the first sweep point. `Vxi11BodeScope.prepare` no longer decides whether ASET
is necessary. The out-of-range retry keeps its additional ASET call.

## Generator settings mode

Every recipe with `needsGenerator: true` includes a required
`generatorSettingsMode` question (`current` or `configure`). It is asked for
every measurement and is not remembered across requests.

- `current`: the host reads the current waveform, amplitude and offset from
  the generator status, keeps them and only steps the frequency. The plan
  records these values with `source: device`.
- `configure`: the form asks for `generatorWaveform` and `amplitudeVpp` when
  the user did not state them; `offsetV` defaults to 0. The first frequency of
  a series or the sweep start is the start frequency.
- A model-supplied mode without matching text evidence is removed by
  `enforceStatedGeneratorSettingsMode`, so the form always asks.
- The audio frequency series, Bode sweep and digital series tools carry
  `useCurrentSettings` and only send amplitude/waveform when configuring.
  There is no implicit 1 Vpp default.

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
  plan under its `planRef`. A `classified` result is relayed verbatim; the
  WaveformAgent then delegates the original request to the agent named in
  `route`, or handles the `other` category itself.
- `present_input_form` — renders the canonical form with translated texts. The
  guard rejects any change to keys, types, option values, ranges, units or the
  question count. Answers are stored host-side in the session; the model only
  receives `{submitted, cancelled, stateRef, answerCount}`.
- `execute_plan` — advances a stored plan through `PlanExecutor`. The executor
  resolves `fromStep` values, pauses for plan approval, marks manual setup
  steps complete without a second prompt, runs generated setup steps directly
  (explicitly marked steps still pause), delegates each measure step to the
  existing sub-agents, and runs teardown on failure or cancellation. Scope writes performed through the instrument agent refresh
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
- **Plan approval authorizes setup changes.** `configure_generator` steps are
  planned with `requiresUserConfirmation: false`: the plan approval lists
  every step and is the single authorization point. Changes outside an
  approved plan still require confirmation. Teardown remains
  `requiresUserConfirmation: false` because switching the generator off is
  safety-restoring. The executor still pauses for explicitly marked steps, so
  manually constructed plans keep the second confirmation gate.
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
round trips, safety boundaries, equipment probing, automatic and user-driven
classification, golden step lists, missing-input sourcing, form ordering, plan
construction, the mocked PlannerAgent, the tool wrappers, the form controller
and widget, plan execution, and the end-to-end pipeline for every BPMN end
event. The `bpmn_coverage_test.dart` table maps each edge to a scenario and
asserts that every abort reason and execution status is covered. The
`unsupported_method` reason is retired from the pipeline (stage 3 now asks the
user and returns `classified`), but remains part of the result contract for
direct stage callers.

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
