import 'dart:io';
import 'dart:typed_data';

import '../core/logger.dart';
import '../instrument/dart_vxi11.dart';
import '../instrument/scpi_parser.dart';
import 'waveform_models.dart';

/// Number of acquisition samples per transferred point required to fit the
/// complete acquisition record into [transferPoints].
///
/// `WFSU SP` sparses the transfer: with `SP,7` the scope sends every seventh
/// acquisition sample. If [transferPoints] is smaller than the record depth
/// (for example 7 Mpts on USB, capped at 100k points), the first `NP` samples
/// cover only a fraction of the display. The sparsing factor makes the whole
/// record fit instead, so the waveform view shows the same cycles as the
/// oscilloscope screen.
int waveformSparsingFor(int desiredPoints, int transferPoints) {
  if (transferPoints <= 0 || desiredPoints <= transferPoints) return 1;
  return (desiredPoints / transferPoints).ceil();
}

/// Performs a complete waveform acquisition from a Siglent SDS oscilloscope
/// over VXI-11.
class WaveformAcquisition {
  final String ipAddress;

  WaveformAcquisition(this.ipAddress);

  /// Connects to the instrument, queries all required SCPI parameters and
  /// waveform data for the selected channels, then returns a [WaveformRawData].
  ///
  /// Before acquiring waveform data, the trigger mode is queried via `TRMD?`.
  /// A running acquisition is completed as a single acquisition first, then
  /// the display is frozen so the transferred frame is stable and complete.
  /// After acquisition, the original trigger mode is restored.
  ///
  /// Throws [AcquisitionException] on any VXI-11 or parsing error.
  Future<WaveformRawData> acquire({
    bool ch1 = true,
    bool ch2 = true,
    bool ch3 = false,
    bool ch4 = false,
    void Function()? onConnected,
    Vxi11Instrument? instr,
    int? maxTransferPoints,
  }) async {
    final bool ownInstr = instr == null;
    final activeInstr =
        instr ?? Vxi11Instrument(ipAddress, sourceLabel: 'waveformAcq');
    String? originalTriggerMode;
    try {
      if (ownInstr) {
        try {
          await activeInstr.open(timeoutSeconds: 10.0);
          onConnected?.call();
        } catch (e) {
          throw AcquisitionException('open', e.toString());
        }
      }

      // --- Query trigger mode ---
      // The instrument may echo the command, e.g. "TRMD AUTO" or "TRMD STOP".
      // We extract only the mode value (the part after the last space).
      try {
        final rawResponse = (await activeInstr.queryString('TRMD?')).trim();
        // Strip command echo: take everything after the last space
        final lastSpace = rawResponse.lastIndexOf(' ');
        originalTriggerMode = lastSpace >= 0
            ? rawResponse.substring(lastSpace + 1).trim()
            : rawResponse;
      } catch (e) {
        AppLogger().error('Failed to query trigger mode: $e');
      }

      // --- Global parameters (Requirement 1.2) ---
      final timebase = await _queryValue(activeInstr, 'TDIV?');

      // Freezing a running scope in the middle of a sweep leaves no complete
      // waveform in acquisition memory, so `WF? DAT2` returns an empty block.
      // This happens after a scope setting change restarts the acquisition
      // (for example a new timebase for an FFT): the automatic refresh stops
      // the trigger before the first new sweep has finished. Arm one single
      // acquisition and wait until it has completed instead.
      final bool freshFrameRequired = await _needsFreshFrame(
        activeInstr,
        originalTriggerMode,
      );
      final bool frameCompleted = freshFrameRequired
          ? await _armAndWaitForComplete(activeInstr, timebase: timebase)
          : true;
      // The single-shot ARM above stops the scope when the frame is complete.
      // Remember that we changed the run state so the restore below can resume
      // continuous acquisition even when the original mode is unknown.
      var triggerStateChanged = freshFrameRequired;

      // Freeze the display so the transferred frame stays stable. When the
      // single acquisition above already stopped the scope this is a no-op.
      if (originalTriggerMode != null &&
          originalTriggerMode.isNotEmpty &&
          originalTriggerMode != 'STOP') {
        try {
          await activeInstr.writeString('TRMD STOP');
          triggerStateChanged = true;
        } catch (e) {
          AppLogger().error('Failed to stop trigger: $e');
        }
      }

      final trdl = await _queryValue(activeInstr, 'TRDL?');
      var sampleRate = await _queryValue(activeInstr, 'SARA?');

      // Configure waveform transfer setup so the complete display span
      // (timebase * 14 divisions) is transferred, not just its beginning.
      const int horizontalDivisions = 14;
      // VXI-11 could transfer the full deep memory, but the waveform view
      // only needs enough samples for the raster, measurements and spectrum.
      // A 7M-point record took 4.2 s at 500 us/div; 250k points take about
      // 1 s and still give ~6k samples per period for a 3 kHz signal.
      const int defaultMaxTransferPoints = 250000;
      // On Linux the SDS1x04X-E USBTMC firmware only tolerates short read
      // requests (see UsbtmcContext.siglentMaxReadTransferSize). Deep-memory
      // transfers would take minutes in 48-byte chunks, so the number of
      // transferred samples is limited in USB mode.
      const int usbMaxTransferPoints = 100000;
      final int transportCap = Vxi11Instrument.isUsbMode && Platform.isLinux
          ? usbMaxTransferPoints
          : defaultMaxTransferPoints;
      final int effectiveMaxTransferPoints = (maxTransferPoints ?? transportCap)
          .clamp(1201, transportCap);

      // --- Acquisition record length and trigger position ---
      // SANU? returns the record length ("SANU 1.40E+04pts"); some firmware
      // appends the trigger position after a comma. With FP=0 in WFSU we read
      // from index 0, so the trigger position (when present) lets us compute
      // the time offset T(n) = (n - triggerPosition) / sampleRate + trdl.
      // The point count is the actual record length of the completed frame.
      // It is preferred over TDIV * 14 * SARA because SARA can lag behind for
      // a moment after a timebase change and would produce a wrong sparsing
      // factor.
      int recordPoints = 0;
      int triggerPosition = 0;
      try {
        final sanuRaw = (await activeInstr.queryString('SANU? C1')).trim();
        final sanu = ScpiParser.parseSanu(sanuRaw);
        recordPoints = sanu.$1;
        triggerPosition = sanu.$2;
      } catch (_) {
        // Fall back to display-centric formula if SANU? fails
      }

      final int displayPoints = (timebase * horizontalDivisions * sampleRate)
          .ceil();
      final int desiredPoints = recordPoints > 0 ? recordPoints : displayPoints;
      final int transferPoints = desiredPoints.clamp(
        1201,
        effectiveMaxTransferPoints,
      );
      // WFSU SP is the sparsing factor: the scope sends every SP-th sample.
      // Pick it so the whole record fits into the transfer cap; a fixed SP
      // would truncate the record and the app would show fewer cycles than
      // the oscilloscope. The spectrum and measurements use the resulting
      // effective sample rate (SARA / SP).
      final int waveformSparsing = waveformSparsingFor(
        desiredPoints,
        transferPoints,
      );
      try {
        await activeInstr.writeString(
          'WFSU SP,$waveformSparsing,NP,$transferPoints,FP,0',
        );
      } catch (e) {
        AppLogger().error('WFSU setup failed: $e');
      }
      final int sparsing = await _querySparsing(
        activeInstr,
        fallback: waveformSparsing,
      );

      // --- Channel status check ---
      // Check if channels are active on the oscilloscope.
      // Fetch only if both: selected in UI (checkbox) AND active on the instrument.
      final isCh1Active = ch1 && await _queryStatus(activeInstr, 'C1:TRACE?');
      final isCh2Active = ch2 && await _queryStatus(activeInstr, 'C2:TRACE?');
      final isCh3Active = ch3 && await _queryStatus(activeInstr, 'C3:TRACE?');
      final isCh4Active = ch4 && await _queryStatus(activeInstr, 'C4:TRACE?');

      // --- Per-channel parameters ---
      final vdivCh1 = isCh1Active
          ? await _queryValue(activeInstr, 'C1:VDIV?')
          : null;
      final voffsetCh1 = isCh1Active
          ? await _queryValue(activeInstr, 'C1:OFST?')
          : null;
      final vdivCh2 = isCh2Active
          ? await _queryValue(activeInstr, 'C2:VDIV?')
          : null;
      final voffsetCh2 = isCh2Active
          ? await _queryValue(activeInstr, 'C2:OFST?')
          : null;
      final vdivCh3 = isCh3Active
          ? await _queryValue(activeInstr, 'C3:VDIV?')
          : null;
      final voffsetCh3 = isCh3Active
          ? await _queryValue(activeInstr, 'C3:OFST?')
          : null;
      final vdivCh4 = isCh4Active
          ? await _queryValue(activeInstr, 'C4:VDIV?')
          : null;
      final voffsetCh4 = isCh4Active
          ? await _queryValue(activeInstr, 'C4:OFST?')
          : null;

      // --- Waveform data ---
      var ch1Raw = isCh1Active
          ? await _queryDataBlock(activeInstr, 'C1:WF? DAT2')
          : null;
      var ch2Raw = isCh2Active
          ? await _queryDataBlock(activeInstr, 'C2:WF? DAT2')
          : null;
      var ch3Raw = isCh3Active
          ? await _queryDataBlock(activeInstr, 'C3:WF? DAT2')
          : null;
      var ch4Raw = isCh4Active
          ? await _queryDataBlock(activeInstr, 'C4:WF? DAT2')
          : null;

      bool anyChannelActive() =>
          isCh1Active || isCh2Active || isCh3Active || isCh4Active;
      bool allChannelsEmpty() =>
          (!isCh1Active || (ch1Raw?.isEmpty ?? true)) &&
          (!isCh2Active || (ch2Raw?.isEmpty ?? true)) &&
          (!isCh3Active || (ch3Raw?.isEmpty ?? true)) &&
          (!isCh4Active || (ch4Raw?.isEmpty ?? true));

      // An empty block means the scope has no complete frame in memory, for
      // example when the trigger was frozen during a sweep that a setting
      // change had just restarted. Re-arm once and retry before reporting a
      // failed acquisition.
      if (anyChannelActive() &&
          allChannelsEmpty() &&
          freshFrameRequired &&
          frameCompleted) {
        AppLogger().warning(
          'Waveform transfer returned an empty block at TDIV=$timebase; '
          're-arming the acquisition and retrying once.',
        );
        await _armAndWaitForComplete(activeInstr, timebase: timebase);
        // The re-armed frame may have a different sample rate than the empty
        // frame, for example when the first attempt ran right after a
        // timebase change and SARA still reported the previous setting.
        try {
          sampleRate = await _queryValue(activeInstr, 'SARA?');
        } catch (_) {
          // Keep the previous sample rate.
        }
        try {
          final sanuRaw = (await activeInstr.queryString('SANU? C1')).trim();
          triggerPosition = ScpiParser.parseSanu(sanuRaw).$2;
        } catch (_) {
          // Keep the previous trigger position.
        }
        ch1Raw = isCh1Active
            ? await _queryDataBlock(activeInstr, 'C1:WF? DAT2')
            : null;
        ch2Raw = isCh2Active
            ? await _queryDataBlock(activeInstr, 'C2:WF? DAT2')
            : null;
        ch3Raw = isCh3Active
            ? await _queryDataBlock(activeInstr, 'C3:WF? DAT2')
            : null;
        ch4Raw = isCh4Active
            ? await _queryDataBlock(activeInstr, 'C4:WF? DAT2')
            : null;
      }

      AppLogger().info(
        'Waveform transfer: TDIV=$timebase, SARA=$sampleRate, '
        'SP=$sparsing, NP=$transferPoints, desired=$desiredPoints, '
        'record=$recordPoints, points=[${ch1Raw?.length}, ${ch2Raw?.length}, '
        '${ch3Raw?.length}, ${ch4Raw?.length}]',
      );

      if (anyChannelActive() && allChannelsEmpty()) {
        // No signal or no trigger event: this is a valid empty acquisition,
        // not an error. The waveform view opens and shows placeholder values.
        AppLogger().warning(
          'No waveform data on the active channels at TDIV=$timebase; '
          'opening an empty acquisition.',
        );
      }

      // --- Restore original trigger mode ---
      // Do this before the finally block so the connection is still fully open.
      // TRMD is a set command (not a query), so we do NOT read a response after it.
      //
      // When the original mode could not be read - for example while Auto Setup
      // is still running on another VXI-11 link - an acquisition that armed a
      // single shot or froze the display would otherwise leave the scope
      // stopped. Resume continuous acquisition in that case; a frozen frame
      // ('STOP', 'SINGLE') was detected above and is left untouched.
      String? restoreTriggerMode;
      if (originalTriggerMode != null && originalTriggerMode.isNotEmpty) {
        restoreTriggerMode = originalTriggerMode;
      } else if (triggerStateChanged) {
        restoreTriggerMode = 'AUTO';
        AppLogger().warning(
          'Trigger mode could not be read; resuming continuous acquisition '
          'with AUTO after the acquisition stopped the scope.',
        );
      }
      if (restoreTriggerMode != null && restoreTriggerMode != 'STOP') {
        try {
          await activeInstr.writeString('TRMD $restoreTriggerMode');
        } catch (e) {
          AppLogger().error('Failed to restore trigger mode: $e');
        }
      }

      return WaveformRawData(
        ch1Raw: ch1Raw,
        ch2Raw: ch2Raw,
        ch3Raw: ch3Raw,
        ch4Raw: ch4Raw,
        vdivCh1: vdivCh1,
        voffsetCh1: voffsetCh1,
        vdivCh2: vdivCh2,
        voffsetCh2: voffsetCh2,
        vdivCh3: vdivCh3,
        voffsetCh3: voffsetCh3,
        vdivCh4: vdivCh4,
        voffsetCh4: voffsetCh4,
        timebase: timebase,
        trdl: trdl,
        sampleRate: sampleRate,
        triggerPosition: triggerPosition,
        sparsing: sparsing,
      );
    } finally {
      if (ownInstr) {
        await activeInstr.close();
      }
    }
  }

