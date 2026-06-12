#

## 1. Introduction & Overview

**SDS-Remote** is a remote control interface and help center for Siglent SDS 1000X-E series oscilloscopes.
It provides a modern graphical user interface (GUI) for instrument control, waveform acquisition and analysis, data logging,
screen capture and device interaction and help through an integrated AI-powered chat interface.

> **Note:** This application is not affiliated with Siglent or any other commercial entity.

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

The **Profiles** feature allows you to save and restore your device configuration.

### 5.1 Saving a Profile

1. Configure your oscilloscope as desired.
2. Click the **Profiles** button in the top bar.
3. Enter a descriptive name in the "Create New Profile" field.
   * Names are limited to 30 characters
   * Only alphanumeric characters, underscores (`_`), and hyphens (`-`) are allowed
4. Click **Save**. The configuration is stored in .lss file format in the applications working directory

### 5.2 Loading and managing Profiles

* **Load**: Apply settings to the connected oscilloscope
* **Delete**: Permanently remove a saved profile
* **Sorting**: Sort by **Name** or **Date** (ascending/descending)

## 6. Data Logger

Data logging can be configured for the following parameters:  

| Parameter | Description |
| :-------- | :-------- |
| Vpp | Peak to peak voltage |  
| Mean | Mean voltage |
| Rms | Root mean square voltage |
| Duty | Duty cycle |
| Freq | Frequency |

Parameter logging is available for channels 1 and 2. The logging duration is configurable, ranging from 1 minute to 24 hours, and up to 5 parameters can be selected.
An optional report name (up to 150 characters) can be entered. The measurement interval and recording duration are adjustable via slider controls.

After data acquisition is complete, a PDF measurement report containing a data chart and summary statistics can be generated. The report includes:

* Start/End values
* Min/Max values
* Measurement chart

Once recording begins, a real-time plot tracks the selected parameters. Upon completion, a PDF report can be generated. If enabled in settings, all recorded data points are also exported to a CSV file in the application working directory.

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
* **Play** — Executes the current macro content against the connected oscilloscope. Disabled during recording or playback.
* **Edit** — Opens the **Macro Editor** (see section 7.2) with the current macro content for manual editing. Disabled during recording or playback.
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

* Line number gutter on the left side, synchronized with scrolling.
* Full keyboard editing support.
* Unsaved changes are indicated by a `*` after the file name in the header.
* **Close** button returns to the Macro Recorder file list.

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
    scpi("C" + ch + ":TRA ON")
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

Repeatedly executes the block as long as the condition isn't true. The condition is re-evaluated before each iteration. A maximum of **100 iterations** is enforced to prevent infinite loops. If the limit is exceeded, playback stops with an error.

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

The Waveform Acquisition feature allows you to record waveform data for Channels 1 and 2. The X/Y cursor function provides additional measurement capabilities for detailed waveform analysis.  

The zoom slider enables you to zoom in and out of the waveform display, allowing specific sections of the waveform to be examined in greater detail.  

Press the **Save** button to store an image of the recorded waveforms in the application working directory. If the **Save CSV Data** option is enabled in the settings, the waveform data points are also saved as a CSV file in the application working directory.  

The **Load Reference** button allows previously saved CSV waveform data to be loaded and displayed as a reference waveform.

## 9. Control Panel

The Control Panel allows you to remotely operate your oscilloscope. After each command, the displayed oscilloscope screen is automatically updated.  

Press the **Save** button to store a screenshot in the application working directory.

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
| screeshots | Display screenshots |
| waveform/images | Waveform images |
| waveform/csv | Waveform csv data |
| logger/reports | Data logger reports |
| logger/csv | Data logger csv data |
| profiles | Device profiles |
| automation/macros | Macro (.m) files |
| automation/reports | Macro PDF reports |

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

* Review the troubleshooting section
* Check logs at `/tmp/sds/logging/sds.log` (Linux) or `%TEMP%\sds\logging\sds.log` (Windows)
* Submit issues or feature requests via the [sdsremote](https://github.com/klumw/sdsremote) GitHub repository Issues section

---

## 14. License

This software is released under the terms and conditions of the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.html).
