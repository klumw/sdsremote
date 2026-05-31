import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'constants.dart';
import 'driver/usb_driver.dart';
import 'protocol_helpers.dart';

/// Exceptions specific to USBTMC protocol failures.
class UsbtmcException implements Exception {
  final String message;
  UsbtmcException(this.message);

  @override
  String toString() => 'UsbtmcException: $message';
}

/// A simple, zero-dependency Asynchronous Mutex queue to serialize physical transfers.
class _AsyncMutex {
  Future<void> _last = Future.value();

  Future<T> protect<T>(Future<T> Function() criticalSection) {
    final completer = Completer<void>();
    final next = _last.then((_) => criticalSection()).whenComplete(() {
      completer.complete();
    });
    _last = completer.future;
    return next;
  }
}

/// Models a USBTMC device, packaging standard Bulk transfers with USBTMC headers.
class UsbtmcDevice {
  final UsbDevice _usbDevice;
  final _AsyncMutex _lock = _AsyncMutex();

  int _bTag = 1;
  int _termChar = 0x0A; // '\n'
  bool _termCharEnabled = true;

  UsbtmcDevice(this._usbDevice);

  int get termChar => _termChar;
  set termChar(int value) => _termChar = value;

  bool get termCharEnabled => _termCharEnabled;
  set termCharEnabled(bool value) => _termCharEnabled = value;

  /// Maximum payload bytes per USBTMC multi-transfer DEV_DEP_MSG_OUT chunk
  /// (per USBTMC spec §3.2.1.1).
  ///
  /// Devices (e.g. Siglent SDS oscilloscopes) may have small internal USB
  /// receive buffers (~1-4 KB).  Sending, say, 47 KB of profile data in a
  /// single USB transaction causes the device to NAK continuously after its
  /// FIFO fills up, resulting in LIBUSB_ERROR_TIMEOUT.
  ///
  /// The USBTMC 1.0 spec explicitly allows sending a DEV_DEP_MSG_OUT message
  /// using multiple bulk transfers.  Key requirements (see §3.2.1.1):
  ///
  ///   1. ALL transfers MUST use the SAME bTag  (the old code incorrectly
  ///      incremented bTag per chunk, which makes the device STALL the
  ///      Bulk-OUT endpoint).
  ///   2. TransferSize in every header MUST be the TOTAL payload length
  ///      (not the chunk size).
  ///   3. EOM=0 on all transfers except the last (EOM=1).
  ///   4. Each USB transaction (header + chunk) must be 4-byte aligned.
  static const int _maxChunkSize = 4096;

  /// Delay between USBTMC multi-transfer chunks so the device firmware can
  /// drain its receive FIFO before the next chunk arrives.
  static const Duration _chunkDelay = Duration(milliseconds: 20);

  /// Writes binary data using USBTMC DEV_DEP_MSG_OUT multi-transfer
  /// messaging (USBTMC 1.0 spec §3.2.1.1).
  ///
  /// Payloads larger than [_maxChunkSize] are split across multiple USB
  /// bulk transfers.  All chunks share the SAME bTag and TransferSize
  /// (= total payload length).  Only the last chunk has EOM=1.
  Future<int> writeBinary(Uint8List payload, {Duration? timeout}) async {
    return _lock.protect(() async {
      if (payload.isEmpty) return 0;


      // Use ONE bTag for ALL chunks (per USBTMC spec §3.2.1.1).
      _bTag = UsbtmcProtocolHelpers.nextbTag(_bTag);

      int offset = 0;

      while (offset < payload.length) {
        final isLast = (offset + _maxChunkSize >= payload.length);
        final chunkLen = isLast ? payload.length - offset : _maxChunkSize;

        // SAME bTag for all chunks, TransferSize = TOTAL payload length.
        final header = UsbtmcProtocolHelpers.encodeBulkOutHeader(
          _bTag, payload.length, isLast, // EOM = 1 only on last chunk
        );

        // Compute alignment padding for this USB transaction:
        // transaction length = header(12) + chunk payload
        final chunkTotalLen = UsbtmcConstants.headerSize + chunkLen;
        final paddingLen = UsbtmcProtocolHelpers.getPaddingLength(chunkTotalLen);
        final padding = Uint8List(paddingLen);

        // Build the packet: header + chunk data + padding
        final packet = Uint8List(chunkTotalLen + paddingLen);
        packet.setRange(0, header.length, header);
        packet.setRange(
          header.length, header.length + chunkLen,
          Uint8List.sublistView(payload, offset, offset + chunkLen),
        );
        if (paddingLen > 0) {
          packet.setRange(header.length + chunkLen, packet.length, padding);
        }

        await _usbDevice.write(packet, timeout: timeout);

        offset += chunkLen;

        // Give the device time to drain its FIFO before the next chunk.
        if (!isLast) {
          await Future.delayed(_chunkDelay);
        }
      }

      return payload.length;
    });
  }

