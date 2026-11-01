---
name: usb-debugging
description: Debugging USB/USBTMC problems in SDS-Remote (Siglent SDS1000X-E over USB) — symptom-to-cause mapping, log evidence, known SDS1x04X-E firmware limits, transfer-size tuning for slow screen dumps, the diagnostic tool, and the implemented workarounds. Use when USB connections fail, waveform acquisition raises libusb errors, screen dumps hang or wedge the oscilloscope, or the Control Panel is extremely slow.
---

# USB debugging (SDS-Remote)

Use together with `sdsremote-dev`; its rules for asking about the test suite and
live tests apply. Never edit the pub cache — the USB stack lives in
`packages/usbtmc_dart_patched/`.

## 1. Ground rules

- **Ask before live tests.** A failed transfer can wedge the oscilloscope; only
  a physical replug or power cycle recovers it.
- In USB mode the app holds the USB interface for the lifetime of the process.
  Close the app before running external tools or scripts.
- A Flutter **hot restart does not release the libusb claim** (the old isolate's
  handle stays claimed). Use a full restart (`q` + `flutter run`) when testing
  USB changes.
- Do not retry a wedged device in a tight loop. The app's 5 s reconnect attempts
  produce one kernel probe each and cannot revive the firmware.

## 2. Where the evidence is

| Source | Command / path |
|---|---|
| Application log | `<system temp>/sds/logging/sds.log` (`/tmp/sds/logging/sds.log` on Linux) |
| Debug logging | `flutter run -d linux -- --loglevel=DEBUG` (measurements are logged at DEBUG only) |
| Kernel USB log | `journalctl -k --since "-5 minutes"` or `dmesg`; filter `usb\|usbtmc\|xhci` |
| Device presence | `lsusb`, `lsusb -t` (topology/hub) |
| Device attributes | `/sys/bus/usb/devices/<dev>/` (`idVendor`, `idProduct`, `serial`); interface `bInterfaceClass/SubClass/Protocol` must be `fe/03/01` |
| Kernel driver node | `/sys/class/usbmisc/usbtmc*`, `/dev/usbtmc*` (absent while libusb holds the interface) |

Siglent SDS1104X-E: VID/PID `f4ec:ee38`; SDS1202X-E: `f4ed:ee3a`.

## 3. Symptom → cause

| Symptom | Meaning |
|---|---|
| `Acquire waveform error: AcquisitionException: <cmd> – query failed: libusb bulk read error: -1 (IO_ERROR)` | Fatal USB transfer error during acquisition (often on the first query, e.g. `TDIV?`). libusb `-1` = `IO_ERROR`; the kernel usually logs `usb_control_msg returned -71` (EPROTO) at the same time. The instrument's USB stack stopped answering. |
| `Acquire display error: libusb bulk read error: -1 (IO_ERROR)` | Same failure on the SCDP screen-dump path (Control Panel), not the waveform path. |
| Control Panel takes ~80 s to open, but commands inside it are fast | Not a first-call overhead: the panel fetches a 768,067-byte SCDP block and the USBTMC read request size is too small (48-byte workaround). See §4.1. |
| `libusb bulk write error: -7 (TIMEOUT)` during a profile upload | A single large Bulk-OUT transfer was sent on Linux; the firmware accepts one 64-byte packet per transfer and locks its endpoint on larger ones. Use `profileWriteChunked` (Linux). See §4.2. |
| The instrument disappears from the bus for ~20–30 s right after a profile upload | Expected: the SDS1x04X-E resets its USB interface while applying the profile. `awaitProfileApplied` waits for re-enumeration; do not replug unless it does not return within ~2 minutes. |
| `libusb bulk write error: -1 (IO_ERROR)` | The device is already wedged; a write to the dead endpoint fails. |
| `libusb bulk read error: -7 (TIMEOUT)` | Not fatal: per-transfer timeout; the connection stays usable and `isFatalUsbError` is false. |
| Kernel: `usb_control_msg returned -71`, `usbtmc ...: can't read capabilities`, repeating every few seconds | The kernel usbtmc driver re-probed after libusb released the interface; the device answers control transfers with EPROTO. It is wedged. |
| `Failed to claim interface 0: error code -6 (BUSY)` | Another handle/process claims interface 0: a stale app instance, a hot-restart leftover, or the kernel driver. |
| Device listed by `lsusb` but every transfer fails | Presence on the bus does **not** mean usable. Expect a replug. |
| Spectrum fundamental is ~7× too high (e.g. 1 kHz reads as 7 kHz) | `WFSU SP` is the **sparsing** factor: the scope sends only every SP-th sample. Use `WaveformRawData.effectiveSampleRate` (`SARA / SP`), not `SARA`, for the frequency axis. Fixed in the spectrum path (M5). |
| Waveform measurement frequency is ~10× too low or `—`, while the same channel in the acquisition history shows a plausible value | The waveform time axis was stretched over the 14-division display window even though a sparsed USB record covered only `points * SP / SARA` seconds. Use the effective interval `SP / SARA` for `computeTimeAxis` and `measureRawChannel` (the history summary already did). Fixed for display and measurements. |
| The waveform chart shows far fewer cycles than the oscilloscope screen (e.g. 1–2 instead of 14) | A fixed `WFSU SP,7` together with the 100k-point USB transfer cap transfers only 700k of the 7 Mpts record, i.e. 1/10 of the display. Choose `SP = ceil(desiredPoints / transferPoints)` so the full record fits. `waveformSparsingFor` does this; the `WFSU?` read-back stays authoritative. |

