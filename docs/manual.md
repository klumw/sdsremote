# SDS-Remote Help

## 1. Introduction & Overview

**SDS-Remote** is a remote control interface and help center for Siglent SDS 1000X-E series oscilloscopes.  
It provides a modern graphical user interface (GUI) for instrument control, waveform acquisition,  
screen capture, and interaction via an integrated AI-powered chat interface.

**Note: This application is in no way affiliated with Siglent or any other commercial entities.**

---

### Key Features

* **Remote Oscilloscope Control**  
  Control your oscilloscope over a network using the VXI-11 protocol

* **Waveform Acquisition**  
  Capture and display waveform data from enabled channels (CH1, CH2)

* **Remote Control Panel**  
  Acquire and view the oscilloscope display. Remote control your oscilloscope with a virtual front panel

* **AI Chat Interface**  
  Send commands and query oscilloscope functionality using natural language

* **Device Profile Management**  
  Save and restore oscilloscope configurations as local files (.lss) for quick setup

* **Device Parameter Monitoring**  
  View real-time parameters such as timebase, sample rate, and voltage settings Cursor-based measurements are supported

* **Data Export**  
  Save screen captures as images and export waveform data as CSV files for further analysis

### Connection Requirement

> **Note:** Only network-based connections via IP address are supported. USB connections are not supported.  
> Ensure the oscilloscope and host system are on the same network

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
   
* **Profiles**
  * Shows/hides the profile management panel  
  * Allows saving, loading, and deleting device configurations  
  * Disabled when offline

* **AI Toggle**
  * Shows/hides AI chat interface  
  * Disabled if AI is not configured

* **Help**
  * Opens this documentation

* **News**
  * Displays application updates

* **Settings**
  * Opens configuration panel (IP and AI settings, export options)

* **Save**
  * Saves current waveform and cursor data as PNG and optionally CSV data if enabled
  * Files are saved in the application working directory

---

### 2.2 Status Bar

* **Device IP**: Connected oscilloscope address  
* **Status Indicator**:
  * `ONLINE` (green)  
  * `OFFLINE` (red)

---

## 3. Configuration

Access via the **Settings** button.

### 3.1 Oscilloscope Settings

* **IP Address**  
  Example:  
  `192.168.1.100`

### 3.2 Preferences

* **Export CSV Data**  
  Enables waveform data export alongside images

### 3.3 AI Settings  

> **See section 4.2 for more information**

---

## 4. AI System

This feature allows you to interact with the oscilloscope using natural language, or to ask questions about the oscilloscope and its capabilities.  

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

Here's a list of LLMs that are proven to work with the application:  

**deepseek-v4-flash, gpt-4o, gpt-5.4-mini, gemini-3-flash, claude-haiku**  
*For exact model names, see your provider homepage.*

> Important: The AI ​​may make errors regarding information and device operation. Use is at your own risk.
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

* Toggle using the **AI button** in the top bar.

#### Capabilities

* **Technical Assistance**  
  Example: *“How do I configure trigger delay on an SDS1104X-E?”*

* **SCPI Command Execution**  
  Examples:  
  * “Set channel 1 vertical scale to 1V/div”  
  * “Get current timebase setting”
  * “Send command C1:TRA OFF“

> Note: For best results, English input is recommended.  
> Use **send command** syntax to send SCPI commands.
---

### 4.4 AI Troubleshooting

* **AI Disabled**
  * Check AI config settings

* **No AI Response**
  * Validate API credentials and quota  
  * Check logs  
  * Confirm internet connectivity  

---

## 5. Device Profiles

The **Profiles** feature allows you to save and restore the configuration of your oscilloscope (using the `.lss` file format).

### 5.1 Saving a Profile

1. Configure your oscilloscope as desired.  
2. Click the **Profiles** button in the top bar.  
3. Enter a descriptive name in the "Create New Profile" field.  
   * Names are limited to 30 characters  
   * Only alphanumeric characters, underscores (`_`), and hyphens (`-`) are allowed  
4. Click **Save**. The configuration is stored locally in the application directory

### 5.2 Loading and Managing Profiles

* **Load**: Apply settings to the connected oscilloscope  
* **Delete**: Permanently remove a saved profile 
* **Sorting**: Sort by **Name** or **Date** (ascending/descending)

> **Note:** Profile operations require the device to be **ONLINE**

---

## 6. Getting Started

### Basic Connection Setup

1. Connect the oscilloscope to the network.  
2. Obtain its IP address.  
3. Open SDS-Remote.  
4. Open **Settings**.  
5. Enter the IP address.  
6. Click **TEST CONNECTION**.  
7. Save configuration.  
8. Verify status is `ONLINE`.

### Application Directory

The application directory is the place where images,csv and profile files are stored.  
The directory is OS specific:

* **Linux:** *~/.config/sdsremote*  
* **Windows:** *%LocalAppData%\sdsremote*

---

## 7. Troubleshooting (Non-AI)

### Connection Issues

* **Offline Status**
  * Verify device power and network connection  
  * Ensure oscilloscope is not in standby  
  * Validate IP address  
  * Check firewall (VXI-11 uses port 111)  
  * Use connection test  

* **Waveform Acquisition Failure**
  * Ensure at least one channel is enabled  
  * Verify trigger configuration  
  * Confirm valid acquisition state  

---

### Display Issues

* Minimum resolution: **1100 × 600**  
* Update graphics drivers if needed  
* Large displays may affect UI scaling  

---

## 8. Technical Details

### Communication

* Protocol: VXI-11 over TCP/IP  
* Command Interface: SCPI  
* Network-only operation (no USB support)

### Data Formats

* **Screen Capture**: BMP (device) → PNG (application)  
* **Waveform Data**: Binary → voltage/time values  
* **Device Profiles**: SCPI XML → .lss files  
* **Exports**: PNG (images), CSV (waveforms)

### Performance

* Waveforms are downsampled for display efficiency  
* Screen captures are compressed  
* AI response times depend on knowledge search activities and provider latency (may vary)

---

## 9. Support and Feedback

* Review the troubleshooting section  
* Check logs at `/tmp/sds/logging/sds.log` (Linux) or `%TEMP%\sds\logging\sds.log` (Windows)  
* Submit issues or feature requests via the [sdsremote](https://github.com/klumw/sdsremote) GitHub repository Issues section  

---
## 10. License

* **This software is released under the terms and conditions of the [Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0.html)**
