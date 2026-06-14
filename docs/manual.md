#

## 1. Introduction & Overview

**SDS-Remote** is a remote control interface and help center for Siglent SDS 1000X-E series oscilloscopes.
It provides a modern graphical user interface (GUI) for instrument control, waveform acquisition and analysis, data logging,
screen capture and device interaction and help through an integrated AI-powered chat interface.

> **Note:** This application is not affiliated with Siglent or any other commercial entity.

### 1.1 Compatibility

SDS-Remote is designed for the **Siglent SDS 1000X-E** series oscilloscopes (SDS1104X-E, SDS1204X-E, etc.). It communicates with the instrument via the VXI-11 protocol over TCP/IP (port 111) or via USBTMC (USB). While the application may partially work with other Siglent oscilloscope series that share the same SCPI command set, only the SDS 1000X-E series is tested and officially supported.

**Minimum Requirements:**

| Requirement | Specification |
|:------------|:--------------|
| Operating System | Linux or Windows |
| Display Resolution | 1100 × 600 minimum |
| Oscilloscope | Siglent SDS 1000X-E series |
| Network | TCP/IP (port 111) for VXI-11, or USB for USBTMC |
| Internet (AI features) | Required for AI chat functionality |

### 1.2 General Usage Advice

**Workflow Recommendations**

* Start by connecting to the oscilloscope using the **Settings** panel. Verify the status bar shows `ONLINE` before proceeding.
* Use the **Control Panel** for interactive operation — it provides immediate visual feedback through the screen capture.
* Use **Acquire Waveform** when you need precise measurements, cursor analysis, or reference waveform comparison.
* Use the **Data Logger** for long-term monitoring and trend analysis.
* Use the **Macro Recorder** to automate repetitive tasks. Record a sequence once, then replay it as needed.
* Save your oscilloscope configuration as a **Profile** before starting critical measurements so you can restore it later.
* The **AI Chat** is most effective for SCPI command assistance and troubleshooting questions.

**Performance Tips**

* Network (VXI-11) connections are generally more reliable than USB for sustained operation. USB support is experimental and may have device-specific compatibility issues.
* When using USB mode, the application detaches the kernel driver (`usbtmc`) to claim the device. Other software accessing the oscilloscope via USB may interfere.
* Screen captures (Control Panel) update after every command, which takes approximately 1–3 seconds depending on network latency and screen complexity. Rapid consecutive button presses are rate-limited to prevent command queue overflows.
* Waveform acquisition downloads the full 1201-point-per-channel dataset from the oscilloscope, which may take several seconds. The waveform is downsampled for rendering performance.
* The Data Logger queries the oscilloscope at the configured interval. Very short intervals (10 seconds) with many parameters enabled may cause measurement timing jitter due to SCPI query overhead.

**File Storage**

All user data (screenshots, waveforms, profiles, macros, reports) is stored under the application data directory:

| Platform | Path |
|:---------|:-----|
| Linux | `~/.local/share/sdsremote/` |
| Windows | `%LocalAppData%\sdsremote` |

See section 10 (Application Directory) for a complete breakdown of subdirectories.

### 1.3 Known Limitations

* **AI Accuracy** — The AI chat subsystem uses large language models that may generate incorrect SCPI commands or inaccurate technical advice. Always verify critical commands before execution. SDS-Remote is not liable for any damage resulting from AI-generated instructions.
* **USB Mode** — USB direct connection is experimental. Device detection, kernel driver handling, and bulk transfer reliability vary across platforms and firmware versions. Profile loading via USB may encounter compatibility issues on Linux depending on the device's USB firmware version.
* **Single Device** — The application connects to one oscilloscope at a time. Simultaneous control of multiple instruments is not supported.
* **No Data Streaming** — The application uses request-response SCPI communication. Continuous high-speed data streaming (e.g., at the full sample rate) is not supported. The Data Logger operates at minimum 10-second intervals.
* **Macro Playback** — Macros run on a dedicated VXI-11 connection. During playback, most UI functions are disabled. The Control Panel, Acquire Waveform, Data Logger, and AI Chat cannot be used concurrently with macro playback.
* **Window Close Protection** — The application intercepts the window close event. If a macro has unsaved changes, a dialog prompts to save or discard before closing.
* **Waveform Downsampling** — Acquired waveforms are downsampled to approximately 800–1000 points for display to maintain rendering performance. The full dataset is preserved in CSV exports.
* **Command Echo Handling** — The oscilloscope echoes every SCPI command back. The application automatically drains these echoes before queries, but this adds a small latency overhead to each command-response cycle.

