import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'logger.dart';

/// XDR encoding/decoding helper.
/// All integers are big-endian 4-byte values.
/// Opaque data is length-prefixed and padded to 4-byte boundaries.
class XdrBuffer {
  final BytesBuilder? _builder;
  final Uint8List _bytes;
  int _offset = 0;

  /// Creates an XdrBuffer for encoding.
  XdrBuffer()
      : _builder = BytesBuilder(),
        _bytes = Uint8List(0);

  /// Creates an XdrBuffer for decoding from [bytes].
  XdrBuffer.fromBytes(Uint8List bytes)
      : _builder = null,
        _bytes = bytes;

  // ── Encoding ──────────────────────────────────────────────────────────────

  /// Encodes [value] as a 4-byte big-endian unsigned integer.
  void writeUint32(int value) {
    final buf = Uint8List(4);
    ByteData.view(buf.buffer).setUint32(0, value, Endian.big);
    _builder!.add(buf);
  }

  /// Encodes [value] as a 4-byte big-endian signed integer.
  void writeInt32(int value) {
    final buf = Uint8List(4);
    ByteData.view(buf.buffer).setInt32(0, value, Endian.big);
    _builder!.add(buf);
  }

  /// Encodes [value] as uint32 0 (false) or 1 (true).
  void writeBool(bool value) {
    writeUint32(value ? 1 : 0);
  }

  /// Encodes [bytes] as XDR opaque: 4-byte length prefix, then the bytes,
  /// then zero-padding to the next 4-byte boundary.
  void writeOpaque(Uint8List bytes) {
    writeUint32(bytes.length);
    _builder!.add(bytes);
    final pad = (4 - bytes.length % 4) % 4;
    if (pad > 0) {
      _builder.add(Uint8List(pad));
    }
  }

  /// UTF-8 encodes [s] then calls [writeOpaque].
  void writeString(String s) {
    writeOpaque(Uint8List.fromList(utf8.encode(s)));
  }

  /// Returns the accumulated encoded bytes.
  Uint8List toBytes() => _builder!.toBytes();

  // ── Decoding ──────────────────────────────────────────────────────────────

  /// Returns true if there are unread bytes remaining.
  bool get hasMore => _offset < _bytes.length;

  /// Reads a 4-byte big-endian unsigned integer.
  int readUint32() {
    _checkRemaining(4);
    final bd = ByteData.view(_bytes.buffer, _bytes.offsetInBytes + _offset, 4);
    _offset += 4;
    return bd.getUint32(0, Endian.big);
  }

  /// Reads a 4-byte big-endian signed integer.
  int readInt32() {
    _checkRemaining(4);
    final bd = ByteData.view(_bytes.buffer, _bytes.offsetInBytes + _offset, 4);
    _offset += 4;
    return bd.getInt32(0, Endian.big);
  }

  /// Reads a uint32 and returns false for 0, true for non-zero.
  bool readBool() => readUint32() != 0;

  /// Reads a length-prefixed opaque byte array (with padding consumed).
  Uint8List readOpaque() {
    final len = readUint32();
    _checkRemaining(len);
    final data = Uint8List.fromList(_bytes.sublist(_offset, _offset + len));
    _offset += len;
    final pad = (4 - len % 4) % 4;
    _checkRemaining(pad);
    _offset += pad;
    return data;
  }

  /// Reads an XDR opaque string and decodes it as UTF-8.
  String readString() => utf8.decode(readOpaque());

  void _checkRemaining(int needed) {
    if (_offset + needed > _bytes.length) {
      throw StateError(
          'XDR decode error: expected $needed bytes at offset $_offset, '
          'but only ${_bytes.length - _offset} remaining');
    }
  }
}

/// ONC-RPC client over TCP with Record Marking framing (RFC 1057).
///
/// Record Marking send: prepend a 4-byte big-endian header where
/// bit 31 = 1 (last fragment) and bits 30–0 = payload length.
///
/// Record Marking receive: read 4-byte header, extract length from bits 30–0,
/// read that many bytes. Repeat if bit 31 is 0 (more fragments).
/// Concatenate all fragments.
class RpcClient {
  final Socket _socket;

  // Buffer for incoming bytes from the socket stream.
  final List<int> _buffer = [];
  late final StreamIterator<Uint8List> _streamIter;

  RpcClient(Socket socket) : _socket = socket {
    _streamIter = StreamIterator<Uint8List>(_socket);
  }

