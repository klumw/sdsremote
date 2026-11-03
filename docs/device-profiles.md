# Device Profiles, Commands and Knowledge

This document describes the device-profile architecture introduced for the
Instrument Agent and the signal-generator tools. It records the extraction of
device-specific knowledge out of the system prompts, the command-package schema,
the validation path and the migration status.

## 1. Purpose

Device-specific knowledge was previously embedded in
`lib/src/ai/agents/systemprompts.dart` (the instrument-agent prompt and its large
SCPI reference) and in signal-generator tool descriptions. The refactoring
splits that knowledge into two independently maintainable sources:

1. **Command definitions** – machine-readable SCPI packages in
   `assets/devices/commands/`.
2. **Device knowledge** – Markdown operating knowledge in
   `assets/devices/knowledge/`.

The active device profile supplies both at runtime. The general system prompt
keeps only agent-wide rules.

## 2. Architecture

```
assets/devices/
├── commands/
│   ├── fy6900_scpi_commands.json
│   ├── jds6600_scpi_commands.json
│   └── siglent_sds1000xe_scpi_commands.json
└── knowledge/
    ├── fy6900.md
    ├── jds6600.md
    └── sds1000xe.md

lib/src/devices/
├── device_profile_models.dart      data model, profile ids, error codes
├── device_command_package.dart     JSON parsing and schema validation
├── device_command_registry.dart    indexing, resolution, raw validation
├── device_knowledge.dart           Markdown parsing, sections, search
├── device_asset_source.dart        abstraction, filesystem and in-memory sources
├── flutter_device_asset_source.dart Flutter asset-bundle source
├── siggen_waveform_capabilities.dart device-specific waveform mapping
├── device_profile_store.dart       catalog, atomic loading, identity resolution
└── device_agent_context.dart       prompt context and command gate
```

Data flow:

```
DeviceProfileStore.loadProfile(profileId)
  -> load command asset -> DeviceCommandPackageParser.parse
  -> load knowledge asset -> DeviceKnowledgeParser.parse
  -> verify both belong to the same profile
  -> build DeviceCommandRegistry
  -> cache DeviceProfile (only after every step succeeded)

DeviceAgentContext(profile, identity)
  -> buildPromptSection()
     -> profile metadata and identity status
     -> command reference generated from the registry
     -> knowledge Markdown
  -> validateRawCommand(...) -> registry

InstrumentAgent
  -> system prompt = general prompt + DeviceAgentContext.buildPromptSection()
  -> VXI-11 tool validates every raw command through DeviceCommandGate
```

## 3. Profile catalog and identity

The catalog in `device_profile_store.dart` is explicit and deterministic:

| Profile id | Display name | Command asset | Knowledge asset |
|---|---|---|---|
| `sds1000xe` | Siglent SDS1000X-E series | `siglent_sds1000xe_scpi_commands.json` | `sds1000xe.md` |
| `fy6900` | FeelElec FY6900 series | `fy6900_scpi_commands.json` | `fy6900.md` |
| `jds6600` | JOY-IT/Juntek JDS6600 series | `jds6600_scpi_commands.json` | `jds6600.md` |

`jd6600` is an explicit alias for `jds6600`. The application setting has always
used `jds6600`; the command package declares `configured_device: jd6600`. Both
normalize to the canonical profile id `jds6600`.

Identity resolution reads the model field of `*IDN?` and matches it against
anchored expressions:

| Profile | Model expression |
|---|---|
| `sds1000xe` | `^SDS(?:1102|1202|1104|1204)X-E$` |
| `fy6900` | `^FY6900(?:-\d+M)?$` |
| `jds6600` | `^JDS6600(?:-LITE)?$` |

Rules:

- Whitespace in the model is removed before matching.
- No substring matching is used. If a model matches more than one profile, the
  result is `IDENTITY_AMBIGUOUS` and the caller must ask for explicit
  configuration.