---

#### Connection Requirement

> **Note:** Network-based (IP address) and direct USB control is supported. USB support is experimental.
> For network connection ensure that the oscilloscope and host system are connected to the same network.

---

## 2. User Interface

### 2.1 Top Bar

* **Control Panel**  

  * Displays oscilloscope screen
  * Provides a virtual control interface
  * Disabled when offline or during active operations

* **Acquire Waveform**  
  * Captures waveform data from selected channels
  * Displays status during acquisition
  * Supports cursor measurements

* **AI Toggle**  
  * Shows/hides AI chat interface
  * Disabled if AI is not configured

* **Profiles**  
  * Save and Upload your device configuration

* **Data Logger**
  * Log key parameters over time
  * Export pdf reports or save data points in a csv file

* **Macro Recorder**
  * Record, edit and play back SCPI command sequences
  * Automate repetitive measurement and configuration tasks
  * Supports variables, conditionals and loops for advanced automation
  * Button label changes to **Recording...** during recording and **Playback** during playback

* **Help**
  * Opens this documentation

* **News**  
  * Displays application updates

* **Settings**  
  * Opens configuration panel (IP and AI settings, export options)

* **Save**  
  * Saves images, reports and csv data for the different app functionalities
  * All files are saved in the application working directory

---

### 2.2 Status Bar

* **Device IP**: Connected oscilloscope address if network connection is set in the configuration
* **Status Indicator**:
  * `ONLINE` (green)
  * `OFFLINE` (red)

---

## 3. Settings

### 3.1.1 Connection Dropdown

* **Choose between network or USB connection**

* **IP Address**
  Example:
  `192.168.1.100`
  (only available in network mode)

### 3.1.2 CSV data export

* **Save csv data**  
  Enables additional csv data export for waveform acquisition and data logger

### 3.1.3 Ask for filename on save

* Enables a file name dialog on save.

### 3.1.4 AI Settings

> **See section 4.2 for more information**

---

## 4. AI System

This feature enables interaction with the oscilloscope using natural-language commands and allows users to ask questions about device functionality and operation.

### 4.1 AI Server Requirements

The AI chat feature communicates directly with AI providers via their APIs.

#### Supported Providers and Models

| Provider |
|------|
| DeepSeek |
| OpenAI |
| Anthropic |
| Google |
| Mistral |
| Cohere |
| EdenAI |
| OpenRouter |
| xAI |

The following large language models (LLMs) are known to operate correctly with the application:

**deepseek-v4-flash, gpt-4o, gpt-5.4-mini, gemini-3.5-flash, claude-haiku**  
*For exact model names, see your provider homepage.*

> Important: The AI subsystem may generate inaccurate information or incorrect operating instructions. Use this functionality at your own risk.
---

### 4.2 AI Model Configuration

1. Open **Settings**
2. Select AI provider from dropdown
3. Enter API Key
4. Enter model name
5. Save configuration

---

### 4.3 AI Chat Interface

#### Access

* Open or close the AI chat interface using the **AI** button in the top toolbar.

#### Capabilities

* **Technical Assistance**  
  Example: *“How do I configure the trigger delay?”*

* **SCPI Command Execution**  
  Examples:
  * “Set channel 1 vertical scale to 1V/div”
  * “Get current timebase setting”
  * “Switch channel 1 on“

> Note: For best results, English language input is recommended.
> Use **send command** syntax to send native SCPI commands (e.g.: 'send command C1:TRA ON').
---