  /// Closes the underlying socket.
  Future<void> close() async {
    await _streamIter.cancel();
    await _socket.close();
  }

  /// Sends [payload] with a Record Marking header.
  Future<void> _send(Uint8List payload) async {
    // Bit 31 = 1 (last fragment), bits 30–0 = length.
    final headerValue = 0x80000000 | payload.length;
    final header = Uint8List(4);
    ByteData.view(header.buffer).setUint32(0, headerValue, Endian.big);
    _socket.add(header);
    _socket.add(payload);
    await _socket.flush();
  }

  /// Reads exactly [n] bytes from the socket stream, buffering as needed.
  Future<Uint8List> _readExact(int n) async {
    try {
      while (_buffer.length < n) {
        if (!await _streamIter.moveNext()) {
          throw StateError(
            'Socket closed unexpectedly by the instrument while waiting for $n bytes. '
            'This often happens if the instrument is busy or the connection was reset.',
          );
        }
        _buffer.addAll(_streamIter.current);
      }
      final result = Uint8List.fromList(_buffer.sublist(0, n));
      _buffer.removeRange(0, n);
      return result;
    } on SocketException catch (e) {
      throw StateError('Network error while reading from socket: ${e.message} (OS Error: ${e.osError})');
    }
  }

  /// Reads a complete Record Marking message, concatenating all fragments.
  Future<Uint8List> _receive() async {
    final fragments = <int>[];
    while (true) {
      final headerBytes = await _readExact(4);
      final headerValue =
          ByteData.view(headerBytes.buffer).getUint32(0, Endian.big);
      final isLastFragment = (headerValue & 0x80000000) != 0;
      final length = headerValue & 0x7FFFFFFF;
      final fragment = await _readExact(length);
      fragments.addAll(fragment);
      if (isLastFragment) break;
    }
    return Uint8List.fromList(fragments);
  }

  /// Sends an RPC CALL and returns the reply payload as an [XdrBuffer].
  ///
  /// Encodes the RPC CALL message, sends it with Record Marking framing,
  /// receives the reply, validates xid/MSG_ACCEPTED/SUCCESS, and returns
  /// the remaining bytes as an [XdrBuffer] for the caller to decode.
  ///
  /// Throws a [StateError] on xid mismatch, MSG_DENIED, or non-SUCCESS reply.
  Future<XdrBuffer> call({
    required int program,
    required int version,
    required int procedure,
    required Uint8List params,
    required int xid,
  }) async {
    // Build RPC CALL message.
    final req = XdrBuffer();
    req.writeUint32(xid);       // xid
    req.writeUint32(0);         // msg_type = CALL(0)
    req.writeUint32(2);         // rpcvers = 2
    req.writeUint32(program);   // prog
    req.writeUint32(version);   // vers
    req.writeUint32(procedure); // proc
    req.writeUint32(0);         // credentials flavor = AUTH_NULL(0)
    req.writeUint32(0);         // credentials body length = 0
    req.writeUint32(0);         // verifier flavor = AUTH_NULL(0)
    req.writeUint32(0);         // verifier body length = 0
    _builder(req, params);

    await _send(req.toBytes());

    // Receive and parse RPC REPLY.
    final replyBytes = await _receive();
    final reply = XdrBuffer.fromBytes(replyBytes);

    final replyXid = reply.readUint32();
    if (replyXid != xid) {
      throw StateError(
          'RPC xid mismatch: expected $xid, got $replyXid');
    }

    final msgType = reply.readUint32(); // 1 = REPLY
    if (msgType != 1) {
      throw StateError('RPC reply has unexpected msg_type: $msgType');
    }

    final replyStat = reply.readUint32(); // 0 = MSG_ACCEPTED, 1 = MSG_DENIED
    if (replyStat != 0) {
      throw StateError('RPC call was denied (reply_stat=$replyStat)');
    }

    // Consume verifier (flavor + length).
    reply.readUint32(); // verifier flavor
    reply.readUint32(); // verifier body length

    final acceptStat = reply.readUint32(); // 0 = SUCCESS
    if (acceptStat != 0) {
      throw StateError(
          'RPC call failed with accept_stat=$acceptStat');
    }

    // Return remaining bytes as XdrBuffer for the caller to decode.
    final remaining = Uint8List.fromList(
        replyBytes.sublist(reply._offset));
    return XdrBuffer.fromBytes(remaining);
  }

