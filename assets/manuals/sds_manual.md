#

## 1. Introduction & Overview

Welcome to the SDS-Remote Help Center.

***SDS-Remote*** is a remote control application for the Siglent SDS 1000X-E series.
It combines instrument control and waveform analysis with data logging, macro recording and playback, screen capture and an optional AI-assisted chat interface.

> **Before you connect a probe to any circuit,** read [Electrical Safety](#electrical-safety) in section 1.2. The probe ground of a mains-powered oscilloscope is connected to protective earth, and an incorrect connection can damage equipment or cause injury.&#10;For optimal results, make sure your oscilloscope is running the latest available firmware version

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
| Internet (AI features) | Required for all AI features |

### 1.2 Safety and General Usage Advice

#### Electrical Safety

Read the electrical safety instructions for the equipment you are using. The information provided below is purely supplementary; the values ​​and procedures specified in the equipment manual take precedence.
The oscilloscope is a mains-powered measuring instrument. Its inputs are not isolated from protective earth, and a probe can connect your circuit to the mains protective conductor. Read this section before you connect a probe to any circuit.

**Input ratings and measurement category**

* The SDS1000X-E channel inputs have a **1 MΩ** input impedance. Check the maximum voltage rating for your exact model in its datasheet and on the front panel.
* The SDS1000X-E is specified for **Measurement Category I** — circuits that are not directly connected to the mains. Siglent's documentation explicitly excludes **CAT II, CAT III and CAT IV** and measurements on **mains circuits**.  
* Never exceed the lowest applicable rating of the oscilloscope input, the probe and the measurement setup.

**Probes and attenuation**

* Every probe has its own voltage rating. It is often lower than the oscilloscope input rating and depends on the probe model, the **1X/10X** setting and the measurement category. Check the marking on the probe and its datasheet. Never exceed the probe rating, even when the oscilloscope input could withstand the voltage.
* A **10X** probe divides the voltage by ten and usually has a higher voltage rating than the same probe in **1X** mode. A 1X probe also loads the circuit more heavily. Use 10X for most measurements and 1X only when the lower loading and higher sensitivity are needed.
* Set the oscilloscope's probe attenuation (1X, 10X, ...) to match the physical probe before measuring — in the oscilloscope's channel menu or with `C<n>:ATTN`. The application cannot detect which physical probe is connected. The Data Logger reads the attenuation with `C<n>:ATTN?` and scales its voltage values; the waveform and measurement views use the oscilloscope's scaled readings. A mismatch makes all voltage readings wrong by the attenuation factor (for example ten times too high), which can hide a hazardous voltage.
* Use only probes that meet the manufacturer's specifications and the applicable safety standard (for example UL 61010-031) for the measurement.

**Grounding and protective earth**

* On a conventional mains-powered oscilloscope, the **probe ground clip is connected to the chassis and to protective earth (PE)** through the mains cord. All channel ground clips are connected to the same chassis ground.
* Connect the ground clip only to the circuit's **0 V reference or protective earth**. Never connect it to a live conductor, to the mains, or to any point that is not at earth potential. Doing so creates a short circuit through the protective earth conductor and can cause injury, fire or equipment damage.
* **Never remove, disconnect, bypass or defeat the oscilloscope's protective earth connection** — for example with a cheater plug, by bending the earth pin, or by "floating" the oscilloscope through an isolation transformer. The protective earth is a safety feature, not an optional reference.
* Do not assume that a battery-powered or isolated circuit is safe: the probe ground still connects the circuit to earth through the oscilloscope.

**Mains and hazardous potentials**

* **Do not use ordinary passive probes for direct mains measurements.** Even when a probe's voltage rating appears sufficient, the probe ground clip and the oscilloscope input are earth-referenced. A standard probe cannot safely measure a live mains conductor.
* Measurements between two live potentials, or on any circuit that is not earth-referenced, require an appropriately rated **differential probe** or an isolated measurement system. Check its differential voltage, common-mode voltage and measurement-category ratings. A differential probe does not automatically make a mains measurement safe.
* Work on de-energized circuits where possible. Discharge capacitors, use insulated tools and do not work alone on hazardous equipment. If you are unsure whether a measurement is safe, do not connect the probe and ask a qualified person.

#### Quick Start

> **⚠️ WARNING — Electrical safety**
> The probe ground clip is connected to protective earth on a conventional mains-powered oscilloscope. Never connect it to a live mains conductor or to any point that is not at earth potential. Use the correct probe attenuation, stay within the input and probe ratings, and use a suitably rated differential probe for measurements involving hazardous potentials. Read [Electrical Safety](#electrical-safety) above before you connect a probe.

1. Connect the oscilloscope to the network or USB and select the connection in [Settings](#32-connection-mode).
2. Wait until the status bar shows `ONLINE`.
3. Set the probe attenuation on the oscilloscope to match the probe.
4. Open the [Control Panel](#9-control-panel) for interactive operation or [Acquire Waveform](#8-waveform-analysis) for measurements.

**Workflow Recommendations**

* Start by connecting to the oscilloscope using the **Settings** panel. Verify the status bar shows `ONLINE` before proceeding.
* Use the **[Control Panel](#9-control-panel)** for interactive operation — it provides immediate visual feedback through the screen capture.
* Use **[Acquire Waveform](#8-waveform-analysis)** when you need precise measurements,  
  cursor analysis, or [reference waveform](#86-reference-waveforms) comparison.
* Use the **[Data Logger](#6-data-logger)** for long-term monitoring and trend analysis.
* Use the **[Macro Recorder](#7-macro-recorder)** to automate repetitive tasks. Record a sequence once, then replay it as needed.
* Save your oscilloscope configuration as a **Profile** before starting critical measurements so you can restore it later.
* The **AI Chat** is most effective for oscilloscope-related questions and SCPI command assistance.

**Performance Tips**

* Screen captures in the Control Panel update after every command and take approximately 1–3 seconds.
* Waveform acquisition downloads a sparsely sampled record, up to 250,000 points per channel over VXI-11 or USB on Windows and up to 100,000 points per channel over USB on Linux, and may take several seconds.
* The Data Logger queries the oscilloscope at the configured interval. Short intervals with many parameters enabled may cause measurement timing jitter.

**File Storage**

All user data (screenshots, waveforms, profiles, macros, reports) is stored under the application data directory; see [12. Application Directory](#12-application-directory) for the platform paths and subdirectories.

### 1.3 Known Limitations

* **Single Device in the Main Views** — The Control Panel, Acquire Waveform, Data Logger, Bode Plot and AI assistants control one oscilloscope at a time. Macro playback can open additional VXI-11 connections to other SCPI devices through device handles ([7.5.1 Connection](#751-connection)); those connections belong to the macro and are not available to the main views. The signal generator is a separate serial device.
* **No Data Streaming** — The application uses request-response SCPI communication. Continuous high-speed data streaming (e.g., at the full sample rate) is not supported.
* **Macro Playback** — Macro playback uses its own connection object, separate from the main view's connection. Over VXI-11 it opens an independent TCP connection; over USB the application shares one USBTMC device handle per process. A macro can use VXI-11 (`connect("IP")`), USBTMC (`connect(usb)`) or additional VXI-11 device handles. During playback, most UI functions are disabled. The Control Panel, Acquire Waveform, Data Logger, and AI Chat cannot be used concurrently with macro playback.
* **Waveform Transfer and Downsampling** — The application transfers a sparsely sampled record, not the full acquisition memory. The transfer is capped at 250,000 points per channel over VXI-11 and USB on Windows, and at 100,000 points per channel over USB on Linux (see [8.1 Acquiring Waveforms](#81-acquiring-waveforms)). For display, the first 8 transferred samples are removed and every second remaining sample is used. CSV exports contain these displayed points with their actual sample timestamps; automatic measurements and the spectrum use the transferred record before this display decimation.

---

#### Connection Requirement

> **Note:** For network connection ensure that the oscilloscope and host system are connected to the same network.

---

## 2. User Interface

### 2.1 Top Bar

* **[Control](#9-control-panel)**  

  * Displays oscilloscope screen
  * Provides a virtual control interface
  * Disabled when offline or during active operations

* **[Waveform](#8-waveform-analysis)**  
  * Captures waveform data from selected channels
  * Displays status during acquisition
  * Supports cursor measurements

* **Profiles**  
  * Save and Load your device configuration

* **[Logger](#6-data-logger)**
  * Log key parameters over time
  * Export PDF reports and, when **Save CSV data** is enabled, CSV data

* **Bode**
  * Opens the [Bode Plot](#10-bode-plot) panel when a supported signal generator is configured and detected
  * Requires the oscilloscope to be online

* **[Macro](#7-macro-recorder)**
  * Record, edit and play back SCPI command sequences
  * Automate repetitive measurement and configuration tasks
  * Supports variables, conditionals and loops for advanced automation
  * Button label changes to **Recording...** during recording and **Playback** during playback

* **AI Chat** (sparkle icon)
  * Shows/hides [AI Chat](#42-ai-chat-interface) interface
  * The button shows only its icon and names the panel in its tooltip

* **Help**
  * Opens the [Help panel](#23-help-panel) with this documentation
  
* **News**  
  * Displays application updates

* **Settings**  
  * Opens configuration panel (IP and AI settings, export options)

* **Save**  
  * Saves the output of the active view: a PDF screenshot report (Control Panel), a PDF report (Waveform, Data Logger, Bode Plot) and CSV data where applicable (see [3.5 Export Options](#35-export-options))

* **Assistant microphone** (mic icon in the AI assistants)
  * The main AI Chat and the Control Panel, Waveform, Macro Recorder and Help AI Assistants each have a microphone button next to their input field.
  * The microphone is off when an assistant opens; the crossed-out icon shows the inactive state. Pressing the button switches it on and it listens continuously until it is switched off or the assistant closes.
  * Every spoken utterance is transcribed locally and sent to the open assistant as a chat message.
  * While the microphone is active, animated audio bars appear in the top bar. They turn green while the utterance is transcribed and while the assistant answers.
  * The microphone pauses while the assistant answers and resumes automatically afterwards. Switching panels or closing the assistant switches it off.
  * The AI provider, token and model must be configured in Settings ([4.1 AI Model Configuration](#41-ai-model-configuration)); otherwise the microphone button stays disabled.

---

### 2.2 Status Bar

* **Device IP**: Connected oscilloscope address if network connection is set in the configuration
* **Status Indicator**:
  * `ONLINE` (green)
  * `OFFLINE` (red)

---

### 2.3 Help Panel

The **Help** button in the top bar opens this documentation in a separate help window. The window provides a search field and links to every manual section. A floating button in the bottom-right corner jumps back to the top of the text; it appears as soon as the manual has been scrolled down.

#### AI Assistant

The **AI Agent** button next to the **SDS-Remote Help** title opens the Help AI assistant.

* The assistant answers questions from this manual and links directly to the matching sections.
* For problems with the application, it reads the recent application log and explains the relevant entries.
* It has the same microphone button as the other AI assistants ([2.1 Top Bar](#21-top-bar)).
* The trash button in the assistant header clears the transcript and the AI session, so the next question starts without the previous turns.

---

## 3. Settings

The **Settings** panel is opened by clicking the gear icon in the top toolbar. All settings are persisted to the application preferences file and restored on the next launch.

### 3.1 Opening Settings

Click the **Settings** icon (gear) in the top toolbar. The panel appears as a floating dialog titled "Device Configuration".

### 3.2 Connection Mode

Select the physical connection type used to communicate with the oscilloscope:

* **Network (VXI-11)** — Connects via TCP/IP using the VXI-11 protocol. This is the recommended mode for most setups. Requires the oscilloscope to be on the same network as the host computer.
* **USB (USBTMC)** — Connects via USB using the USBTMC protocol. The device is auto-detected — no IP address is needed. USB support is experimental.

### 3.3 IP Address

*Available only in Network (VXI-11) connection mode.*

Enter the IPv4 address of the oscilloscope. The address must be reachable from the host computer. The application first connects to the RPC portmapper on TCP port 111, asks it for the VXI-11 core-channel port, and then connects to that returned port. Both connections must be permitted by the network and any firewall (see [13. Troubleshooting](#13-troubleshooting-non-ai)).

**Example:** `192.168.1.100`

The current IP address is also displayed in the status bar at the bottom of the main window.  
If the address is incorrect or the device is unreachable, the status bar shows `OFFLINE` in red.

### 3.4 AI Provider Settings

The Settings panel provides three fields for AI configuration ([4.1 AI Model Configuration](#41-ai-model-configuration)):

* **AI Provider** — Dropdown list of supported providers.
* **AI API Token** — Your provider API key. The field masks input for privacy and requires at least 8 characters. See [4.6 Security and Privacy](#46-security-and-privacy) for storage, file permissions and revocation.
* **LLM Model** — The exact model name string as specified by your provider.

### 3.5 Export Options

Two toggle switches control default export behavior across the application:

* **Save CSV data** — Controls whether the Data Logger and the Bode Plot also write a CSV file when you save their PDF report. It has no effect on the Waveform view: saving a waveform always writes both a PDF report and a CSV file (see [8.7 Saving Waveform Data](#87-saving-waveform-data)).
* **Ask for filename on save** — When enabled, a dialog prompts for a custom filename prefix before each save operation, including PDF reports created by the Waveform AI assistant.
  When disabled, default prefixes are used (for example `screen_dump_report`, `waveform_report`, `waveform_data`, `data_logging_report`, `data_logger_data`, `bode_plot_report` and `bode_plot_data`).  
  A numeric suffix is always appended to avoid overwriting existing files, regardless of this setting.

The following table shows which files each save action writes:

| Save action | PDF report | CSV file |
|:------------|:-----------|:---------|
| Waveform **Save** | Always | Always |
| Waveform AI report | Always | Never |
| Data Logger **Save** | Always | Only when **Save CSV data** is on |
| Bode Plot **Save** | Always | Only when **Save CSV data** is on |
| Control Panel **Save** | Always | Never |

CSV files contain plain-text numerical values for spreadsheets and analysis tools. Waveform CSV files contain the displayed, downsampled points, not the full oscilloscope acquisition memory ([8.7 Saving Waveform Data](#87-saving-waveform-data)). Data Logger CSV files contain the recorded measurement samples.

Both settings take effect immediately and persist across application restarts.

### 3.6 Signal Generator

Select the signal generator used by the [Bode Plot](#10-bode-plot) and the [Signal Generator Window](#911-signal-generator-window):

* **No Signal Generator** — disables generator features (default).
* **JDS6600** — JOY-IT/Juntek JDS6600 and JDS6600-Lite.
* **FY6900** — FeelElec FY6900 series.

The selection is restored on the next launch. When a generator is selected, the application scans the serial ports, identifies the generator and enables the **Bode** button and the Signal Generator Window (default Ctrl+J, configurable in [3.10 Signal Generator Shortcut](#310-signal-generator-shortcut)).  
The detected model supplies the frequency, amplitude and offset limits (see [10.2 Signal Generators and Model Limits](#102-signal-generators-and-model-limits)).

The application loads the device profile for the selected generator at startup. The profile contains the supported SCPI commands and the operating knowledge used by the AI assistants. The configured profile and the identity detected from the device are reported separately.

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
3. Closes the Settings panel.

The status bar updates to reflect the new connection state. If `ONLINE` is shown, the oscilloscope is reachable and ready for operation.

> **Note:** The API token is stored in plain text in the preferences file (`preferences/preferences.json`) within the application directory; it is not encrypted.  
> Ensure appropriate file system permissions if working in a shared environment, and see [4.6 Security and Privacy](#46-security-and-privacy) for details and revocation instructions.

### 3.9 Calculator Shortcut

The engineering calculator opens with **Ctrl+R** by default. In **Settings → Calculator → Window shortcut** choose one of:

| Shortcut | Notes |
|:---------|:------|
| `Ctrl` + `R` | Default |
| `Ctrl` + `Shift` + `R` | Alternative if Ctrl+R is reserved by the desktop |
| `Ctrl` + `Alt` + `C` | Mnemonic alternative |
| `F9` | Keyboard-only alternative |

The selection is restored on the next launch.
There is no toolbar button: the calculator is available only through the configured shortcut.

### 3.10 Signal Generator Shortcut

The Signal Generator Window opens with **Ctrl+J** by default. In **Settings → Signal Generator Window → Window shortcut** — directly below the generator selection — choose one of:

| Shortcut | Notes |
|:---------|:------|
| `Ctrl` + `J` | Default |
| `Ctrl` + `Shift` + `J` | Alternative if Ctrl+J is reserved by the desktop |
| `Ctrl` + `Alt` + `G` | Mnemonic alternative |
| `F10` | Keyboard-only alternative |

The selection is restored on the next launch.
There is no toolbar button: the window is available only through the configured shortcut while a generator is selected and detected.
The shortcut is ignored while a macro is playing.

---

## 4. AI System

The [AI Chat](#42-ai-chat-interface) feature enables natural-language interaction with the oscilloscope — ask device-related questions,  
send SCPI commands, or get troubleshooting help.  
The AI communicates directly with your chosen provider's API (no intermediate server) and requires an active internet connection.

### 4.1 AI Model Configuration

Configure the AI in the **Settings** panel ([3.4 AI Provider Settings](#34-ai-provider-settings)): select a provider, enter the API token and the model name, and click **SAVE CONFIGURATION**.

After saving, the **AI Chat** button in the top toolbar becomes enabled and the AI features are initialized immediately; no restart is needed. All AI assistants and microphone buttons use the same configuration.

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

#### Model Names

The application does not ship a fixed catalog of model names. The string entered in **LLM Model** is combined with the provider prefix and sent to the provider; the provider decides which identifiers are valid.

The built-in agents use `deepseek-flash` as their default DeepSeek model. Enter `deepseek-flash` in the **LLM Model** field for the default configuration (recommended for the best results).

For every other provider, use the exact model identifier from that provider's current model list. Model names are introduced and retired regularly, so an identifier that worked previously may stop working. The `gpt-4o` text in the model field is only an example placeholder, not a recommendation.

### 4.2 AI Chat Interface

#### Opening and Closing

Click the **AI Chat** button in the top toolbar to open or close the chat interface. The chat replaces the main content area ([Control Panel](#9-control-panel), Waveform, etc.) while open.  
Your conversation history is preserved while the panel remains open; closing and reopening the chat clears the history. The trash button in the chat header clears the transcript and the AI session, so the next question starts without the previous turns.

The [Help panel](#23-help-panel), the [Control Panel](#910-ai-assistant), [Acquire Waveform](#812-ai-assistant-experimental), [Macro Editor](#77-ai-assistant) and [Engineering Calculator](#118-ai-assistant) have their own AI assistants that work directly in those views without replacing them.

#### Interface Layout

The chat window consists of:

* **Message Area** — A scrollable conversation history. User messages appear right-aligned in cyan bubbles. AI responses appear left-aligned with gray backgrounds. The area auto-scrolls as new content arrives.
* **Streaming Indicator** — While the AI is generating a response, a pulsing cyan cursor (`▊`) might appear at the end of the message, indicating more content is coming.
* **Input Field** — A text field at the bottom for typing messages. Press **Enter** to send (Shift+Enter for newline is not supported — text wraps automatically).
* **Capture Commands** — In the Waveform and Control Panel assistants, the short commands `record`, `update` and `snapshot` request fresh data without a model round trip.
* **History Button** — A history icon next to the input field expands the last five user inputs. Selecting an entry sends that prompt again. It appears once the chat has at least one user input. The same history is available in the Control Panel, Waveform, Macro Recorder, Help and Calculator AI assistants.
* **Send Button** — A paper-plane icon to the right of the input field. Disabled while the AI is generating a response.
* **Stop Button** — While the AI is generating a response, the send button changes to a square stop button.  
  Pressing it aborts the response immediately and marks it as `terminated by user`.

#### Message History

The chat maintains a multi-turn conversation history within the session. The AI remembers previous exchanges, so you can ask follow-up questions or refine commands without repeating context.

### 4.3 Capabilities and Usage

#### Device Questions (Knowledge Base)

Ask questions about oscilloscope features, specifications, measurements, or troubleshooting. The AI searches the built-in knowledge base and returns the relevant documentation.

**Examples:**
* *"What is the maximum sample rate of the oscilloscope"*
* *"How do I configure the trigger delay?"*
* *"Explain the difference between Auto and Normal trigger mode."*
* *"What SCPI command sets the timebase?"*

The knowledge base is bundled with the application. When it contains a tutorial video on the topic, the assistant appends a clickable **Videos** link that opens in the default browser.

#### SCPI Command Execution

> **⚠️ WARNING — AI-generated SCPI commands**
> The assistant can produce incorrect commands. A command can change oscilloscope settings, start or stop an acquisition, alter the trigger, or change the signal generator output. Verify the target device, channel, parameter and value before you confirm or rely on a command. AI output is not a guaranteed measurement and is not a safety assessment of your circuit or probe setup.

Describe what you want to do in natural language, and the assistant translates it to SCPI commands sent to the connected oscilloscope.

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

#### Signal Generator Control

When a JDS6600 or FY6900 is configured and connected, the AI Chat can also control the separate signal generator. The request must contain a signal-generator keyword: **Signal Generator**. In the AI Chat the bare word **Generator** is also accepted. For example: “Signal Generator frequency channel 1 10 kHz”. Without a keyword the AI Chat treats the request as an oscilloscope command or asks for clarification.

When a signal-generator keyword is present, the AI Chat treats the request as a signal-generator command. The keyword only selects the target device; it is not a separate confirmation step. An explicit instruction such as “Signal Generator frequency channel 1 10 kHz” states the requested value, so the AI Chat applies it immediately. It supports channel 1/2, frequency, amplitude (Vpp), DC offset, waveform, duty cycle, phase and output on/off, reading the current settings and device limits, resetting both channels to safe defaults and stopping a running modulation or sweep. The Waveform assistant supports the same generator control, but requires the normal confirmation step before applying a change ([8.12 AI Assistant](#812-ai-assistant-experimental)).

Waveform names are validated against the active device profile. A name that the selected generator does not support is rejected with a clear message instead of being guessed. The one documented exception is the FY6900 cross-model mapping: JDS6600-only names map to the closest FY6900 preset, and PULS on channel 2 becomes RECT. The assistant reports the requested and the actual name.

#### SDS-Remote Software Help

When you ask about the SDS-Remote application itself (installation, configuration, features),  
the AI directs you to the built-in Help system rather than attempting to answer from its own knowledge.

### 4.4 Limitations and Best Practices

* **AI Accuracy** — Responses are grounded in the knowledge base or actual device responses, but the language model may still misinterpret queries or produce incorrect SCPI syntax. Always verify critical commands. SDS-Remote is not liable for damage resulting from AI-generated instructions.
* **AI Safety** — AI output is not a safety assessment. The assistant cannot determine whether your circuit, probe, grounding or measurement setup is safe. Follow [Electrical Safety](#electrical-safety) and verify every AI-generated instruction before applying it to your equipment.
* **Provider Dependency** — Response quality and speed depend on the chosen AI provider and model.
* **API Costs** — AI usage may incur costs according to your provider's pricing. Monitor your API usage.
* **English Recommended** — The knowledge base and system prompts are written in English. Queries in other languages may produce less accurate results.


### 4.5 Troubleshooting

* **AI Chat button appears disabled (gray)**
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
  * Switch to a more capable model.

* **Knowledge base returns no results**
  * The question may be outside the documented scope of the SDS1000X-E series.
  * Try rephrasing with more general terms.
  * Consult the official Siglent documentation for topics not covered in the knowledge base.

* **Provider API errors**
  * Verify the API token is correct and has not expired.
  * Check that your provider account has available quota/credits.
  * Ensure the model name exactly matches your provider's naming convention.
  * Some providers require specific account tiers for API access.

### 4.6 Security and Privacy

#### API Key Storage

The **AI API Token** is stored in plain text in `preferences/preferences.json` in the application directory ([12. Application Directory](#12-application-directory)). It is **not encrypted**. Anyone who can read that file can read the token and use it against your provider account.

* Restrict the file to your user account. On Linux: `chmod 600 ~/.local/share/sdsremote/preferences/preferences.json`. On Windows: remove access for other users in the file's security properties.
* Do not copy `preferences.json` into backups, bug reports, chat messages, screenshots or support requests. Redact the `ai_api_token` field if you must share the file.
* In normal operation the application logs only the token length, not the token itself. Log files can still contain SCPI commands, measurement values and file paths; review them before sharing.
* To replace a key, create a new key in your provider's dashboard, enter it in **Settings → AI API Token**, and click **SAVE CONFIGURATION**. Then revoke the old key at the provider. Clearing the field and saving disables the AI features in SDS-Remote, but it does not revoke the key at the provider.

#### What Is Sent to the AI Provider

The AI features send requests directly to the API of the provider selected in [4.1 AI Model Configuration](#41-ai-model-configuration). SDS-Remote has no intermediate AI server. The provider's own privacy policy and data-retention rules apply.

| Data | Handling |
|:-----|:---------|
| Chat message text, including speech transcripts | Sent to the provider. |
| Conversation history and system prompts | Sent to the provider. |
| SCPI commands and query responses used by the assistant | Sent to the provider as tool calls and tool results. |
| Measurements, waveform/spectrum summaries, classification and fault-analysis results | Computed locally; the text results are sent to the provider. |
| Raw waveform samples | Analyzed locally; not sent to the provider. |
| Screen captures and chart images | Created locally; not sent to the provider. |
| Application-log excerpts read by the Help or instrument assistant | Read locally; the selected lines are sent to the provider. |
| Uploaded specification PDF/TXT | Read locally; the extracted text is sent to the provider. The file itself is not uploaded. |
| Microphone audio | Transcribed locally with whisper.cpp; the audio is not sent to the provider. |

The whisper speech-recognition model is downloaded on first use from the whisper.cpp model repository; this download does not contain your recordings. The transcript produced locally is then sent to the selected AI provider as a chat message, like typed text.

#### Local and Remote Processing

Local processing includes speech transcription, screen and chart capture, waveform conversion and decimation, automatic measurements, FFT/spectrum analysis, waveform classification, fault analysis, audio/digital measurement analysis, report generation and file storage.

Remote processing includes natural-language understanding, command generation, reasoning over the tool results and the text of the assistant's answer. The provider receives the data listed above; it does not receive raw audio, raw waveform samples or images.

#### Disabling AI

AI is optional. To disable it, clear the **AI Provider**, **AI API Token** or **LLM Model** field and click **SAVE CONFIGURATION**. The AI Chat button remains disabled, the assistant microphones stay disabled, and no AI requests are sent. All non-AI features — Control Panel, Acquire Waveform, Data Logger, Bode Plot, Macro Recorder, calculator and file operations — continue to work. AI features require an internet connection; the core measurement and control features do not.

#### AI and Measurement Safety

AI-generated commands and interpretations are not a safety assessment. The assistant does not know the ratings of your probe, the common-mode voltage of your circuit, or whether the probe ground is connected safely unless you tell it and it can read the relevant device settings. Do not rely on the AI to decide whether a measurement is safe; follow [Electrical Safety](#electrical-safety).

---

## 5. Device Profiles

The **Profiles** feature allows you to save the complete oscilloscope configuration and restore it later.  
This is useful for switching between measurement setups, sharing instrument configurations, or restoring a known-good state before critical measurements.
Profile files are stored with the `.lss` extension in the `profiles/` subdirectory of the application working directory.  

### 5.1 Profiles Panel

Click the **Profiles** button in the top toolbar to open the Profiles panel. The panel displays:

**Header**

* Panel title "Profiles" with a save icon.
* **Close** button (X) returns to the main view.

**Save Area**

* A text input field labeled "Create New Profile" for entering a profile name.
* **Name restrictions**: Maximum 30 characters. Only alphanumeric characters (`a–z`, `A–Z`, `0–9`), underscores (`_`), and hyphens (`-`) are allowed.
* A **Save** button that reads the current oscilloscope configuration and stores it as an `.lss` file.
* During the save operation (which can take up to 15 seconds for large configurations),  
  the Save button is disabled and shows a progress indicator.

**File List**

* Lists all saved `.lss` profile files in the `profiles/` directory.
* Each entry shows the file name and last modified date.
* **Sorting**: Sort by **Name** or **Date** in ascending or descending order using the sort controls above the list.
* Per-file actions:
  * **Load** (upload icon) — Sends the stored configuration to the oscilloscope.  
    Only enabled when the device is online. The load operation has a 15-second timeout.
  * **Delete** (trash icon) — Permanently removes the profile file. Deleted profiles cannot be recovered.

> **Note:** After a profile is loaded, the oscilloscope screen automatically refreshes to reflect the restored configuration.

### 5.2 Saving a Profile

1. Configure your oscilloscope as desired (using the physical device, [Control Panel](#9-control-panel), or [AI Chat](#42-ai-chat-interface)).
2. Click the **Profiles** button in the top toolbar.
3. Enter a descriptive name in the "Create New Profile" field.
4. Click **Save**. The application reads the full configuration from the oscilloscope and saves it to the `profiles/` directory.

> **Note:** Saving a profile requires the device to be online.

### 5.3 Loading a Profile

1. Ensure the oscilloscope is connected and online.
2. Open the **Profiles** panel.
3. Click the **Load** icon next to the desired profile.
4. The stored configuration is sent to the oscilloscope in one write operation.

> **Note:** Loading a profile will overwrite the current oscilloscope configuration.  
> The operation cannot be undone on the device, so consider saving the current configuration first if you may need it later.

### 5.4 Using Profiles in Macros

Profile loading is supported in macro scripts via the `loadProfile` command (see [7.5.4 Device Profiles](#754-device-profiles)).  
When macro recording is active, loading a profile through the [Profiles panel](#51-profiles-panel) automatically appends a `loadProfile` command to the macro script,  
making it easy to include profile restoration in automated workflows.

## 6. Data Logger

The **Data Logger** records oscilloscope measurement parameters over time, plots them on a real-time chart, and generates PDF reports.  
It is ideal for monitoring signal drift, characterizing component behavior over time, or documenting long-duration measurements.

### 6.1 Opening the Data Logger

Click the **Logger** button in the top toolbar to open the Data Logger panel.  
The panel shows a configuration dialog when first opened.  
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
| **Gain (dB)** | CH1 vs. CH2 | Voltage gain from the reference channel (CH1) to the signal channel (CH2) |

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

> **Note — very small signals:** Gain (dB) is only meaningful while both RMS voltages are well above the oscilloscope's noise floor and its 8-bit quantisation.  
> Below an RMS voltage of **10 mV** the calculated gain no longer describes the device under test and can jump by tens of decibels between samples.  
> For that reason **no gain value is recorded when either channel's RMS voltage is below 10 mV**  
> — the sample carries no Gain (dB) entry, which appears as an empty cell in the CSV export and as `Gain: invalid`  
> in the cursor popup, and the chart draws its line straight across it. A reading of exactly 10 mV is still measured.  
> **Note:** Gain (dB) is a **voltage** gain, not a power gain. If the impedance at both measurement points is equal, voltage gain in dB equals power gain in dB.

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
  labeled with a `%` and a `dB` suffix respectively.  
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
| **Stopped** | **New** — Returns to the configuration dialog (clears data). &#10;**Restart** — Starts a new recording with the same configuration (clears previous data, keeps settings). |

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

If the **Save CSV data** option is enabled in Settings, a CSV file with all recorded measurement samples is exported alongside the PDF report to the `logger/csv/` subdirectory. These are the samples taken at the configured measurement interval, not oscilloscope waveform samples.  
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

Loading, editing, saving and deleting macro files are local operations and work without a connected oscilloscope or signal generator. Only recording capture, playback and debug stepping require a device connection.

### 7.1 Macro Recorder Panel

The Macro Recorder panel is opened by clicking the **Macro** button in the top toolbar.  
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
  During recording, the button shows a blinking red dot and the label changes to "Recording...".  
  Disabled during playback.
* **Stop** — Stops the current recording or playback. During playback, the label changes to "Stop Playback". Only enabled when recording or playback is active.
* **Play** — Executes the current macro content against the connected oscilloscope.  
  Disabled during recording, playback, or when no macro content has been loaded or recorded.
* **Edit** — Opens the **Macro Editor** (see [7.2 Macro Editor](#72-macro-editor)) with the current macro content for manual editing.  
  Disabled during recording, playback, or when no macro content is available.
* **Save** — Saves the macro to a `.m` file. If a file was previously loaded, it is overwritten silently. Otherwise, a dialog prompts for a file name (up to 30 characters, alphanumeric plus `_` and `-`).  
  Enabled whenever macro content is available, regardless of the device connection.

**File List**

* Lists all saved `.m` macro files in the `automation/macros/` directory.
* Each entry shows the file name (without `.m` extension) and last modified date.
* **Sorting**: Use the controls above the list to order the entries by **Name** or **Date**, ascending or descending.
* Per-file actions:
  * **Load** (upload icon) — Loads the macro content into the recorder. Always enabled; loading and saving are local file operations and do not require a device connection.
  * **Delete** (trash icon) — Permanently removes the macro file.

**Print Output**

As soon as a `print()` statement produces output during playback, a **Print Output** panel appears on the left of the panel, next to the macro file list.  
It lists the messages of the current playback, scrolls to the newest line, and can be cleared with the icon in its header.  
The panel is hidden while it contains no messages. Starting a new playback, recording a new macro, or loading another macro clears the output.  
While the [Macro Editor](#72-macro-editor) is open, the same messages also appear in the lower half of its left output sidebar.

Printed values are formatted for readability: frequencies use Hz, kHz or MHz, voltages use mV or V, and scientific notation (for example `8.000000E+3`) is never shown.  
The unit is taken from the SCPI query that produced the value when it is known; otherwise the label before the value (such as `Frequency:` or `Vpp:`) selects it.

### 7.2 Macro Editor

Clicking the **Edit** button opens the Macro Editor with the current macro content.  
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

### 7.3 Recording a Macro

1. Ensure the oscilloscope is connected and online.
2. Open the **Macro Recorder** panel and click **New Record**.
3. A `connect("IP")` line is automatically inserted at the start of the macro (or `connect(usb)` if USB connection mode is active).
4. Perform actions through the AI Chat, Control Panel, or load a device profile — each SCPI command is automatically appended to the macro.
5. Click **Stop** when finished.
6. Review the recorded commands in the editor (click **Edit**).
7. Click **Save** to store the macro as a `.m` file.

> **Note:** Only SCPI commands sent during recording are captured. Manual waveform acquisitions, Data Logger operations, and UI interactions are not recorded.

### 7.4 Playing a Macro

1. Load a macro from the file list, or record/edit one.
2. Ensure the oscilloscope is connected and online.
3. Click **Play** to execute the macro.
4. The top toolbar button changes to **Playback**.
5. Click **Stop** to cancel playback at any time.
6. After completion, a status icon appears in the panel header and a snackbar message confirms the result.

### 7.5 Macro Syntax Reference

Macro files (`.m`) contain one command per line. Blank lines and lines starting with `#` (comments) are ignored.

All brace pairs `{` `}` must be balanced before playback begins; the parser validates this and reports errors with line numbers.

#### 7.5.1 Connection

```
connect("192.168.1.100")
```

Establishes a VXI-11 connection to the oscilloscope at the given IP address. This is always the first command in a recorded macro. A macro can contain one default oscilloscope connection and one `connect(SIG, usb)` connection; every additional device is opened as a named device handle with `name = connect("IP")` (see below).

```
connect(usb)
```
Connects to the oscilloscope via USBTMC (USB) instead of network. The device is auto-detected — no IP address is needed. When recording a macro while the application is in USB connection mode, `connect(usb)` is automatically inserted instead of `connect("IP")`.

```
connect(SIG, usb)
```

Connects to the signal generator selected in **Settings → Signal Generator** (JDS6600 or FY6900).  
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

```
cmd(SIG, "SOUR1:FREQ 1KHZ")
query(SIG, "SOUR1:FREQ?")
```

The `SIG` selector sends the command to the signal generator connected with `connect(SIG, usb)` instead of the oscilloscope.

These commands use the same SCPI driver as the [Signal Generator Window](#911-signal-generator-window) and the Bode Plot.
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

The `while` statement repeats its block as long as the condition is true. In this example the condition compares the acquisition status returned by `SAST?` with the string `Trig'd`; while the status is different, the macro waits and then checks again. The condition is re-evaluated before each iteration. A maximum of **100 iterations** is enforced to prevent infinite loops. If the limit is exceeded, playback stops with an error.

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
ch1State = query("C1:TRA?")
assert("Channel 1 should be on", ch1State == "ON")
```

Evaluates a condition and stops playback with an error message if the condition is false.  
The first argument is a descriptive text shown in the error message. The remaining arguments form a condition using the same operators as `if`/`while`.

Assertions are useful for validating oscilloscope state during automated test sequences:

```
ch1State=query("C1:TRA?")
assert("Channel 1 must be enabled", ch1State == "ON")
```

> **Note:** SCPI responses are strings. Quote text values in comparisons: `ch1State == "ON"`, not `ch1State == ON`. An unquoted `ON` is parsed as a variable name and stops playback with `Variable "ON" is undefined`.

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

The Macro Recorder panel offers ready-made templates through the **Templates** button in the file-list header. Choosing one loads its commands into the editor as an unsaved macro, which can be reviewed, adjusted and saved like any other macro:

* **5 V power supply check** — measures Vpp, mean and RMS on CH1.
* **UART baud rate** — measures the frequency and duty cycle of a UART line.
* **PWM duty cycle** — measures frequency, duty cycle and pulse width.
* **Clock signal present** — checks for a periodic clock with a 50 % duty cycle.

Templates are a starting point, not a measurement guarantee: channel numbers, trigger settings and thresholds may need to be adapted to the actual setup.

### 7.7 AI Assistant

The **AI Agent** button in the Macro Editor header opens a chat panel to the right of the editor.

The assistant works directly on the macro that is open in the editor:

* It answers questions about the macro language and reads the current macro.
* It creates or changes the complete macro content and validates the result against the macro syntax. Changes are applied immediately and marked as unsaved; `Ctrl` + `Z` in the editor restores the previous state.
* It can inspect the connected oscilloscope, the configured signal generator, the variables and `print()` output of the current run, and the application log to explain errors.
* It can list available profile files, add `loadProfile(...)` statements, and perform calculations and unit conversions for constant values.

The chat stays open, including its complete history, when the editor is closed and reopened later in the same session. An answer that is still streaming when the editor closes continues to update and is visible on reopen. Press the AI Chat button again to close the chat panel. The trash button in the chat header clears the transcript and the AI session, so the next question starts without the previous turns.

---

## 8. Waveform Analysis

The Waveform Acquisition feature captures waveform data from the connected oscilloscope and displays it as an interactive chart.  
The waveform display supports cursor measurements, zoom and pan controls, [reference waveform](#86-reference-waveforms) overlays, and export of a PDF measurement report together with CSV data.

### 8.1 Acquiring Waveforms

1. Ensure the oscilloscope is connected and online.
2. Enable the channels you want to capture using the channel toggles in the [Control Panel](#9-control-panel) or the [Device Parameters](#83-device-parameters-panel) sidebar (see [8.2 Channel Selection](#82-channel-selection)).
3. Click the **Waveform** button in the top toolbar. A progress indicator is shown during acquisition.
4. After acquisition completes, the waveform chart is displayed in the main area with the **Device Parameters** panel on the right side.

> **Note:** At least one channel must be enabled for acquisition to succeed. The oscilloscope must have a valid trigger; otherwise the acquisition may time out.

**Waveform transfer limit:** The application transfers a sparsely sampled record, not the full acquisition memory. The maximum number of transferred points per channel depends on the transport and operating system:

| Transport | Maximum transferred &#10;points per channel |
|:----------|--------------------------------------:|
| VXI-11 (network) | 250,000 |
| USB (USBTMC) on Linux | 100,000 |
| USB (USBTMC) on Windows | 250,000 |

The transfer cap does not depend on the oscilloscope model. The 100,000-point cap is applied to USB mode on Linux for every supported model; it exists because the SDS1x04X-E USBTMC firmware only tolerates short read requests, and a deep-memory transfer in small chunks would take minutes. On every transport the application asks the oscilloscope to send every n-th acquisition sample (`WFSU SP`), so the whole display span is covered with the allowed number of points. The transfer is therefore sparse, not truncated. See [8.7 Saving Waveform Data](#87-saving-waveform-data) for the relationship between transferred points, displayed points and CSV data.

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

Each active channel also shows a colored triangle in a vertical column directly to the left of the chart, outside the graticule. The triangle is aligned with the channel's vertical offset level; the channel number is inside the triangle, and the offset value with unit is shown beside it. For each active channel, the chart draws a white dashed horizontal line through that channel's 0 V level. A yellow dashed horizontal line marks the original 0 V point without channel offset, and a yellow triangle outside the right edge marks that point.

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
* **Zoom** — Slider to zoom the waveform display; see [8.5 Zoom and Pan](#85-zoom-and-pan).
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

Click the **Save** button in the top toolbar while a waveform is displayed to export the measurement data. **Save** writes a PDF measurement report and a CSV file; no separate image file is created. Unlike the Data Logger and Bode Plot, the waveform CSV is written regardless of the **Save CSV data** setting.

#### PDF Report

The PDF is saved to the `waveform/reports/` subdirectory and contains:

* Title, optional report name (from the filename prefix dialog), date/time and device name.
* An image of the waveform chart as it is currently displayed.
* The automatic measurements and device parameters described in [8.8 Measurements, Difference and Mask](#88-measurements-difference-and-mask) and [8.3 Device Parameters Panel](#83-device-parameters-panel).
* The reference comparison and mask-test result when available.
* Spectrum analysis for each acquired channel; see [8.9 Spectrum Analysis](#89-spectrum-analysis).

#### CSV Export

A CSV file containing the displayed waveform points is saved alongside the report to the `waveform/csv/` subdirectory.  
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

Time values are the actual sample timestamps of the exported (downsampled) points, normalized so the first row starts at 0. The interval therefore reflects the real sample spacing of the displayed waveform and is not necessarily `1 / Sample Rate`. `# Sample Rate` is the oscilloscope's acquisition sample rate (`SARA?`); when the transfer is sparsely sampled, the exported time step is larger than `1 / Sample Rate`, so use the Time column. Channel columns are empty when a channel was not acquired.

> **Tip:** The exported CSV files can be reloaded later as reference waveforms using the **Load Reference** feature ([8.6 Reference Waveforms](#86-reference-waveforms)).

#### Data Path and Resolution

The waveform view uses different representations of one acquisition:

| Stage | What it contains | Used by |
|:------|:-----------------|:--------|
| Acquisition memory | The oscilloscope's full record | Not transferred completely |
| Transferred record | Every n-th acquisition sample, selected by the `WFSU SP` sparsing factor, &#10;up to the transport cap (see [8.1 Acquiring Waveforms](#81-acquiring-waveforms)) | Automatic measurements, spectrum, conversion to display data |
| Display data | The first 8 transferred samples are discarded, then every second remaining sample is kept | Waveform chart, cursor measurements, CSV and PWL/WAV/VCD exports |
| CSV file | The display data with its real sample timestamps, normalized so the first row starts at 0 | Reloading as a reference waveform, spreadsheet analysis |

**Raw acquisition data** is the oscilloscope's full acquisition memory. **Transferred data** is the sparsely sampled record the application requests from it; it is already reduced. **Downsampled data** in this manual means the display data: the transferred record after the leading-sample removal and the 2:1 decimation. Neither the chart nor the CSV contains the raw acquisition memory or the complete transferred record; the CSV file contains the downsampled points shown in the chart. With the 250,000-point transfer cap the chart and CSV carry at most about 125,000 points; with the 100,000-point USB/Linux cap they carry at most about 50,000 points.

Automatic measurements and the spectrum are computed from the transferred record before the display decimation; the chart and the CSV use the decimated display points.

#### Filename Prefix

If the **Ask for filename on save** option is enabled in Settings, a dialog prompts for a custom filename prefix before each save.  
The default prefix is `waveform_report` (PDF) and `waveform_data` (CSV). A numeric suffix is automatically appended to avoid overwriting existing files.

### 8.8 Measurements, Difference and Mask

After every acquisition the measurement panel below the chart is filled automatically. Values that cannot be determined from the data are shown as `—`; they are never reported as zero. The info icon next to a channel name lists the reason (for example flatline signal, unstable period or unavailable rise/fall transition).

#### Automatic Measurements

The **Measurements** view shows per enabled channel:

* The applied vertical settings **V/div** and **Offset** as metric cells, in the same style as the measurement values.
* Vpp, RMS, frequency, duty cycle, rise time, fall time and overshoot.
* **Details** adds Vmax, Vmin, Vmean, high level (Top), low level (Base), pulse width, number of complete periods, analyzed sample count and the effective sample interval Δt.
* Once more than one acquisition has been stored, a history line shows mean ± standard deviation of Vpp, RMS, frequency and duty over the last acquisitions.
* Numeric values in the cards are limited to two decimal places; insignificant trailing zeros are omitted.

All time-based values use the effective sample interval of the transferred record. When the transfer is sparsely sampled (`WFSU SP` greater than 1), the interval reflects the real spacing of the transferred samples; this can happen over USB and over VXI-11 when the record is deeper than the transfer cap. When the record covers less than two complete periods, the frequency is derived from the available mid-level crossings and marked as a short-record estimate.
* Channels without data or switched off are not shown.

#### PWM and Signal Integrity

The **PWM** toggle switches the cards to the PWM/signal-integrity view:

* Frequency, duty cycle, mean/min/max pulse width and pulse-width standard deviation.
* Period jitter as the standard deviation of the measured periods.
* Rising/falling edge counts, 10–90 % rise/fall times, overshoot and undershoot.

For non-periodic signals (flatline, noise or an unstable period) the PWM values stay empty instead of showing invented numbers.

#### Measurement Explanations

Every metric label in the cards has an info icon. Hovering over it shows a short offline explanation of how the value is defined — for example that RMS is the root-mean-square voltage, that frequency is derived from rising mid-level crossings, or that duty cycle is the high time as a share of the period. The texts are bundled with the application.

#### Ripple & Noise Measurement

The wave icon in the **Measurements** header opens the **Ripple & Noise** dialog:

* Choose the channel, V/div and offset, and whether the 20 MHz bandwidth limit should be enabled.
* **Offset (V)** shifts the channel vertically (`C<n>:OFST`) so the AC-coupled ripple stays inside the input range and does not clip. It is a channel offset, not a DC bias on the circuit and not part of the RMS/Vpp calculation; leave it at 0 when the trace is already centered.
* The preset switches the channel to AC coupling (`A1M`), applies the bandwidth limit, V/div and offset, then reads RMS and Vpp.
* With **Restore previous channel settings** enabled (default), the coupling, bandwidth limit, V/div and offset observed before the preset are written back afterwards.
* The result shows the RMS ripple/noise and the peak-to-peak value. Values below a few hundred µV are usually dominated by the probe ground lead and the probe attenuation.

#### Timebase Optimization

* The Measurements header permanently shows **Trigger source CHx: Optimize for** followed by **Time-Domain Analysis** and **Frequency-Analysis**. The buttons are disabled when the trigger channel has no usable period.
* **Time-Domain Analysis** sets a timebase that shows about four periods of the trigger source signal and refreshes the waveform view with a fresh acquisition.
* **Frequency-Analysis** sets a timebase that shows about 50 periods, giving the spectrum enough cycles for a useful FFT, and refreshes the waveform in the same way.
* Both calculations use only the channel selected as the oscilloscope trigger source; other displayed channels do not influence the result. The timebase is never changed automatically.

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

### 8.9 Spectrum Analysis

The waveform analysis area has two tabs above the chart: **Time domain** shows the waveform chart together with the measurement panel, and **Spectrum** shows the windowed FFT of the last acquisition.

#### Opening the Spectrum

1. Acquire a waveform (see [8.1 Acquiring Waveforms](#81-acquiring-waveforms)). Every channel that carries transferred data is analyzed.
2. Click **Spectrum** above the chart. A progress indicator is shown while the spectrum is computed.
3. A new acquisition invalidates the cached spectrum and recomputes it automatically while the Spectrum tab is active.

If the acquisition contains fewer than 20 usable samples, or every measured periodic channel shows fewer than 20 full periods, the **Spectrum** button is disabled and no FFT values are shown.

#### Controls

| Control | Meaning |
|:--------|:--------|
| **Channel** | **All channels** overlays every acquired trace; selecting CH1–CH4 shows only that channel. &#10;The selection also determines whose peak markers, metric cards and peak table are shown. |
| **Window** | Window function applied before the FFT: Rectangular, Hann (default), Hamming, Blackman-Harris or Flat-top.  &#10;The window fixes the trade-off between frequency resolution and leakage;  &#10;selecting Rectangular shows a leakage warning because it is only suitable for coherently sampled signals. |
| **FFT size** | `Auto` or an explicit upper bound (4096 to 1,048,576 points). The actual size is always the largest power of two that fits the available samples. |
| **Unit** | Level unit of the chart and peaks: **dBFS** (dB relative to the channel full scale derived from V/div), **dBV** or **dBm** into 50 Ω. |
| **Peak markers** | Number of automatic peak markers (3, 5 or 10). Markers are labeled 1…n; marker 1 is the fundamental. |
| **Logarithmic** | Switches the frequency axis between linear and logarithmic. In logarithmic mode the DC bin is omitted. |
| **Zoom** | Horizontal frequency zoom: **−** and **+** change the zoom factor, &#10;the center value shows the current factor (1.0x … 1000x) and the reset button returns to the full frequency range. |

#### Horizontal Zoom and Pan

The frequency axis can be stretched horizontally to make closely spaced peaks and sidebands easier to read:

* Turn the mouse wheel over the chart to zoom in or out around the pointer position. Scrolling up zooms in, scrolling down zooms out.
* While zoomed, drag horizontally in the chart to pan across the frequency range. The cursor changes to a grab hand; the visible range is shown below the chart.
* The **Zoom** control provides the same function with buttons: **−**, **+** and reset. The factor is relative to the full axis (Nyquist on the right).
* The x-axis tick labels automatically use more decimals as the visible span shrinks, so neighboring peaks remain distinguishable.
* Peak markers outside the visible range are hidden in the chart; their entries remain in the peak table below.
* A new acquisition, a changed window, an FFT-size change or switching the linear/log axis resets the zoom to the full range. The zoom applies to the chart image in the PDF report.

#### Chart and Traces

* With **All channels** selected, the chart overlays one color-coded trace per acquired channel; selecting a single channel limits the chart to that trace. In **All channels** mode the peak markers of every displayed channel are drawn; the metric cards and the peak table still describe the channel selected in the **Channel** drop-down.
* The vertical range starts at the highest level rounded up to the next 10 dB and spans up to 120 dB.
* Peak markers are drawn as vertical lines with a dot and a `n  frequency` label at the peak level.
* The info line below the controls shows channel, FFT size, sample rate, frequency resolution, the assumed full scale and the active window.

#### Metric Cards

The cards describe the selected channel:

| Metric | Definition |
|:-------|:-----------|
| **Fundamental** | Frequency and level of the strongest peak. |
| **THD** | Total harmonic distortion of harmonics 2…n relative to the fundamental, in percent and dB. |
| **THD+N** | All distortion and noise relative to the fundamental, in dB. |
| **SNR** | Signal-to-noise ratio in dB; harmonics are excluded from the noise. |
| **SINAD** | Signal-to-noise-and-distortion ratio in dB. |
| **ENOB** | Effective number of bits derived from SINAD: `(SINAD − 1.76) / 6.02`. |
| **SFDR** | Spurious-free dynamic range: strongest spur relative to the fundamental, in dBc. |
| **Noise floor** | Mean noise power per noise bin, in dBFS. |

Values that cannot be determined are shown as `-`; they are never reported as zero.

#### Peak Table

The table lists the automatic markers of the selected channel with marker number, frequency, peak amplitude in volts, level in dBFS and level relative to the fundamental in dBc.

#### Conventions

* The first 8 samples of the acquisition are skipped to avoid the leading acquisition transient.
* The DC component is removed before windowing by default.
* Amplitude scaling uses the coherent gain of the window, so a sine wave reads its correct peak amplitude; noise and distortion metrics use the noise-power bandwidth of the window.
* When the transfer is sparsely sampled, the spectrum uses the effective sample rate of the transferred record, so the frequency axis, resolution and Nyquist frequency refer to that rate.
* The same spectrum section is included in the PDF measurement report (see [8.7 Saving Waveform Data](#87-saving-waveform-data)).

### 8.10 Waveform Export

Click the **Export** button in the top toolbar while a waveform is displayed to open the export dialog. Formats and options:

| Format | Content | Options |
|:-------|:--------|:--------|
| **LTspice PWL** | `time value` pairs, one per line | Channel; optional `PWL(...)` wrapper |
| **WAV** | 16-bit PCM mono, uniform grid, normalized to full scale | Channel |
| **VCD** | Digital state changes, 1 ns timescale, all acquired channels | High threshold in volts |
| **Clipboard** | Measurement table as tab-separated text | — |

* All export formats use the displayed (downsampled) points, not the full acquisition memory.
* Files are written to the `waveform/exports/` subdirectory.
* Non-uniform point lists (for example a loaded reference) are linearly resampled onto a uniform grid for WAV.
* VCD timestamps are normalized so the earliest sample starts at 0.
* For external CSV data as a reference, place the file in `waveform/csv/` and use **Load Reference** ([8.6 Reference Waveforms](#86-reference-waveforms)); no separate file picker is required.

### 8.11 Timelapse

The clock icon in the bottom bar of the Control Panel, next to the automatic screen capture toggle, opens **Timelapse**:

* Set the interval as a positive whole number of seconds (1–86400), the number of frames (1–10000) and the file-name prefix. The dialog shows the resulting total duration.
* **Start** stops auto capture and the live screen and captures the oscilloscope screen at the chosen interval. Frames are written as PNG files into a timestamped run folder under `timelapse/` in the application directory, for example `timelapse/2026-10-31_14-30-05/timelapse_0001.png`.
* A snackbar reports the current frame and offers **Stop**; the clock icon also turns into the rotating arrows indicator that stops the run.
* The clock icon is disabled while no oscilloscope is online; a running timelapse can still be stopped if the connection drops.
* Auto capture and the live screen cannot be started while a timelapse runs.
* The run ends after the planned frame count, on **Stop**, or when a capture fails. The final snackbar names the number of frames and the output folder.

### 8.12 AI Assistant (experimental) ⚠️

The **AI Agent** button in the header of the **Device Parameters** panel opens the Waveform AI assistant.&#10;The trash button in the panel header clears the session, **always clear the session** before you start a new conversation.

#### Questions About the Acquisition

The assistant answers questions about the current acquisition from the available measurements and analysis:

* Time-domain measurements, device parameters, reference comparison and mask result.
* Spectrum analysis, including the metric cards and peak markers ([8.9 Spectrum Analysis](#89-spectrum-analysis)).
* Waveform classification and comparison against reference signal types, comparison of two channels, and waveform features.
* The last four acquisitions for comparison with an earlier capture.

Example questions:  
* “Which channel has the lowest THD?”  
* “What kind of waveform is this?”  
* “Compare this signal with a sine wave”  
* “Does this look like a PWM signal?”  
* “How similar are CH1 and CH2?”  
* “Acquire a new waveform and compare it with the previous one”

#### Audio Measurements

Audio-specific requests are delegated to an AudioAgent sub-agent. This covers level, RMS/peak, clipping, DC offset, THD, THD+N, SINAD, harmonics, intermodulation, distortion, SNR, noise floor, crest factor, hum, interference, spectral peaks, bandwidth, rise/fall time, phase, delay, transients, dropout, stability, crosstalk, dynamic range, gain, frequency response, phase response, group delay, sweeps and coherence.

The assistant asks once whether the audio measurements may run autonomously, including the necessary oscilloscope/generator changes and Bode sweeps. After confirmation the AudioAgent runs all needed measurements, may change scope or generator settings, can acquire a fresh waveform and can start a Bode sweep. Without permission it performs read-only measurements and proposes the required change instead. The structured result is returned to the Waveform AI, which presents the summary and measurement values in the user's language. Canceling the assistant request stops the audio analysis and a running Bode sweep immediately. Several sweep-based measurements within one request share a single Bode sweep.

#### Acquisition

The assistant can start a new acquisition immediately or after a requested delay of up to 600 seconds. A combined request such as “acquire in 10 seconds and then measure Vpp on CH2” is answered from the measurements returned with the capture. Pressing Stop cancels a pending delayed acquisition. The capture commands `record`, `update` and `snapshot` start an immediate acquisition without a model round trip ([4.2 AI Chat Interface](#42-ai-chat-interface)).

#### Oscilloscope Control

Read-only queries, such as the current volts/div or a live measurement, are executed immediately. Every setting change is first proposed with the exact channel, parameter and new value and is applied only after confirmation. After a confirmed change the assistant verifies the value with a read-back query and starts a fresh acquisition. A message that starts with **Scope**, **Oscilloscope**, **Oszi** or **Oszilloskop** is routed as an oscilloscope command, but the keyword does not replace the confirmation step.

#### Signal Generator Commands

When a JDS6600 or FY6900 is configured and connected, the assistant can control the signal generator under the same routing rule as the AI Chat, except that the bare word **Generator** is not accepted ([4.3 Signal Generator Control](#signal-generator-control)). The generator keyword selects the generator but does not replace the confirmation step. Without a signal-generator keyword, a request such as “frequency on channel 1” refers to the oscilloscope.

---

## 9. Control Panel

The Control Panel provides a virtual representation of the oscilloscope's physical front panel,  
allowing remote operation of the device.  
Click the **Control** button in the top toolbar to open it — the current oscilloscope screen is captured and displayed with interactive control overlays.  
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
It streams the display from the oscilloscope and updates continuously.
While Live is active, automatic screen capture is disabled and no screen dumps are fetched after SCPI commands.

The live screen is not available over USB connections or on two-channel models.

The **Timelapse** button (clock icon) sits in the bottom bar of the Control Sidebar, next to the automatic screen capture toggle, and starts or stops a timelapse run (see [8.11 Timelapse](#811-timelapse)).

### 9.2 Control Sidebar

The right side of the panel contains the virtual controls, organized into functional groups.  
All buttons and knobs are disabled when the device is offline or when the application is busy processing a previous command.

#### Intensity Adjust

A rotary knob at the top-left of the control area for adjusting the oscilloscope's display intensity (brightness).

#### Menu Grid

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

Clicking a channel button while the **[Acquire Waveform](#8-waveform-analysis)** panel is also active toggles channel visibility in both the waveform chart and the Control Panel,  
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
  The knob rotates visually to reflect the change.
* **Tap** — Click a knob without dragging to set a specific value. This executes the knob specific tap function.

### 9.7 Event Processing

To prevent command collisions, the Control Panel enforces a single-command-at-a-time lock:

* When a button or knob action is triggered, all controls are temporarily disabled.
* The command is processed, the screen is refreshed, and a brief cooldown period elapses before controls are re-enabled.
* This ensures reliable operation even during rapid interaction.

### 9.8 Macro Recording Integration

While the **[Macro Recorder](#7-macro-recorder)** is recording, every button press and knob adjustment in the Control Panel is automatically captured as a SCPI command line in the macro script.  
This allows you to build automation sequences by simply operating the virtual front panel normally.

### 9.9 Saving Screenshots

Press the **Save** button in the top toolbar while the Control Panel is active to save the current oscilloscope screen as a PDF report.  
The report contains the screenshot, the capture time, the device (name, serial number, firmware, connection), the acquisition settings (timebase, trigger delay) and the channel settings (state, coupling, bandwidth limit, probe attenuation, V/div, offset).  
The PDF is stored in the `screenshots/reports/` subdirectory of the application working directory.

### 9.10 AI Assistant

The Control Panel has its own AI assistant. The **AI Agent** button at the bottom-left of the control sidebar — at the same height as the automatic screenshot toggle — opens a chat overlay that covers the control sidebar. The close button in the overlay header collapses it again; the conversation is kept while the Control Panel remains open. The trash button in the overlay header clears the transcript and the AI session, so the next question starts without the previous turns.

Describe the desired setup in plain language, for example:

* "Set channel 1 to 200 mV per division with an offset of 0.2 V, then do an autoset."
* "Give me the frequency on channel 3 and the RMS voltage."
* "Why is the signal on CH1 so noisy? Suggest better settings."

The assistant can press buttons and turn knobs, set channel, timebase and trigger values, run Auto Setup, and read live measurements. It asks a clarifying question when a channel, value or unit is missing, and reports results in plain language without SCPI commands or raw device responses.

The capture commands `record`, `update` and `snapshot` fetch a fresh screen dump of the current oscilloscope display without a model round trip ([4.2 AI Chat Interface](#42-ai-chat-interface)). The assistant can also read the current waveform summary to explain measurement values and suggest better settings.

---

### 9.11 Signal Generator Window

When **Settings → Signal Generator** is set to **JDS6600** or **FY6900** and the generator was detected,  
press the configured shortcut (default **Ctrl+J**) to open the Signal Generator Window as a separate OS window.  
There is no toolbar button. Pressing the shortcut while the window is open brings it to the front.

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

* Arbitrary waveforms cannot be used for a Bode sweep.

The phase and duty-cycle behavior of both generator families is described in [15.6 Family-Specific Behavior](#156-family-specific-behavior).

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
| Outputs off after sweep | When enabled (default), both generator outputs are switched off after completion, failure or cancellation. &#10;Turn it off to leave the generator output running at the last sweep frequency. |

The form shows the active model limits below the waveform field, for example:

`Model FY6900-60M: Sine up to 60 MHz · amplitude up to 24 Vpp · offset ±12 V`

**START SWEEP** is disabled while the configuration is invalid. The reason is displayed above the button, for example when the stop frequency exceeds the limit for the detected model and selected waveform.

### 10.5 Running a Sweep

1. Verify the wiring and the DUT.
2. Configure the frequency range, waveform, amplitude, offset and channels.
3. Click **START SWEEP**.
4. The generator output is enabled. The oscilloscope is prepared (including automatic vertical scaling) and each point is measured after the settling time.
5. The gain and, when enabled, the phase are calculated for each point; the plots update as the sweep progresses.
6. **STOP** cancels the sweep.

During the sweep, generator detection is paused and the Signal Generator Window cannot change settings.  
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

The **Save** action in the top toolbar captures the Bode Plot and writes a PDF report to `bode/reports/`.  
The report contains the plot, the report name, the sweep configuration and an **Analysis** table with peak, −3 dB, bandwidth, Q factor and 0 dB crossover. When **Save CSV data** is enabled in the Settings, the sweep points are additionally written as CSV to `bode/csv/`.  
The generator identity (for example `FeelElec,FY6900-60M`) and the oscilloscope name are included.

### 10.8 Troubleshooting

* **Bode button is missing** — the oscilloscope is offline, no generator is configured, the generator was not detected, or a macro is playing.
* **START SWEEP is disabled** — the configuration is invalid; read the message below the fields.  
  A common cause is a stop frequency above the limit of the detected model and selected waveform.
* **Frequency write failed** — the generator did not confirm the frequency. Check the serial (USB) connection and the model limits.
* **No or unstable gain/phase** — increase the amplitude or settling time, reduce the frequency range, and verify that the oscilloscope inputs are not clipped.  
  Below about 5 mV RMS the point is omitted; below 1 mV Vin the gain is not valid.
* **Generator output stays on** — if the application was interrupted, switch the outputs off in the Signal Generator Window (default Ctrl+J) or on the device.
* **Serial (USB) port cannot be opened** — see the serial port prerequisites in [10.1 Prerequisites](#101-prerequisites).

---

## 11. Engineering Calculator (Ctrl+R)

The Engineering Calculator is a separate window for electronics, measurement, audio, DSP, embedded and RF calculations.

Open it with **Ctrl+R** or the shortcut configured in [3.9 Calculator Shortcut](#39-calculator-shortcut).
There is no toolbar button.
The window opens in the center of the main SDS-Remote window.
Pressing the shortcut again re-centers and focuses the existing calculator window.
The calculator is independent of the oscilloscope connection.

All calculator functions work without AI.
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
| `AUTO` / `ENG` / `FIXED` / `SCI` | Cycles the number format: Auto → Engineering → Fixed-point → Scientific. &#10;Fixed-point uses the decimal places from the calculator settings |
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
A bare `m` means meters, so `10m` is ten meters; write `10 mm` for millimeters.

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
Formulas with an illustration show the matching circuit diagram above the
formula expression; the images are bundled from `assets/formulas/`.
The **Inverting Amplifier** (`Av = rf / ri`) and **Non-Inverting Amplifier**
(`Av = (1 + rf / ri)`) formulas are examples; their results are labeled
`Av (voltage gain)`. The **Differential Amplifier** formula
(`V0 = -(rf / r1)(v1 - v2)`) also shows its schematic.

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

### 11.8 AI Assistant

The **AI Agent** button in the title bar opens the **Calculator AI** panel.

The assistant can:

* answer calculation questions and run engineering formulas;
* check units and dimensions with the deterministic calculator engine;
* distinguish linear gain from logarithmic gain and state level references;
* read the current expression, program, variables and display settings read-only.

The trash button in the panel header clears the transcript and the AI session, so the next question starts without the previous turns.

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
| **Use in program** | Inserts the last code block from the answer into the Programs editor without running it. &#10;Existing code requires confirmation before replacement |
| **Use as variable** | Opens the normal **Store variable** dialog with the result prefilled |

If the answer has no code block, **Use in program** inserts the cited calculation instead.
Results appear only as footnote markers; the assistant does not append a separate result card.
The **Copy** button below an answer copies the complete answer.

The panel header also provides **Insert calculator variable** for inserting a variable name into the prompt.

#### Operation

While a response is running, the send button becomes a stop button.
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
| `preferences` | Application settings, including the AI API token in plain text |
| `screenshots/reports` | Control Panel screenshot PDF reports |
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
  * If in network mode, validate the IP address. VXI-11 first connects to the RPC portmapper on TCP port 111 and then to the VXI-11 core-channel port returned by the portmapper. A firewall must allow both connections; a rule limited to port 111 is not sufficient.

* **USB connection lost / `libusb bulk write error` / `libusb bulk read error: -1 (IO_ERROR)`**
  * `IO_ERROR` on a four-channel model (SDS1104X-E/SDS1204X-E) means the instrument's USBTMC firmware stopped responding. The oscilloscope is still listed on the bus but no longer answers any transfer. Unplug and replug the USB cable, or power-cycle the oscilloscope; no application restart is required.
  * Waveform transfers are capped at 100,000 points per channel for USB on Linux and at 250,000 points per channel over VXI-11 or USB on Windows. This is a transfer limit, not the oscilloscope's acquisition memory depth: the application requests every n-th sample so the full display span is covered. See [8.1 Acquiring Waveforms](#81-acquiring-waveforms).
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

* Protocol: VXI-11 over TCP/IP or USBTMC over USB
* Network: VXI-11 uses the RPC portmapper on TCP port 111, then the VXI-11 core-channel port returned by the portmapper
* Command Interface: SCPI

### Data Formats

* **Screen Capture**: BMP (device) → PNG (application) → PDF report (Control Panel save)
* **Waveform Data**: Binary → voltage/time values
* **[Device Profiles](#5-device-profiles)**: SCPI XML → .lss files
* **Other Export Formats**: PNG (Timelapse), CSV (Waveform — displayed points; [Data Logger](#6-data-logger) — recorded samples; Bode Plot — sweep points), PDF (Waveform, [Data Logger](#6-data-logger), Bode Plot, [Control Panel](#9-control-panel)), PWL/WAV/VCD (Waveform Export)
* **Macro Files**: Plain text `.m` files with one command per line

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
| `SOUR<n>:FREQ <value>[unit]` | Sets the frequency, no unit means Hz. The value must be positive and within the model and waveform limit&#10;(see [10.2 Signal Generators and Model Limits](#102-signal-generators-and-model-limits)). | `SOUR1:FREQ 1KHZ` |
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

During macro playback an error stops the playback.

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