### 4.4 AI Troubleshooting

* **AI Disabled**
  * Verify the AI configuration settings.

* **No AI Response**
  * Verify API credentials and account quota availability.
  * Check logs
  * Confirm internet connectivity

---

## 5. Device Profiles

The **Profiles** feature allows you to save the complete oscilloscope configuration and restore it later. This is useful for switching between measurement setups, sharing instrument configurations, or restoring a known-good state before critical measurements.

Profile files are stored with the `.lss` extension in the `profiles/` subdirectory of the application working directory. The file format is SCPI XML — the raw configuration data provided by the oscilloscope's `PNSU?` query.

### 5.1 Profiles Panel

Click the **Profiles** button in the top toolbar to open the Profiles panel. The panel displays:

**Header**

* Panel title "Profiles" with a save icon.
* **Close** button (X) returns to the main view.

**Save Area**

* A text input field labeled "Create New Profile" for entering a profile name.
* **Name restrictions**: Maximum 30 characters. Only alphanumeric characters (`a–z`, `A–Z`, `0–9`), underscores (`_`), and hyphens (`-`) are allowed.
* A **Save** button that reads the current oscilloscope configuration via the `PNSU?` SCPI query and stores it as an `.lss` file.
* During the save operation (which can take up to 15 seconds for large configurations), the Save button is disabled and shows a progress indicator.

**File List**

* Lists all saved `.lss` profile files in the `profiles/` directory.
* Each entry shows the file name and last modified date.
* **Sorting**: Sort by **Name** or **Date** in ascending or descending order using the sort controls above the list.
* Per-file actions:
  * **Load** (upload icon) — Sends the stored XML configuration to the oscilloscope via `profileWrite`. Only enabled when the device is online. The load operation has a 15-second timeout.
  * **Delete** (trash icon) — Permanently removes the profile file.

> **Note:** After a profile is loaded, the oscilloscope screen automatically refreshes to reflect the restored configuration.

### 5.2 Saving a Profile

1. Configure your oscilloscope as desired (using the physical device, Control Panel, or AI chat).
2. Click the **Profiles** button in the top toolbar.
3. Enter a descriptive name in the "Create New Profile" field.
4. Click **Save**. The application sends `PNSU?` to the oscilloscope, receives the full XML configuration, and saves it to the `profiles/` directory.

> **Note:** Saving a profile requires the device to be online. The `PNSU?` query returns an IEEE 488.2 definite-length block containing the complete instrument setup in XML format. The save operation may take several seconds depending on configuration size.

### 5.3 Loading a Profile

1. Ensure the oscilloscope is connected and online.
2. Open the **Profiles** panel.
3. Click the **Load** icon next to the desired profile.
4. The profile's XML configuration is sent to the oscilloscope as a single atomic write via `profileWrite`. For USB connections, there might be problems under Linux, because of USB incompatabilities depending on the device USB firmware version.
5. The oscilloscope screen automatically refreshes after the profile is applied.

> **Note:** Loading a profile will overwrite the current oscilloscope configuration. The operation cannot be undone on the device, so consider saving the current configuration first if you may need it later.

### 5.4 Using Profiles in Macros

Profile loading is supported in macro scripts via the `loadProfile` command (see section 7.5.4). When macro recording is active, loading a profile through the Profiles panel automatically appends a `loadProfile` command to the macro script, making it easy to include profile restoration in automated workflows.

### 5.5 Deleting a Profile

Click the **Delete** icon next to a profile to permanently remove it from the `profiles/` directory. Deleted profiles cannot be recovered.

## 6. Data Logger

The **Data Logger** records oscilloscope measurement parameters over time, plots them on a real-time chart, and generates PDF reports. It is ideal for monitoring signal drift, characterizing component behavior over time, or documenting long-duration measurements.

### 6.1 Opening the Data Logger

Click the **Data Logger** button in the top toolbar to open the Data Logger panel. The panel replaces the main waveform/control panel area and shows a configuration dialog when first opened. The button icon rotates during active recording.

### 6.2 Measurable Parameters