Distinguish the failing feature from the log line: `Acquire waveform error` is
the acquisition; `Acquire display error` is SCDP (Control Panel).

## 4. Known SDS1x04X-E USBTMC firmware limits

- Read request size is firmware-dependent:
  - Older firmware (e.g. 8.2.6.1.37R9) only handled USBTMC reads of up to
    **48 bytes** reliably; larger requests could wedge the USB interface until
    a replug or power cycle (upstream scopehal issue #652).
  - Firmware **8.1.6.1.37R17** tolerates **8192-byte** reads. Measured on an
    SDS1104X-E: SCDP 768,067 B in ~0.86 s, 100k-point waveform ~63 ms per
    channel. Stress-tested with 3 full app sequences and 13 SCDP dumps (10 in
    a row plus 3 repeated dumps).
  - At 48 bytes **every** screen dump is slow — three consecutive dumps took
    84 s, 79 s and 79 s. There is no first-call/warm-up overhead; the commands
    inside the Control Panel are ordinary fast SCPI round trips. Transfer-size
    scaling and the tuning procedure are in §4.1.
- Failure reports as EPROTO (`-71`) on bulk and control transfers; the device
  stays enumerated but unresponsive.
- Current settings:
  - `UsbtmcContext.newDeviceByVidPid` sets `device.maxReadTransferSize = 8192`
    for Siglent VID `0xf4ec` on Linux (`siglentMaxReadTransferSize`).
  - `UsbtmcDevice.doRead` caps the request size, terminates on EOM, treats the
    `TransferSize` of a non-final message as that message's own size (not the
    reply total), and still honors IEEE 488.2 definite-length headers.
    Multi-message replies are read completely.
- `WaveformAcquisition` limits `WFSU NP` to **100,000 points** per channel in
  Linux USB mode to keep acquisitions quick (at 8192 bytes a deep-memory
  transfer would still take seconds per channel).
- `WFSU SP` is the **sparsing** factor (`SP,7` = every 7th acquisition sample).
  The transferred bytes therefore have the effective rate `SARA / SP`; the
  spectrum must use `WaveformRawData.effectiveSampleRate`. The acquisition
  reads the actual value back with `WFSU?`, so a firmware that clamps `SP`
  cannot shift the frequency axis.
- Screen dumps are fetched normally again (automatic refresh, auto capture and
  timelapse work); at 8192 bytes they take < 1 s.
- If an older-firmware instrument shows USB errors, update the scope firmware
  (or temporarily lower the cap with `--cap=48` in the diagnostic tool).

### 4.1 Slow Control Panel / SCDP: tuning the read size