- Configured and detected identities are separate fields:
  `configured_profile`, `detected_profile`, `status` and `message`.
- Status values: `confirmed`, `configuredOnly`, `detectedOnly`, `mismatch`,
  `unknown`, `ambiguous`.

## 4. Command package schema version 1.0

### 4.1 Top-level fields

| Field | Required | Notes |
|---|---|---|
| `schema_version` | yes | Only `1.0` is accepted. |
| `package_id` | yes | Unique package identifier. |
| `manufacturer` | recommended | Falls back to `knowledge_package.manufacturer`. |
| `configured_device` | recommended | Falls back to the requested profile id. Must normalize to the requested profile. |
| `device_scope` | optional | `model` and `firmware`. Falls back to `knowledge_package.series`. |
| `protocol` | optional | Default `SCPI`. |
| `waveforms` | optional | `supported`, `accepted_aliases`, `unsupported_note`, `cross_model_mapping`. |
| `syntax` | optional | `source_channel`, `units_optional`, `unit_case_insensitive`, `unit_rules`, `header_aliases`, `header_alias_notes`. |
| `commands` | yes | Non-empty list of command definitions. |
| `provenance` | optional | Free-form source/validation information. |
| `knowledge_package` | optional | Legacy SDS layout; read when top-level fields are absent. |

Unknown top-level and command fields are preserved in `extensions` maps. They do
not affect execution.

### 4.2 Command fields

| Field | Required | Notes |
|---|---|---|
| `command_id` | yes | Stable technical key; unique per package. |
| `name` | yes | Human-readable name. |
| `alias_or_description` | optional | Long alias from the SDS package. |
| `description` | optional | Human-readable description. |
| `scpi_pattern` | yes | Declarative template; never executed as code. |
| `query_pattern` | required for documented queries | Null when no query is documented. |
| `operation_kind` | yes | `query`, `action`, `setter_query`, `unspecified`. |
| `query_support` | yes | `query_only`, `none`, `documented`, `not_specified`. |
| `parameters` | optional | Parameter definitions; commands without them are pattern-only. |
| `scpi_pattern_aliases` | optional extension | Additional documented write forms, e.g. `OUTP<n> <state>`. |
| `query_pattern_aliases` | optional extension | Additional documented query forms, e.g. `OUTP<n>?`. |
| `device_scope` | optional | Per-command model/firmware scope. |
| `provenance` | optional | Per-command source information. |

Consistency rules enforced by the parser:

- `query` requires `query_support` `query_only` or `documented` and a
  `query_pattern`.
- `action` requires `query_support` `none` and no `query_pattern`.
- `setter_query` requires `query_support` `documented` and both patterns.
- `query_only` and `documented` require a `query_pattern`.
- `none` and `not_specified` must not declare a `query_pattern`.

### 4.3 Migration rules

Two documented migration rules keep older packages loadable:

1. `operation_kind: unspecified` + `query_support: not_specified`:
   - if `scpi_pattern` ends with `?`, it is classified as `query`/`query_only`
     with the same pattern as the query form;
   - otherwise it is classified as `action`/`none`.
   The applied rule is recorded in the command's `extensions.migration`.
2. A `query` command with no `query_pattern` whose `scpi_pattern` already ends
   with `?` uses that same pattern as the query form. No query form is invented
   for a setter.

These rules cover the two SDS commands (`PNSU`, `VERT`) that use
`unspecified`.

### 4.4 Parameter definitions

| Field | Notes |
|---|---|
| `name` | Placeholder name without angle brackets. |
| `type` | `integer`, `number`, `enum`, `string`. |
| `required` | Defaults to true. |
| `allowed_values` | Explicit enum/integer choices. |
| `values_ref` | Only `waveforms.supported_and_aliases` is supported. |
| `unit` | `accepted` list and `default` unit. |
| `minimum` / `maximum` | Optional documented bounds. Omitted means unknown; no bound is invented. |