The following parameters can be logged per channel. Up to **5 parameters** total (across both channels) can be selected simultaneously:

| Parameter | Description |
|:----------|:------------|
| **Vpp** | Peak-to-peak voltage |
| **Mean** | Average (mean) voltage |
| **Rms** | Root mean square voltage |
| **Duty** | Duty cycle (percentage) |
| **Freq** | Signal frequency |

All voltage values are automatically scaled by the probe attenuation factor (queried from the oscilloscope via `C1:ATTN?` / `C2:ATTN?`).

### 6.3 Configuration

When the Data Logger panel opens in the **configuring** state, a setup dialog is displayed with the following controls:

#### Measurement Selection

* Toggle checkboxes for each parameter on CH1 and CH2 independently.
* A counter shows the number of selected parameters (maximum 5).
* At least one parameter must be selected before starting.

#### Measurement Interval

* Slider from **10 to 60 seconds** in 5-second steps.
* Controls how frequently the oscilloscope is queried for new measurements.

#### Recording Duration

* A row of preset buttons: **1 min, 5 min, 10 min, 20 min, 30 min, 1 h, 2 h, 6 h, 12 h, 24 h**.
* The total number of data points is calculated as `(duration × 60) ÷ interval + 1`.

#### Report Name

* An optional text field (up to **150 characters**) for a descriptive report name.
* This name appears at the top of the real-time chart and in the PDF report heading.

### 6.4 Real-Time Plot

Once recording starts, the Data Logger panel expands to show a real-time XY plot in the main area:

**Chart Display**

* Time axis (X) with automatic unit scaling: seconds (`s`), minutes (`min`), or hours (`h`) depending on total duration.
* Each selected parameter is plotted as a separate colored line.
* The elapsed time counter updates with each new data point.

**Hover Tooltip**

* Hover the mouse over the chart to see exact measurement values at any time position.
* The tooltip shows the time and all enabled parameter values (respecting line visibility toggles).

**Legend Toggle Chips**

* Below the chart, colored legend chips represent each active measurement line.
* Click a chip to **hide** or **show** that line on the chart — useful for focusing on specific parameters in multi-line plots.

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

After recording is stopped (and at least 2 data points exist), save a PDF report by clicking the **Save** button in the top toolbar. The report includes:

* **Headline** — "Data Logger Report" title.
* **Report Name** — The description entered during configuration.
* **Chart Image** — A PNG capture of the real-time plot.
* **Measurement Values Table** — For each enabled parameter:
  * Start value (first data point)
  * End value (last data point)
  * Minimum value
  * Maximum value
* **Total Recording Time** — Formatted with appropriate unit scaling.

Reports are saved to the `logger/reports/` subdirectory of the application working directory.

### 6.7 CSV Export

If the **Save CSV Data** option is enabled in Settings, a CSV file with all raw data points is exported alongside the PDF report to the `logger/csv/` subdirectory. The CSV contains a timestamp column and one column per measured parameter, with the report name included as a metadata comment.

### 6.8 Probe Attenuation

The Data Logger automatically queries the oscilloscope's probe attenuation settings before recording begins. Voltage measurements (Vpp, Mean, Rms) are scaled by the probe divider factor so that reported values match the actual signal levels at the probe tip. Probe dividers are displayed in the configuration dialog after the initial query completes.

## 7. Macro Recorder

The **Macro Recorder** automates repetitive measurement and configuration tasks by recording, editing and playing back sequences of SCPI commands.  
Macros support variables, conditionals (`if`/`else`), loops (`while`) and assertions, making them suitable for automated test procedures and batch instrument configuration.

Macro files are stored with the `.m` extension in the `automation/macros/` subdirectory of the application working directory.

### 7.1 Macro Recorder Panel

The Macro Recorder panel is opened by clicking the **Macro Recorder** button in the top toolbar. The panel is divided into three areas:

**Header**