  /// Appends raw [bytes] to [buf] without any length prefix.
  static void _builder(XdrBuffer buf, Uint8List bytes) {
    buf._builder!.add(bytes);
  }
}

/// Maps VXI-11 error codes to human-readable descriptions.
/// Exposed for testing.
class Vxi11ErrorMessages {
  static String forCode(int code) {
    switch (code) {
      case 0:  return 'No error';
      case 4:  return 'Invalid link identifier';
      case 11: return 'Device locked by another link';
      case 15: return 'I/O timeout';
      case 17: return 'I/O error';
      case 23: return 'Abort';
      default: return 'Unknown error $code';
    }
  }
}

/// High-level VXI-11 instrument client.
///
/// Usage:
/// ```dart
/// final instr = Vxi11Instrument('192.168.1.100');
/// instr.open();
/// instr.writeString('*IDN?');
/// print(instr.readString());
/// instr.close();
/// ```
class Vxi11Instrument {
  final String _host;
  final String _deviceName;
  int _timeoutMs = 10000;
  RpcClient? _rpc;
  int? _linkId;
  String _lastError = '';
  int _xidCounter = 1;

  Vxi11Instrument(String host, {String name = 'inst0'})
      : _host = host,
        _deviceName = name;

  /// The host address this instrument connects to.
  String get host => _host;

  /// The device name used when creating the VXI-11 link.
  String get deviceName => _deviceName;

  /// Returns the most recent error message.
  String lastError() => _lastError;

  /// Opens portmapper + VXI-11 connections and creates a link.
  Future<int> open({double timeoutSeconds = 10.0}) async {
    _timeoutMs = (timeoutSeconds * 1000).round();
    AppLogger().log('VXI-11: Opening connection to $_host');

    // Step 1: Connect to portmapper on port 111.
    Socket pmSocket;
    try {
      pmSocket = await Socket.connect(
        _host,
        111,
        timeout: Duration(milliseconds: _timeoutMs),
      );
    } catch (e) {
      AppLogger().log('VXI-11: Failed to connect to portmapper (port 111) on $_host: $e');
      rethrow;
    }
    final pmRpc = RpcClient(pmSocket);

    // Step 2: Encode GETPORT params: prog=0x0607af, vers=1, prot=6 (TCP), port=0.
    final getportParams = XdrBuffer();
    getportParams.writeUint32(0x0607af); // prog
    getportParams.writeUint32(1);        // vers
    getportParams.writeUint32(6);        // prot = TCP
    getportParams.writeUint32(0);        // port = 0

    // Step 3: Call GETPORT (procedure 3) on portmapper program 100000, version 2.
    XdrBuffer reply;
    try {
      reply = await pmRpc.call(
        program: 100000,
        version: 2,
        procedure: 3,
        params: getportParams.toBytes(),
        xid: _xidCounter++,
      );
    } catch (e) {
      AppLogger().log('VXI-11: GETPORT RPC call failed: $e');
      await pmRpc.close();
      rethrow;
    }

    // Step 4: Decode port from reply.
    final port = reply.readUint32();
    AppLogger().log('VXI-11: Portmapper returned VXI-11 port: $port');

    // Step 5: Close portmapper socket.
    await pmRpc.close();

    // Step 6: Throw if port is 0 (service not available).
    if (port == 0) {
      AppLogger().log('VXI-11: Service not available on $_host (port 0 returned)');
      throw StateError('VXI-11 service not available on $_host');
    }

    // Step 7: Connect TCP socket to host:port (VXI-11 service).
    Socket vxiSocket;
    try {
      vxiSocket = await Socket.connect(
        _host,
        port,
        timeout: Duration(milliseconds: _timeoutMs),
      );
    } catch (e) {
      AppLogger().log('VXI-11: Failed to connect to VXI-11 service on $_host:$port: $e');
      rethrow;
    }
    _rpc = RpcClient(vxiSocket);

    // Step 8: Encode CREATE_LINK params:
    //   client_id(i32) | lock_device(bool=false) | lock_timeout_ms(u32=0) | device_name(string)
    final createLinkParams = XdrBuffer();
    createLinkParams.writeInt32(0);           // client_id = 0
    createLinkParams.writeBool(false);        // lock_device = false
    createLinkParams.writeUint32(0);          // lock_timeout_ms = 0
    createLinkParams.writeString(_deviceName); // device_name

    // Step 9: Call CREATE_LINK (procedure 10) on program 0x0607af, version 1.
    final createLinkReply = await _rpc!.call(
      program: 0x0607af,
      version: 1,
      procedure: 10,
      params: createLinkParams.toBytes(),
      xid: _xidCounter++,
    );

    // Step 10: Decode CREATE_LINK result:
    //   error(i32) | link_id(i32) | abort_port(u32) | max_recv_size(u32)
    final error = createLinkReply.readInt32();
    final linkId = createLinkReply.readInt32();
    createLinkReply.readUint32(); // abort_port (unused)
    createLinkReply.readUint32(); // max_recv_size (unused)

    // Step 11: Throw if error != 0.
    if (error != 0) {
      _lastError = 'VXI-11 error $error: ${_vxi11ErrorMessage(error)}';
      throw StateError(_lastError);
    }

    // Step 12: Store link_id.
    _linkId = linkId;

    return 0;
  }

