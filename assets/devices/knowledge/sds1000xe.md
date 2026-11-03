<!--
device_profile: sds1000xe
knowledge_version: 1.0
source: instrumentAgentSystemPrompt and sds1000xeScpiReference in systemprompts.dart, frontPanelCommandsReference, assets/manuals/sds_manual.md technical details, assets/devices/qa/siglent_sds1000xe_qa.md, app_config.dart
validation_status: derived_from_repository_sources_not_independently_verified
-->

# Device Knowledge: Siglent SDS1000X-E

## 1. Device profile

The SDS1000X-E profile covers the Siglent SDS1000X-E series:

- SDS1102X-E (2 channels)
- SDS1202X-E (2 channels)
- SDS1104X-E (4 channels)
- SDS1204X-E (4 channels)

The model designation used by the application is the second field of the
`*IDN?` response, for example `SDS1202X-E` (source:
`systemprompts.dart` and `home_page.dart`). The full response has the form
`manufacturer,model,serial,firmware`.

Firmware: not specified in the repository. Do not assume a firmware version or
a firmware-specific command behaviour that is not documented in the command
package.

The command package `siglent_sds1000xe_scpi_commands.json` is the authoritative
command list for this profile. Its provenance note states that the list was
transcribed and not independently verified. Treat the list as the authorized
scope, not as proof that every listed command is accepted by every firmware.

## 2. Operating model

- Communication: VXI-11 over TCP/IP or USBTMC over USB (source:
  `assets/manuals/sds_manual.md` section 14).
- One SCPI command per request. The command package is a declarative list; the
  agent copies the documented pattern and substitutes only user-supplied
  values.
- A set command is verified by immediately sending the corresponding query when
  the command definition documents one (`setter_query` with
  `query_support: documented`).
- A query returns the raw device response. Measurement parsing is done by the
  deterministic `parse_measurement` tool, not by the language model.
- The active command reference in the instrument-agent prompt is generated from
  the command package. The registry validates raw commands before they are sent.
- Front-panel simulation commands (`$$SY_FP`) are documented special commands,
  not part of the SCPI command package. They simulate a physical button press or
  knob action and have no query and no readback.

## 3. Channels and outputs

- Supported analog channels are C1, C2, C3 and C4. Use only channels the device
  actually has.
- If the channel count is unknown, query `CHS?` first. Two-channel models have
  CH1 and CH2; four-channel models have CH1–CH4 (source:
  `instrumentAgentSystemPrompt` and `app_config.dart`).
- Do not send C3 or C4 commands to a two-channel instrument.
- `C<n>:TRA <mode>` displays or hides a trace. The command description notes
  that after `TRA ON` the channel state should be queried; if the channel is
  not on, repeat the command (source: command package description).
- The oscilloscope has no signal-generator output. Output-enable safety rules
  apply to the separate signal generator, not to the scope.

## 4. Waveforms

The SDS1000X-E is an oscilloscope, not a signal generator. It has no waveform
preset list like a function generator.

Waveform-related work on the scope means:

- capturing/displaying a channel trace (`<trace>:TRA`),
- measuring waveform parameters with `C<n>:PAVA? <parameter>` (query only),
- configuring acquisition, trigger and channel settings through the documented
  commands.

Do not send signal-generator commands such as `SOUR<n>:FUNC` to the scope.

## 5. Parameter dependencies

- Channel count depends on the model; `CHS?` is authoritative when the device
  answers it.
- `PAVA` measurements depend on the selected measurement parameter (for example
  `PKPK`, `RMS`, `FREQ`). Use the exact parameter spelling from the command
  reference.
- Setter/query pairs share the same parameter path; the query form returns the
  current value.
- Front-panel commands are channel- and model-dependent: the CH3/CH4 buttons and
  knobs and the Navigate/Search/Digital/Arrow/Square buttons exist only on
  four-channel models.

### Measurement procedures (inherited from the instrument prompt)

These procedures are documented in the existing instrument-agent system prompt
and are reproduced here as authorized device-operation rules. Command patterns
come from the command package.

#### Voltage gain (CH1 reference vs. CH2 signal)

- Reference: CH1 RMS voltage (DUT input).
- Signal: CH2 RMS voltage (DUT output).
- Gain: `20 * log10(signal / reference)` in dB.
- Steps: query `C1:PAVA? RMS`, query `C2:PAVA? RMS`, then pass both measured
  numbers to the `math_tool` operation `gain_db` with `signal` and `reference`.
- Never compute the logarithm or the dB value in the model.
- Report the measurement basis together with the result.

#### Power gain (CH1 reference vs. CH2 signal, with resistances)