* Displays the panel title "Macro Recorder" with a movie-clapper icon.
* Shows the currently loaded file name (with a `*` suffix if unsaved changes exist).
* After playback, a status icon appears:
  * Green checkmark — Macro completed successfully.
  * Red error icon — Macro failed with an error.
  * Orange cancel icon — Macro playback was stopped by the user.
* **Close** button (X) closes the panel and returns to the main view.

**Action Buttons**

* **Record** — Starts recording a new macro. All SCPI commands sent through the AI chat, the Control Panel, or loaded via profiles are captured into the macro. During recording, the button shows a blinking red dot and the label changes to "Recording...". Disabled during playback.
* **Stop** — Stops the current recording or playback. During playback, the label changes to "Stop Playback". Only enabled when recording or playback is active.
* **Play** — Executes the current macro content against the connected oscilloscope. Disabled during recording, playback, or when no macro content has been loaded or recorded.
* **Edit** — Opens the **Macro Editor** (see section 7.2) with the current macro content for manual editing. Disabled during recording, playback, or when no macro content is available.
* **Save** — Saves the macro to a `.m` file. If a file was previously loaded, it is overwritten silently. Otherwise, a dialog prompts for a file name (up to 30 characters, alphanumeric plus `_` and `-`). Enabled only after recording, loading, or editing a macro.

**File List**

* Lists all saved `.m` macro files in the `automation/macros/` directory.
* Each entry shows the file name (without `.m` extension) and last modified date.
* **Sorting**: Sort by **Name** or **Date** in ascending or descending order using the sort controls above the list.
* Per-file actions:
  * **Load** (upload icon) — Loads the macro content into the editor. Only enabled when the device is online.
  * **Delete** (trash icon) — Permanently removes the macro file.

### 7.2 Macro Editor

Clicking the **Edit** button or the **Load** button on a file opens the Macro Editor. This is a full text editor with line numbers, designed for writing and modifying macro scripts.

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

### 7.3 Recording a Macro

1. Ensure the oscilloscope is connected and online.
2. Open the **Macro Recorder** panel and click **Record**.
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

Establishes a VXI-11 connection to the oscilloscope at the given IP address. This is always the first command in a recorded macro. Only one `connect` statement should appear per macro.

```
connect(usb)
```

> ⚠️ **Experimental** — USB direct connection support for macros is experimental and may not work reliably on all systems. Requires a USBTMC-compatible oscilloscope connected via USB.

Connects to the oscilloscope via USBTMC (USB) instead of network. The device is auto-detected — no IP address is needed. When recording a macro while the application is in USB connection mode, `connect(usb)` is automatically inserted instead of `connect("IP")`.

#### 7.5.2 SCPI Commands

```
scpi("C1:TRA ON")
```

Sends a raw SCPI write command to the device. The command is not queried — no response is read. Use this for configuration commands that do not return a value.

```
query("C1:VDIV?")
```

Sends a SCPI query and reads the response. The response is logged but not stored. Use this for commands that return a value when you do not need to save it.

```
myVar=query("C1:VDIV?")
```

Sends a SCPI query and stores the cleaned response in a variable named `myVar`. Variable names may contain alphanumeric characters and underscores (`[a-zA-Z0-9_]+`). Variables persist for the duration of the playback session and can be used in conditions and `print` statements.

> **Note:** The oscilloscope echoes every command back. The macro engine automatically drains these echoes before queries to prevent buffer overflows. Query responses are cleaned by stripping the command echo and trailing unit suffixes (e.g. `V`, `mV`, `%`).

#### 7.5.3 Timing

```
wait(2.5)
```

Pauses macro execution for the specified number of seconds. Fractional values (e.g. `0.5`) are supported. Use this to allow the oscilloscope time to settle after configuration changes or between measurements.

#### 7.5.4 Device Profiles

```
loadProfile("/home/user/.local/share/sdsremote/profiles/my_setup.lss")
```

Loads a previously saved device profile (`.lss` file) and sends its configuration to the oscilloscope. The path must be an absolute file path. This command is automatically recorded when you load a profile during macro recording.

#### 7.5.5 Variables and Output

```
print(myVar)
```