  /// Maps a VXI-11 error code to a human-readable description.
  String _vxi11ErrorMessage(int code) => Vxi11ErrorMessages.forCode(code);

  /// Sends a SCPI/VXI-11 command string to the instrument.
  Future<void> writeString(String cmd) async {
    if (_linkId == null) {
      _lastError = 'Connection not open';
      throw StateError(_lastError);
    }

    final cmdBytes = Uint8List.fromList(utf8.encode(cmd));

    // Encode DEVICE_WRITE params:
    // link_id(i32) | timeout_ms(u32) | lock_timeout_ms(u32=0) | flags(i32=8) | data(opaque)
    final params = XdrBuffer();
    params.writeInt32(_linkId!);       // link_id
    params.writeUint32(_timeoutMs);    // timeout_ms
    params.writeUint32(0);             // lock_timeout_ms = 0
    params.writeInt32(8);              // flags = 8 (OP_FLAG_END)
    params.writeOpaque(cmdBytes);      // data

    // Call DEVICE_WRITE (procedure 11) on program 0x0607af, version 1.
    final reply = await _rpc!.call(
      program: 0x0607af,
      version: 1,
      procedure: 11,
      params: params.toBytes(),
      xid: _xidCounter++,
    );

    // Decode result: error(i32) | size(u32)
    final error = reply.readInt32();
    final size = reply.readUint32();

    if (error != 0) {
      _lastError = 'VXI-11 error $error: ${_vxi11ErrorMessage(error)}';
      throw StateError(_lastError);
    }

    if (size != cmdBytes.length) {
      _lastError = 'DEVICE_WRITE size mismatch: expected ${cmdBytes.length}, got $size';
      throw StateError(_lastError);
    }
  }

  /// Reads a string response from the instrument.
  Future<String> readString({int maxLen = 256}) async {
    if (_linkId == null) {
      _lastError = 'Connection not open';
      throw StateError(_lastError);
    }

    // Encode DEVICE_READ params:
    // link_id(i32) | request_size(u32) | timeout_ms(u32) | lock_timeout_ms(u32=0) | flags(i32=0) | term_char(i32=0)
    final params = XdrBuffer();
    params.writeInt32(_linkId!);    // link_id
    params.writeUint32(maxLen);     // request_size
    params.writeUint32(_timeoutMs); // timeout_ms
    params.writeUint32(0);          // lock_timeout_ms = 0
    params.writeInt32(0);           // flags = 0
    params.writeInt32(0);           // term_char = 0

    // Call DEVICE_READ (procedure 12) on program 0x0607af, version 1.
    final reply = await _rpc!.call(
      program: 0x0607af,
      version: 1,
      procedure: 12,
      params: params.toBytes(),
      xid: _xidCounter++,
    );

    // Decode result: error(i32) | reason(i32) | data(opaque)
    final error = reply.readInt32();
    reply.readInt32(); // reason (unused)
    final data = reply.readOpaque();

    if (error != 0) {
      _lastError = 'VXI-11 error $error: ${_vxi11ErrorMessage(error)}';
      throw StateError(_lastError);
    }

    return utf8.decode(data).trim();
  }

  /// Reads an IEEE 488.2 definite-length binary data block.
  Future<Uint8List> readDataBlock() async {
    if (_linkId == null) {
      _lastError = 'Connection not open';
      throw StateError(_lastError);
    }
    return _stripIeeeHeader(await _readRaw());
  }