  /// Writes profile data (e.g. XML configuration) to the device in a single
  /// USB bulk transfer — one DEV_DEP_MSG_OUT message, no chunking.
  ///
  /// Unlike [writeBinary], which splits large payloads across multiple
  /// USBTMC multi-transfer chunks (§3.2.1.1), this method sends the entire
  /// payload in ONE bulk transaction.  This is required for profile upload
  /// (SCPI `*LRN` / `*LDS` style commands) where the instrument firmware
  /// expects the complete XML block atomically and does not correctly
  /// reassemble multi-transfer DEV_DEP_MSG_OUT messages.
  ///
  /// The USB host controller transparently handles low-level packetization
  /// (max 512/1024 bytes per packet for FS/HS) and automatic NAK/retry flow
  /// control — the device's FIFO never overflows because the hardware
  /// throttles the host at the USB protocol level.
  Future<int> profileWrite(Uint8List payload, {Duration? timeout}) async {
    return _lock.protect(() async {
      if (payload.isEmpty) return 0;

      // ── Pre-transfer cleanup ──────────────────────────────────────────
      // Previous bulk-out transfers (from kernel driver or a failed
      // writeBinary) may leave a partial URB on the wire.  Clear the
      // Bulk-OUT endpoint halt and abort any pending USBTMC transfer so
      // the device starts parsing our DEV_DEP_MSG_OUT from a clean state.
      try {
        await _usbDevice.clearHalt();
      } catch (_) {
        // Best-effort; proceed even if the endpoint was not stalled.
      }

      try {
        // USBTMC INITIATE_ABORT_BULK_OUT (bRequest=1) — cancels any
        // pending Bulk-OUT transfer inside the device's USBTMC firmware.
        await _usbDevice.controlTransfer(
          requestType: 0xA1, // Device-to-Host, Class, Interface
          request: UsbtmcConstants.initiateAbortBulkOut,
          value: 0,
          index: 0,
          data: Uint8List(2),
          timeout: const Duration(milliseconds: 500),
        );
      } catch (_) {
        // Best-effort; some devices may not support this request.
      }

      // Flush any in-flight kernel-driver URBs that were queued before
      // we detached the kernel driver.
      await Future.delayed(const Duration(milliseconds: 10));
      // ──────────────────────────────────────────────────────────────────

      // Single bTag for the single DEV_DEP_MSG_OUT message.
      _bTag = UsbtmcProtocolHelpers.nextbTag(_bTag);

      // Build the DEV_DEP_MSG_OUT header: EOM=1 (this is the only message).
      final transferSize = payload.length;
      final header = UsbtmcProtocolHelpers.encodeBulkOutHeader(
        _bTag,
        transferSize,
        true, // EOM = 1
      );

      // 4-byte alignment padding (USBTMC spec requirement).
      final totalLen = UsbtmcConstants.headerSize + payload.length;
      final paddingLen = UsbtmcProtocolHelpers.getPaddingLength(totalLen);

      // print('USBTMC: profileWrite sending ${payload.length} bytes in one transfer');

      // Single contiguous packet: header + payload + padding.
      final packet = Uint8List(totalLen + paddingLen);
      packet.setRange(0, header.length, header);
      packet.setRange(header.length, header.length + payload.length, payload);
      if (paddingLen > 0) {
        packet.setRange(
          header.length + payload.length,
          packet.length,
          Uint8List(paddingLen),
        );
      }

      await _usbDevice.write(packet, timeout: timeout);

      // print('USBTMC: profileWrite complete — ${payload.length} payload bytes sent');
      return payload.length;
    });
  }