Logs the current value of the variable `myVar` to the application log. If the variable is undefined, `<undefined>` is logged. Use this for debugging macro execution or recording measurement values.

##### String Concatenation

String arguments in `scpi()`, `connect()`, `query()`, `loadProfile()`, and `print()` can be built from multiple pieces joined by `+`. Each piece can be a quoted string literal or a variable reference:

```
val = 1
scpi("C1:VDIV " + val + "V")
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
    scpi("C" + ch + ":TRMD SINGLE")
}
```

#### 7.5.6 Conditionals: if / else

```
if(myVar == 1.0) {
    scpi("C1:TRA ON")
}
```

An `else` block can be appended using `}else{` or `} else {` on the closing line:

```
if(myVar >= 2.5) {
    scpi("C1:VDIV 5V")
} else {
    scpi("C1:VDIV 1V")
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

> **Note:** Comparison operators `<`, `<=`, `>`, `>=` require both operands to be valid numbers. An error is reported if either operand cannot be parsed as a number.

#### 7.5.7 Loops: while

```
while(query("SAST?")!="Trig'd"){
  wait(4)
}
```

In this example the while statement repeats the block as long as the condition isn't true. The condition is re-evaluated before each iteration. A maximum of **100 iterations** is enforced to prevent infinite loops. If the limit is exceeded, playback stops with an error.

**Loop control:**

* `break` — Immediately exits the innermost `while` loop. Using `break` outside a loop is an error.
* `continue` — Skips the remaining commands in the current iteration and re-evaluates the loop condition. Using `continue` outside a loop is an error.

#### 7.5.8 Assertions

```
assert("Channel 1 should be on", ch1State == ON)
```

Evaluates a condition and stops playback with an error message if the condition is false. The first argument is a descriptive text shown in the error message. The remaining arguments form a condition using the same operators as `if`/`while`.

Assertions are useful for validating oscilloscope state during automated test sequences:

```
ch1State=query("C1:TRA?")
assert("Channel 1 must be enabled", ch1State == ON)
```

#### 7.5.9 Macro Example

```
# Automated calibration check
connect("192.168.1.100")
wait(2)

# Load reference configuration
loadProfile("/home/user/.local/share/sdsremote/profiles/calibration.lss")
wait(5)

# Enable both channels
scpi("C1:TRA ON")
scpi("C2:TRA ON")
wait(1)

# Read and validate channel 1
c1vdiv=query("C1:VDIV?")
print(c1vdiv)
assert("C1 VDIV must be 1V", c1vdiv == 1.0)

# Read and validate channel 2
c2vdiv=query("C2:VDIV?")
print(c2vdiv)
if(c2vdiv != 1.0) {
    scpi("C2:VDIV 1V")
    wait(1)
}