  /// Reads the acquisition status via `SAST?`.
  ///
  /// Returns the lowercase status value without the command echo, or `null`
  /// when the instrument does not answer. The SDS1000X-E reports one of
  /// `Ready`, `Auto`, `Stop`, `Arm`, `Trig'd` and `FStop`.
  Future<String?> _queryAcquisitionStatus(Vxi11Instrument instr) async {
    try {
      final raw = (await instr.queryString('SAST?')).trim();
      if (raw.isEmpty) return null;
      final lastSpace = raw.lastIndexOf(' ');
      final value = lastSpace >= 0 ? raw.substring(lastSpace + 1) : raw;
      final status = value.trim().toLowerCase();
      if (status.isEmpty ||
          status.startsWith('-') ||
          status.contains('error') ||
          status.contains('undefined')) {
        return null;
      }
      return status;
    } catch (_) {
      return null;
    }
  }

  /// Whether the scope must complete a fresh acquisition before it is frozen.
  ///
  /// A stopped scope keeps the frame the user froze; a running or armed
  /// acquisition must finish a sweep first, otherwise `TRMD STOP` can abort an
  /// incomplete frame and `WF? DAT2` returns an empty block. Without a status
  /// answer, only the continuous trigger modes are treated as running so a
  /// manually stopped frame is never overwritten.
  Future<bool> _needsFreshFrame(
    Vxi11Instrument instr,
    String? triggerMode,
  ) async {
    final status = await _queryAcquisitionStatus(instr);
    if (status != null) return !status.contains('stop');
    final mode = triggerMode?.toUpperCase();
    return mode == 'AUTO' || mode == 'NORM';
  }