Symptom: opening the Control Panel takes ~80 s, while commands inside the
panel are fast. The open fetches a 768,067-byte SCDP block; its duration is
set by the USBTMC read request size, and the per-message latency is ~5–9 ms
regardless of payload. Throughput therefore scales inversely with the request
count:

| USBTMC read request | SCDP duration (768,067 B) |
|---|---|
| 48 B | 78–84 s |
| 512 B | 7.6 s |
| 2032 B | 2.2 s |
| 8192 B | 0.86 s |

Tuning procedure:

1. Close the app (it holds the USB interface).
2. Run `dart run tool/usb_diag.dart screen --cap=8192 --repeat=10`. Every dump
   should finish in < 1 s and every stage's `*IDN?` must succeed.
3. Also run the full sequence: `dart run tool/usb_diag.dart app --cap=8192`.
4. If EPROTO/`IO_ERROR` appears, replug the scope and step back to a smaller
   cap (2032, 512, or 48 for older firmware).
5. Set `UsbtmcContext.siglentMaxReadTransferSize` to the largest value that
   survived the stress test, and update the measured values in this skill.

### 4.2 Profile upload (`*LDS` / `*LRN`) over USB — Linux workarounds

The SDS1x04X-E firmware does not correctly reassemble multi-transfer
DEV_DEP_MSG_OUT messages for the XML profile block and accepts only **one
64-byte packet per Bulk-OUT transfer** on Linux; a single larger transfer
locks the Bulk-OUT endpoint until the instrument is reset.

- **Linux:** `UsbtmcDevice.profileWriteChunked` sends one DEV_DEP_MSG_OUT
  header (EOM=1, TransferSize = total payload) followed by raw continuation
  transfers of one 64-byte packet each. The first packet carries the 12-byte
  USBTMC header plus up to 52 payload bytes (`_firstSegmentPayloadSize`);
  later transfers carry up to 64 bytes, and when exactly 64 bytes remain the
  code sends 63 so the USB transfer ends with a short packet (USB 2.0
  §5.8.3). There is a 1 ms delay between segments so the firmware can drain
  its receive FIFO.
- **Windows:** `UsbtmcDevice.profileWrite` sends the whole payload in one bulk
  transfer; WinUSB splits it into 64-byte URBs itself.
- **Pre-transfer cleanup (both paths):** `clearHalt()` on both endpoints, then
  USBTMC INITIATE_ABORT_BULK_OUT (control request `0xA1`, bRequest `1`,
  2-byte payload, 500 ms timeout), then a 10 ms pause to flush in-flight
  kernel-driver URBs. This clears a partial transfer left by a previous failed
  upload.
- **Never cancel an upload mid-transfer** and never send the XML in one large
  transfer on Linux: both can leave the Bulk-OUT endpoint locked until a
  device reset.
- **Platform selection:** `Vxi11Instrument.writeProfileData` chooses
  `profileWriteChunked` on Linux and `profileWrite` elsewhere. Callers are
  Load Profile in `home_page.dart` and `*LDS`/`*LRN` in `macro_evaluator.dart`.
- **After the upload:** the instrument resets its USB interface while applying
  the profile and leaves the bus for roughly 20 s (re-enumeration observed at
  ~30 s). `Vxi11Instrument.awaitProfileApplied` first tries `*OPC?` (15 s
  write / 45 s read timeout). If that fails it invalidates the shared USB
  connection and waits up to 120 s for the device to reappear; the ping timer
  reconnects afterwards. Over VXI-11 the same method retries `*OPC?` on
  VXI-11 error 15 (I/O timeout) up to 6 times, 2 s apart.
- `writeBinary` (ordinary SCPI commands) also chunks at 4096 bytes with a
  20 ms delay and one bTag; that path is for command payloads, not profiles.

## 5. Diagnostic tool

`tool/usb_diag.dart` — run with the app closed:

```bash
dart run tool/usb_diag.dart waveform   # IDN, TRACE?, WFSU NP=100000, all active channels, IDN
dart run tool/usb_diag.dart screen     # IDN, SCDP, IDN
dart run tool/usb_diag.dart all        # waveform then screen
dart run tool/usb_diag.dart app        # exact app sequence: TRMD AUTO/STOP/restore,
                                       # TDIV?, TRDL?, SARA?, WFSU, SANU?, VDIV/OFST,
                                       # 4 channels, 5 s gap, SCDP with the app's 30 s timeout
dart run tool/usb_diag.dart screen --cap=8192 --repeat=10   # transfer-size / stress test
```

`--cap=N` overrides the app's 8192-byte read size; `--repeat=N` repeats SCDP.

It finds the device by VID/PID from sysfs (no address needed), prints
`maxReadTransferSize`, byte counts, durations and response heads, and re-runs
`*IDN?` after every stage to detect a wedge.

Measured reference values (SDS1104X-E, FW 8.1.6.1.37R17, 8192-byte cap):

| Operation | Size | Duration |
|---|---|---|
| `*IDN?` | 61 B | < 0.1 s |
| `C1..C4:WF? DAT2` (NP=100000) | 50,024 B each | ~63 ms each (48-byte cap: ~1.1 s) |
| `SCDP` | 768,067 B | ~0.86 s (48-byte cap: 85–89 s) |

Values far outside these, or `IO_ERROR`, mean the device is wedged.

## 6. Recovering a wedged device

1. Close the app / release the USB handle.
2. Physically unplug and replug the USB cable, or power-cycle the oscilloscope.
   Re-enumeration takes about 30 s.
3. The app reconnects automatically via the ping timer once the device is back;
   no app restart is required.
4. A `libusb_reset_device` port reset exists in the driver but is not wired
   into recovery; do not rely on it.

## 7. Code map

| File | Responsibility |
|---|---|
| `packages/usbtmc_dart_patched/lib/src/usbtmc_device.dart` | USBTMC framing, `doRead` (EOM, IEEE header, transfer-size cap), `writeBinary` chunking, profile upload (`profileWrite`/`profileWriteChunked`) |
| `packages/usbtmc_dart_patched/lib/src/usbtmc_context.dart` | Linux + VID `0xf4ec` → 8192-byte cap |
| `packages/usbtmc_dart_patched/lib/src/driver/libusb_driver.dart` | libusb FFI, error codes (`UsbTransferException`), kernel-driver auto-detach |
| `lib/src/instrument/dart_vxi11.dart` | Shared USB connection, fatal-error invalidation, query/data-block/screen-dump paths, `writeProfileData`/`awaitProfileApplied` |
| `lib/src/waveform/waveform_acquisition.dart` | `WFSU` setup (`NP` cap, `SP` sparsing capture) |
| `lib/src/waveform/waveform_models.dart` | `WaveformRawData.sparsing` / `effectiveSampleRate` (spectrum frequency axis) |
| `lib/src/widgets/home_page.dart` | Screen-dump path; Control Panel is disabled while a waveform acquisition runs |
| `tool/usb_diag.dart` | Standalone USB diagnostic |

## 8. Hardware notes

- Siglent recommends a direct connection (**no hub**) and a short cable with RF
  chokes. An SDS1104X-E behind a shared hub has produced EPROTO errors in
  practice; a CH340 signal generator on the same hub re-enumerated during tests.
- `dmesg` normally shows `bulk endpoint 0x81/0x1 has invalid maxpacket 64` for
  this scope: the firmware reports 64-byte packets for high-speed bulk
  endpoints. Profile uploads are therefore chunked to 64 bytes on Linux.
- Windows uses WinUSB (Zadig). The 8192-byte chunk size is applied on Linux
  only.

## 9. References

- scopehal issue #652 — Siglent SDS1104X-E USBTMC failures:
  https://github.com/ngscopeclient/scopehal/issues/652
- scopehal commit `9517f33` — configurable USBTMC transfer size (`:48`):
  https://github.com/ngscopeclient/scopehal/commit/9517f33
- scopehal-docs PR #83 — "As Workaround for Siglent SDS1x04X-E set size to 48":
  https://github.com/ngscopeclient/scopehal-docs/commit/a98ada3a3be8a09e957a2d1f467d1ddbcf805dfb