  /// Initiates a Request Bulk-IN and reads the formatted response.
  Future<Uint8List> doRead(int maxBytesRequested, {required bool useTermChar, Duration? timeout}) async {
    return _lock.protect(() async {
      // print('USBTMC: doRead start - maxBytesRequested: $maxBytesRequested');
      final List<int> accumulatedData = [];
      bool isLastMessage = false;
      int? totalExpectedSize;

      const int maxChunkSize = 128 * 1024; // Cap single transfer size to 128 KB for safety and compatibility

      while (true) {
        if (accumulatedData.isNotEmpty) {
          if (totalExpectedSize != null && accumulatedData.length >= totalExpectedSize) {
            // print('USBTMC: Stopping outer loop - reached expected size $totalExpectedSize (accumulated: ${accumulatedData.length})');
            break;
          }
          if (totalExpectedSize == null && isLastMessage) {
            // print('USBTMC: Stopping outer loop - standard EOM received (accumulated: ${accumulatedData.length})');
            break;
          }
          if (accumulatedData.length >= maxBytesRequested) {
            // print('USBTMC: Stopping outer loop - reached maxBytesRequested (accumulated: ${accumulatedData.length})');
            break;
          }
        }

        _bTag = UsbtmcProtocolHelpers.nextbTag(_bTag);

        // Request the remaining bytes up to maxBytesRequested or expected size
        int remainingToRequest = maxBytesRequested - accumulatedData.length;
        if (totalExpectedSize != null) {
          final remainingBytes = totalExpectedSize - accumulatedData.length;
          if (remainingBytes < remainingToRequest) {
            remainingToRequest = remainingBytes;
          }
        }
        // print('USBTMC: requesting next message - bTag: $_bTag, remainingToRequest: $remainingToRequest');

        // Build and transmit the Bulk-IN request header (12 bytes)
        final requestHeader = UsbtmcProtocolHelpers.encodeMsgInBulkOutHeader(
          _bTag,
          remainingToRequest,
          useTermChar && _termCharEnabled,
          _termChar,
        );

        await _usbDevice.write(requestHeader, timeout: timeout);

        int expectedTransferSize = 0;
        bool isFirstRead = true;
        int messageBytesRead = 0;
        int consecutiveEmptyReads = 0;

        // Loop reading until either we get our expected bytes or the message is fully read.
        while (true) {
          int targetRemaining = remainingToRequest - messageBytesRead;
          if (!isFirstRead && expectedTransferSize > 0) {
            targetRemaining = expectedTransferSize - messageBytesRead;
            if (targetRemaining <= 0) {
              break;
            }
          }

          int requestSz = targetRemaining;
          if (isFirstRead) {
            requestSz += UsbtmcConstants.headerSize;
          }

          // Cap transfer size
          if (requestSz > maxChunkSize) {
            requestSz = maxChunkSize;
          }

          // Round requested buffer size up to nearest 512 boundary to prevent libusb overflow
          final rawSize = requestSz + (512 - (requestSz % 512)) % 512;

          final rawBuffer = await _usbDevice.read(rawSize, timeout: timeout);
          if (rawBuffer.isEmpty) {
            consecutiveEmptyReads++;
            // print('USBTMC: rawBuffer was empty (ZLP) - count: $consecutiveEmptyReads');
            if (consecutiveEmptyReads >= 5) {
              // print('USBTMC: Too many consecutive empty reads, breaking inner loop');
              break;
            }
            if (messageBytesRead < expectedTransferSize) {
              // The message is not yet fully read; this is a ZLP/early completion of a USB packet.
              // Continue reading the rest of the current USBTMC message.
              continue;
            }
            break; // Zero-length read from device at end of message
          }
          consecutiveEmptyReads = 0;
          // print('USBTMC: read returned ${rawBuffer.length} bytes (requested $rawSize)');

          int payloadOffset = 0;
          int payloadLen = rawBuffer.length;

          if (isFirstRead) {
            if (rawBuffer.length < UsbtmcConstants.headerSize) {
              throw UsbtmcException('Short read: no space for USBTMC response header');
            }

            // Validate Bulk-IN Response Header
            final respMsgId = rawBuffer[0];
            final respBTag = rawBuffer[1];
            final respBTagInv = rawBuffer[2];

            if (respMsgId != UsbtmcConstants.devDepMsgIn) {
              // print('USBTMC ERROR: MsgID mismatch! respMsgId: $respMsgId, expected: ${UsbtmcConstants.devDepMsgIn}');
              // print('USBTMC ERROR: rawBuffer contents (len=${rawBuffer.length}): $rawBuffer');
              throw UsbtmcException('Unexpected MsgID in Bulk-IN header: $respMsgId');
            }
            if (respBTag != _bTag) {
              throw UsbtmcException('bTag mismatch in response: got $respBTag, expected $_bTag');
            }
            if (respBTagInv != UsbtmcProtocolHelpers.invertbTag(respBTag)) {
              throw UsbtmcException('Invalid bTagInverse in response');
            }

            final byteData = ByteData.sublistView(rawBuffer, 4, 8);
            expectedTransferSize = byteData.getUint32(0, Endian.little);

            // Byte 8 is bmTransferAttributes. Bit 0 is EOM.
            final transferAttributes = rawBuffer[8];
            isLastMessage = (transferAttributes & 0x01) != 0;
            // print('USBTMC: Header parsed - expectedTransferSize: $expectedTransferSize, isLastMessage (EOM): $isLastMessage');

            // Determine total transfer size on the first read of the transfer
            if (accumulatedData.isEmpty) {
              totalExpectedSize = expectedTransferSize;
              // print('USBTMC: Initial totalExpectedSize set from Bulk-IN TransferSize: $totalExpectedSize');

              // Check if we also have an IEEE definite-length header that indicates a larger size
              if (rawBuffer.length > UsbtmcConstants.headerSize) {
                final payloadStart = rawBuffer[UsbtmcConstants.headerSize];
                if (payloadStart == 0x23) { // '#' character
                  int idx = UsbtmcConstants.headerSize + 1;
                  if (idx < rawBuffer.length) {
                    final nDigitsChar = rawBuffer[idx];
                    if (nDigitsChar >= 0x31 && nDigitsChar <= 0x39) {
                      final nDigits = nDigitsChar - 0x30;
                      idx++;
                      if (idx + nDigits <= rawBuffer.length) {
                        final lenStr = String.fromCharCodes(rawBuffer.sublist(idx, idx + nDigits));
                        final parsedSize = int.tryParse(lenStr);
                        if (parsedSize != null) {
                          final ieeeSize = 1 + 1 + nDigits + parsedSize;
                          if (ieeeSize > totalExpectedSize) {
                            totalExpectedSize = ieeeSize;
                            // print('USBTMC: IEEE definite-length header specifies a larger size: $totalExpectedSize');
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            payloadOffset = UsbtmcConstants.headerSize;
            payloadLen = rawBuffer.length - UsbtmcConstants.headerSize;
            isFirstRead = false;
          }

          // Cap the payload length to avoid accumulating alignment/padding bytes at the end of the message
          int capLen = expectedTransferSize - messageBytesRead;
          if (payloadLen > capLen) {
            payloadLen = capLen;
          }

          // Add payload data to accumulator (excluding header)
          final actualChunk = rawBuffer.sublist(payloadOffset, payloadOffset + payloadLen);
          accumulatedData.addAll(actualChunk);
          messageBytesRead += actualChunk.length;
          // print('USBTMC: Accumulated chunk of ${actualChunk.length} bytes (messageBytesRead: $messageBytesRead/$expectedTransferSize)');

          // Terminate early if we reached the size defined by the device transfer header
          if (messageBytesRead >= expectedTransferSize) {
            break;
          }
        }

        // print('USBTMC: Outer loop step completed - accumulated length: ${accumulatedData.length}');
        // Prevent infinite loop if we read nothing in this request
        if (messageBytesRead == 0) {
          break;
        }
      }

      // print('USBTMC: doRead completed - returning ${accumulatedData.length} bytes');
      return Uint8List.fromList(accumulatedData);
    });
  }

  /// Sends a write-only SCPI text command. Automatically appends a newline terminator.
  Future<void> command(String scpi, {Duration? timeout}) async {
    final trimmed = scpi.trim();
    final fullCmd = '$trimmed\n';
    final payload = Uint8List.fromList(utf8.encode(fullCmd));
    await writeBinary(payload, timeout: timeout);
  }

  /// Sends an SCPI query and awaits the instrument's ASCII/text response.
  Future<String> query(String scpi, {Duration? timeout}) async {
    await command(scpi, timeout: timeout);

    // Read response (ASCII mode)
    final buffer = await doRead(
      UsbtmcConstants.maxPacketSize * 1024, // High max capacity
      useTermChar: true,
      timeout: timeout,
    );

    return utf8.decode(buffer).trim();
  }

  /// Reads raw binary bytes from device (without interpretation of termination characters).
  Future<Uint8List> readRaw(int expectedBytes, {Duration? timeout}) async {
    return doRead(expectedBytes, useTermChar: false, timeout: timeout);
  }

  /// Writes raw binary bytes to the device.
  Future<int> writeRaw(Uint8List bytes, {Duration? timeout}) async {
    return writeBinary(bytes, timeout: timeout);
  }

  /// Drains any leftover bytes from the Bulk-IN endpoint to ensure a clean state.
  Future<void> drainBulkIn() async {
    try {
      // print('USBTMC: Draining Bulk-IN endpoint...');
      int totalDrained = 0;
      while (true) {
        // Read with a very short timeout to check for leftover data in the FIFO
        final data = await _usbDevice.read(131072, timeout: const Duration(milliseconds: 50));
        if (data.isEmpty) {
          break;
        }
        totalDrained += data.length;
      }
      if (totalDrained > 0) {
        // print('USBTMC: Successfully drained $totalDrained leftover bytes from Bulk-IN FIFO.');
      } else {
        // print('USBTMC: Bulk-IN endpoint was already empty.');
      }
    } catch (e) {
      // Ignore read errors/timeouts during drain as they indicate the endpoint is empty
      // print('USBTMC: Bulk-IN drain completed.');
    }
  }

  /// Performs full USBTMC initialization sequence:
  ///   1. Clear endpoint halts
  ///   2. Drain Bulk-IN
  ///   3. INITIATE_CLEAR + CHECK_CLEAR_STATUS
  ///   4. GET_CAPABILITIES
  ///   5. REN_CONTROL (assert Remote Enable if device supports it)
  ///
  /// Step 4 and 5 are required by the USBTMC/USB488 spec (see Linux usbtmc
  /// kernel driver and Arduino USB Host Shield reference implementation).
  /// Without REN_CONTROL some devices (e.g. Siglent SDS oscilloscopes) may
  /// reject bulk data transfers with LIBUSB_ERROR_TIMEOUT.
  Future<void> clear() async {
    try {
      // print('USBTMC: Clearing standard USB bulk endpoint halts...');
      await _usbDevice.clearHalt();
    } catch (e) {
      // print('USBTMC: clearHalt failed: $e');
    }

    // Drain any leftover data in the Bulk-IN pipe
    await drainBulkIn();

    try {
      // print('USBTMC: Initiating USBTMC Clear control request (INITIATE_CLEAR, bRequest=5)...');
      final initStatus = await _usbDevice.controlTransfer(
        requestType: 0xA1, // Class-specific, interface recipient, Device-to-Host
        request: UsbtmcConstants.initiateClear, // bRequest=5 per USBTMC spec Table 15
        value: 0,
        index: 0, // Interface 0
        data: Uint8List(1),
        timeout: const Duration(seconds: 2),
      );

      if (initStatus.isNotEmpty) {
        final status = initStatus[0];
        // print('USBTMC: INITIATE_CLEAR returned status: $status');
        if (status == 2) { // PENDING
          // Poll CHECK_CLEAR_STATUS until success or failure
          for (int i = 0; i < 10; i++) {
            await Future.delayed(const Duration(milliseconds: 100));
            final checkStatus = await _usbDevice.controlTransfer(
              requestType: 0xA1,
              request: UsbtmcConstants.checkClearStatus, // bRequest=6 per USBTMC spec Table 15
              value: 0,
              index: 0,
              data: Uint8List(2),
              timeout: const Duration(seconds: 2),
            );
            if (checkStatus.length >= 2) {
              final pollStatus = checkStatus[0];
              // print('USBTMC: CHECK_CLEAR_STATUS returned: $pollStatus');
              if (pollStatus == 1) { // SUCCESS
                break;
              } else if (pollStatus >= 0x80) { // FAILED (any status >= 0x80 is an error)
                // print('USBTMC: CHECK_CLEAR_STATUS reported failure: $pollStatus');
                break;
              }
            }
          }
        }
      }
      // print('USBTMC: Clear operation completed.');
    } catch (e) {
      // print('USBTMC: Clear failed with exception: $e');
    }

    // ── USBTMC GET_CAPABILITIES (bRequest=7) ──────────────────────────────
    // Queries the device for USBTMC/USB488 capabilities.
    // Response is 24 bytes (see USBTMC spec Table 37).
    try {
      // print('USBTMC: Querying GET_CAPABILITIES...');
      final caps = await _usbDevice.controlTransfer(
        requestType: 0xA1, // Device-to-Host, Class, Interface
        request: 7,        // GET_CAPABILITIES
        value: 0,
        index: 0,
        data: Uint8List(24),
        timeout: const Duration(seconds: 2),
      );
      if (caps.length >= 24) {
        // Byte 12-13: bcdUSB488 (BCD version number)
        final bcdUSB488 = (caps[13] << 8) | caps[12];
        // Byte 14: USB488Interface capabilities
        final usb488Iface = caps[14];
        // Byte 15: USB488Device capabilities
        final usb488Dev = caps[15];

        // ── REN_CONTROL (bRequest=0xA0) ─────────────────────────────────
        // If USB488Interface.D1 (bit 1) is set, the device accepts
        // REN_CONTROL, GO_TO_LOCAL, and LOCAL_LOCKOUT requests.
        // We must assert REN (Remote Enable) so the device enters remote
        // mode and accepts SCPI commands.
        if ((usb488Iface & 0x02) != 0) {
          // print('USBTMC: Device supports REN_CONTROL — asserting Remote Enable...');
          final renStatus = await _usbDevice.controlTransfer(
            requestType: 0xA1, // Device-to-Host, Class, Interface
            request: 0xA0,     // REN_CONTROL
            value: 0x01,       // Assert REN
            index: 0,
            data: Uint8List(1), // 1-byte buffer for device status response
            timeout: const Duration(seconds: 2),
          );
          if (renStatus.isNotEmpty) {
            final status = renStatus[0];
            // print('USBTMC: REN_CONTROL returned status: $status');
          }
        } else {
          // print('USBTMC: Device does not support REN_CONTROL — skipping');
        }
      } else {
        // print('USBTMC: GET_CAPABILITIES returned ${caps.length} bytes (expected 24)');
      }
    } catch (e) {
      // print('USBTMC: GET_CAPABILITIES / REN_CONTROL failed: $e');
    }
  }

  /// Performs a low-level USB port reset to recover a hung device.
  /// Note: This invalidates the device handle. You MUST close this UsbtmcDevice
  /// and re-open it via UsbtmcContext.newDevice() after calling this method.
  Future<void> reset() async {
    await _usbDevice.reset();
  }

  /// Closes the physical USB connection.
  Future<void> close() async {
    await _usbDevice.close();
  }
}
