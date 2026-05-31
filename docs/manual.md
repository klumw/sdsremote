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

## 7. Acquire Waveform

The Waveform Acquisition feature allows you to record waveform data for Channels 1 and 2. The X/Y cursor function provides additional measurement capabilities for detailed waveform analysis.  

The zoom slider enables you to zoom in and out of the waveform display, allowing specific sections of the waveform to be examined in greater detail.  

Press the **Save** button to store an image of the recorded waveforms in the application working directory. If the **Save CSV Data** option is enabled in the settings, the waveform data points are also saved as a CSV file in the application working directory.  

The **Load Reference** button allows previously saved CSV waveform data to be loaded and displayed as a reference waveform.

## 8. Control Panel

The Control Panel allows you to remotely operate your oscilloscope. After each command, the displayed oscilloscope screen is automatically updated.  

Press the **Save** button to store a screenshot in the application working directory.

---

## 9. Getting Started

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

---

## 10. Troubleshooting (Non-AI)

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

## 11. Technical Details

### Communication

* Protocol: VXI-11 over TCP/IP or USB direct connect
* Command Interface: SCPI
* Network-based operation only (USB connections are not supported).

### Data Formats

* **Screen Capture**: BMP (device) → PNG (application)
* **Waveform Data**: Binary → voltage/time values
* **Device Profiles**: SCPI XML → .lss files
* **Other Export Formats**: PNG (Control Panel, Waveform), CSV (Waveform, Data Logger), PDF (Data Logger)

### Performance

* Waveforms are downsampled to improve rendering performance and display responsiveness.
* Screen captures are compressed to reduce storage requirements.
* AI response times depend on provider latency and knowledge retrieval operations and may vary significantly.

---

## 12. Support and Feedback

* Review the troubleshooting section
* Check logs at `/tmp/sds/logging/sds.log` (Linux) or `%TEMP%\sds\logging\sds.log` (Windows)
* Submit issues or feature requests via the [sdsremote](https://github.com/klumw/sdsremote) GitHub repository Issues section

---

## 13. License

This software is released under the terms and conditions of the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.html).