  /// Arms one single acquisition and waits until the scope has stopped.
  ///
  /// The wait is bounded by one screen sweep ([timebase] times 14 divisions)
  /// plus processing time. Returns whether the scope reported a completed
  /// acquisition; when the trigger never fires (wrong level, missing signal),
  /// the wait times out and the caller freezes the last frame.
  Future<bool> _armAndWaitForComplete(
    Vxi11Instrument instr, {
    required double timebase,
  }) async {
    try {
      await instr.writeString('ARM');
    } catch (e) {
      AppLogger().warning('Failed to arm a single acquisition: $e');
      return false;
    }
    final double sweepSeconds = (timebase * 14).abs();
    final int timeoutMs = ((sweepSeconds + 3) * 1000)
        .round()
        .clamp(2000, 30000)
        .toInt();
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      final status = await _queryAcquisitionStatus(instr);
      if (status != null && status.contains('stop')) return true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    AppLogger().warning(
      'The single acquisition did not complete within '
      '${(timeoutMs / 1000).round()} s (TDIV=$timebase); using the last '
      'completed frame.',
    );
    return false;
  }

  /// Reads the WFSU sparsing factor that the instrument actually uses.
  ///
  /// The firmware may reject or clamp the requested factor, so the value from
  /// `WFSU?` is authoritative. `SP,0` and `SP,1` both mean "every sample".
  Future<int> _querySparsing(
    Vxi11Instrument instr, {
    required int fallback,
  }) async {
    try {
      final response = (await instr.queryString('WFSU?')).trim();
      final match = RegExp(r'SP,(\d+)').firstMatch(response);
      final value = match == null ? null : int.tryParse(match.group(1)!);
      if (value == null) return fallback;
      return value <= 1 ? 1 : value;
    } catch (_) {
      return fallback;
    }
  }