# Verify final state
c2vdiv=query("C2:VDIV?")
assert("C2 VDIV must be 1V after correction", c2vdiv == 1.0)
```

After playback check your logfile to see all macro messages.


## 8. Acquire Waveform

The Waveform Acquisition feature captures waveform data from the connected oscilloscope and displays it as an interactive chart. The waveform display supports cursor measurements, zoom and pan controls, reference waveform overlays, and export of both PNG images and CSV data.

### 8.1 Acquiring Waveforms

1. Ensure the oscilloscope is connected and online.
2. Enable the channels you want to capture using the channel toggles in the Control Panel or the Device Parameters sidebar (see section 8.2).
3. Click the **Acquire Waveform** button in the top toolbar. A progress indicator is shown during acquisition.
4. After acquisition completes, the waveform chart is displayed in the main area with the **Device Parameters** panel on the right side.

> **Note:** At least one channel (CH1 or CH2) must be enabled for acquisition to succeed. The oscilloscope must have a valid trigger; otherwise the acquisition may time out.

### 8.2 Channel Selection

Channel visibility can be toggled in two places:

* **Control Panel** — The CH1 and CH2 buttons in the virtual front panel toggle each channel on or off.
* **Device Parameters Panel** — The channel status indicators (CH1, CH2) in the sidebar also toggle channel visibility.

Channel colors in the waveform display:

| Channel | Color |
|:--------|:------|
| CH1 | Yellow |
| CH2 | Magenta |
| Reference | White (dashed) |

### 8.3 Device Parameters Panel

When a waveform is displayed, a sidebar panel appears on the right side showing the current oscilloscope parameters:

**Global Parameters**

| Parameter | Description |
|:----------|:------------|
| Timebase | Horizontal scale in seconds per division |
| Trigger Delay | Trigger position offset |
| Sample Rate | Current sampling rate in samples per second |

**Per-Channel Parameters** (shown when the channel has data)

| Parameter | Description |
|:----------|:------------|
| V/div | Vertical scale in volts per division |
| Offset | Vertical offset in volts |

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

Use the **Zoom** slider in the Device Parameters panel (range: 1.0× to 4.0×, in 0.25× steps). When zoom is greater than 1.0×, horizontal and vertical pan sliders appear at the bottom and right edges of the waveform display.

#### Pan

* **Horizontal pan** — Slider at the bottom of the waveform display (cyan). Adjusts the horizontal viewport.
* **Vertical pan** — Slider at the right side of the waveform display (orange). Adjusts the vertical viewport.

When zoom is returned to 1.0×, the pan position resets to center.

### 8.6 Reference Waveforms

Previously saved waveform data can be loaded as a reference overlay for comparison with live waveforms.

#### Loading a Reference

1. Click the **Load Reference** button in the Device Parameters panel.
2. Select a CSV file from the `waveform/csv/` directory.
3. If the CSV contains both CH1 and CH2 data, choose which channel to load.
4. The reference waveform is displayed as a white dashed line over the live waveform.

#### Managing References

* The reference waveform toggle (**REF**) appears in the channel status area of the Device Parameters panel.
* Click the **REF** indicator to show or hide the reference waveform.
* The reference time axis is automatically aligned to the live waveform for accurate comparison.

### 8.7 Saving Waveform Data

Click the **Save** button in the top toolbar while a waveform is displayed to export the data.

#### PNG Export

A PNG image of the current waveform display (including cursors if enabled) is saved to the `waveform/images/` subdirectory of the application working directory.

#### CSV Export

A CSV file containing the raw waveform data points is saved alongside the PNG to the `waveform/csv/` subdirectory. The CSV format is:

```
# SDS-Remote Waveform Data
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

Time values start at 0 and increment by `1 / Sample Rate` for each row. Channel columns are empty (` `) when a channel was not acquired.

> **Tip:** The exported CSV files can be reloaded later as reference waveforms using the **Load Reference** feature (section 8.6).

#### Filename Prefix

If the **Ask for filename on save** option is enabled in Settings, a dialog prompts for a custom filename prefix before each save. The default prefix is `waveform` (image) and `waveform_data` (CSV). A numeric suffix is automatically appended to avoid overwriting existing files.

## 9. Control Panel

The Control Panel provides a virtual representation of the oscilloscope's physical front panel, allowing remote operation of the device. Click the **Control Panel** button in the top toolbar to open it — the current oscilloscope screen is captured and displayed with interactive control overlays. After each command, the screen is automatically refreshed.

The panel is divided into two main areas: the **Screen Display** on the left and the **Control Sidebar** on the right. When the device is offline, an "OFFLINE" overlay blocks the control sidebar.

### 9.1 Screen Display

The left portion shows the live oscilloscope screen as a captured image. Below the screen, a row of soft keys mirrors the physical soft keys on the oscilloscope:

| Soft Key | Function |
|:---------|:---------|
| **M1 – M6** | Context-sensitive soft keys matching the on-screen labels |
| **Menu** | Opens the oscilloscope's main menu (round button, rightmost) |

Click a soft key to activate the corresponding on-screen function. The soft keys update automatically after each screen refresh, reflecting the oscilloscope's current menu state.

### 9.2 Control Sidebar

The right side of the panel contains the virtual controls, organized into functional groups. All buttons and knobs are disabled when the device is offline or when the application is busy processing a previous command.

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

