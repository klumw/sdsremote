#

## 1. Introduction & Overview

Welcome to the SDS-Remote Help Center.

***SDS-Remote*** is a remote control application for the Siglent SDS 1000X-E series.
It combines instrument control and waveform analysis with data logging, macro recording and playback, screen capture and an optional AI-assisted chat interface.

### 1.1 Compatibility

SDS-Remote is designed for the **Siglent SDS 1000X-E** series oscilloscopes (SDS1104X-E, SDS1204X-E, etc.).
It communicates with the instrument via VXI-11 over TCP/IP or via USBTMC (USB).

The application may partially work with other Siglent series that share the same SCPI command set.
Only the SDS 1000X-E series is tested and officially supported.

**Minimum Requirements:**

| Requirement | Specification |
|:------------|:--------------|
| Operating System | Linux or Windows |
| Display Resolution | 1100 × 600 minimum |
| Oscilloscope | Siglent SDS 1000X-E series |
| Network | TCP/IP for VXI-11, or USB for USBTMC |
| Internet (AI features) | Required for [AI chat](#42-ai-chat-interface) functionality |

### 1.2 General Usage Advice

**Workflow Recommendations**

* Start by connecting to the oscilloscope using the **Settings** panel. Verify the status bar shows `ONLINE` before proceeding.
* Use the **[Control Panel](#9-control-panel)** for interactive operation — it provides immediate visual feedback through the screen capture.
* Use **[Acquire Waveform](#8-acquire-waveform)** when you need precise measurements,  
  cursor analysis, or [reference waveform](#86-reference-waveforms) comparison.
* Use the **[Data Logger](#6-data-logger)** for long-term monitoring and trend analysis.
* Use the **[Macro Recorder](#7-macro-recorder)** to automate repetitive tasks. Record a sequence once, then replay it as needed.
* Save your oscilloscope configuration as a **Profile** before starting critical measurements so you can restore it later.
* The **AI Chat** is most effective for oscilloscope related questions and SCPI command assistance.

**Performance Tips**

* Network (VXI-11) connections are generally more reliable than USB for sustained operation.  
  USB support is experimental and may have device-specific compatibility issues.
* Screen captures (Control Panel) update after every command, which takes approximately 1–3 seconds depending on network latency and screen complexity.  
  Rapid consecutive button presses are rate-limited to prevent command queue overflows.
* Waveform acquisition downloads the full dataset from the oscilloscope, which may take several seconds.  
  The waveform is downsampled for rendering performance.
* The Data Logger queries the oscilloscope at the configured interval. Very short intervals (10 seconds) with many parameters enabled may cause measurement timing jitter due to SCPI query overhead.

**File Storage**

All user data (screenshots, waveforms, profiles, macros, reports) is stored under the application data directory:

| Platform | Path |
|:---------|:-----|
| Linux | `~/.local/share/sdsremote/` |
| Windows | `%LocalAppData%\sdsremote` |

See [12. Application Directory](#12-application-directory) for a complete breakdown of subdirectories.

### 1.3 Known Limitations

* **AI Accuracy** — The AI chat subsystem uses large language models that may generate incorrect SCPI commands or inaccurate technical advice.  
  Always verify critical commands before execution. SDS-Remote is not liable for any damage resulting from AI-generated instructions.
* **Single Device** — The application connects to one oscilloscope at a time. Simultaneous control of multiple instruments is only supported in the Macro-Recorder.
* **No Data Streaming** — The application uses request-response SCPI communication.  
  Continuous high-speed data streaming (e.g., at the full sample rate) is not supported.  
  The Data Logger operates at minimum 10-second intervals.
* **Macro Playback** — Macros run on a dedicated VXI-11 connection. During playback, most UI functions are disabled. The Control Panel, Acquire Waveform, Data Logger, and AI Chat cannot be used concurrently with macro playback.
* **Waveform Downsampling** — Acquired waveforms are downsampled for display to maintain rendering performance.  
  CSV exports contain the same downsampled points that are displayed, with their actual sample timestamps.
* **Gain (dB) with very small signals** — Below an RMS voltage of 10 mV on either channel the gain calculation reflects the oscilloscope's noise floor and its 8 bit quantisation instead of the device under test,  
  and the result can vary by tens of decibels between samples.  
  The Data Logger records no gain value for such samples (see the note in [6.2 Measurable Parameters](#62-measurable-parameters)).

---

#### Connection Requirement

> **Note:** Network-based (IP address) and direct USB control is supported. USB support is experimental.  
> For network connection ensure that the oscilloscope and host system are connected to the same network.

---

## 2. User Interface

### 2.1 Top Bar

* **[Control Panel](#9-control-panel)**  

  * Displays oscilloscope screen
  * Provides a virtual control interface
  * Disabled when offline or during active operations

* **[Acquire Waveform](#8-acquire-waveform)**  
  * Captures waveform data from selected channels
  * Displays status during acquisition
  * Supports cursor measurements

* **AI**  
  * Shows/hides [AI chat](#42-ai-chat-interface) interface
  * Disabled if AI is not configured

* **Profiles**  
  * Save and Upload your device configuration

* **[Data Logger](#6-data-logger)**
  * Log key parameters over time
  * Export pdf reports or save data points in a csv file

* **Bode**
  * Opens the [Bode Plot](#10-bode-plot) panel when a supported signal generator is configured and detected
  * Requires the oscilloscope to be online

* **[Macro Recorder](#7-macro-recorder)**
  * Record, edit and play back SCPI command sequences
  * Automate repetitive measurement and configuration tasks
  * Supports variables, conditionals and loops for advanced automation
  * Button label changes to **Recording...** during recording and **Playback** during playback

* **Help**
  * Opens this documentation
  * The sparkle icon next to the **SDS-Remote Help** title opens the AI Help Assistant.
    It answers questions from this manual and links directly to the matching sections.    
  * The sparkle icon is only active while an AI provider, API token and model are configured (see [4. AI System](#4-ai-system))  
  
* **News**  
  * Displays application updates

* **Settings**  
  * Opens configuration panel (IP and AI settings, export options)

* **Save**  
  * Saves images, reports and csv data for the different app functionalities
  * All files are saved in the application working directory

* **Timelapse** (clock icon)
  * Captures the oscilloscope screen at a fixed interval into a timestamped folder (see [8.11 Timelapse](#811-timelapse))
  * While a run is active, the icon shows the rotating arrows indicator and pressing it stops the run

> **Tip:** The toolbar button of the currently open view is highlighted with a cyan border: **Control Panel** or **Acquire Waveform**, and the open panel (AI, Profiles, Data Logger, Bode, Macro Recorder or Help).

---

### 2.2 Status Bar

* **Device IP**: Connected oscilloscope address if network connection is set in the configuration
* **Status Indicator**:
  * `ONLINE` (green)
  * `OFFLINE` (red)

---

## 3. Settings

The **Settings** panel is opened by clicking the gear icon in the top toolbar. All settings are persisted to the application preferences file and restored on the next launch.

### 3.1 Opening Settings

Click the **Settings** icon (gear) in the top toolbar. The panel appears as a floating dialog titled "Device Configuration".

### 3.2 Connection Mode

Select the physical connection type used to communicate with the oscilloscope:

* **Network (VXI-11)** — Connects via TCP/IP using the VXI-11 protocol. This is the recommended mode for most setups. Requires the oscilloscope to be on the same network as the host computer.
* **USB (USBTMC)** — Connects via USB using the USBTMC protocol. The device is auto-detected — no IP address is needed. USB support is experimental and may have compatibility issues depending on the device's USB firmware version.

### 3.3 IP Address

*Available only in Network (VXI-11) connection mode.*

Enter the IPv4 address of the oscilloscope. The address must be reachable from the host computer on port 111.

**Example:** `192.168.1.100`

The current IP address is also displayed in the status bar at the bottom of the main window.  
If the address is incorrect or the device is unreachable, the status bar shows `OFFLINE` in red.

### 3.4 AI Provider Settings

Refer to [4.1 AI Model Configuration](#41-ai-model-configuration) for detailed instructions on configuring the [AI chat](#42-ai-chat-interface) feature.  
The Settings panel provides three fields for AI configuration:

* **AI Provider** — Dropdown list of supported providers (DeepSeek, OpenAI, Anthropic, Google, Mistral, Cohere, EdenAI, OpenRouter, xAI).
* **AI API Token** — Your provider API key. The field masks input for privacy. A minimum of 8 characters is required.
* **LLM Model** — The exact model name string as specified by your provider (e.g. `gpt-4o`, `deepseek-v4-flash`, `claude-haiku`).

The AI chat feature is only enabled when all three fields are populated. If the AI button in the top toolbar appears disabled, verify these settings.

### 3.5 Export Options

Two toggle switches control default export behavior across the application:

* **Save CSV data** — When enabled, waveform acquisitions and data logger recordings automatically export a companion CSV file alongside the primary output (PDF report).  
  CSV files contain raw numerical data suitable for import into spreadsheet applications or analysis tools.  
  When disabled, only the primary output format is saved.
* **Ask for filename on save** — When enabled, a dialog prompts for a custom filename prefix before each save operation.  
  When disabled, default prefixes are used (e.g. `screen_dump`, `waveform`, `data_logging_report`).  
  A numeric suffix is always appended to avoid overwriting existing files, regardless of this setting.

Both settings take effect immediately and persist across application restarts.

### 3.6 Signal Generator

Select the signal generator used by the [Bode Plot](#10-bode-plot) and the [signal generator window](#911-signal-generator-window-ctrlj):

* **No Signal Generator** — disables generator features (default).
* **JDS6600** — JOY-IT/Juntek JDS6600 and JDS6600-Lite.
* **FY6900** — FeelElec FY6900 series.

The selection is persisted as `siggen_device` and restored on the next launch. When a generator is selected, the application scans the serial ports, identifies it via `*IDN?` and enables the **Bode** button and the signal generator window (Ctrl+J).  
The detected model supplies the frequency, amplitude and offset limits; see the Bode Plot chapter ([10. Bode Plot](#10-bode-plot)).

### 3.7 Network Connection

Basic connection setup for network mode. Skip steps 1–3 if USB is selected in **Connection Mode**.

1. Connect the oscilloscope to the same network as the host computer.
2. Obtain the oscilloscope's IP address.
3. In **Settings**, enter the IP address in the **IP Address** field (see [3.3 IP Address](#33-ip-address)).
4. Click **SAVE CONFIGURATION**.
5. Verify that the status bar shows your device as `ONLINE`.

For USB (USBTMC), select that connection mode instead and connect the USB cable; the device is auto-detected.

### 3.8 Saving Configuration

Click the **SAVE CONFIGURATION** button to persist all settings. The application:

1. Stores the connection mode, IP address, signal generator selection, AI provider, API token, and model name to the preferences file.
2. Reconnects to the oscilloscope using the new connection settings.
3. Initializes the AI chat service if all AI fields are populated.
4. Closes the Settings panel.

The status bar updates to reflect the new connection state. If `ONLINE` is shown, the oscilloscope is reachable and ready for operation.

The main window's size and position are saved automatically when the application closes and restored on the next launch.  
If the saved position is no longer visible on a connected display (for example after disconnecting a monitor),  
the window opens centered instead.

> **Note:** The API token is stored in plain text in the preferences file (`preferences/preferences.json`) within the application directory.  
> Ensure appropriate file system permissions if working in a shared environment.

### 3.9 Calculator Shortcut

The engineering calculator opens with **Ctrl+R** by default. In **Settings → Calculator → Window shortcut** choose one of:

| Shortcut | Notes |
|:---------|:------|
| `Ctrl` + `R` | Default |
| `Ctrl` + `Shift` + `R` | Alternative if Ctrl+R is reserved by the desktop |
| `Ctrl` + `Alt` + `C` | Mnemonic alternative |
| `F9` | Keyboard-only alternative |

The selection is stored as `calculator_shortcut` and restored on the next launch.
There is no toolbar button: the calculator is available only through the configured shortcut.
The shortcut is handled globally in the main window; text fields do not use Ctrl+R natively.

---

## 4. AI System

The [AI chat](#42-ai-chat-interface) feature enables natural-language interaction with the oscilloscope — ask device-related questions,  
send SCPI commands, or get troubleshooting help.  
The AI communicates directly with your chosen provider's API (no intermediate server) and requires an active internet connection.

### 4.1 AI Model Configuration

Before using the AI, configure it in the **Settings** panel (see [3.4 AI Provider Settings](#34-ai-provider-settings)):

1. Open **Settings** (gear icon in the top toolbar).
2. Select your **AI Provider** from the dropdown (DeepSeek, OpenAI, Anthropic, Google, Mistral, Cohere, EdenAI, OpenRouter, or xAI).
3. Enter your **API Key** (token). The field masks input for privacy. Minimum 8 characters.
4. Enter the **LLM Model** name exactly as specified by your provider.
5. Click **SAVE CONFIGURATION**.

After saving, the **AI** button in the top toolbar becomes enabled (colored icon instead of greyed out).  
The application initializes the agent system immediately — no restart is needed.

#### Supported Providers

| Provider | Notes |
|:---------|:------|
| DeepSeek | Recommended default. Good balance of speed and accuracy. |
| OpenAI | Requires an OpenAI API key. |
| Anthropic | Claude models. Requires an Anthropic API key. |
| Google | Gemini models. Requires a Google AI Studio API key. |
| Mistral | Requires a Mistral API key. |
| Cohere | Requires a Cohere API key. |
| EdenAI | Multi-provider gateway. |
| OpenRouter | Multi-provider gateway with unified billing. |
| xAI | Grok models. Requires an xAI API key. |

#### Recommended Models

The following models are verified to work with the application:

- deepseek-flash
- gpt-6-luna
- gemini-flash
- claude-sonnet
- qwen-3.x-max
- mistral-code

For the exact model name string required by your provider, consult your provider's API documentation or model listing page.

### 4.2 AI Chat Interface

#### Opening and Closing

Click the **AI** button in the top toolbar to open or close the chat interface. The chat replaces the main content area ([Control Panel](#9-control-panel), Waveform, etc.) while open.  
Your conversation history is preserved while the panel remains open; closing and reopening the chat clears the history.

The Macro Editor ([7.2 Macro Editor](#72-macro-editor)), the Control Panel ([9.10 AI Control Panel Assistant](#910-ai-control-panel-assistant)) and the Engineering Calculator ([11.8 Calculator AI Assistant](#118-calculator-ai-assistant-optional)) have their own AI assistants that work directly in those panels without replacing them.

#### Interface Layout

The chat window consists of:

* **Message Area** — A scrollable conversation history. User messages appear right-aligned in cyan bubbles. AI responses appear left-aligned with grey backgrounds. The area auto-scrolls as new content arrives.
* **Streaming Indicator** — While the AI is generating a response, a pulsing cyan cursor (`▊`) might appear at the end of the message, indicating more content is coming.
* **Input Field** — A text field at the bottom for typing messages. Press **Enter** to send (Shift+Enter for newline is not supported — text wraps automatically).
* **Send Button** — A paper-plane icon to the right of the input field. Disabled while the AI is generating a response.
* **Stop Button** — While the AI is generating a response, the send button changes to a square stop button.  
  Pressing it aborts the response immediately and marks it as `terminated by user`.

#### Message History

The chat maintains a multi-turn conversation history within the session. The AI remembers previous exchanges, so you can ask follow-up questions or refine commands without repeating context.  
Closing the chat panel clears the history; a fresh conversation starts when reopened.

### 4.3 Capabilities and Usage

#### Device Questions (Knowledge Base)

Ask questions about oscilloscope features, specifications, measurements, or troubleshooting.  
The AI searches the built-in knowledge base and returns the relevant documentation.

**Examples:**
* *"What is the maximum sample rate of the oscilloscope"*
* *"How do I configure the trigger delay?"*
* *"Explain the difference between Auto and Normal trigger mode."*
* *"What SCPI command sets the timebase?"*

The knowledge base is bundled with the application.
The Search Agent queries it and returns the most relevant sections.

#### SCPI Command Execution

Describe what you want to do in natural language, and the Instrument Agent translates it to SCPI commands sent to the connected oscilloscope.

**Examples:**
* *"Set channel 1 vertical scale to 1V/div"* → sends `C1:VDIV 1V`
* *"Get the current timebase setting"* → sends `TDIV?` and returns the value
* *"Switch channel 1 on"* → sends `C1:TRA ON`
* *"What is the device identification?"* → sends `*IDN?` and returns the response
* *"What is the amplification from CH2 to CH1?"*

#### Native SCPI Commands

For precise control, use the **send command** syntax to bypass natural-language interpretation:

```
send command C1:VDIV 500mV
```

This sends the SCPI command directly to the oscilloscope without any translation.  
The device response (for queries) is returned verbatim.

**Examples:**
* `send command C1:TRA ON`
* `send command C1:VDIV?`
* `send command *IDN?`

#### SDS-Remote Software Help

When you ask about the SDS-Remote application itself (installation, configuration, features),  
the AI directs you to the built-in Help system rather than attempting to answer from its own knowledge.

### 4.4 Limitations and Best Practices

* **AI Accuracy** — The AI does not use its training data for oscilloscope answers.  
  All responses are grounded in the knowledge base or actual device responses. However, the underlying language model may still misinterpret queries or produce incorrect SCPI command syntax.  
  Always verify critical commands.
* **Provider Dependency** — Response quality and speed depend entirely on the chosen AI provider and model.  
  Different providers have different strengths for technical content.
* **Internet Required** — AI features require an active internet connection to reach the provider's API.  
  Without internet, the AI button is effectively non-functional even if configured.
* **API Costs** — The AI communicates directly with your provider's API. Usage may incur costs according to your provider's pricing. Monitor your API usage to avoid unexpected charges.
* **English Recommended** — The knowledge base and system prompts are written in English.  
  Queries in other languages may produce less accurate results.

> **Warning:** The AI subsystem may generate inaccurate information or incorrect operating instructions.  
> Always verify critical SCPI commands before execution. SDS-Remote is not liable for any damage resulting from AI-generated instructions.


### 4.5 Troubleshooting

* **AI button appears disabled (grey)**
  * The AI has not been configured or configuration is incomplete.
  * Verify that all three fields in Settings are populated: Provider, API Token, and Model name.
  * The API token must be at least 8 characters.
  * Save the configuration and check that the button becomes enabled.

* **No response / timeout**
  * Verify your API credentials and account quota.
  * Check internet connectivity.
  * Try a different model — some models may be temporarily unavailable.
  * Check the application logs at `/tmp/sds/logging/sds.log` (Linux) or `%TEMP%\sds\logging\sds.log` (Windows) for detailed error messages.

* **Irrelevant or incorrect SCPI commands**
  * Use the **send command** syntax for precise control: `send command C1:VDIV 1V`.
  * Try rephrasing your request more specifically.
  * Switch to a more capable model (e.g. `gpt-4o` instead of a smaller/faster model).

* **Knowledge base returns no results**
  * The question may be outside the documented scope of the SDS1000X-E series.
  * Try rephrasing with more general terms.
  * Consult the official Siglent documentation for topics not covered in the knowledge base.

* **Provider API errors**
  * Verify the API token is correct and has not expired.
  * Check that your provider account has available quota/credits.
  * Ensure the model name exactly matches your provider's naming convention.
  * Some providers require specific account tiers for API access.

---

## 5. Device Profiles

The **Profiles** feature allows you to save the complete oscilloscope configuration and restore it later.  
This is useful for switching between measurement setups, sharing instrument configurations, or restoring a known-good state before critical measurements.

Profile files are stored with the `.lss` extension in the `profiles/` subdirectory of the application working directory.  
The file format is SCPI XML — the raw configuration data provided by the oscilloscope's `PNSU?` query.

### 5.1 Profiles Panel

Click the **Profiles** button in the top toolbar to open the Profiles panel. The panel displays:

**Header**

* Panel title "Profiles" with a save icon.
* **Close** button (X) returns to the main view.

**Save Area**

* A text input field labeled "Create New Profile" for entering a profile name.
* **Name restrictions**: Maximum 30 characters. Only alphanumeric characters (`a–z`, `A–Z`, `0–9`), underscores (`_`), and hyphens (`-`) are allowed.
* A **Save** button that reads the current oscilloscope configuration via the `PNSU?` SCPI query and stores it as an `.lss` file.
* During the save operation (which can take up to 15 seconds for large configurations),  
  the Save button is disabled and shows a progress indicator.

**File List**

* Lists all saved `.lss` profile files in the `profiles/` directory.
* Each entry shows the file name and last modified date.
* **Sorting**: Sort by **Name** or **Date** in ascending or descending order using the sort controls above the list.
* Per-file actions:
  * **Load** (upload icon) — Sends the stored XML configuration to the oscilloscope via `profileWrite`.  
    Only enabled when the device is online. The load operation has a 15-second timeout.
  * **Delete** (trash icon) — Permanently removes the profile file.

> **Note:** After a profile is loaded, the oscilloscope screen automatically refreshes to reflect the restored configuration.

### 5.2 Saving a Profile

1. Configure your oscilloscope as desired (using the physical device, [Control Panel](#9-control-panel), or [AI chat](#42-ai-chat-interface)).
2. Click the **Profiles** button in the top toolbar.
3. Enter a descriptive name in the "Create New Profile" field.
4. Click **Save**. The application sends `PNSU?` to the oscilloscope, receives the full XML configuration, and saves it to the `profiles/` directory.

> **Note:** Saving a profile requires the device to be online. The `PNSU?` query returns an IEEE 488.2 definite-length block containing the complete instrument setup in XML format.  
> The save operation may take several seconds depending on configuration size.

### 5.3 Loading a Profile

1. Ensure the oscilloscope is connected and online.
2. Open the **Profiles** panel.
3. Click the **Load** icon next to the desired profile.
4. The profile's XML configuration is sent to the oscilloscope as a single atomic write via `profileWrite`.
   USB connections may have problems under Linux depending on the device's USB firmware version.
5. The oscilloscope screen automatically refreshes after the profile is applied.

> **Note:** Loading a profile will overwrite the current oscilloscope configuration.  
> The operation cannot be undone on the device, so consider saving the current configuration first if you may need it later.

### 5.4 Using Profiles in Macros

Profile loading is supported in macro scripts via the `loadProfile` command (see [7.5.4 Device Profiles](#754-device-profiles)).  
When macro recording is active, loading a profile through the [Profiles panel](#51-profiles-panel) automatically appends a `loadProfile` command to the macro script,  
making it easy to include profile restoration in automated workflows.

### 5.5 Deleting a Profile

Click the **Delete** icon next to a profile to permanently remove it from the `profiles/` directory.  
Deleted profiles cannot be recovered.

## 6. Data Logger

The **Data Logger** records oscilloscope measurement parameters over time, plots them on a real-time chart, and generates PDF reports.  
It is ideal for monitoring signal drift, characterizing component behavior over time, or documenting long-duration measurements.

### 6.1 Opening the Data Logger

Click the **Data Logger** button in the top toolbar to open the Data Logger panel.  
The panel replaces the main waveform/control panel area and shows a configuration dialog when first opened.  
The button icon rotates during active recording.

### 6.2 Measurable Parameters

The following parameters can be logged. Vpp, Mean, Rms, Duty and Freq are available per channel (CH1–CH4 on four-channel instruments); Gain (dB) is a single cross-channel measurement.  
Up to **5 parameters** total can be selected simultaneously:

| Parameter | Channels | Description |
|:----------|:---------|:------------|
| **Vpp** | CH1–CH4 | Peak-to-peak voltage |
| **Mean** | CH1–CH4 | Average (mean) voltage |
| **Rms** | CH1–CH4 | Root mean square voltage |
| **Duty** | CH1–CH4 | Duty cycle (percentage) |
| **Freq** | CH1–CH4 | Signal frequency |
| **Gain (dB)** | CH1 vs. CH2 | Voltage gain from the reference channel (CH1) to the signal channel (CH2) (unchanged on four-channel instruments) |

On startup all voltage values are automatically scaled by the probe attenuation factor.

#### Gain (dB)

Measures the voltage gain between two channels and records it as a decibel value:

`gain = 20 × log10( V_CH2 / V_CH1 )`

* **CH1 (reference)** — the reference signal, typically the DUT input.
* **CH2 (signal)** — the signal under test, typically the DUT output.
* Both channels are measured as **RMS** voltage.
* A positive result means CH2 carries the larger measured voltage; a negative result means it carries the smaller one.

| CH1 (reference) | CH2 (signal) | Gain |
|---:|---:|---:|
| 1.0 V | 1.0 V | 0.00 dB |
| 1.0 V | 2.0 V | +6.02 dB |
| 1.0 V | 0.5 V | -6.02 dB |
| 100 mV | 500 mV | +13.98 dB |
| 100 mV | 10 mV | -20.00 dB |
| 100 mV | 5 mV | no value (below the noise floor) |

Each voltage is scaled by its own probe divider before the ratio is taken, so differing probe attenuation on the two channels is handled correctly rather than biasing the result.  
If either voltage cannot be measured, or it falls below the noise floor described below, no gain value is recorded for that sample.

> **Note — very small signals:** Gain (dB) is only meaningful while both RMS voltages are well above the oscilloscope's own noise floor and its 8 bit quantisation.  
> Below an RMS voltage of **10 mV** a single ADC step is a large fraction of the signal,  
> so the calculated gain no longer describes the device under test: it can jump by tens of decibels from one sample to the next although nothing changed in the circuit.  
> For that reason **no gain value is recorded when either channel's RMS voltage is below 10 mV** — the sample simply carries no Gain (dB) entry,  
> which appears as an empty cell in the CSV export and as `Gain: invalid` in the cursor popup,  
> and the chart draws its line straight across such samples.  
> A reading of exactly 10 mV is still measured. If the signal under test is genuinely smaller than that, the gain has to be determined where the levels are higher, for example after an amplifier stage.

> **Note:** Gain (dB) is a **voltage** gain, not a power gain. A power gain in dB would additionally require the impedance at both measurement points to be known.  
> If the impedance of both measurement points is equal, voltage gain in dB equals power gain in dB.

### 6.3 Configuration

When the Data Logger panel opens in the **configuring** state, a setup dialog is displayed with the following controls:

#### Measurement Selection

* Toggle checkboxes for each parameter on CH1–CH4 independently. CH3 and CH4 are offered only when a four-channel oscilloscope was detected.
* A counter shows the number of selected parameters (maximum 5).
* At least one parameter must be selected before starting.
* **Gain (dB)** has a single toggle rather than one per channel, because it is derived from both channels at once.  
  It counts as one parameter.

#### Measurement Interval

* Slider from **10 to 60 seconds** in 5-second steps.
* Controls how frequently the oscilloscope is queried for new measurements.

#### Recording Duration

* A row of preset buttons: **1 min, 5 min, 10 min, 20 min, 30 min, 1 h, 2 h, 6 h, 12 h, 24 h**.
* The total number of data points is calculated as `(duration × 60) ÷ interval + 1`.

#### Report Name

* An optional text field (up to **150 characters**) for a descriptive report name.
* This name appears at the top of the real-time chart and in the PDF report heading.

#### Alarm Rules

For every selected parameter an optional threshold rule can be configured:

* **Lower** and **Upper** fields accept a numeric value in the parameter's unit. An empty field disables that bound.
* Values **equal** to a bound are still inside the allowed range; only strict crossings raise an alarm.
* A checkbox enables or disables the rule without deleting its bounds.
* Rules are evaluated after every sample. An alarm is raised once when the value leaves the range and re-arms after it returns, so a signal that stays outside does not produce repeated events.
* Invalid samples (missing value, `***` out-of-range response, gain below the noise floor) neither raise nor clear an alarm.

### 6.4 Real-Time Plot

Once recording starts, the Data Logger panel expands to show a real-time XY plot in the main area:

**Chart Display**

* Time axis (X) with automatic unit scaling: seconds (`s`), minutes (`min`), or hours (`h`) depending on total duration.
* Each selected parameter is plotted as a separate colored line.
* Voltage measurements (Vpp, Mean, Rms) share the left Y-axis; frequency uses the right Y-axis; duty cycle and Gain (dB) use their own auto-scaled inner axes on the left,  
  labelled with a `%` and a `dB` suffix respectively.  
  The gain axis always includes the 0 dB (unity gain) reference line.
* The elapsed time counter updates with each new data point.

**Hover Tooltip**

* Hover the mouse over the chart to see exact measurement values at any time position.
* The tooltip shows the time and all enabled parameter values (respecting line visibility toggles).

**Legend Toggle Chips**

* Below the chart, colored legend chips represent each active measurement line.
* Click a chip to **hide** or **show** that line on the chart — useful for focusing on specific parameters in multi-line plots.

**Statistics Strip**

* Once at least two samples are available, a strip below the legend shows per parameter: mean (μ), sample standard deviation (σ), the least-squares trend per minute and the percentage drift from the first to the last valid value.
* Invalid samples are skipped; a parameter without valid values is omitted.

**Alarm Overlay and Events**

* Configured bounds are drawn as dashed red lines on the corresponding axis (voltage, frequency, duty cycle or gain). Hide a line with its legend chip to hide its threshold lines as well.
* Each threshold crossing is marked with a faint vertical line and a red dot at the measured value.
* A red status strip shows currently active alarms and the most recent events with their recording time, parameter and value.

**Running Indicator**

* During recording, a pulsing green indicator is shown in the header area.

### 6.5 Controls

The bottom control bar adapts to the current state:

| State | Available Controls |
|:------|:-------------------|
| **Configuring** | **Start** — Begins recording with the current configuration |
| **Running** | **Stop** — Stops recording immediately and finalizes data |
| **Stopped** | **New** — Returns to the configuration dialog (clears data). **Restart** — Starts a new recording with the same configuration (clears previous data, keeps settings). |

Clicking **Close** (X) in the header returns to the main view. The Data Logger state (plot data, configuration, hidden lines) is preserved so you can close and reopen the panel without losing results.

### 6.6 PDF Report

After recording is stopped (and at least 2 data points exist), save a PDF report by clicking the **Save** button in the top toolbar.  
The report includes:

* **Headline** — "Data Logger Report" title.
* **Report Name** — The description entered during configuration.
* **Chart Image** — A PNG capture of the real-time plot.
* **Measurement Values Table** — For each enabled parameter, including Gain (dB):
  * Start value (first data point)
  * End value (last data point)
  * Minimum value
  * Maximum value
* **Statistics Table** — For each enabled parameter: mean, median, sample standard deviation, linear trend per minute and percentage drift.
* **Alarm Events Table** — When a rule fired: recording time, parameter, measured value and the violated bound.
* **Total Recording Time** — Formatted with appropriate unit scaling.

Reports are saved to the `logger/reports/` subdirectory of the application working directory.

### 6.7 CSV Export

If the **Save CSV Data** option is enabled in Settings, a CSV file with all raw data points is exported alongside the PDF report to the `logger/csv/` subdirectory.  
The CSV contains a timestamp column and one column per measured parameter — `Gain (dB)` among them when gain logging is enabled — with the report name included as a metadata comment.
Alarm events are appended as comment lines (`# Alarm Events: …`), so tools that parse the data table are unaffected.

### 6.8 Probe Attenuation

The Data Logger automatically queries the oscilloscope's probe attenuation settings before recording begins.

Voltage measurements (Vpp, Mean, Rms), as well as the RMS voltages that Gain (dB) is derived from, are scaled by the probe divider factor.
Reported values therefore match the actual signal levels at the probe tip.

Probe dividers are displayed in the configuration dialog after the initial query completes.
The dividers of all channels with selected measurements are queried and shown.

Gain (dB) always uses the CH1 and CH2 probe dividers, regardless of how many channels the instrument has.

## 7. Macro Recorder

The **Macro Recorder** automates repetitive measurement and configuration tasks by recording,  
editing and playing back sequences of SCPI commands.  
Macros support variables, conditionals (`if`/`else`), loops (`while`) and assertions, making them suitable for automated test procedures and batch instrument configuration.

Macro files are stored with the `.m` extension in the `automation/macros/` subdirectory of the application working directory.

### 7.1 Macro Recorder Panel

The Macro Recorder panel is opened by clicking the **Macro Recorder** button in the top toolbar.  
The panel is divided into three areas:

**Header**

* Displays the panel title "Macro Recorder" with a movie-clapper icon.
* Shows the currently loaded file name (with a `*` suffix if unsaved changes exist).
* After playback, a status icon appears:
  * Green checkmark — Macro completed successfully.
  * Red error icon — Macro failed with an error.
  * Orange cancel icon — Macro playback was stopped by the user.
* **Close** button (X) closes the panel and returns to the main view.

**Action Buttons**

* **New Record** — Starts recording a new macro. If the editor already contains a macro, a confirmation dialog (Cancel/OK) asks whether to overwrite it.  
  All SCPI commands sent through the [AI chat](#42-ai-chat-interface), the [Control Panel](#9-control-panel), or loaded via profiles are captured into the macro.  
  During recording, the button shows a blinking red dot and the label changes to "Recording...".  
  Disabled during playback.
* **Stop** — Stops the current recording or playback. During playback, the label changes to "Stop Playback". Only enabled when recording or playback is active.
* **Play** — Executes the current macro content against the connected oscilloscope.  
  Disabled during recording, playback, or when no macro content has been loaded or recorded.
* **Edit** — Opens the **Macro Editor** (see [7.2 Macro Editor](#72-macro-editor)) with the current macro content for manual editing.  
  Disabled during recording, playback, or when no macro content is available.
* **Save** — Saves the macro to a `.m` file. If a file was previously loaded, it is overwritten silently. Otherwise, a dialog prompts for a file name (up to 30 characters, alphanumeric plus `_` and `-`).  
  Enabled only after recording, loading, or editing a macro.

**File List**

* Lists all saved `.m` macro files in the `automation/macros/` directory.
* Each entry shows the file name (without `.m` extension) and last modified date.
* **Sorting**: Sort by **Name** or **Date** in ascending or descending order using the sort controls above the list.
* Per-file actions:
  * **Load** (upload icon) — Loads the macro content into the editor. Only enabled when the device is online.
  * **Delete** (trash icon) — Permanently removes the macro file.

**Print Output**

As soon as a `print()` statement produces output during playback, a **Print Output** panel appears on the left of the panel, next to the macro file list.  
It lists the messages of the current playback, scrolls to the newest line, and can be cleared with the icon in its header.  
The panel is hidden while it contains no messages. Starting a new playback, recording a new macro, or loading another macro clears the output.  
While the [Macro Editor](#72-macro-editor) is open, the same messages also appear in the lower half of its left output sidebar.

Printed values are formatted for readability: frequencies use Hz, kHz or MHz, voltages use mV or V, and scientific notation (for example `8.000000E+3`) is never shown.  
The unit is taken from the SCPI query that produced the value when it is known; otherwise the label before the value (such as `Frequency:` or `Vpp:`) selects it.

### 7.2 Macro Editor

Clicking the **Edit** button or the **Load** button on a file opens the Macro Editor.  
This is a full text editor with line numbers, designed for writing and modifying macro scripts.

**Features**

* Full keyboard editing support.
* Unsaved changes are indicated by a `*` after the file name in the header.

#### Keyboard Shortcuts

| Shortcut | Action |
|:---------|:-------|
| `Ctrl` + `S` | Save macro file |
| `Ctrl` + `Z` | Undo last edit |
| `Ctrl` + `D` or `Ctrl` + `X` | Delete current line |
| `Ctrl` + `/` | Toggle line comment (`#`) |
| `Ctrl` + `Backspace` | Delete word left of cursor |
| `Ctrl` + `Delete` | Delete word right of cursor |
| `Tab` | Indent (insert 2 spaces) |
| `Shift` + `Tab` | Outdent (remove up to 2 leading spaces) |
| `Home` | Smart home — first non-whitespace, then column 0 |
| `Shift` + `Home` | Extend selection to start of line |
| `End` | Jump to end of line |
| `Shift` + `End` | Extend selection to end of line |
| `Ctrl` + `Home` | Jump to document start |
| `Ctrl` + `End` | Jump to document end |

#### Debugging

The debug bar below the editor header controls execution:

* **Play** — starts a fresh debug run from the beginning and runs until the first breakpoint (or the end).  
  Without breakpoints it behaves like the Play button in the Macro Recorder panel.
* **Step** — starts a debug session on the first click and executes one statement; each further click executes the next statement.  
  Stepping enters `if`/`while` bodies; comments are skipped.
* **Continue** — enabled only while the macro is paused; runs until the next breakpoint (or to the end).
* **Stop** — cancels a running playback or debug session.

**Breakpoints** — click a line number in the gutter to toggle a breakpoint (red dot).  
Breakpoints bind to executable statement lines; blank lines and comment-only lines are ignored.  
Right-click an existing breakpoint for a context menu: delete it, enable or disable it, enable or disable all breakpoints, or delete all breakpoints.  
Disabled breakpoints are drawn hollow and do not pause execution.

**Current line** — the statement being executed is highlighted in the gutter and in the editor,  
and the editor scrolls it into view.  
The status line names the statement.

**Variables** — after each step a watch panel to the left of the editor lists the current macro variables (`name = value`).  
The values are selectable and can be copied. The sidebar is split into two equal halves: variables in the upper half and the print output below.  
It remains visible until the next session starts or the macro is edited.

A debug session keeps the instrument connection and all macro variables alive between clicks.  
Starting a full playback, editing the macro, closing the editor, or leaving the Macro Recorder panel ends it.  
Stepping works on statements, not physical source lines: a compound statement is followed by the statements in its body.

#### AI Macro Assistant

The **AI** button in the editor header (sparkle icon) opens a chat panel to the right of the editor.  
The button is enabled only when an AI provider, API token and model are configured in the settings ([4. AI System](#4-ai-system)).

The assistant works directly on the macro that is open in the editor.

Changes are applied immediately and are marked as unsaved. `Ctrl` + `Z` in the editor restores the previous version. Press the AI button again to close the chat panel. While the assistant is working, the send button changes to a square stop button; pressing it aborts the response immediately and marks it as `terminated by user`.

The chat stays open, including its complete history, when the editor is closed and reopened later in the same session.  
An answer that is still streaming when the editor closes continues to update the transcript and is visible on reopen.

### 7.3 Recording a Macro

1. Ensure the oscilloscope is connected and online.
2. Open the **Macro Recorder** panel and click **New Record**.
3. A `connect("IP")` line is automatically inserted at the start of the macro (or `connect(usb)` if USB connection mode is active).
4. Perform actions through the AI chat, Control Panel, or load a device profile — each SCPI command is automatically appended to the macro.
5. Click **Stop** when finished.
6. Review the recorded commands in the editor (click **Edit**).
7. Click **Save** to store the macro as a `.m` file.

> **Note:** Only SCPI commands sent during recording are captured. Manual waveform acquisitions, data logger operations, and UI interactions are not recorded.

### 7.4 Playing a Macro

1. Load a macro from the file list, or record/edit one.
2. Ensure the oscilloscope is connected and online.
3. Click **Play** to execute the macro.
4. The top toolbar button changes to **Playback** and most other functions are disabled during playback.
5. Click **Stop** to cancel playback at any time.
6. After completion, a status icon appears in the panel header and a snackbar message confirms the result.

### 7.5 Macro Syntax Reference

Macro files (`.m`) contain one command per line. Blank lines and lines starting with `#` (comments) are ignored.

All brace pairs `{` `}` must be balanced before playback begins; the parser validates this and reports errors with line numbers.

#### 7.5.1 Connection

```
connect("192.168.1.100")
```

Establishes a VXI-11 connection to the oscilloscope at the given IP address. This is always the first command in a recorded macro. Only one default oscilloscope connection should be opened per macro; additional devices are opened with device handles (see below).

```
connect(usb)
```
Connects to the oscilloscope via USBTMC (USB) instead of network. The device is auto-detected — no IP address is needed. When recording a macro while the application is in USB connection mode, `connect(usb)` is automatically inserted instead of `connect("IP")`.

```
connect(SIG, usb)
```

Connects to the signal generator selected in **Settings → Signal Generator** (JDS6600 or FY6900).  
The generator type is read from the settings and the device is auto-detected on the USB serial ports.  
Playback stops with an error when no type is configured or no matching generator is reachable.  
A macro may contain one default oscilloscope `connect` and one `connect(SIG, usb)`; both connections are independent.

##### Device Handles

Device handles allow control of multiple SCPI devices.

```
myscope = connect("192.168.1.100")
```

Assigning `connect("IP")` to a variable opens an additional VXI-11 connection and returns a **device handle**.  
The handle addresses that device in `cmd()` and `query()` calls, so one macro can control several SCPI devices:

```
scopeA = connect("192.168.1.100")
scopeB = connect("192.168.1.101")
connect("192.168.1.102")
model = query(scopeA, "*IDN?")
cmd(scopeB, "ASET")
cmd("C1:TRA ON")
```

* `cmd(handle, "CMD")` and `query(handle, "CMD")` work in every position where `query()` is allowed: as a statement,  
  in assignments, in `print()`, in conditions, and in `assert(..., cmd(handle, ...))`.
* Each handle owns an independent connection. Commands without a selector keep addressing the default oscilloscope connection opened by the first `connect(...)` line.
* Handles are network (VXI-11) connections. `connect(usb)` and `connect(SIG, usb)` do not return a handle, and a macro that uses handles should connect the oscilloscope with `connect("IP")` rather than `connect(usb)`.
* Assigning the same address to the same variable again reuses the open connection.  
  Assigning a different address, or any normal value, closes the old connection first.  
  All handles are closed when playback ends.
* A handle stores its device address as the variable value, so `print(myscope)` shows `192.168.1.100`.  
  Use `cmd(myscope, "...")` rather than `cmd(myscope)` — the one-argument form expects command text and rejects handles.
* A variable that merely contains an IP address string is not a handle: `cmd(addr, "...")` fails with "does not hold a device handle".

#### 7.5.2 SCPI Commands

```
cmd("C1:TRA ON")
```

Sends a raw SCPI write command to the device. The command is not queried — no response is read. Use this for configuration commands that do not return a value.

```
query("C1:VDIV?")
```

Sends a SCPI query and reads the response. The response is logged but not stored. Use this for commands that return a value when you do not need to save it.

```
myVar=query("C1:VDIV?")
```

Sends a SCPI query and stores the cleaned response in a variable named `myVar`. Variable names may contain alphanumeric characters and underscores (`[a-zA-Z0-9_]+`).  
Variables persist for the duration of the playback session and can be used in conditions and `print` statements.

> **Note:** The oscilloscope echoes every command back. The macro engine automatically drains these echoes before queries to prevent buffer overflows.  
> Query responses are cleaned by stripping the command echo and trailing unit suffixes (e.g. `V`, `mV`, `%`).

```
cmd(SIG, "SOUR1:FREQ 1KHZ")
query(SIG, "SOUR1:FREQ?")
```

The `SIG` selector sends the command to the signal generator connected with `connect(SIG, usb)` instead of the oscilloscope.

These commands use the same SCPI driver as the [signal generator window](#911-signal-generator-window-ctrlj) and the Bode plot.
Only headers defined by that driver are accepted; an undefined header stops playback with a SCPI error (for example `-113`).
The complete command reference is in [15. SCPI Commands Signal Generator](#15-scpi-commands-signal-generator).

`query(SIG, …)` returns the driver's response and can be used everywhere `query(…)` is allowed: as a statement, in assignments, in `print()`, and in conditions.
Use `cmd(SIG, …)` for set commands and `query(SIG, …)` for queries.

A device handle opened with `myscope = connect("192.168.1.100")` can be used instead of `SIG` as the selector,  
for example `cmd(myscope, "ASET")` or `query(myscope, "*IDN?")`.  
See [7.5.1 Connection](#751-connection).

#### 7.5.3 Timing

```
wait(2.5)
```

Pauses macro execution for the specified number of seconds. Fractional values (e.g. `0.5`) are supported. Use this to allow the oscilloscope time to settle after configuration changes or between measurements.

#### 7.5.4 Device Profiles

```
loadProfile("/home/user/.local/share/sdsremote/profiles/my_setup.lss")
```

Loads a previously saved device profile (`.lss` file) and sends its configuration to the oscilloscope.  
The path must be an absolute file path. This command is automatically recorded when you load a profile during macro recording.

#### 7.5.5 Variables and Output

```
print(myVar)
```

Logs the current value of the variable `myVar` to the application log. If the variable is undefined, `<undefined>` is logged. Use this for debugging macro execution or recording measurement values.

##### String Concatenation

String arguments in `cmd()`, `connect()`, `query()`, `loadProfile()`, and `print()` can be built from multiple pieces joined by `+`.  
Each piece can be a quoted string literal or a variable reference:

```
val = 1
cmd("C1:VDIV " + val + "V")
```

This sends `C1:VDIV 1V` to the oscilloscope after resolving the variable `val`.

```
ch = "1"
query("C" + ch + ":VDIV?")
```

Sends the query `C1:VDIV?` and reads the response.

```
subnet = "1.100"
connect("192.168." + subnet)
```

Concatenation works with all string-accepting commands, including in `if`/`while` conditions and `assert` expressions:

```
expected = "1.0"
if(query("C" + ch + ":VDIV?") == expected) {
    cmd("C" + ch + ":TRMD SINGLE")
}
```

#### 7.5.6 Conditionals: if / else

```
if(myVar == 1.0) {
    cmd("C1:TRA ON")
}
```

An `else` block can be appended:

```
if(myVar >= 2.5) {
    cmd("C1:VDIV 5V")
} else {
    cmd("C1:VDIV 1V")
}
```

**Supported comparison operators:**

| Operator | Description | Operand Type |
|:---------|:------------|:-------------|
| `==` | Equal to | String or numeric |
| `!=` | Not equal to | String or numeric |
| `<` | Less than | Numeric only |
| `<=` | Less than or equal | Numeric only |
| `>` | Greater than | Numeric only |
| `>=` | Greater than or equal | Numeric only |

**Boolean operators:**

| Operator | Description | Example |
|:---------|:------------|:--------|
| `!` | Logical NOT — negates a condition | `!(v > 5)` |
| `&&` | Logical AND — true if both sides are true | `v > 3 && v < 5` |
| `\|\|` | Logical OR — true if either side is true | `v < 3 \|\| v > 5` |

> **Operator Precedence:** `!` binds first, then comparisons (`>` `>=` `<` `<=`), then `==` / `!=`, then `&&`, then `||`.  
> Use parentheses `()` to override the default order.

**NOT operator examples:**

```
# Negate a comparison
if(!(v > 5)) {
    cmd("C1:TRA OFF")
}

# Negate a compound expression
if(!(freq >= 990 && freq <= 1010)) {
    fail("Frequency out of range")
}

# Negate a variable's truthiness ("ON"→false, "OFF"→true, "0"→true)
if(!flag) {
    cmd("C1:TRA OFF")
}
```

> **Note:** Comparison operators `<`, `<=`, `>`, `>=` require both operands to be valid numbers.  
> An error is reported if either operand cannot be parsed as a number. Boolean operators `&&` and `||` use short-circuit evaluation — the right side is not evaluated if the left side already determines the result.

#### 7.5.7 Loops: while

```
while(query("SAST?")!="Trig'd"){
  wait(4)
}
```

In this example the while statement repeats the block as long as the condition isn't true.  
The condition is re-evaluated before each iteration. A maximum of **100 iterations** is enforced to prevent infinite loops. If the limit is exceeded, playback stops with an error.

**Loop control:**

* `break` — Immediately exits the innermost `while` loop. Using `break` outside a loop is an error.
* `continue` — Skips the remaining commands in the current iteration and re-evaluates the loop condition.  
  Using `continue` outside a loop is an error.

#### 7.5.8 Exit with Error: fail

```
fail("Channel 1 voltage out of range")
```

Immediately stops macro playback with the specified error message. The message is displayed in the status area and logged. Use this to abort execution when an unrecoverable condition is detected.

```
fail("Vpp:" + vpp + " exceeds limit of " + maxVpp)
```

The message can be built from multiple pieces using string concatenation (`"text" + var + "text"`),  
just like `print()` and `cmd()`.

**Example:**

```
vpp=query("C1:PAVA? PKPK")
maxVpp = 3.5
if(vpp > maxVpp) {
    fail("C1 Vpp " + vpp + " exceeds maximum " + maxVpp)
}
```

The `fail` statement is useful inside `if` blocks and `else` branches for early termination when validation fails.

#### 7.5.9 Assertions

```
assert("Channel 1 should be on", ch1State == ON)
```

Evaluates a condition and stops playback with an error message if the condition is false.  
The first argument is a descriptive text shown in the error message. The remaining arguments form a condition using the same operators as `if`/`while`.

Assertions are useful for validating oscilloscope state during automated test sequences:

```
ch1State=query("C1:TRA?")
assert("Channel 1 must be enabled", ch1State == ON)
```

#### 7.5.10 Macro Example
```
# connect via network or usb
connect(usb)
# set trigger mode to normal
cmd("TRMD NORM")
# wait for trigger
while(query("SAST?")!="Trig'd"){
  wait(0.5) 
}
# Minimum Peak to Peak voltage
minVpp = 3.0
if (query("C1:PAVA? PKPK") < minVpp){
  fail("actual vpp is < minVpp(" + minVpp + "V)")
}
assert("C1 Vpp must be >= " + minVpp, query("C1:PAVA? PKPK") >= minVpp)
# Get the frequency for channel 1
freq = query("C1:PAVA? FREQ")
# Check that Channel 1 frequency is between 990-1010Hz
assert("C1 frequency must be > 990 Hz and < 1010 but was " + freq, !(freq <= 990) && !(freq >= 1010))
```

Detailed macro playback messages are available in your log file.

### 7.6 Macro Templates

The Macro Recorder panel offers ready-made templates through the template icon in the file-list header. Choosing one loads its commands into the editor as an unsaved macro, which can be reviewed, adjusted and saved like any other macro:

* **5 V power supply check** — measures Vpp, mean and RMS on CH1.
* **UART baud rate** — measures the frequency and duty cycle of a UART line.
* **PWM duty cycle** — measures frequency, duty cycle and pulse width.
* **Clock signal present** — checks for a periodic clock with a 50 % duty cycle.

Templates are a starting point, not a measurement guarantee: channel numbers, trigger settings and thresholds may need to be adapted to the actual setup.

---

## 8. Acquire Waveform

The Waveform Acquisition feature captures waveform data from the connected oscilloscope and displays it as an interactive chart.  
The waveform display supports cursor measurements, zoom and pan controls, [reference waveform](#86-reference-waveforms) overlays, and export of a PDF measurement report together with CSV data.

### 8.1 Acquiring Waveforms

1. Ensure the oscilloscope is connected and online.
2. Enable the channels you want to capture using the channel toggles in the [Control Panel](#9-control-panel) or the [Device Parameters](#83-device-parameters-panel) sidebar (see [8.2 Channel Selection](#82-channel-selection)).
3. Click the **Acquire Waveform** button in the top toolbar. A progress indicator is shown during acquisition.
4. After acquisition completes, the waveform chart is displayed in the main area with the **Device Parameters** panel on the right side.

> **Note:** At least one channel must be enabled for acquisition to succeed. The oscilloscope must have a valid trigger; otherwise the acquisition may time out.

### 8.2 Channel Selection

Channel visibility can be toggled in two places:

* **Control Panel** — The CH1 and CH2 buttons in the virtual front panel toggle each channel on or off.  
  On four-channel instruments, CH3 and CH4 buttons appear below CH1 and CH2; the single scale (V <-> mV) and Position knobs then act on the selected channel.
* **Device Parameters Panel** — The channel status indicators in the sidebar (CH1, CH2 and, on four-channel instruments, CH3 and CH4) also select which channels are acquired.

Channel colors in the waveform display:

| Channel | Color |
|:--------|:------|
| CH1 | Yellow |
| CH2 | Magenta |
| CH3 | Light blue |
| CH4 | Green |
| Reference | White (dashed) |

### 8.3 Device Parameters Panel

When a waveform is displayed, a sidebar panel appears on the right side showing the current oscilloscope parameters:

**Global Parameters**

| Parameter | Description |
|:----------|:------------|
| Timebase | Horizontal scale in seconds per division |
| Trigger Delay | Trigger position offset |
| Sample Rate | Current sampling rate in samples per second |

**Per-Channel Parameters**

The per-channel vertical settings (V/div and offset) are shown on each channel card in the [Measurements panel](#88-measurements-difference-and-mask) below the chart, together with the automatic measurements.

**Controls**

* **Cursors X** — Toggle switch to show/hide vertical (time) cursor lines.
* **Cursors Y** — Toggle switch to show/hide horizontal (voltage) cursor lines.
* **Zoom** — Slider from 1.0× to 4.0× (0.25× steps). When zoomed in, horizontal and vertical pan sliders appear at the edges of the waveform display.
* **Load Reference** — Opens a file picker to load a previously saved waveform CSV as a reference overlay.

### 8.4 Cursor Measurements

The cursor system provides precise time and voltage measurements directly on the waveform display.

#### X Cursors (Time)

* Displayed as two vertical dashed **cyan** lines.
* Toggled via the **Cursors X** switch in the Device Parameters panel.
* Measurements shown in the draggable info panel:
  * Cursor 1 time
  * Cursor 2 time
  * Delta time (Δt)
  * Frequency (1/Δt)

#### Y Cursors (Voltage)

* Displayed as two horizontal dashed **orange** lines.
* Toggled via the **Cursors Y** switch in the Device Parameters panel.
* Measurements shown in the draggable info panel:
  * Cursor 1 voltage
  * Cursor 2 voltage
  * Delta voltage (ΔV)

#### Interaction

* **Drag a cursor line** — Click and drag any cursor line to reposition it. The cursor changes to a resize handle (`↔` for X cursors, `↕` for Y cursors) when hovering over a cursor.
* **Move the info panel** — Click and drag the cursor measurement panel to reposition it anywhere on the waveform display.
* Cursor positions are clamped to the visible waveform area.

### 8.5 Zoom and Pan

The zoom and pan controls allow detailed inspection of specific waveform regions.

#### Zoom

Use the **Zoom** slider in the Device Parameters panel (range: 1.0× to 4.0×, in 0.25× steps).  
When zoom is greater than 1.0×, horizontal and vertical pan sliders appear at the bottom and right edges of the waveform display.

#### Pan

* **Horizontal pan** — Slider at the bottom of the waveform display (cyan). Adjusts the horizontal viewport.
* **Vertical pan** — Slider at the right side of the waveform display (orange). Adjusts the vertical viewport.

When zoom is returned to 1.0×, the pan position resets to center.

### 8.6 Reference Waveforms

Previously saved waveform data can be loaded as a reference overlay for comparison with live waveforms.

#### Loading a Reference

1. Click the **Load Reference** button in the Device Parameters panel.
2. Select a CSV file from the `waveform/csv/` directory.
3. If the CSV contains more than one channel (CH1–CH4), choose which channel to load.
4. The reference waveform is displayed as a white dashed line over the live waveform.

#### Managing References

* The reference waveform toggle (**REF**) appears in the channel status area of the Device Parameters panel.
* Click the **REF** indicator to show or hide the reference waveform.
* The reference time axis is automatically aligned to the live waveform for accurate comparison.
* **Use Current as Reference** copies the displayed waveform of an enabled channel into the reference without saving a CSV first. If more than one channel has data, a dialog asks which one to use.
* **Difference** overlays `live − reference` as an orange trace. The comparison follows the manual reference offset (see [8.8 Measurements, Difference and Mask](#88-measurements-difference-and-mask)).

### 8.7 Saving Waveform Data

Click the **Save** button in the top toolbar while a waveform is displayed to export the measurement data. **Save** writes a PDF measurement report and a CSV file; no separate image file is created.

#### PDF Report

The PDF is saved to the `waveform/reports/` subdirectory and contains:

* Title, optional report name (from the filename prefix dialog), date/time and device name.
* An image of the waveform chart as it is currently displayed.
* The automatic measurements per channel: Vpp, RMS, frequency, duty, rise, fall and overshoot.
* Levels and timing: Vmax, Vmin, Vmean, Top, Base, pulse width, number of periods, sample count and Δt.
* Device parameters: timebase, trigger delay, sample rate, and V/div plus offset per acquired channel.
* The reference comparison (RMS error, maximum and mean deviation, coverage) and the mask-test result (PASS/FAIL, violations, first/last violation time, maximum deviation) when available.

#### CSV Export

A CSV file containing the raw waveform data points is saved alongside the report to the `waveform/csv/` subdirectory.  
The CSV format is:

```
# SDS-Remote Waveform Data
# Format Version: 2
# Time axis: sample time
# Saved: <timestamp>
# Device: <device name or IP>
# Timebase: <value> s/div
# Trigger Delay: <value> s
# Sample Rate: <value> Sa/s
# CH1 V/div: <value> V
# CH1 Offset: <value> V
# CH2 V/div: <value> V
# CH2 Offset: <value> V
# Cursors X Enabled: <true/false>
# Cursors Y Enabled: <true/false>
#
Time (s),CH1 (V),CH2 (V)
<time1>,<ch1_v1>,<ch2_v1>
<time2>,<ch1_v2>,<ch2_v2>
...
```

On four-channel instruments the CSV additionally contains the CH3/CH4 metadata comments and two more columns:

```
# CH3 V/div: <value> V
# CH3 Offset: <value> V
# CH4 V/div: <value> V
# CH4 Offset: <value> V
#
Time (s),CH1 (V),CH2 (V),CH3 (V),CH4 (V)
<time1>,<ch1_v1>,<ch2_v1>,<ch3_v1>,<ch4_v1>
...
```

Time values are the actual sample timestamps of the exported (downsampled) points, normalised so the first row starts at 0. The interval therefore reflects the real sample spacing of the displayed waveform and is not necessarily `1 / Sample Rate`. Channel columns are empty (` `) when a channel was not acquired.

> **Note:** CSV files written before format version 2 used `1 / Sample Rate` as the time step. They remain loadable as reference waveforms, but their time axis keeps the values stored in the file.

> **Tip:** The exported CSV files can be reloaded later as reference waveforms using the **Load Reference** feature ([8.6 Reference Waveforms](#86-reference-waveforms)).

#### Filename Prefix

If the **Ask for filename on save** option is enabled in Settings, a dialog prompts for a custom filename prefix before each save.  
The default prefix is `waveform_report` (PDF) and `waveform_data` (CSV). A numeric suffix is automatically appended to avoid overwriting existing files.

### 8.8 Measurements, Difference and Mask

After every acquisition the analysis panel below the chart is filled automatically. Values that cannot be determined from the data are shown as `—`; they are never reported as zero. The info icon next to a channel name lists the reason (for example flatline signal, unstable period or unavailable rise/fall transition).

#### Automatic Measurements

The **Measurements** view shows per enabled channel:

* The applied vertical settings **V/div** and **Offset** as metric cells, in the same style as the measurement values.
* Vpp, RMS, frequency, duty cycle, rise time, fall time and overshoot.
* **Details** adds Vmax, Vmin, Vmean, high level (Top), low level (Base), pulse width, number of complete periods, analysed sample count and the effective sample interval Δt.
* Once more than one acquisition has been stored, a history line shows mean ± standard deviation of Vpp, RMS, frequency and duty over the last acquisitions.
* Channels without data or switched off are not shown.

#### PWM and Signal Integrity

The **PWM** toggle switches the cards to the PWM/signal-integrity view:

* Frequency, duty cycle, mean/min/max pulse width and pulse-width standard deviation.
* Period jitter as the standard deviation of the measured periods.
* Rising/falling edge counts, 10–90 % rise/fall times, overshoot and undershoot.

For non-periodic signals (flatline, noise or an unstable period) the PWM values stay empty instead of showing invented numbers.

#### Measurement Explanations

Every metric label in the cards has an info icon. Hovering over it shows a short offline explanation of how the value is defined — for example that RMS is the root-mean-square voltage, that frequency is derived from rising mid-level crossings, or that duty cycle is the high time as a share of the period. The texts come with the application and need no AI configuration.

#### Ripple & Noise Measurement

The wave icon in the **Measurements** header opens the **Ripple & Noise** dialog:

* Choose the channel, V/div and offset, and whether the 20 MHz bandwidth limit should be enabled.
* The preset switches the channel to AC coupling (`A1M`), applies the bandwidth limit, V/div and offset, then reads RMS and Vpp.
* With **Restore previous channel settings** enabled (default), the coupling, bandwidth limit, V/div and offset observed before the preset are written back afterwards.
* The result shows the RMS ripple/noise and the peak-to-peak value. Values below a few hundred µV are usually dominated by the probe ground lead and the probe attenuation.

#### Clock Detection

After every acquisition the measurements are checked for a clock signal: a stable frequency, a duty cycle within ±5 % of 50 % and a period jitter of at most 2 %.

* When a clock is detected, a banner above the measurement panel names the channel, frequency and duty cycle and suggests the nearest standard 1-2-5 timebase that puts about four periods on the screen.
* **Apply** sends the suggested timebase to the oscilloscope; **Dismiss** hides the banner.
* The timebase is never changed automatically.

#### Difference Trace

A loaded or captured reference can be compared against the live waveform:

* Enable **Difference** in the Reference section of the Device Parameters panel.
* The orange trace shows `live − reference`; the loaded reference is shifted by the current manual alignment offset first.
* The panel shows RMS error, maximum deviation, mean error and coverage (the share of live points covered by the reference). Points outside the reference range are not compared and lower the coverage.

#### Software Mask Test

A reference can define a tolerance band:

* Enable **Mask** in the measurement panel. A reference must be loaded or captured first.
* **Tolerance** is set either as a percentage of the reference Vpp or in volts. **Time** adds an optional horizontal tolerance; `off` disables it.
* The band is drawn as a semi-transparent area; violating live points are marked in red.
* The result banner shows **PASS**, or **FAIL** with the number of violations, the first and last violation time and the maximum deviation in volts.
* Live points outside the reference range are skipped, so missing reference data does not create false violations.
* The mask test evaluates the current acquisition. Continuous monitoring is not part of this feature.

> **Tip:** The **Measurements** panel can be collapsed with the chevron in its header to gain space for the chart.

### 8.9 Waveform Export

Click the **Export** button in the top toolbar while a waveform is displayed to open the export dialog. Formats and options:

| Format | Content | Options |
|:-------|:--------|:--------|
| **LTspice PWL** | `time value` pairs, one per line | Channel; optional `PWL(...)` wrapper |
| **WAV** | 16-bit PCM mono, uniform grid, normalised to full scale | Channel |
| **VCD** | Digital state changes, 1 ns timescale, all acquired channels | High threshold in volts |
| **Clipboard** | Measurement table as tab-separated text | — |

* Files are written to the `waveform/exports/` subdirectory.
* Non-uniform point lists (for example a loaded reference) are linearly resampled onto a uniform grid for WAV.
* VCD timestamps are normalised so the earliest sample starts at 0.
* For external CSV data as a reference, place the file in `waveform/csv/` and use **Load Reference** ([8.6 Reference Waveforms](#86-reference-waveforms)); no separate file picker is required.

### 8.10 Sensor Calibration

Open Sensor Calibration with the linear-scale button in the calculator title bar; see [11.11 Sensor Calibration](#1111-sensor-calibration).

### 8.11 Timelapse

The clock icon in the top toolbar opens **Timelapse**:

* Set the interval as a positive whole number of seconds (1–86400), the number of frames (1–10000) and the file-name prefix. The dialog shows the resulting total duration.
* **Start** stops auto capture and the live screen and captures the oscilloscope screen at the chosen interval. Frames are written as PNG files into a timestamped run folder under `timelapse/` in the application directory, for example `timelapse/2026-10-31_14-30-05/timelapse_0001.png`.
* A snackbar reports the current frame and offers **Stop**; the toolbar icon also turns into the rotating arrows indicator that stops the run.
* Auto capture and the live screen cannot be started while a timelapse runs.
* The run ends after the planned frame count, on **Stop**, or when a capture fails. The final snackbar names the number of frames and the output folder.

## 9. Control Panel

The Control Panel provides a virtual representation of the oscilloscope's physical front panel,  
allowing remote operation of the device.  
Click the **Control Panel** button in the top toolbar to open it — the current oscilloscope screen is captured and displayed with interactive control overlays.  
After each command, the screen is automatically refreshed.

The panel is divided into two main areas: the **Screen Display** on the left and the **Control Sidebar** on the right.  
When the device is offline, an "OFFLINE" overlay is shown over the control sidebar; the AI assistant button remains usable.

### 9.1 Screen Display

The left portion shows the live oscilloscope screen as a captured image. Below the screen, a row of soft keys mirrors the physical soft keys on the oscilloscope:

| Soft Key | Function |
|:---------|:---------|
| **M1 – M6** | Context-sensitive soft keys matching the on-screen labels |
| **Menu** | Opens the oscilloscope's main menu (round button, rightmost) |

Click a soft key to activate the corresponding on-screen function. The soft keys update automatically after each screen refresh, reflecting the oscilloscope's current menu state.

On four-channel instruments connected over the network, a **Live** toggle appears next to the automatic screen capture toggle below the screen.
It streams the display directly from the oscilloscope's built-in web server and updates continuously.

While Live is active, automatic screen capture is disabled and no screen dumps are fetched after SCPI commands.
The toggle is offered only while the web server is reachable.
If the server stops responding, the application returns to ordinary screen captures and disables the Live toggle until the server answers again.

The live screen is not available over USB connections or on two-channel models.

### 9.2 Control Sidebar

The right side of the panel contains the virtual controls, organized into functional groups.  
All buttons and knobs are disabled when the device is offline or when the application is busy processing a previous command.

#### Intensity Adjust

A rotary knob at the top-left of the control area for adjusting the oscilloscope's display intensity (brightness).

#### Menu Grid

A 3×3 grid of buttons corresponding to the oscilloscope's front-panel menu keys:

| Button | Action |
|:-------|:-------|
| **Cursors** | Opens the cursor measurement menu |
| **Acquire** | Opens the acquisition mode settings |
| **Save/Recall** | Opens save/recall file operations |
| **Measure** | Opens the automatic measurement menu |
| **Clear Sweeps** | Clears accumulated waveform sweeps |
| **Utility** | Opens the utility/system menu |
| **Default** | Resets the oscilloscope to default settings (cyan) |
| **Display/Persist** | Opens display and persistence settings |
| **Print** | Triggers a print/screenshot action |

On **four-channel instruments**, an additional navigation row appears below the menu grid with **Navigate**, **Arrow Left**, **Square** and **Arrow Right**.  
The Horizontal section also shows **Search**, and the Trigger section shows **Digital**.  
These buttons are hidden on two-channel instruments.

#### Vertical Buttons

A column of four buttons to the right of the menu grid:

| Button | Action |
|:-------|:-------|
| **History** | Opens the waveform history browser |
| **Decode** | Opens the serial decode menu |
| **Run/Stop** | Toggles between running and stopped acquisition |
| **Auto Setup** | Automatically configures the oscilloscope for the input signal (blue) |

### 9.3 Vertical Controls (CH1 / CH2)

Each channel has an independent set of controls in the **Vertical** section:

| Control | Description |
|:--------|:------------|
| **V/div Knob** (top) | Adjusts the vertical scale (volts per division). Labeled "V ↔ mV". |
| **Math / Ref Button** | CH1: Opens the Math (FFT) menu. CH2: Opens the Reference waveform menu. |
| **CH1 / CH2 Button** | Toggles the channel on or off. CH1 is yellow, CH2 is magenta. |
| **Position Knob** (bottom) | Adjusts the vertical position (offset) of the waveform. |

Clicking a channel button while the **[Acquire Waveform](#8-acquire-waveform)** panel is also active toggles channel visibility in both the waveform chart and the Control Panel,  
keeping them synchronized.

### 9.4 Horizontal Controls

The **Horizontal** section contains controls for the time base:

| Control | Description |
|:--------|:------------|
| **Time/div Knob** | Adjusts the horizontal scale (seconds per division). Labeled "s ↔ ns". |
| **Roll Button** | Toggles Roll mode for slow timebase settings. |
| **Position Knob** | Adjusts the horizontal trigger position. |

### 9.5 Trigger Controls

The **Trigger** section provides four trigger mode buttons and a level knob:

| Control | Description |
|:--------|:------------|
| **Setup** | Opens the trigger configuration menu. |
| **Auto** | Sets the trigger mode to Auto (free-running when no trigger). |
| **Normal** | Sets the trigger mode to Normal (waits for trigger event). |
| **Single** | Arms a single acquisition on the next trigger event. |
| **Level Knob** | Adjusts the trigger threshold level. |

### 9.6 Knob Interaction

Virtual knobs support two interaction modes:

* **Drag** — Click and drag a knob up/down or left/right to adjust the value continuously.  
  The knob rotates visually to reflect the change. Each drag gesture translates to a SCPI knob command sent to the oscilloscope.
* **Tap** — Click a knob without dragging to set a specific value. This executes the knob specific tap function.

Knobs are disabled while another command is being processed to prevent overlapping SCPI requests,  
which could cause command queue overflows on the oscilloscope.

### 9.7 Event Processing

To prevent command collisions, the Control Panel enforces a single-command-at-a-time lock:

* When a button or knob action is triggered, all controls are temporarily disabled.
* The SCPI command is sent, the oscilloscope processes it, the screen is refreshed, and a brief cooldown period elapses before controls are re-enabled.
* This ensures reliable operation even during rapid interaction.

### 9.8 Macro Recording Integration

While the **[Macro Recorder](#7-macro-recorder)** is recording, every button press and knob adjustment in the Control Panel is automatically captured as a SCPI command line in the macro script.  
This allows you to build automation sequences by simply operating the virtual front panel normally.

### 9.9 Saving Screenshots

Press the **Save** button in the top toolbar while the Control Panel is active to save the current oscilloscope screen as a PNG file.  
Screenshots are stored in the `screenshots/` subdirectory of the application working directory.  
The image format is PNG.

### 9.10 AI Control Panel Assistant

The Control Panel has its own AI assistant. A sparkle button at the bottom-left of the control sidebar — at the same height as the automatic screenshot toggle — opens a chat overlay that covers the control sidebar.  
The close button in the overlay header collapses it again; the conversation is kept while the Control Panel remains open.

Describe the desired setup in plain language, for example:

* "Set channel 1 to 200 mV per division with an offset of 0.2 V, then do an autoset."
* "Give me the frequency on channel 3 and the RMS voltage."
* "Why is the signal on CH1 so noisy? Suggest better settings."

For the last question the assistant can call the `read_waveform_summary` tool. It returns the automatic measurements of the waveform currently displayed in the Waveform view (per channel: Vpp, RMS, mean, frequency, duty, rise/fall, overshoot, sample interval and notes) plus device parameters and any active difference or mask result. The assistant explains these values and suggests settings; it never invents or recalculates measurements. If no waveform is displayed, it says so and asks for an acquisition first.

---

### 9.11 Signal Generator Window (Ctrl+J)

When **Settings → Signal Generator** is set to **JDS6600** or **FY6900** and the generator was detected,  
press **Ctrl+J** to open the signal generator window as a separate OS window.  
There is no toolbar button. Pressing Ctrl+J while the window is open brings it to the front.

**Apply changes** sends only the modified values.
**Refresh from device** re-reads all registers.
**Use device values** discards pending edits.

The output switch takes effect immediately and is independent of Apply.
The confirmed device state and pending edits are displayed separately.

---

## 10. Bode Plot

The **Bode Plot** measures the frequency response of a device under test (DUT).
The configured signal generator sweeps the frequency.
The oscilloscope measures the RMS voltages at the DUT input and output and, optionally, the phase.
The application plots the gain in dB and the phase in degrees against a shared frequency axis.

### 10.1 Prerequisites

* The oscilloscope is connected and the status bar shows `ONLINE`.
* A supported signal generator is selected in **Settings → Signal Generator** (see [3.6 Signal Generator](#36-signal-generator)):
  * **JDS6600** — JOY-IT/Juntek JDS6600 and JDS6600-Lite
  * **FY6900** — FeelElec FY6900 series
  * **No Signal Generator** disables the Bode function.
* The generator is detected.
* Wiring:
  * Generator output → DUT input.
  * DUT output → oscilloscope **CH2** (Vout).
  * Oscilloscope **CH1** → generator output / DUT input (Vin).
  * Generator and oscilloscope share a common ground.
* The generator's serial port is accessible:
  * Linux: the user is a member of the `dialout` group.
  * Windows: the CH340 USB-serial driver is installed.
* The desired frequency range and amplitude are within the limits of the detected model (see [10.2 Signal Generators and Model Limits](#102-signal-generators-and-model-limits)).  
  The configuration form shows the active limits.

> **Note:** The Bode button is unavailable while a macro is playing or a waveform acquisition is running.  
> While a sweep is running, the [signal generator window](#911-signal-generator-window-ctrlj) (Ctrl+J) is read-only.

### 10.2 Signal Generators and Model Limits

| Model | Sine | Square | Triangle / pulse / other |
|:------|-----:|-------:|-------------------------:|
| JDS6600-LITE | 15 MHz | 15 MHz | 6 MHz |
| JDS6600 | 60 MHz | 15 MHz | 6 MHz |
| FY6900-20M | 20 MHz | 15 MHz | 10 MHz |
| FY6900-30M | 30 MHz | 25 MHz | 10 MHz |
| FY6900-50M | 50 MHz | 25 MHz | 10 MHz |
| FY6900-60M | 60 MHz | 25 MHz | 10 MHz |
| FY6900-100M | 100 MHz | 25 MHz | 10 MHz |

Amplitude and DC-offset limits:

| Generator | Amplitude | DC offset |
|:----------|:----------|:----------|
| JDS6600 / JDS6600-LITE | 20 Vpp below 10 MHz, 10 Vpp at/above 10 MHz | ±9.99 V |
| FY6900 | 24 Vpp up to 5 MHz, 20 Vpp up to 10 MHz, 10 Vpp up to 20 MHz, 5 Vpp above 20 MHz | ±12 V up to 20 MHz, ±2.5 V above 20 MHz |

Generator-specific notes:

* **JDS6600:** one global phase register (CH2 relative to CH1). Phase commands address this register regardless of the selected generator channel.
* **FY6900:** per-channel phase; the selected generator channel is addressed. Waveform selection uses the FY6900's own shape list (Sine, Square, Rectangle, Trapezoid, Ramp, …).  
  Duty cycle is adjustable on **Rectangle**; setting duty with **Square** selected switches the device to Rectangle.
* Arbitrary waveforms cannot be used for a Bode sweep.
* The generator outputs are switched off automatically when the sweep completes, fails or is cancelled.

### 10.3 Opening the Bode Plot

1. Connect the oscilloscope and wait for `ONLINE`.
2. Select the generator in **Settings → Signal Generator** and save the configuration.
3. Wait until the generator is detected.
4. Click **Bode** in the top toolbar. The Bode Plot panel opens with the configuration form.

The Bode panel is not available when no generator is configured or no generator is detected.

### 10.4 Configuring a Sweep

| Field | Description |
|:------|:------------|
| Report Name | Optional name (max. 150 characters) for the saved report. |
| Start / Stop | Frequency range; choose Hz, kHz or MHz per field. |
| Points | Number of sweep points (2–500). |
| Amplitude | Generator output in Vpp; limited by the model and frequency. |
| Offset | Generator DC offset; limited by the model and frequency. |
| Settle (ms) | Extra settling time per point; the application enforces at least three periods and 800 ms and caps the value at 5 s. |
| Spacing | Logarithmic (default) or linear frequency spacing. |
| Waveform | Sweep waveform (sine, square, triangle, pulse, …). |
| Vin channel | Oscilloscope channel connected to the DUT input (default CH1). |
| Vout channel | Oscilloscope channel connected to the DUT output (default CH2). |
| Measure phase | Enables phase measurement in addition to gain. |
| Outputs off after sweep | When enabled (default), both generator outputs are switched off after completion, failure or cancellation. Turn it off to leave the generator output running at the last sweep frequency. |

The form shows the active model limits below the waveform field, for example:

`Model FY6900-60M: Sine up to 60 MHz · amplitude up to 24 Vpp · offset ±12 V`

**START SWEEP** is disabled while the configuration is invalid. The reason is displayed above the button, for example when the stop frequency exceeds the limit for the detected model and selected waveform.

### 10.5 Running a Sweep

1. Verify the wiring and the DUT.
2. Configure the frequency range, waveform, amplitude, offset and channels.
3. Click **START SWEEP**.
4. The generator output is enabled. The oscilloscope is prepared (including automatic vertical scaling) and each point is measured after the settling time.
5. The gain and, when enabled, the phase are calculated for each point; the plots update as the sweep progresses.
6. **STOP** cancels the sweep. By default the generator outputs are switched off on completion, failure and cancellation; the **Outputs off after sweep** button in the configuration form keeps them on instead.

During the sweep, generator detection is paused and the signal generator window cannot change settings.  
Points with no usable measurement (Vin/Vout below 5 mV RMS, out-of-range values or an unstable input) are retried and, if they remain invalid, left out of the plot instead of appearing as spikes.

### 10.6 Reading the Results

* The **gain plot** shows `20 · log10(Vout / Vin)` in dB.
* The **phase plot** shows the phase in degrees. The oscilloscope measures the input relative to the output, so the displayed sign is corrected for the usual generator → DUT → scope wiring.
* Both plots share the same logarithmic frequency axis.
* The sweep progress and the current/last point are shown above the plots. After a sweep, **NEW** returns to the configuration form.

**Automatic Analysis**

When valid gain points are available, the panel below the plots and the gain chart show:

* **Peak** — highest gain and its frequency.
* **−3 dB** — upper roll-off frequency (interpolated on the logarithmic frequency axis, relative to the peak gain).
* **Bandwidth** and **Q factor** — when the curve also has a lower −3 dB crossing (resonant/band-pass response). `Q = peak frequency / bandwidth`.
* **0 dB** — first frequency where the gain crosses 0 dB.
* Dashed markers with labels in the gain plot at the peak, −3 dB and 0 dB frequencies.
* Notes explain values that cannot be determined (for example no −3 dB crossing or a gain that never reaches 0 dB).

### 10.7 Reports and CSV

The **Save** action in the top toolbar captures the Bode plot and writes a PDF report to `bode/reports/`.  
The report contains the plot, the report name, the sweep configuration and an **Analysis** table with peak, −3 dB, bandwidth, Q factor and 0 dB crossover. When **Save csv data** is enabled in the Settings, the sweep points are additionally written as CSV to `bode/csv/`.  
The generator identity (for example `FeelElec,FY6900-60M`) and the oscilloscope name are included.

### 10.8 Troubleshooting

* **Bode button is missing** — the oscilloscope is offline, no generator is configured, the generator was not detected, or a macro is playing.
* **START SWEEP is disabled** — the configuration is invalid; read the message below the fields.  
  A common cause is a stop frequency above the limit of the detected model and selected waveform.
* **Frequency write failed** — the generator did not confirm the frequency. Check the serial(USB) connection and the model limits. The FY6900 firmware can report frequencies with a small rounding error (~0.1 Hz); the driver tolerates this.
* **No or unstable gain/phase** — increase the amplitude or settling time, reduce the frequency range, and verify that the oscilloscope inputs are not clipped.  
  Below about 5 mV RMS the point is omitted; below 1 mV Vin the gain is not valid.
* **Generator output stays on** — the application switches the outputs off when the sweep ends.  
  If the application was interrupted, switch them off in the signal generator window (Ctrl+J) or on the device.
* **Serial(USB) port cannot be opened** — on Linux add the user to the `dialout` group and log in again; on Windows install the CH340 driver.

---

## 11. Engineering Calculator (Ctrl+R)

The Engineering Calculator is a separate window for electronics, measurement, audio, DSP, embedded and RF calculations.

Open it with **Ctrl+R** or the shortcut configured in [3.9 Calculator Shortcut](#39-calculator-shortcut).
There is no toolbar button.
The window opens in the center of the main SDS-Remote window.
Pressing the shortcut again re-centers and focuses the existing calculator window.
The calculator is independent of the oscilloscope connection.

All calculator functions work without AI.
The optional [Calculator AI Assistant](#118-calculator-ai-assistant-optional) is opened with the bordered sparkle button in the title bar, left of the syntax-help question mark.
The **Component value codes** button (book icon) in the title bar opens reference charts for resistor and capacitor color codes, inductor value codes and inductor color-dot markings. The dialog has one tab per chart; scroll to zoom into a chart and drag to pan.

### 11.1 Display and Keypad

**Entering a calculation**

1. Click the expression field or press a keypad key.
2. Type an expression such as `2 mA * 10 kΩ`.
3. Press `Enter` or click `=`.

The large line shows the result, for example `20 V`.
The line below shows the normalized expression, stored or used variables and the physical dimension when applicable.

The small icons above the expression field provide undo, redo, previous/next calculation, paste and copy result.

The top keypad row controls the operating modes:

| Key | Action |
|:----|:-------|
| `SHIFT` | Applies the amber secondary function printed above the keys |
| `INV` | Applies the inverse or hyperbolic alternative; mutually exclusive with SHIFT |
| `DEG` / `RAD` / `GRAD` | Cycles the angle unit for plain numbers: degrees → radians → gradians |
| `AUTO` / `ENG` / `FIXED` / `SCI` | Cycles the number format: Auto → Engineering → Fixed-point → Scientific. Fixed-point uses the decimal places from the calculator settings |
| `DEC` / `HEX` / `OCT` / `BIN` | Cycles the integer display base; the extra row provides `0x`, `0b`, `0o` and `A`–`F` |
| `CLR` | Clears the expression and the result |

Common keys:

| Key | Primary | SHIFT | INV |
|:----|:--------|:------|:----|
| `sin` / `cos` / `tan` | `sin(`, … | `asin(`, … | `sinh(`, … |
| `ln` | `ln(` | `exp(` | `log2(` |
| `log` | `log10(` | `10^(` | `log(` |
| `exp` | `exp(` | `e^(` | `pi` |
| `xʸ` | `^` | `^(1/` | `^2` |
| `√` | `sqrt(` | `cbrt(` | `√(` |
| `x²` | `^2` | `^3` | `^(1/2)` |
| `1/x` | `1/(` | `%` | `ppm` |
| `n!` | `!` | `gamma(` | `comb(` |
| `ABS` | `abs(` | `mag(` | `arg(` |
| `mod`, `∠`, `j`, `°`, `%` | Insert the corresponding operator or unit | — | — |
| `STO` / `RCL` | Store the current result in a variable / recall a variable | — | — |
| `UNIT` / `CONV` | Unit picker with Greek unit symbols (`µ`, `μ`, `Ω`, `°`, `Å`) / unit conversion dialog | — | — |
| `HIST` / `VAR` / `FORM` / `PROG` | Switch the side panel to history, variables, formulas or programs | — | — |
| `FAV` | List favorites | — | — |
| `ANS` | Insert the previous result | — | — |
| `±` | Toggle the sign of the selection or insert a minus | — | — |
| `=` | Evaluate | — | — |
| `⌫` | Delete the selection or the character before the cursor | — | — |

### 11.2 Expression Syntax

Expressions are parsed by the calculator and never executed as code.
Spaces are optional: `2mA*10kΩ` and `2 mA * 10 kΩ` produce the same result.
Use a decimal point for fractional values; `1.5` is valid, while `1,5` is rejected.
Commas separate the arguments of a function or the elements of a vector.

| Form | Example | Result |
|:-----|:--------|:-------|
| Multiplication and division before addition and subtraction | `2 + 3 * 4` | `14` |
| Parentheses | `(2 + 3) * 4` | `20` |
| Power is right-associative and binds before unary minus | `2^3^2`, `-2^2` | `512`, `-4` |
| Implicit multiplication | `2(3 + 4)`, `2π` | `14`, `6.2831853072` |
| Implicit multiplication binds tighter than `/` | `x = 3; 1/2x` | `0.1666666667` |
| Factorial | `5!` | `120` |
| Percent | `200 * 50%` | `100` |
| Vector and matrix | `[1, 2, 3]`, `[[1, 2], [3, 4]]` | `[1, 2, 3]` |
| Index (1-based) | `[10, 20, 30][2]` | `20` |
| Assignment | `R1 = 10 kΩ` | `10 kΩ`; stores `R1` |
| Function definition | `f(x) = x^2 + 1`, then `f(3)` | `10` |
| Several statements | `R1 = 10 kΩ; C1 = 100 nF; 1/(2*pi*R1*C1)` | `159.1549430919 Hz` |
| Conversion | `230 mV to V`, `to(20 dBm, W)` | `0.23 V`, `0.1 W` |

Use a semicolon to separate statements in the expression field.
Programs may also use one statement per line.

The selected angle mode applies to plain numbers:

* In `DEG`, `sin(30)` returns `0.5`.
* In `RAD`, `sin(30)` returns `-0.9880316241`; use `sin(30°)` for an angle that is explicitly in degrees.
* In `GRAD`, `sin(30)` returns `0.4539904997`.

### 11.3 Units, Prefixes and Levels

Values carry an SI dimension.
Adding or comparing incompatible dimensions produces a dimension error; multiplication and division combine units.

| Task | Input | Result |
|:-----|:------|:-------|
| Current from voltage and resistance | `230 mV / 10 kΩ` | `23 µA` |
| RC time constant | `4.7 kΩ * 2.2 µF` | `10.34 ms` |
| Ohm's law | `3.3 V / 220 Ω` | `15 mA` |
| RC cutoff frequency | `1/(2*pi*10 kΩ*100 nF)` | `159.1549430919 Hz` |
| Temperature conversion | `25 °C to °F` | `77 °F` |
| Energy conversion | `1 kWh to J` | `3600000 J` |

Write prefixes directly before the unit: `mV`, `µF`, `kΩ`, `MHz`.
Prefixes are case-sensitive: `m` means milli and `M` means mega; `s` means seconds and `S` means siemens.

A bare `k` after a number means 1000, so `10k` is `10000`.
A bare `m` means metres, so `10m` is ten metres; write `10 mm` for millimetres.

The `UNIT` key opens the unit picker, including the Greek symbols `µ`, `μ`, `Ω`, `°` and `Å`.
The `CONV` key opens the conversion dialog.

Logarithmic units use fixed references:

* `dBm` (1 mW power), `dBW` (1 W power), `dBV` (1 V RMS), `dBu` (0.775 V RMS), `dBµV` (1 µV RMS), `dBSPL` (20 µPa).
* `dBFS` is an amplitude ratio relative to digital full scale. Converting it to volts requires a full-scale reference: `dbfs_to_vrms(level, full_scale)`.
* `dBi` and `dBd` are antenna gains; `0 dBd = 2.15 dBi`.

Level arithmetic follows physical rules:

```text
20 dBm + 3 dB      = 23 dBm    level plus gain
20 dBm - 3 dB      = 17 dBm    level minus gain
20 dBm - 5 dBm     = 15 dB     ratio of two levels
3 dB + 3 dB        = 6 dB      cascaded logarithmic gains
20 dBm + 20 dBm    → dimension error (two absolute levels)
```

### 11.4 Complex Numbers

Use `j` for the imaginary unit.
`∠` enters a polar angle; the angle uses the current DEG/RAD/GRAD mode unless it carries a unit.

| Input | Result |
|:------|:-------|
| `(50 + j25) Ω` | `(50 + j25) Ω` |
| `75∠30° Ω` | `75∠30° Ω` |
| `polar(50 + j25)` | `55.9016994375∠26.5650511771°` |
| `rect(polar(3 + j4))` | `3 + j4` |
| `abs(3 + j4)` | `5` |
| `arg(3 + j4)` | `53.1301023542` |

The functions `conj(z)`, `re(z)` and `im(z)` return the conjugate, real part and imaginary part.
Complex trigonometric functions use radians.
Impedance, reflection coefficient, VSWR, return loss and mismatch loss are also available through the formula library.

### 11.5 Variables, Functions and Programs

#### Variables

Store a value in one of three ways:

* Type an assignment such as `R1 = 10 kΩ` and press `Enter`.
* Evaluate a value, press `STO` and enter a name in the **Store variable** dialog.
* Open the **Variables** tab, click **Add** and enter a name and expression.

Use `RCL` to insert a stored variable into the expression.
The **Variables** tab lists all stored variables.
**Clear** removes all stored variables after confirmation; user functions and the calculation history are kept.

```text
R1 = 10 kΩ
C1 = 100 nF
FC = 1 / (2*pi*R1*C1)
FC
```

The result is `159.1549430919 Hz`.

#### User Functions

Define a function with an assignment and call it in later expressions:

```text
f(x) = x^2 + 1
f(3)
```

The result is `10`.
Functions can be defined only at the top level of a program.
Delete a function in the **Variables** tab.

#### Programs

Open the **Programs** tab and enter a multi-line program.
Press **Run** to execute it.
The result of the last statement is shown in the display, and assignments remain available as variables.

```text
R1 = 10 kΩ
C1 = 100 nF
fc = 1/(2*pi*R1*C1)
fc
```

The result is `159.1549430919 Hz`.

Values can be supplied in the program itself, as above, or stored before **Run** in the expression field.
For example, store `vin = 12 V`, then run:

```text
r1 = 10 kΩ
r2 = 4.7 kΩ
vin * r2 / (r1 + r2)
```

The result is `3.8367346939 V`.

The **Ω** button in the program header opens the unit picker and inserts the selected unit or Greek symbol at the caret.
**Save** stores the program under a name; the saved-program list provides **Load** and **Delete**.

The editor has a line-number gutter.
When **Run** fails, the error message in the main display names the 1-based line and column, for example `Line 2, column 5`.
The failing line number turns red and the faulty token gets a wavy red underline; editing clears the underline.

Programs support these control forms:

| Form | Example |
|:-----|:--------|
| Conditional | `if(condition, then, else)` |
| Counting loop | `for(i, from, to, expression)` |
| Conditional loop | `while(condition, expression)` |
| Sum | `sum(n^2, n, 1, 10)` → `385` |
| Product | `product(expression, variable, from, to)` |
| Integral | `integrate(expression, variable, from, to)` |
| Derivative | `derivative(expression, variable, at)` |
| Root finding | `solve(x^2 - 4, x, 1)` |

Loop and call limits prevent runaway programs.

### 11.6 Formula Library

The **Formulas** tab provides a searchable library grouped into these categories:

* Basic Electrical
* Filters and Analog
* Measurement and Uncertainty
* Audio and DSP
* Digital and Embedded
* RF and Antennas
* Math and Numerical

Every formula has named inputs with runnable defaults.
The dialog shows the formula, its assumptions and the result.

**Example: RC cutoff frequency**

1. Open **Formulas** and search for `RC cutoff frequency`.
2. Keep the default inputs: resistance `10 kΩ`, capacitance `100 nF`.
3. Click **Run**.

The result is `159.1549430919 Hz`.

The **Unit** button opens the same unit picker as the program editor.
It inserts the selected unit or Greek symbol at the caret of the last active input field.
Formula results are recorded in the history with the formula name.

### 11.7 History, Favorites and Persistence

Every successful evaluation records its expression, normalized form, result, unit, timestamp, variables used and formula name when applicable.

**Example: reuse a calculation**

1. Calculate `2 mA * 10 kΩ`.
2. Open the **History** tab.
3. Click `2 mA * 10 kΩ` to load the expression again.
4. Click the result to copy it.
5. Click the star to add the calculation to favorites.

The arrow icons above the expression field move through previous and next calculations.
The history can also be exported as CSV, JSON or a Markdown report.
The **Programs** tab exports and imports the complete workspace as JSON.

The workspace contains variables, functions, settings, history, favorites and programs.
It is stored in `calculator/workspace.json` in the application working directory:

* Linux: `~/.local/share/sdsremote/calculator/workspace.json`
* Windows: `%LocalAppData%\sdsremote\calculator\workspace.json`

### 11.8 Calculator AI Assistant (optional)

The bordered sparkle button in the title bar opens the **Calculator AI** panel from the left side over the keypad.
The optional assistant uses the AI provider, token and model configured in the SDS-Remote settings.
Without a complete configuration, the panel shows a configuration banner; the calculator itself remains fully usable.

The assistant can:

* answer calculation questions and run engineering formulas;
* ask for missing or ambiguous parameters instead of inventing values;
* check units and dimensions with the deterministic calculator engine;
* distinguish linear gain from logarithmic gain and state level references;
* read the current expression, program, variables and display settings read-only;
* use a private scratch workspace for temporary variables and formulas.

**Example prompts**

* `What is the cutoff frequency of a 10 kΩ and 100 nF RC low-pass filter?`
* `Convert 20 dBm to mW and add a 3 dB cable loss.`
* `Design a voltage divider for 12 V to 3.3 V with a 10 kΩ upper resistor.`
* `Check the program in the editor and explain the error.`

#### Results and footnote actions

The assistant never changes the calculator state on its own.
Each calculator result is cited in the answer as a numbered footnote marker `[1]`, `[2]`, ….
Hovering a marker shows the result and the calculation that produced it.
Right-clicking a marker opens these actions:

| Action | Effect |
|:-------|:-------|
| **Copy** | Copies the result |
| **Insert result** | Inserts the result value and unit into the expression field; the expression is not evaluated until you press `=` |
| **Use in program** | Inserts the last code block from the answer into the Programs editor without running it. Existing code requires confirmation before replacement |
| **Use as variable** | Opens the normal **Store variable** dialog with the result prefilled |

If the answer has no code block, **Use in program** inserts the cited calculation instead.
Results appear only as footnote markers; the assistant does not append a separate result card.
The **Copy** button below an answer copies the complete answer.

The panel header also provides **Insert calculator variable** for inserting a variable name into the prompt.

#### Operation

While a response is running, the send button becomes a stop button.
Press `Esc` to close the panel when it is open.
Closing the panel keeps the transcript for the current calculator window; closing the calculator window discards it.

### 11.9 Keyboard Shortcuts

| Shortcut | Action |
|:---------|:-------|
| `Enter` | Evaluate the expression |
| `Esc` | Close the Calculator AI panel when it is open; otherwise clear the expression and result |
| `Ctrl` + `Z` / `Ctrl` + `Y` | Undo / redo in the expression field |
| `Ctrl` + `R` (configurable) | Open or focus the calculator window from the main application |
| `Ctrl` + `C` / `Ctrl` + `V` | Copy / paste text in the expression field |

### 11.10 Limits and Conventions

* Absolute temperatures are stored internally in kelvin.
  `°C` and `°F` conversions use their affine offsets.
  Do not multiply absolute temperatures as if they were temperature differences.
* `dBFS` has no fixed full-scale voltage.
  Use `dbfs_to_vrms` or `vrms_to_dbfs` with an explicit reference.
* Matrix indexes start at 1; a negative index counts from the end.
* Function, variable and unit names share one namespace.
  Unit symbols and built-in function names are reserved; use `R1`, `C1` and `L1` rather than `R`, `C` and `L`.
* Adding incompatible dimensions fails.
  For example, `230 mV + 10 kΩ` reports a dimension error; convert one operand or choose a compatible quantity.
* Adding two absolute levels fails.
  For example, `20 dBm + 20 dBm` is rejected; add a gain such as `20 dBm + 3 dB` or subtract two levels to obtain a ratio.
* Results use IEEE-754 double precision.
  Very large or undefined results are reported as overflow or domain errors instead of `NaN` or infinity.

### 11.11 Sensor Calibration

The linear-scale button in the calculator title bar opens **Sensor Calibration**.
The dialog fits a straight line through measured sensor values and known reference values and turns that line into firmware constants.

**What it is for**

Use it when a sensor output is approximately linear but its gain and offset are unknown, differ from the datasheet, or are shifted by the circuit around the sensor. The dialog computes the least-squares fit

`reference = slope * measured + intercept`

and reports how well the line matches the points (R²). Typical applications:

* Bench-calibrating a current shunt and its amplifier against a reference ammeter.
* Pressure, force, temperature or Hall sensors with an analog output (for example 0.5–4.5 V for 0–10 bar).
* Calibrating an ADC input chain, a programmable gain stage or a complete measurement channel.
* Deriving gain and offset constants for the firmware of the sensor's own microcontroller.

The dialog works offline; the oscilloscope connection is not required.

**How to use it**

1. Pick at least two, preferably three to five, calibration points spread over the working range.
2. For each point, measure the sensor output with the oscilloscope — typically the **Mean** measurement of the sensor's channel — and enter it under **Measured**. Enter the known physical value under **Reference**.
3. Press **Add point** for additional pairs; empty rows are ignored.
4. The fit and its quality update as you type. R² close to 1 means the points follow a straight line well.
5. Press **Copy snippet** to put the generated correction code on the clipboard.

Example: a current sensor outputs 2.50 V at 0 A and 4.50 V at 10 A. The fit gives a slope of 5 A/V and an intercept of −12.5 A, so 4.50 V maps to 10 A.

The **Mean** value of a Data Logger recording in the main window can be read there and entered manually. The automatic **From Data Logger** prefill is not available in the calculator window.

**What is generated**

The dialog shows the slope, the intercept, R² and the number of points. **Copy snippet** additionally produces an Arduino/ESP32-ready C++ function:

```cpp
// Sensor calibration generated by SDS-Remote
// Fit quality: R^2 = 0.9998 (3 points)
const float CAL_SLOPE = 5.000000f;
const float CAL_INTERCEPT = -12.500000f;

float calibrate(float rawValue) {
  return CAL_SLOPE * rawValue + CAL_INTERCEPT;
}
```

`rawValue` must be in the same unit as the **Measured** column (for example volts). `calibrate` returns the value in the unit of the **Reference** column (for example amperes). The constants are plain C++ and can be copied into any sketch or adapted to another language.

**Limits and pitfalls**

* At least two complete points are required; an error is shown when fewer exist or when all measured values are identical.
* With exactly two points R² is always 1.0. Use three or more points to check whether the sensor is actually linear.
* The model is a straight line. Sensors with strong nonlinearity, saturation, hysteresis or temperature dependence need a lookup table, a polynomial or temperature compensation that this dialog does not provide.
* Place the points over the range you will actually use. Extrapolating far beyond the calibrated span is unreliable.
* A high R² describes the fit, not the absolute accuracy. Keep the reference instrument's accuracy and the oscilloscope's measurement accuracy in mind.

---

## 12. Application Directory

The application directory stores captured images, CSV exports, profiles and the calculator workspace.
The directory is OS specific:

* **Linux:** `~/.local/share/sdsremote/`
* **Windows:** `%LocalAppData%\sdsremote`

| Subfolder | Description |
| :-------- | :-------- |
| `preferences` | Application settings |
| `screenshots` | Display screenshots |
| `waveform/csv` | Waveform CSV data |
| `waveform/reports` | Waveform PDF measurement reports |
| `waveform/exports` | Waveform export files (PWL, WAV, VCD) |
| `logger/reports` | Data Logger reports |
| `logger/csv` | Data Logger CSV data |
| `timelapse` | Timelapse run folders with PNG frames |
| `bode/reports` | Bode Plot PDF reports |
| `bode/csv` | Bode Plot CSV data |
| `profiles` | Device profiles |
| `automation/macros` | Macro `.m` files |
| `calculator` | Calculator workspace and exported history |

---

## 13. Troubleshooting (Non-AI)

### Connection Issues

* **Offline Status**
  * Verify device power and network connection
  * Ensure oscilloscope is not in standby
  * If in network mode, validate IP address, firewall (VXI-11 uses port 111)

* **USB connection lost / `libusb bulk write error`**
  * On IO_ERROR, PIPE and NO_DEVICE the application invalidates the shared USB connection and drops its cached instrument.  
    If the oscilloscope is still enumerated, it reconnects automatically within a few seconds.
  * If the device has disappeared from the bus (`lsusb` no longer lists it), unplug and replug the USB cable, or power-cycle the oscilloscope.  
    After a replug no application restart is required.
  * USB is less reliable than VXI-11; use the network connection for long-running macros and profile uploads.

* **Waveform Acquisition Failure**
  * Ensure at least one channel is enabled
  * Verify trigger configuration
  * Confirm valid acquisition state

---

### Display Issues

* Minimum display resolution: **1100 × 600**
* Update graphics drivers if needed
* Large displays may affect UI scaling

---

## 14. Technical Details

### Communication

* Protocol: VXI-11 over TCP/IP or USB direct connect
* Command Interface: SCPI

### Data Formats

* **Screen Capture**: BMP (device) → PNG (application)
* **Waveform Data**: Binary → voltage/time values
* **[Device Profiles](#5-device-profiles)**: SCPI XML → .lss files
* **Other Export Formats**: PNG ([Control Panel](#9-control-panel)), CSV (Waveform, [Data Logger](#6-data-logger)), PDF (Waveform, [Data Logger](#6-data-logger))
* **Macro Files**: Plain text `.m` files with one command per line

### Performance

* Waveforms are downsampled to improve rendering performance and display responsiveness.
* Screen captures are compressed to reduce storage requirements.
* AI response times depend on provider latency and knowledge retrieval operations and may vary significantly.

---

## 15. SCPI Commands Signal Generator

Macros using `connect(SIG, usb)` share one SCPI layer.
The JOY-IT/Juntek JDS6600 and the FeelElec FY6900 therefore accept the same command set.
Only the waveform names and the phase and duty handling differ; see [15.5 Waveform Names](#155-waveform-names) and [15.6 Family-Specific Behavior](#156-family-specific-behavior).

This is a SCPI emulation subset, not a complete implementation:

* One command per line. Command chaining with `;` is rejected.
* `<n>` is the channel number: `1` or `2`.
* Header segments and units are case-insensitive; whole segments may be abbreviated with the aliases in [15.4 Units and Header Aliases](#154-units-and-header-aliases).
* Commands are sent to the generator from a macro with the `SIG` selector — `cmd(SIG, "…")` for set commands and `query(SIG, "…")` for queries; see [7.5.2 SCPI Commands](#752-scpi-commands).

> **Note:** The generator must be selected in **Settings → Signal Generator** (see [3.6 Signal Generator](#36-signal-generator)) and connected with `connect(SIG, usb)` before a command is accepted.  
> An undefined header stops macro playback with a SCPI error.

### 15.1 Common Commands

| SCPI cmd/query | Documentation | Example |
|:---------------|:--------------|:--------|
| `*IDN?` | Device identity as `manufacturer,model,serial,N/A`. Requires a detected generator. | `JOY-IT,JDS6600-LITE,12345,N/A` |
| `*RST` | Safe reset of both channels: outputs off, sine, 1 kHz, 1 Vpp, 0 V offset, 50 % duty, 0° phase. | `*RST` |
| `*CLS` | Clears the error queue. | `*CLS` |
| `*OPC?` | Operation complete; always returns `1`. | `1` |
| `SYST:ERR?` | Oldest queued error as `code,"message"` and removes it from the queue. An empty queue returns `0,"No error"`. | `0,"No error"` |
| `SYST:ERR:COUN?` | Number of queued errors. | `0` |
| `SYST:VERS?` | SCPI version. | `1999.0` |
| `SYST:COMM:BAUD?` | Serial port baud rate. | `115200` |
| `SYST:LOC` | Accepted without effect. | `SYST:LOC` |
| `SYST:REM` | Accepted without effect. | `SYST:REM` |

### 15.2 Source Commands

| SCPI cmd/query | Documentation | Example |
|:---------------|:--------------|:--------|
| `SOUR<n>:FUNC <shape>` | Sets the waveform; accepted shapes in [15.5 Waveform Names](#155-waveform-names). `ARB` is rejected with -113. | `SOUR1:FUNC SIN` |
| `SOUR<n>:FUNC?` | Returns the waveform mnemonic. | `SIN` |
| `SOUR<n>:FREQ <value>[unit]` | Sets the frequency; no unit means Hz. The value must be positive and within the model and waveform limit (see [10.2 Signal Generators and Model Limits](#102-signal-generators-and-model-limits)). | `SOUR1:FREQ 1KHZ` |
| `SOUR<n>:FREQ?` | Returns the frequency in Hz with two decimals. | `1000.00` |
| `SOUR<n>:VOLT <value>[unit]` | Sets the amplitude in Vpp; no unit means V. | `SOUR1:VOLT 3.3VPP` |
| `SOUR<n>:VOLT?` | Returns the amplitude in Vpp with three decimals. | `3.300` |
| `SOUR<n>:VOLT:OFFS <value>[unit]` | Sets the DC offset; no unit means V. | `SOUR1:VOLT:OFFS -1.5V` |
| `SOUR<n>:VOLT:OFFS?` | Returns the DC offset in V with two decimals. | `-1.50` |
| `SOUR<n>:PHAS <value>[unit]` | Sets the phase; no unit means degrees. | `SOUR1:PHAS 90DEG` |
| `SOUR<n>:PHAS?` | Returns the phase in degrees with one decimal. | `90.0` |
| `SOUR<n>:PULS:DCYC <value>[unit]` | Sets the pulse duty cycle; no unit means %. | `SOUR1:PULS:DCYC 25` |
| `SOUR<n>:PULS:DCYC?` | Returns the pulse duty cycle with one decimal. | `25.0` |
| `SOUR<n>:FUNC:SQU:DCYC <value>[unit]` | Sets the square duty cycle; no unit means %. | `SOUR1:FUNC:SQU:DCYC 50` |
| `SOUR<n>:FUNC:SQU:DCYC?` | Returns the square duty cycle with one decimal. | `50.0` |

Set commands return no response.

### 15.3 Output Commands

| SCPI cmd/query | Documentation | Example |
|:---------------|:--------------|:--------|
| `OUTP<n>:STAT <state>` | Switches the channel output on or off. Accepts `ON`, `OFF`, `1` and `0`. | `OUTP1:STAT ON` |
| `OUTP<n>:STAT?` | Returns `1` when the channel output is on, otherwise `0`. | `1` |
| `OUTP<n> <state>` | Short form without the `STAT` node; equivalent to `OUTP<n>:STAT`. | `OUTP1 ON` |
| `OUTP<n>?` | Short form; equivalent to `OUTP<n>:STAT?`. | `1` |
| `OUTP:ALL <state>` | Switches both outputs together. | `OUTP:ALL OFF` |
| `OUTP:ALL?` | Returns `1` only when both outputs are on, otherwise `0`. | `0` |

### 15.4 Units and Header Aliases

Units are optional and case-insensitive; the default applies when the unit is omitted.  
Units are accepted as a suffix of the value (`1KHZ`, `3.3VPP`) or separated by a space (`1 KHZ`).

| Parameter | Units | Default |
|:----------|:------|:--------|
| `FREQ` | `HZ`, `KHZ`, `MHZ` | Hz |
| `VOLT` | `V`, `VPP`, `MV` | V |
| `VOLT:OFFS` | `V`, `VPP`, `MV` | V |
| `PULS:DCYC`, `FUNC:SQU:DCYC` | `%`, `PCT` | % |
| `PHAS` | `DEG`, `DEGREE` | Degrees |

A whole header segment may be replaced by one of these aliases: `SOURCE` = `SOUR`,  
`OUTPUT` = `OUTP`, `VOLTAGE` = `VOLT`, `OFFSET` = `OFFS`, `FUNCTION` = `FUNC`, `DCYCLE` = `DCYC`, `PHASE` = `PHAS`, `STATE` = `STAT`, `FREQUENCY` = `FREQ`.  
`SQUARE` and `PULSE` are not header aliases — use `SQU` and `PULS`.

### 15.5 Waveform Names

| Generator | Waveform names |
|:----------|:---------------|
| JDS6600 | `SIN`, `SQU`, `PULS`, `TRI`, `PSIN`, `CMOS`, `DC`, `HALF`, `FULL`, `POSL`, `NEGL`, `NOIS`, `ERIS`, `EDEC`, `MTON`, `SINC`, `LOR` |
| FY6900 | `SIN`, `SQU`, `RECT`, `TRAP`, `CMOS`, `PULS`, `DC`, `TRI`, `RAMP`, `NRMP`, `STRG`, `STPS`, `NSTP`, `PEXP`, `NEXP`, `PFEX`, `NFEX`, `PLOG`, `NLOG`, `PFLO`, `NFLO`, `PFUL`, `NFUL`, `PHAL`, `NHAL`, `LOR`, `MTON`, `NOIS`, `ECG`, `SINC`, `IMPU`, `AWGN`, `AM`, `FM`, `CHIR` |

* Both families also accept the long spellings `SINE`, `SQUARE`, `PULSE`, `TRIANGLE` and `NOISE`; the FY6900 additionally accepts `RECTANGLE`, `TRAPEZOID` and `RAMP`.
* FY6900-only names (`RECT`, `TRAP`, `RAMP`, …) are rejected with -222 on the JDS6600.  
  On the FY6900, JDS6600-only names are mapped to the closest preset (for example `PSIN` to sine); `PULS` on channel 2 becomes `RECT`.
* `ARB` is not available on either family: `SOUR<n>:FUNC ARB` and `SOUR<n>:FUNC:ARB` return -113.

### 15.6 Family-Specific Behavior

* **Phase** — the JDS6600 has one global CH2-vs-CH1 phase register, so `SOUR1:PHAS` and `SOUR2:PHAS` address the same value and both queries return it.  
  The FY6900 stores the phase per channel.
* **Duty cycle** — on the JDS6600 the duty cycle applies to the pulse and square shape.  
  On the FY6900 the square shape is fixed at 50 %; a duty command switches the channel to Rectangle (`RECT`) so the value takes effect.
* **Limits** — values are checked against the detected model and the active waveform; the limits are listed in [10.2 Signal Generators and Model Limits](#102-signal-generators-and-model-limits).  
  Duty cycle is 0–100 % on the JDS6600 and 0.1–99.9 % on the FY6900; phase is 0–360° on both.

### 15.7 Errors and Unsupported Commands

| Error code | Meaning |
|:-----------|:--------|
| -100 | Device error |
| -113 | Undefined header |
| -114 | Invalid channel suffix |
| -222 | Value out of range |
| -224 | Invalid parameter |

Errors are queued and read with `SYST:ERR?` or counted with `SYST:ERR:COUN?`. During macro playback an error stops the playback.

The following are not supported and return -113:

* Command chaining with `;`
* `MEAS`, `READ` and `CALC` subsystems
* Sweep (`SOUR:SWE`), burst (`SOUR:BURS`) and arbitrary waveforms (`SOUR:FUNC:ARB`)
* Pulse parameters other than `SOUR<n>:PULS:DCYC`
* Channel suffixes other than `1` or `2` (returns -114)

---


## 16. Support and Feedback

### Logging Directory

The log directory is at `/tmp/sds/logging/sds.log` (Linux) or `%TEMP%\sds\logging\sds.log` (Windows).

* Review the troubleshooting section
* Check logs at the given log directory  
* Submit issues or feature requests via the [sdsremote](https://github.com/klumw/sdsremote) GitHub repository Issues section

> **Note:** This application is not affiliated with Siglent or any other commercial entity.

---

## 17. License

This software is released under the terms and conditions of the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.html).