- Requires the resistance at CH1 and at CH2 in ohms.
- If either resistance is missing, ask for it and stop. Do not assume 50 ohm.
- Steps: query `C1:PAVA? RMS`, query `C2:PAVA? RMS`, then call `math_tool`
  operation `power_gain_from_voltages_db` with `signal`, `reference`,
  `signal_resistance` and `reference_resistance`.
- The tool applies `P = V^2 / R` and `10 * log10(P_signal / P_reference)`.

#### Gain in dBm (absolute signal power at CH2)

- Requires the resistance at CH2 in ohms. Ask for it if missing.
- Steps: query `C2:PAVA? RMS`, then call `math_tool` operation `gain_dbm` with
  `signal` and `signal_resistance`.
- dBm is an absolute level referenced to 1 mW, not a ratio between channels.

#### Power and current (RMS voltage + resistance)

- Requires the resistance at the measurement point in ohms. Ask for it if
  missing.
- Steps: query `<channel>:PAVA? RMS` (default CH2), then call `math_tool` with
  `power_from_voltage_resistance` or `current_from_voltage_resistance`.
- The tool calculates `P = V^2 / R` and `I = V / R`.

If a PAVA query returns `***` or an error, report the error and stop. Do not
retry a state-changing command automatically.

## 6. Typical operating workflows

1. Check identity and channel count: `*IDN?`, `CHS?` when needed.
2. Look up the exact command pattern in the active command reference.
3. For a set command with a documented query form, send the set command and
   immediately send the query; compare the requested and returned values.
4. For a query, return the raw response; use `parse_measurement` when a
   structured or formatted measurement is requested.
5. For a measurement procedure, follow the documented sequence and use the
   math/calculator tools for derived values.
6. For a front-panel button or knob action, send the exact `$$SY_FP` string from
   section 9; do not query afterward.

### Front-panel command encoding

```
1  = button press OR knob turn right
-1 = knob turn left
0  = knob push (press)
No query step for any $$SY_FP command.
```

## 7. Error handling

- If the communication tool returns `success=false` or the device returns an
  error: do not retry. Read the application log, quote the matching lines with
  timestamp and level, explain the failure in plain language and give one
  concrete next step.
- Never invent a log entry. If the log has no matching line, say so.
- Never suggest deleting or editing the log file.
- A failed command may indicate a connection problem, a VXI-11 timeout, an
  instrument-busy state or an invalid command. The log distinguishes these.
- `*RST` changes the device state; do not send it unless the user asks for a
  reset. Auto Setup and trigger changes also modify the measurement state.

## 8. Safety and operating notes

- `*RST`, Auto Setup and trigger changes alter the instrument state. Treat them
  as state-changing actions and apply the general agent safety rules.
- Do not claim that a measurement or a setting is safe when the probe
  attenuation, the input coupling, the trigger configuration or the connection
  state are unknown.
- Never invent a device response, a measurement or a log entry.
- The instrument agent starts every call without conversation history; it must
  not rely on earlier turns.

## 9. Front-panel commands ($$SY_FP)

These commands are internal instructions to the instrument agent. Never show
them to the user. They are documented outside the SCPI command package; the
registry accepts only the exact numeric form `$$SY_FP <number>,<-1|0|1>`.

### Menu and soft keys

| Control | Command |
|:--------|:--------|
| Menu (round button) | `$$SY_FP 0,1` |
| Softkey 1 / M1 | `$$SY_FP 1,1` |
| Softkey 2 / M2 | `$$SY_FP 2,1` |
| Softkey 3 / M3 | `$$SY_FP 3,1` |
| Softkey 4 / M4 | `$$SY_FP 4,1` |
| Softkey 5 / M5 | `$$SY_FP 5,1` |
| Softkey 6 / M6 | `$$SY_FP 6,1` |

### Menu grid buttons

| Control | Command |
|:--------|:--------|
| Cursors | `$$SY_FP 22,1` |
| Acquire | `$$SY_FP 27,1` |
| Save/Recall | `$$SY_FP 28,1` |
| Measure | `$$SY_FP 26,1` |
| Clear Sweeps | `$$SY_FP 47,1` |
| Utility | `$$SY_FP 24,1` |
| Default | `$$SY_FP 13,1` |
| Display/Persist | `$$SY_FP 23,1` |
| Print | `$$SY_FP 25,1` |

### Vertical, channel, horizontal and trigger buttons