A command whose pattern contains placeholders without parameter definitions is
marked pattern-only. It can be validated syntactically as a raw command, but it
cannot be built from semantic parameters.

## 5. Registry API

`DeviceCommandRegistry` provides:

| Method | Purpose |
|---|---|
| `getCommand(commandId)` | Stable id lookup. |
| `findCommands(query)` | Search by id, name, alias, description or pattern. |
| `getSupportedWaveforms()` | Canonical names from the package. |
| `resolveWaveform({requested, channel})` | Capability check and documented mapping. |
| `resolveCommand(commandId, parameters, {query})` | Validate and build deterministic SCPI. |
| `validateCommand(commandId, parameters, {query})` | Validation without building. |
| `buildCommand(commandId, parameters, {query})` | Returns the SCPI string. |
| `validateRawCommand(command, {isQuery})` | Guard for transport tools. |
| `getCommandDocumentation(commandId)` | Structured documentation. |
| `normalizeHeaderAliases(command)` | Whole-segment alias normalization. |

Resolution pipeline:

1. Look up the command by id.
2. Check the requested operation against `operation_kind` and `query_support`.
3. Reject commands that are not semantically resolvable.
4. Validate every supplied parameter: unknown keys, required keys, type, enum,
   allowed values, channel and unit.
5. Normalize units to the canonical base unit.
6. Render the pattern: replace `[unit]`, alternatives such as `ON|OFF|1|0`,
   required placeholders and optional groups.
7. Return the deterministic command string plus normalization notes.

Raw validation pipeline:

1. Reject empty commands, command chaining (`;`), newlines and null bytes.
2. Check that the operation matches the presence of `?` in the header token.
3. Normalize whole header segments through `syntax.header_aliases`.
4. Match against the compiled patterns of the requested operation class.
5. Validate channel and every parameter that has a definition.
6. Accept documented special patterns (`$$SY_FP` for `sds1000xe`).
7. Otherwise return `UNKNOWN_COMMAND` with suggestions.
8. Pattern-only commands are accepted with a warning: the value was checked
   syntactically, not against a range.

The VXI-11 tool calls this validation before any recorder callback and before
any transport work. A blocked command never reaches the device.

### Instrument Agent resolver tool

The Instrument Agent exposes `resolve_device_command` with
`{command_id, parameters, query}`. It calls `resolveCommand` and returns the
validated `scpi` string plus the normalized parameters. It never sends the
command: the agent passes the returned string to the `vxi11` tool, which
validates it again before transport. `COMMAND_NOT_RESOLVABLE` means the command
is pattern-only (its placeholders have no parameter definitions); the agent must
use the authorized raw pattern from the active profile instead.

## 6. Units

Units are optional and case-insensitive. Normalization is central in
`DeviceUnitRule`:

| Dimension | Accepted | Canonical output |
|---|---|---|
| Frequency | `HZ`, `KHZ`, `MHZ` | `HZ` (kHz × 1000, MHz × 1,000,000) |
| Voltage | `V`, `VPP`, `MV` | `V` (mV ÷ 1000) |
| Duty | `%`, `PCT` | `%` |
| Phase | `DEG`, `DEGREE` | `DEG` |

Amplitude and DC offset keep separate parameter definitions even though they
share unit spellings; `Vpp` is not treated as a DC offset by any conversion
rule. Missing ranges are marked unknown; the device driver performs the numeric
range check against the detected model.

## 7. Waveform capabilities

The packages list canonical names and accepted aliases. The registry:

- accepts canonical names;
- normalizes accepted aliases to the canonical mnemonic;
- rejects unknown names with `UNSUPPORTED_WAVEFORM`;
- applies no automatic cross-model mapping except through the explicit
  resolver.

For the signal generators the resolver reuses the existing driver tables:

- **JDS6600:** FY6900-only names are rejected with SCPI error `-222`.
- **FY6900:** JDS6600-only names map through
  `Fy6900Protocol.waveformIndex` to the closest existing FY6900 preset.
  `PULS` on CH2 maps to `RECT`.
- Every mapping returns `requested`, `resolved`, `channel`, `mapped` and a note.
  The tool result and the application log report both names.
- `ARB` is rejected on both families.

## 8. Knowledge documents

A knowledge file starts with a metadata comment:

```markdown
<!--
device_profile: fy6900
knowledge_version: 1.0
source: ...
validation_status: ...
-->
```

The loader rejects a file whose `device_profile` does not match the command
package. This prevents mixing, for example, the FY6900 command package with the
JDS6600 knowledge.

The document is parsed into heading sections. `DeviceKnowledgeDocument`
provides:

- `getSection(key)` by id, title, number prefix or id prefix;
- `search(query)` with title-weighted term scoring;
- `referencesFor(commandIdOrName)` for command documentation links.

The three knowledge files follow the requested ten-section structure:

1. Device profile
2. Operating model
3. Channels and outputs
4. Waveforms
5. Parameter dependencies
6. Typical operating workflows
7. Error handling
8. Safety and operating notes
9. Known limitations
10. References

Each file also contains a provenance table that distinguishes documented facts,
inherited system-prompt rules, derived rules and unknown information.

## 9. Agent context

`DeviceAgentContext.buildPromptSection()` produces:

- configured profile, configured device value, detected identity, identity
  status and firmware;
- command package id, schema version, command count, protocol;
- knowledge source and version;
- the supported waveform list;
- the authorized command definitions, generated from the registry in package
  order, including parameters, units, query forms and pattern-only
  placeholders;
- the full device knowledge Markdown.

`buildInstrumentAgentSystemPrompt({deviceContext})` inserts that section into
the general instrument-agent prompt. When no context is available, the prompt
fails closed: it tells the agent not to send commands until a profile is
configured.

The instrument agent updates its context when `*IDN?` reports a model. The same
`DeviceCommandGate` instance is shared by the already constructed VXI-11 tool,
so the validation rules change with the context.

## 10. Error codes

| Code | Meaning |
|---|---|
| `PROFILE_UNKNOWN` | No or unknown profile id. |
| `PROFILE_NOT_LOADED` | Profile not loaded in the current store. |
| `COMMAND_FILE_MISSING` | Command asset not found. |
| `KNOWLEDGE_FILE_MISSING` | Knowledge asset not found. |
| `JSON_SYNTAX_INVALID` | Command file is not valid JSON. |
| `SCHEMA_INVALID` | Required field missing or inconsistent. |
| `SCHEMA_VERSION_UNSUPPORTED` | Schema version is not 1.0. |
| `DUPLICATE_COMMAND_ID` | Duplicate `command_id`. |
| `UNKNOWN_COMMAND` | Header not defined by the profile. |
| `UNKNOWN_PARAMETER` | Parameter not defined for the command. |
| `MISSING_PARAMETER` | Required parameter missing. |
| `INVALID_PARAMETER_VALUE` | Wrong type or value. |
| `INVALID_UNIT` | Unit not documented for the parameter. |
| `UNSUPPORTED_WAVEFORM` | Waveform not supported by the profile. |
| `UNSUPPORTED_CHANNEL` | Channel not allowed by the profile. |
| `UNKNOWN_DEVICE_IDENTITY` | Model matches no profile. |
| `AMBIGUOUS_DEVICE_IDENTITY` | Model matches more than one profile. |
| `PROFILE_INCONSISTENT` | Package metadata does not match the requested profile. |
| `KNOWLEDGE_PROFILE_MISMATCH` | Knowledge file belongs to another profile. |
| `KNOWLEDGE_FILE_INVALID` | Metadata comment or sections invalid. |
| `COMMAND_NOT_RESOLVABLE` | Pattern has placeholders without definitions. |
| `QUERY_NOT_SUPPORTED` | No documented query form. |
| `SET_NOT_SUPPORTED` | Query-only command used as a setter. |
| `DEVICE_COMMUNICATION_FAILED` | Transport/driver failure. |
| `SCPI_ERROR` | Device-reported SCPI error (details carry the code). |

