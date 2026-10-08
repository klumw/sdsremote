import 'dart:typed_data';

import 'logger.dart';
import 'package:sdsremote/scpi_parser.dart';
import 'package:sdsremote/dart_vxi11.dart';
import 'package:sdsremote/waveform_models.dart';

/// Performs a complete waveform acquisition from a Siglent SDS oscilloscope
/// over VXI-11.
class WaveformAcquisition {
  final String ipAddress;

  WaveformAcquisition(this.ipAddress);

  /// Connects to the instrument, queries all required SCPI parameters and
  /// waveform data for the selected channels, then returns a [WaveformRawData].
  ///
  /// Before acquiring waveform data, the trigger mode is queried via `TRMD?`
  /// and set to `STOP` to freeze the display. After acquisition, the original
  /// trigger mode is restored.
  ///
  /// Throws [AcquisitionException] on any VXI-11 or parsing error.
  Future<WaveformRawData> acquire({
    bool ch1 = true,
    bool ch2 = true,
    void Function()? onConnected,
    Vxi11Instrument? instr,
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

      // --- Query and stop trigger mode ---
      // Freeze the display by stopping the trigger so we get a stable waveform.
      // The instrument may echo the command, e.g. "TRMD AUTO" or "TRMD STOP".
      // We extract only the mode value (the part after the last space).
      try {
        await activeInstr.writeString('TRMD?');
        final rawResponse = (await activeInstr.readString()).trim();
        // Strip command echo: take everything after the last space
        final lastSpace = rawResponse.lastIndexOf(' ');
        originalTriggerMode = lastSpace >= 0
            ? rawResponse.substring(lastSpace + 1).trim()
            : rawResponse;
      } catch (e) {
        AppLogger().log('Failed to query trigger mode: $e');
      }
      if (originalTriggerMode != null &&
          originalTriggerMode.isNotEmpty &&
          originalTriggerMode != 'STOP') {
        try {
          await activeInstr.writeString('TRMD STOP');
        } catch (e) {
          AppLogger().log('Failed to stop trigger: $e');
        }
      }

      // --- Global parameters (Requirement 1.2) ---
      final timebase = await _queryValue(activeInstr, 'TDIV?');
      final trdl = await _queryValue(activeInstr, 'TRDL?');
      final sampleRate = await _queryValue(activeInstr, 'SARA?');

      // Configure waveform transfer setup with enough points to cover the
      // full display span (timebase * 14 divisions). This keeps the acquired
      // waveform long enough to show all cycles visible on the screen.
      const int horizontalDivisions = 14;
      const int maxTransferPoints = 12000000;
      final int desiredPoints = (timebase * horizontalDivisions * sampleRate)
          .ceil();
      final int transferPoints = desiredPoints.clamp(1201, maxTransferPoints);
      try {
        await activeInstr.writeString('WFSU SP,7,NP,$transferPoints,FP,0');
      } catch (e) {
        AppLogger().log('WFSU setup failed: $e');
      }

      // --- Trigger position in acquisition memory ---
      // SANU? returns "pointCount,triggerPosition" — the trigger's sample
      // index within the acquisition memory.  With FP=0 in WFSU we read
      // from index 0, so this position lets us compute the correct time
      // offset for each sample: T(n) = (n - triggerPosition) / sampleRate + trdl
      int triggerPosition = 0;
      try {
        await activeInstr.writeString('SANU? C1');
        final sanuRaw = (await activeInstr.readString()).trim();
        triggerPosition = ScpiParser.parseSanu(sanuRaw).$2;
      } catch (_) {
        // Fall back to display-centric formula if SANU? fails
      }

      // --- Channel status check ---
      // Check if channels are active on the oscilloscope.
      // Fetch only if both: selected in UI (checkbox) AND active on the instrument.
      final isCh1Active = ch1 && await _queryStatus(activeInstr, 'C1:TRACE?');
      final isCh2Active = ch2 && await _queryStatus(activeInstr, 'C2:TRACE?');

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

      // --- Waveform data ---
      final ch1Raw = isCh1Active
          ? await _queryDataBlock(activeInstr, 'C1:WF? DAT2')
          : null;
      final ch2Raw = isCh2Active
          ? await _queryDataBlock(activeInstr, 'C2:WF? DAT2')
          : null;

      // --- Restore original trigger mode ---
      // Do this before the finally block so the connection is still fully open.
      // TRMD is a set command (not a query), so we do NOT read a response after it.
      if (originalTriggerMode != null &&
          originalTriggerMode.isNotEmpty &&
          originalTriggerMode != 'STOP') {
        try {
          await activeInstr.writeString('TRMD $originalTriggerMode');
        } catch (e) {
          AppLogger().log('Failed to restore trigger mode: $e');
        }
      }

      return WaveformRawData(
        ch1Raw: ch1Raw,
        ch2Raw: ch2Raw,
        vdivCh1: vdivCh1,
        voffsetCh1: voffsetCh1,
        vdivCh2: vdivCh2,
        voffsetCh2: voffsetCh2,
        timebase: timebase,
        trdl: trdl,
        sampleRate: sampleRate,
        triggerPosition: triggerPosition,
      );
    } finally {
      if (ownInstr) {
        await activeInstr.close();
      }
    }
  }

  /// Sends [cmd], reads a status response, and parses it via [ScpiParser.parseStatus].
  Future<bool> _queryStatus(Vxi11Instrument instr, String cmd) async {
    try {
      await instr.writeString(cmd);
    } catch (e) {
      throw AcquisitionException(cmd, 'write failed: $e');
    }

    String response;
    try {
      response = await instr.readString();
    } catch (e) {
      throw AcquisitionException(cmd, 'read failed: $e');
    }

    return ScpiParser.parseStatus(response);
  }

  /// Sends [cmd], reads a string response, and parses it via [ScpiParser.parseValue].
  /// Wraps any error in [AcquisitionException].
  Future<double> _queryValue(Vxi11Instrument instr, String cmd) async {
    try {
      await instr.writeString(cmd);
    } catch (e) {
      throw AcquisitionException(cmd, 'write failed: $e');
    }

    String response;
    try {
      response = await instr.readString();
    } catch (e) {
      throw AcquisitionException(cmd, 'read failed: $e');
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
      await instr.writeString(cmd);
    } catch (e) {
      throw AcquisitionException(cmd, 'write failed: $e');
    }

    try {
      return await instr.readDataBlock();
    } catch (e) {
      throw AcquisitionException(cmd, 'read data block failed: $e');
    }
  }
}