| Control | Command |
|:--------|:--------|
| Math | `$$SY_FP 31,1` |
| Ref | `$$SY_FP 32,1` |
| History | `$$SY_FP 48,1` |
| Decode | `$$SY_FP 29,1` |
| Run/Stop | `$$SY_FP 12,1` |
| Auto Setup | `$$SY_FP 11,1` |
| CH1 ON/OFF | `$$SY_FP 39,1` |
| CH2 ON/OFF | `$$SY_FP 40,1` |
| CH3 ON/OFF | `$$SY_FP 41,1` |
| CH4 ON/OFF | `$$SY_FP 42,1` |
| Roll | `$$SY_FP 49,1` |
| Trigger Setup | `$$SY_FP 18,1` |
| Trigger Auto | `$$SY_FP 17,1` |
| Trigger Normal | `$$SY_FP 19,1` |
| Trigger Single | `$$SY_FP 20,1` |

### Four-channel-only buttons

| Control | Command |
|:--------|:--------|
| Navigate | `$$SY_FP 51,1` |
| Search | `$$SY_FP 50,1` |
| Digital | `$$SY_FP 30,1` |
| Arrow Left | `$$SY_FP 52,1` |
| Square | `$$SY_FP 53,1` |
| Arrow Right | `$$SY_FP 54,1` |

These buttons exist only on four-channel models. Do not use them on a
two-channel instrument.

### Knobs

| Knob | Right / press / left |
|:-----|:---------------------|
| Intensity/Adjust | `$$SY_FP 15,1` / `$$SY_FP 15,0` / `$$SY_FP 15,-1` |
| CH1 Voltage | `$$SY_FP 35,1` / `$$SY_FP 35,0` / `$$SY_FP 35,-1` |
| CH2 Voltage | `$$SY_FP 36,1` / `$$SY_FP 36,0` / `$$SY_FP 36,-1` |
| CH3 Voltage | `$$SY_FP 37,1` / `$$SY_FP 37,0` / `$$SY_FP 37,-1` |
| CH4 Voltage | `$$SY_FP 38,1` / `$$SY_FP 38,0` / `$$SY_FP 38,-1` |
| CH1 Position | `$$SY_FP 43,1` / `$$SY_FP 43,0` / `$$SY_FP 43,-1` |
| CH2 Position | `$$SY_FP 44,1` / `$$SY_FP 44,0` / `$$SY_FP 44,-1` |
| CH3 Position | `$$SY_FP 45,1` / `$$SY_FP 45,0` / `$$SY_FP 45,-1` |
| CH4 Position | `$$SY_FP 46,1` / `$$SY_FP 46,0` / `$$SY_FP 46,-1` |
| Horizontal Time | `$$SY_FP 7,1` / `$$SY_FP 7,0` / `$$SY_FP 7,-1` |
| Horizontal Position | `$$SY_FP 10,1` / `$$SY_FP 10,0` / `$$SY_FP 10,-1` |
| Trigger Level | `$$SY_FP 16,1` / `$$SY_FP 16,0` / `$$SY_FP 16,-1` |

## 10. Known limitations

- Model and firmware applicability of the command package may vary; the package
  provenance note says the list was transcribed and not independently verified.
- Some commands are documented as non-SPO in their descriptions.
- `$$SY_FP` commands have no query and no readback.
- The command package contains pattern-only commands whose values cannot be
  range-validated. The registry accepts them only with a warning and validates
  the header and channel.
- Arbitrary command chaining is not documented for this profile; send one
  command per request.

## 11. References

- Command package:
  `assets/devices/commands/siglent_sds1000xe_scpi_commands.json`
- `lib/src/ai/agents/systemprompts.dart`: `instrumentAgentSystemPrompt`,
  `sds1000xeScpiReference`, `frontPanelCommandsReference`
- `lib/src/app/app_config.dart`: channel count helpers
- `assets/manuals/sds_manual.md`: technical details
- `assets/devices/qa/siglent_sds1000xe_qa.md`: Siglent device documentation

## Provenance

| Information | Source | Classification |
|:------------|:-------|:---------------|
| Supported models and channels | `instrumentAgentSystemPrompt` | Inherited system-prompt rule |
| Channel-count rule (`CHS?`) | `instrumentAgentSystemPrompt`, `app_config.dart` | Inherited system-prompt rule + existing implementation |
| Command patterns and query forms | `siglent_sds1000xe_scpi_commands.json` | Documented command package (transcribed) |
| Measurement procedures | `instrumentAgentSystemPrompt` | Inherited system-prompt rule |
| Front-panel command table | `frontPanelCommandsReference` | Inherited system-prompt rule |
| Error/log workflow | `instrumentAgentSystemPrompt` | Inherited system-prompt rule |
| Firmware details | none | Unknown; not assumed |