Clicking a channel button while the **Acquire Waveform** panel is also active toggles channel visibility in both the waveform chart and the Control Panel, keeping them synchronized.

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

* **Drag** — Click and drag a knob up/down or left/right to adjust the value continuously. The knob rotates visually to reflect the change. Each drag gesture translates to a SCPI knob command sent to the oscilloscope.
* **Tap** — Click a knob without dragging to set a specific value. This opens a numeric input dialog where you can type the exact value.

Knobs are disabled while another command is being processed to prevent overlapping SCPI requests, which could cause command queue overflows on the oscilloscope.

### 9.7 Event Processing

To prevent command collisions, the Control Panel enforces a single-command-at-a-time lock:

* When a button or knob action is triggered, all controls are temporarily disabled.
* The SCPI command is sent, the oscilloscope processes it, the screen is refreshed, and a brief cooldown period elapses before controls are re-enabled.
* This ensures reliable operation even during rapid interaction.

### 9.8 Macro Recording Integration

While the **Macro Recorder** is recording, every button press and knob adjustment in the Control Panel is automatically captured as a SCPI command line in the macro script. This allows you to build automation sequences by simply operating the virtual front panel normally.

### 9.9 Saving Screenshots

Press the **Save** button in the top toolbar while the Control Panel is active to save the current oscilloscope screen as a PNG file. Screenshots are stored in the `screenshots/` subdirectory of the application working directory. The image format is PNG.

---

## 10. Getting Started

### Basic Connection Setup for Network Mode

*Skip steps 1-3 if you have selected USB in Connection Mode settings*

1. Connect the oscilloscope to the network.
2. Obtain its IP address.
3. In **Settings** enter the IP address.
4. In **Settings** click **TEST CONNECTION**.  
   Check that network/USB low level connectivity works
5. Save configuration.
6. Verify that the status bar shows your device as `ONLINE`.

### Application Directory

The application directory stores captured images, CSV exports, and device profile files.
The directory is OS specific:

* **Linux:** `~/.local/share/sdsremote/`
* **Windows:** `%LocalAppData%\sdsremote`

Files are stored in various subfolders of the application directory, depending on their type.  

| Subfolder | Description |
| :-------- | :-------- |
| preferences | Application settings |
| screenshots | Display screenshots |
| waveform/images | Waveform images |
| waveform/csv | Waveform csv data |
| logger/reports | Data logger reports |
| logger/csv | Data logger csv data |
| profiles | Device profiles |
| automation/macros | Macro (.m) files |

---

## 11. Troubleshooting (Non-AI)

### Connection Issues

* **Offline Status**
  * Verify device power and network connection
  * Ensure oscilloscope is not in standby
  * If in network mode, validate IP address, firewall (VXI-11 uses port 111)
  * Use connection test in settings

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

## 12. Technical Details

### Communication

* Protocol: VXI-11 over TCP/IP or USB direct connect
* Command Interface: SCPI
* Network-based and USB connections are supported.

### Data Formats

* **Screen Capture**: BMP (device) → PNG (application)
* **Waveform Data**: Binary → voltage/time values
* **Device Profiles**: SCPI XML → .lss files
* **Other Export Formats**: PNG (Control Panel, Waveform), CSV (Waveform, Data Logger), PDF (Data Logger)
* **Macro Files**: Plain text `.m` files with one command per line

### Performance

* Waveforms are downsampled to improve rendering performance and display responsiveness.
* Screen captures are compressed to reduce storage requirements.
* AI response times depend on provider latency and knowledge retrieval operations and may vary significantly.

---


## 13. Support and Feedback

### Logging Directory

The log directory  is at `/tmp/sds/logging/sds.log` (Linux) or `%TEMP%\sds\logging\sds.log` (Windows)

* Review the troubleshooting section
* Check logs at the given log directory  
* Submit issues or feature requests via the [sdsremote](https://github.com/klumw/sdsremote) GitHub repository Issues section

---

## 14. License

This software is released under the terms and conditions of the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.html).