`-222` is carried in `details.device_error_code` for the documented FY6900-only
names rejected by the JDS6600. No device-specific error code is invented by the
profile layer.

## 11. Extraction overview

| Source | Content | Category | Target | Status |
|---|---|---|---|---|
| `systemprompts.dart`, `instrumentAgentSystemPrompt` role | Supported SDS models and channels | B device knowledge | `sds1000xe.md` §1, §3 | Moved |
| same | Command fidelity, tool usage, lookup procedure, command types | A general | General instrument prompt | Retained |
| same | Log diagnostics, error handling, list request, output rules | A general | General instrument prompt | Retained |
| same | Measurement parsing tool usage | A general | General instrument prompt | Retained, generic |
| same | Gain, power-gain, dBm, power/current measurement flows | B device knowledge | `sds1000xe.md` §5 | Moved |
| same | Supported channels C1–C4 and `CHS?` rule | B device knowledge | `sds1000xe.md` §3 | Moved |
| same | Authorized SCPI list (`$sds1000xeScpiReference`) | C commands | `siglent_sds1000xe_scpi_commands.json` | Registry-generated reference replaces the embedded list |
| same | Front-panel `$$SY_FP` table | B/C | `sds1000xe.md` §9 + `specialCommandPatterns` | Moved |
| `systemprompts.dart`, `signalGeneratorScpiReference` | Common/source/output commands | C commands | `fy6900`/`jds6600` JSON | Existing package is authoritative |
| same | Unit and header alias rules | C commands | JSON `syntax` + knowledge §2 | Retained |
| same | Waveform lists and aliases | C/B | JSON `waveforms` + knowledge §4 | Retained |
| same | Phase, duty and limit differences | B device knowledge | `fy6900.md`/`jds6600.md` §5 | Moved |
| same | Error codes and unsupported commands | B device knowledge | `fy6900.md`/`jds6600.md` §7 | Moved |
| same | Example workflow | B device knowledge | `fy6900.md`/`jds6600.md` §6 | Moved |
| `signal_generator_tool.dart` | Keyword gate | A general | Frontend prompt/tool | Retained |
| same | Set order and reset defaults | B device knowledge | `fy6900.md`/`jds6600.md` §6 | Moved |
| same | Common waveform values in the schema | B device knowledge | Profile validation | Replaced by profile validation; examples retained |
| `models.dart`, `fy6900_protocol.dart` | Family limits, waveform mapping | B/C | Knowledge + resolver | Reused as device-specific validation |
| `frontendAgentDefaultSystemPrompt` | Signal-generator routing rule | A general | Frontend prompt | Retained |
| `macroAgentSystemPrompt` | Macro language and tools | A general | Macro prompt | Retained |
| same | Embedded signal-generator SCPI reference | C commands | `device_command_reference` tool | Removed; the Macro Agent queries the profile registry dynamically |
| same | Embedded SDS SCPI reference | C commands | Macro prompt | Retained for oscilloscope macros |
| `controlPanelAgentSystemPrompt` | Front-panel `$$SY_FP` table | B/C | `sds1000xe.md` §9 | Still embedded in the Control Panel agent prompt; controlled by the same raw validator |
| `docs/manual.md` | Sections 10.2 and 15 | B/C | Knowledge files | Source |
| `docs/knowledgebase.md` | Siglent documentation | B | Referenced by `sds1000xe.md` | Source |

Categories: A = general agent knowledge, B = device knowledge,
C = machine-readable command definition.

## 12. Tests

`test/src/devices/device_profile_test.dart` covers:

- loading all three profiles;
- knowledge/profile binding and mismatch rejection;
- missing knowledge, invalid JSON, unsupported schema, duplicate ids;
- preservation of unknown optional fields;
- semantic resolution, unit conversion, channel and unit rejection;
- query-only, action and `OUTP:ALL` handling;
- header aliases, raw validation, pattern-only warnings;
- waveform capabilities and cross-model mapping;
- identity resolution and the `jd6600` alias;
- knowledge section/search access;
- agent context construction and validation.

`test/src/system_prompt_test.dart` covers the general prompt, the placeholder
replacement, the fail-closed fallback and the removal of the embedded SDS
reference from the instrument prompt. All tests run without hardware.

## 13. Migration and compatibility

- The Instrument Agent still accepts the `vxi11` tool and raw SCPI strings, but
  every command passes the active profile's raw validator before transport.
- The `set_signal_generator` tool interface is unchanged; `requestedWaveform`
  is an internal addition used to report waveform mappings.
- The signal-generator provider now validates channel, units and waveform
  against the profile before applying any setting.
- `instrumentAgentSystemPrompt` is now the general prompt with a
  `{{DEVICE_CONTEXT}}` placeholder. Callers must use
  `buildInstrumentAgentSystemPrompt` or pass a `DeviceAgentContext`.
- The Instrument Agent owns the three semantic signal-generator tools
  (`read_signal_generator_status`, `set_signal_generator`,
  `signal_generator_action`). `FrontendAgent` (AI Chat) and `WaveformAgent`
  delegate signal-generator requests through their `scpi_instrument_agent`
  tool; neither agent adds signal-generator tools or signal-generator prompt
  rules.
- The Macro Agent no longer embeds a static signal-generator command reference.
  It uses `device_command_reference`, which reads the authorized commands and
  knowledge from the device-profile registry. The SIG selector syntax
  (`connect(SIG, usb)`, `cmd(SIG, ...)`, `query(SIG, ...)`) remains part of the
  macro language so existing and new SIG macros stay editable. The static SDS
  reference remains in the Macro Agent prompt for oscilloscope macros.
- `SiggenScpiInterpreter` remains the macro transport layer. The device
  registry is the authority for the Instrument Agent and signal-generator tools;
  the interpreter's unit/alias tables mirror the packages and are covered by the
  existing signal-generator tests.

## 14. Open questions and unverified assumptions

1. **Firmware differences** are not specified for any device. The packages and
   knowledge files state `not_specified`; no firmware-specific rule is assumed.
2. **SDS command applicability** – the package provenance note says the list was
   transcribed and not independently verified. A command being listed is not
   proof that every firmware accepts it.
3. **SDS parameter values** – most SDS patterns are pattern-only. The registry
   validates the header and channel and warns that values are not range-checked.
   Adding parameter definitions per command would require a verified source.
4. **FY6900 cross-model mapping** – the manual says "closest preset" and gives
   `PSIN` as an example. The implementation reuses the existing driver table
   (`Fy6900Protocol.waveformIndex`); other mappings are not invented. If the
   table and a future manual disagree, the package should be corrected.
5. **Signal-generator numeric ranges** – the registry validates type, unit,
   enum and channel; the driver validates model-dependent ranges. The packages
   do not duplicate those ranges.
6. **Macro agent** – command details are dynamic through
   `device_command_reference`, but the SIG selector syntax remains part of the
   macro language; see §13.
7. **Control Panel agent** – its prompt still embeds the front-panel table. The
   table is duplicated in `sds1000xe.md`; the agent delegates all commands to
   the same validated instrument sub-agent, so the validator still applies.
8. **Resolution limits and firmware-specific value precision** are not stored
   in the packages and are not validated by the registry.
9. **Pattern-only SDS commands** – the raw validator checks the header, channel
   and token shape but cannot range-check values that the package does not
   define. The tool result carries a warning, and the agent prompt requires the
   agent to report that uncertainty instead of claiming the value is safe.