  /// Sends SCDP and reads the raw BMP image bytes.
  Future<Uint8List> getScreenDump() async {
    await writeString('SCDP');
    return _readRaw();
  }

  /// Sends a command and reads the entire response until END is signalled.
  /// Useful for large responses like XML settings.
  Future<Uint8List> readRawResponse(String cmd) async {
    await writeString(cmd);
    return _readRaw();
  }

  /// Reads all available DEVICE_READ data until the instrument signals END.
  Future<Uint8List> _readRaw() async {
    // Use a large chunk size (16 MB) to minimize the number of
    // VXI-11 round trips when reading waveform data or screen dumps.
    // _maxRecvSize only applies to writes (the instrument's receive buffer),
    // not to reads — the instrument can send up to request_size bytes per read.
    const chunkSize = 16 * 1024 * 1024;
    final raw = <int>[];
    while (true) {
      final params = XdrBuffer();
      params.writeInt32(_linkId!);
      params.writeUint32(chunkSize);
      params.writeUint32(_timeoutMs);
      params.writeUint32(0);
      params.writeInt32(0);
      params.writeInt32(0);

      final reply = await _rpc!.call(
        program: 0x0607af,
        version: 1,
        procedure: 12,
        params: params.toBytes(),
        xid: _xidCounter++,
      );

      final error = reply.readInt32();
      final reason = reply.readInt32();
      final data = reply.readOpaque();

      if (error != 0) {
        _lastError = 'VXI-11 error $error: ${_vxi11ErrorMessage(error)}';
        throw StateError(_lastError);
      }

      raw.addAll(data);
      if ((reason & 0x04) != 0 || data.isEmpty) break;
    }
    return Uint8List.fromList(raw);
  }

  /// Strips the IEEE 488.2 `#<n><len>` header if present and returns payload.
  Uint8List _stripIeeeHeader(Uint8List raw) {
    // Find '#'
    int i = 0;
    while (i < raw.length && raw[i] != 0x23) {
      i++;
    }

    if (i >= raw.length) return raw; // no header — return as-is

    i++; // skip '#'
    if (i >= raw.length) return raw;

    final nDigitsChar = raw[i];
    if (nDigitsChar < 0x31 || nDigitsChar > 0x39) {
      // '#' not followed by a digit — probably a BMP with '#' in the data
      // Return from the start (before the '#' we found)
      return raw;
    }
    final nDigits = nDigitsChar - 0x30;
    i++;

    if (i + nDigits > raw.length) return raw;
    final lengthStr = String.fromCharCodes(raw.sublist(i, i + nDigits));
    final blockLength = int.tryParse(lengthStr);
    if (blockLength == null) return raw;
    i += nDigits;

    final available = raw.length - i;
    final take = blockLength < available ? blockLength : available;
    return Uint8List.sublistView(raw, i, i + take);
  }

