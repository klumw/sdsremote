# SDS-Remote - New version 0.4.0 available
The new version 0.4.0 is out, with a lot of new feature around waveform analysis and enhanced AI support  

**SDS-Remote** is a remote control interface and help center for Siglent SDS 1000X-E series oscilloscopes. It provides a modern graphical user interface (GUI) for instrument control, waveform acquisition, screen capture, data logging, and interaction through an integrated AI-powered chat interface. SDS-Remote runs on **Linux** and **Windows**.  For a quick overview, watch the [introductory video](https://youtu.be/sbQIYpyg1p4).

> **Note:** This application is not affiliated with Siglent or any other commercial entity.

---

## 1. What is SDS-Remote and What It Can Do?

SDS-Remote enables remote control and AI-enhanced operation of Siglent SDS1202X-E, SDS1104X-E, SDS1204X-E, and SDS1102X-E oscilloscopes from **Linux** and **Windows**.

### Key Features

- **Remote Oscilloscope Control**: Control your oscilloscope remotely over a network or USB.
- **Waveform Acquisition & Analysis**: Capture and display waveform data from enabled channels. Analyse .
- **Device Parameter Monitoring**: View real-time parameters such as timebase, sample rate, and voltage settings. Cursor-based measurements and AI assisted analysis are supported.
- **Data Logging**: Log key data points over a period of time. Generate PDF measurement reports containing charts and key metrics, or export all recorded measurement points as CSV files.
- **Signal Generator & Bode Plot**: if you own a **JDS6600** or **FY6900** you can do *Bode Plots** with a lot of differen parameters. Set alarms and create rich reports.
- **Macro Recorder**: Record, edit and play back SCPI command sequences. Supports variables, conditionals, loops, and both network and USB connections for automated test procedures.

### Waveform Data Acquisition

Acquire and visualize waveform data. Perform advanced measurements using X/Y cursors and zoom controls for detailed waveform analysis. Use the AI Assistant to do complex Time-Domain or frequency analysis. Export waveform data as image files or CSV datasets.
#### Waveform Analyis
![Waveform Analysis](docs/sdsremote_wf.png)
#### Spectrum Analysis
![Spectrum Analysis](docs/sdsremote_sp.png)

### Remote Control Panel

Acquire and display oscilloscope screenshots in real time. Control your oscilloscope remotely using a virtual front panel.

![Remote Control Panel](docs/sdsremote_cp.png)

### AI Chat Interface

Send commands and query oscilloscope functionality using natural-language prompts or  
talk directly to your app and devices with the build in microphone functionality.

![AI Chat Interface](docs/sdsremote_ai.png)

### Device Profile Management

Save and restore oscilloscope configurations using `.lss` profile files.

![Device Profile Management](docs/sdsremote_dp.png)

### Data Logging

Log key measurement data over configurable durations ranging from 1 minute to 24 hours. Measure frequency drift and peak-to-peak voltage variations and generate reports with a detailed diagram, start/end and min/max values. All data points can also be saved in a separate CSV file.

![Data Logger](docs/sdsremote_dl.png)

#### Signal Generator Support
SDS-Remote supports the widespread Signal Generators FY6900 and JDS6600.
Yuo can either control your Signal Generator remotely via a special control panel
or by the AI assistants build into many SDS-Remote workspaces.

### Macro Recorder

Record, edit and play back SCPI command sequences to automate repetitive measurement and configuration tasks. Supports variables, conditionals (`if`/`else`), loops (`while`), assertions, and both network (`connect("IP")`) and USB (`connect(usb)`) connections.

![Macro Recorder](docs/sdsremote_mr.png)
---

## 2. Installation

### 2.1 Linux Debian `.deb` Package

To install the precompiled Debian `.deb` package on Debian-based Linux distributions (for example, Ubuntu 24.04 or newer), download the [latest package](https://github.com/klumw/sdsremote/releases) from the Releases page and run the following command in your terminal:

```bash
sudo apt install ./sdsremote_[version]_amd64.deb
```

Alternatively, double-click the `.deb` file and follow the installation instructions.

Once installed, you can launch the application from your desktop environment's application menu.

---

### 2.2 Windows MSI Installer

For Windows installation, use the MSI installer: [sdsremote_[version].exe](https://github.com/klumw/sdsremote/releases)

---

## 3. Building the Application Yourself

If you prefer to build SDS-Remote from source, you will need to install the Flutter SDK and its dependencies.

### 3.1 Installing Flutter/Dart

Choose the instructions for your target platform.

#### Linux

1. **Install Dependencies**: Ensure the required development tools are installed:

   ```bash
   sudo apt install curl git unzip cmake ninja-build pkg-config libgtk-3-dev
   ```

2. **Download Flutter**: Download the Flutter SDK from the [official Flutter Linux installation guide](https://docs.flutter.dev/get-started/install/linux).

3. **Extract and Add to PATH**: Extract the archive and add the `flutter/bin` directory to your system `PATH`.

4. **Verify Installation**: Run `flutter doctor` in your terminal to verify that all dependencies are installed and the environment is configured correctly.

#### Windows

1. **Install Dependencies**: Ensure the following components are installed:

   - [Git for Windows](https://git-scm.com/download/win)
   - [Visual Studio 2022](https://visualstudio.microsoft.com/downloads/) with the **Desktop development with C++** workload

2. **Download Flutter**: Download the Flutter SDK from the [official Flutter Windows installation guide](https://docs.flutter.dev/get-started/install/windows).

3. **Extract and Add to PATH**: Extract the archive and add the `flutter\bin` directory to your system `PATH`.

4. **Verify Installation**: Run `flutter doctor` in a command prompt to verify that all dependencies are installed and the environment is configured correctly.

### 3.2 Building the App from Source

1. **Clone the Repository** (if not already cloned):

   ```bash
   git clone https://github.com/klumw/sdsremote.git
   cd sdsremote
   ```

2. **Install Packages**:

   ```bash
   flutter pub get
   ```

3. **Build the Linux Application**:

   ```bash
   flutter build linux
   ```

   The compiled executable will be located in the `build/linux/x64/release/bundle/` directory.

4. **Build the Windows Application**:

   ```bash
   flutter build windows
   ```

   The compiled executable will be located in the `build/windows/x64/runner/Release/` directory.

   To run the executable, ensure that the associated DLLs and the data directory are located in the same folder.

### 3.3 USB Support (Experimental) ⚠️

In General the device network connection is more reliable than the USB connector.
The amounts of data that can be transferred via USB are limited.

#### 3.3.1 USB Support on Windows

For USB support on Windows, place the **x64** `libusb-1.0.dll` from the [libusb project](https://github.com/libusb/libusb) in the same directory as the SDS-Remote executable. (The application also accepts the older file name `libusb.dll` as a fallback.)

Multiple DLL versions are available in the download package. Select the DLL located under `/VS2025/MS64-hotplug`.

Next, verify or install the WinUSB driver for your device:

1. Download the [Zadig](https://zadig.akeo.ie) driver tool.
2. Connect your device.
3. In Zadig, enable **Options → List All Devices**.
4. Select your device and install the WinUSB driver if it is not already installed.

> Note: If you are using a VISA-based application in parallel, it may no longer detect the device after switching to the WinUSB driver.

If the oscilloscope is still not detected:

- Set **Settings → Connection Mode** to **USB (USBTMC)**.
- In Device Manager, the Siglent device must use the **WinUSB** driver (not `usbtmc.sys`). Re-run Zadig with **Replace Driver** if needed, and select the device's USBTMC interface.
- The WinUSB binding is **per device (VID/PID)**: installing it for one Siglent model does not cover another. Run Zadig separately for each model — SDS1104X-E `f4ec:ee38`, SDS1202X-E `f4ed:ee3a` — and pick the matching device when both are connected.
- Use the oscilloscope's USB **Device** port, not the USB host port for flash drives.
- Check `%TEMP%\sds\logging\sds.log` for `USBTMC Windows` messages.

#### 3.3.2 USB Support on Linux

USB access is implemented with libusb, which opens the raw USB device node
(`/dev/bus/usb/<bus>/<device>`). That node is root-only by default, so a udev
rule is required; otherwise the device is detected but opening it fails with
`Failed to open USB device ... Please check physical connection and USB
permissions`.

Install the bundled rule and re-trigger udev:

```bash
sudo cp linux/udev/99-siglent-usbtmc.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger --action=change
# unplug and replug the oscilloscope
```

Verify that the device is present and writable for your user/group:

```bash
lsusb | grep -i siglent        # e.g. f4ec:ee38 for the SDS1104X-E
ls -l /dev/bus/usb/*/*         # your user or group plugdev must have rw-
groups                         # must list plugdev
```

The rule covers the SDS1104X-E (`f4ec:ee38`), the SDS1202X-E (`f4ed:ee3a`) and
`/dev/usbtmc*` via the `usbmisc` subsystem. For other models, add a rule with
their `idVendor`/`idProduct` from `lsusb`.

Some Siglent USB firmware versions are not fully USB compliant. Perform the following compatibility check:

1. Connect your device to a USB port.
2. Run the following command:

   ```bash
   sudo dmesg
   ```

3. If you see messages similar to the following:

   ```bash
   config 1 interface 0 altsetting 0 bulk endpoint 0x81 has invalid maxpacket 64
   usb 1-4: config 1 interface 0 altsetting 0 bulk endpoint 0x1 has invalid maxpacket 64
   ```

   then the device's USB firmware is not fully compliant with the USB standard, and some SDS-Remote functionality, such as profile upload, may not work correctly under Linux.

### 3.4 Running the Application

You can run the built executable directly or start the application in debug/development mode.

#### Linux

```bash
flutter run -d linux
```

The Linux window title bar and task bar show the bundled SDS-Remote icon
(`assets/icons/sds-remote.png`). The GTK header bar (top bar) uses a small 24x24
icon scaled from `assets/icons/sds-remote-icon_128_128.png`. Both icons are
loaded and applied by the GTK runner in
[`linux/runner/my_application.cc`](linux/runner/my_application.cc:65).

#### Windows

```bash
flutter run -d windows
```

### 3.5 Running the Test Suite

Run the unit and widget tests from the project root:

```bash
flutter test
```

The AI search accuracy evaluation in `test/ai_search_accuracy_test.dart` performs
real API calls — one search-agent call plus one grader call per test case. The
LLM under test is configured in the test itself (currently
`edenai:mistral-code-agent-latest`, which also drives its knowledgebase search
sub-agent), while the grader LLM is currently `deepseek:deepseek-v4-flash`.
Both provider keys must therefore be exported. Run the test from the project
root so that the relative paths to `test/ai_test_data.json` and
`docs/knowledgebase.md` resolve:

```bash
export EDENAI_API_KEY="..."
export DEEPSEEK_API_KEY="sk-..."
flutter test -r expanded test/ai_search_accuracy_test.dart
```

The `-r expanded` reporter shows the per-case score and reasoning. A full run
evaluates 20 cases and can take several minutes; the averaged results are printed
and written to `test/ai_search_accuracy_results.json`.

---

## 4. AI Configuration

The AI chat feature supports the following providers:

| Provider |
| --- |
| DeepSeek |
| OpenAI |
| Anthropic |
| Google |
| Mistral |
| Cohere |
| EdenAI |
| OpenRouter |
| xAI |

The following LLMs are known to work with the application:

### Known working models

- deepseek-flash
- gpt-6-luna
- gemini-flash
- claude-sonnet
- qwen-3.x-max
- mistral-code

*For exact model names, refer to your provider's documentation.*

> The AI subsystem may generate inaccurate information or incorrect operating instructions. Use this functionality at your own risk.

---

## 5. License and Feedback

### License

This software is released under the terms and conditions of the [Apache 2.0 License](https://www.apache.org/licenses/LICENSE-2.0.html).

### Feedback and Support

- Review the in-app help manual for troubleshooting guidance.
- Before you report an issue check the application logs at:
  - Linux: `/tmp/sds/logging/sds.log`
  - Windows: `%TEMP%\sds\logging\sds.log`
- Submit issues or feature requests through the [SDS-Remote GitHub Issues page](https://github.com/klumw/sdsremote/issues).