  /// Sends [cmd], reads a status response, and parses it via [ScpiParser.parseStatus].
  Future<bool> _queryStatus(Vxi11Instrument instr, String cmd) async {
    String response;
    try {
      response = await instr.queryString(cmd);
    } catch (e) {
      throw AcquisitionException(cmd, 'query failed: $e');
    }

    return ScpiParser.parseStatus(response);
  }

  /// Sends [cmd], reads a string response, and parses it via [ScpiParser.parseValue].
  /// Wraps any error in [AcquisitionException].
  Future<double> _queryValue(Vxi11Instrument instr, String cmd) async {
    String response;
    try {
      response = await instr.queryString(cmd);
    } catch (e) {
      throw AcquisitionException(cmd, 'query failed: $e');
    }

    try {
      return ScpiParser.parseValue(response);
    } catch (e) {
      throw AcquisitionException(cmd, 'parse failed: $e');
    }
  }

  /// Sends [cmd], reads a binary data block, and parses it via
  /// [ScpiParser.parseDataBlock].
  /// Wraps any error in [AcquisitionException].
  Future<Uint8List> _queryDataBlock(Vxi11Instrument instr, String cmd) async {
    try {
      return await instr.queryDataBlock(cmd);
    } catch (e) {
      throw AcquisitionException(cmd, 'read data block failed: $e');
    }
  }
}