  /// Performs a diagnostic check of the socket and VXI-11 functionality.
  /// Returns a list of diagnostic messages.
  Future<List<String>> testConnection({double timeoutSeconds = 5.0}) async {
    final results = <String>[];
    final timeout = Duration(milliseconds: (timeoutSeconds * 1000).round());

    results.add('Starting diagnostic for $_host...');

    // 1. Portmapper check
    results.add('Step 1: Connecting to Portmapper (port 111)...');
    Socket? pmSocket;
    try {
      pmSocket = await Socket.connect(_host, 111, timeout: timeout);
      results.add('SUCCESS: Portmapper reachable.');
      
      final pmRpc = RpcClient(pmSocket);
      final getportParams = XdrBuffer();
      getportParams.writeUint32(0x0607af); // prog
      getportParams.writeUint32(1);        // vers
      getportParams.writeUint32(6);        // prot = TCP
      getportParams.writeUint32(0);        // port = 0

      results.add('Step 2: Requesting VXI-11 port via RPC...');
      final reply = await pmRpc.call(
        program: 100000,
        version: 2,
        procedure: 3,
        params: getportParams.toBytes(),
        xid: _xidCounter++,
      ).timeout(timeout);

      final port = reply.readUint32();
      await pmRpc.close();
      pmSocket = null;

      if (port == 0) {
        results.add('FAILURE: Portmapper returned port 0. VXI-11 service might not be running.');
        return results;
      }
      results.add('SUCCESS: VXI-11 service found on port $port.');

      // 2. VXI-11 Service check
      results.add('Step 3: Connecting to VXI-11 service (port $port)...');
      Socket? vxiSocket;
      try {
        vxiSocket = await Socket.connect(_host, port, timeout: timeout);
        results.add('SUCCESS: VXI-11 service reachable.');
        
        final vxiRpc = RpcClient(vxiSocket);
        final createLinkParams = XdrBuffer();
        createLinkParams.writeInt32(0);
        createLinkParams.writeBool(false);
        createLinkParams.writeUint32(0);
        createLinkParams.writeString(_deviceName);

        results.add('Step 4: Creating VXI-11 link...');
        final createLinkReply = await vxiRpc.call(
          program: 0x0607af,
          version: 1,
          procedure: 10,
          params: createLinkParams.toBytes(),
          xid: _xidCounter++,
        ).timeout(timeout);

        final error = createLinkReply.readInt32();
        if (error != 0) {
          results.add('FAILURE: CREATE_LINK failed with error $error: ${_vxi11ErrorMessage(error)}');
        } else {
          results.add('SUCCESS: VXI-11 link established.');
          
          // Try a simple *IDN?
          results.add('Step 5: Testing basic SCPI (*IDN?)...');
          final linkId = createLinkReply.readInt32();
          
          // DEVICE_WRITE
          final writeParams = XdrBuffer();
          writeParams.writeInt32(linkId);
          writeParams.writeUint32(timeout.inMilliseconds);
          writeParams.writeUint32(0);
          writeParams.writeInt32(8);
          writeParams.writeOpaque(Uint8List.fromList(utf8.encode('*IDN?')));

          await vxiRpc.call(
            program: 0x0607af,
            version: 1,
            procedure: 11,
            params: writeParams.toBytes(),
            xid: _xidCounter++,
          ).timeout(timeout);

          // DEVICE_READ
          final readParams = XdrBuffer();
          readParams.writeInt32(linkId);
          readParams.writeUint32(256);
          readParams.writeUint32(timeout.inMilliseconds);
          readParams.writeUint32(0);
          readParams.writeInt32(0);
          readParams.writeInt32(0);

          final readReply = await vxiRpc.call(
            program: 0x0607af,
            version: 1,
            procedure: 12,
            params: readParams.toBytes(),
            xid: _xidCounter++,
          ).timeout(timeout);

          final readError = readReply.readInt32();
          if (readError != 0) {
            results.add('FAILURE: SCPI read failed with error $readError.');
          } else {
            readReply.readInt32(); // reason
            final idn = utf8.decode(readReply.readOpaque()).trim();
            results.add('SUCCESS: Device identified as: $idn');
          }

          // DESTROY_LINK
          final destroyParams = XdrBuffer();
          destroyParams.writeInt32(linkId);
          await vxiRpc.call(
            program: 0x0607af,
            version: 1,
            procedure: 23,
            params: destroyParams.toBytes(),
            xid: _xidCounter++,
          ).timeout(timeout);
        }
        await vxiRpc.close();
        vxiSocket = null;
      } catch (e) {
        results.add('FAILURE: VXI-11 service check failed: $e');
        vxiSocket?.destroy();
      }
    } catch (e) {
      results.add('FAILURE: Portmapper check failed: $e');
      pmSocket?.destroy();
    }

    results.add('Diagnostic complete.');
    return results;
  }

  /// Destroys the VXI-11 link and closes the socket.
  ///
  /// If not connected, this is a no-op.
  Future<void> close() async {
    if (_linkId != null) {
      // Encode DESTROY_LINK params: link_id(i32)
      final params = XdrBuffer();
      params.writeInt32(_linkId!);

      try {
        // Call DESTROY_LINK (procedure 23) on program 0x0607af, version 1.
        final reply = await _rpc!.call(
          program: 0x0607af,
          version: 1,
          procedure: 23,
          params: params.toBytes(),
          xid: _xidCounter++,
        );
        // Decode error (ignore it).
        reply.readInt32();
      } catch (_) {
        // Ignore errors during close.
      }

      _linkId = null;
    }

    if (_rpc != null) {
      await _rpc!.close();
      _rpc = null;
    }
  }

  /// Alias for [close]; destroys the link and releases resources.
  Future<void> destroy() => close();
}
