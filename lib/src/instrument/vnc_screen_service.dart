import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// A decoded frame from the instrument's built-in VNC server.
///
/// Pixels are RGBA8888, row-major, [width] × [height] × 4 bytes — the layout
/// Flutter's `ui.decodeImageFromPixels` expects.
class VncFrame {
  const VncFrame({
    required this.width,
    required this.height,
    required this.rgba,
  });

  final int width;
  final int height;
  final Uint8List rgba;
}

/// Reports a protocol or connection problem of [VncScreenService].
class VncScreenException implements Exception {
  const VncScreenException(this.message);

  final String message;

  @override
  String toString() => 'VncScreenException: $message';
}

typedef VncFrameCallback = void Function(VncFrame frame);
typedef VncClosedCallback = void Function(Object? error);

/// Minimal RFB (RFC 6143) client for the VNC server built into Siglent
/// SDS1000X-E oscilloscopes.
///
/// The server listens on TCP port 5900, requires no authentication and serves
/// an 800 × 480 RGB565 framebuffer. It is deliberately spoken to over raw TCP;
/// its dual-mode WebSocket support (used by the web UI) is not needed.
///
/// Protocol compatibility is fragile: the instrument's VNC daemon terminates
/// when a client omits the Cursor pseudo-encoding (-239) from SetEncodings.
/// [encodings] therefore mirrors the vendor noVNC client exactly and must be
/// sent unchanged.
class VncScreenService {
  VncScreenService({
    required this.host,
    this.port = 5900,
    this.onFrame,
    this.onClosed,
  });

  final String host;
  final int port;

  /// Called for every framebuffer update.
  final VncFrameCallback? onFrame;

  /// Called once when the session ends unexpectedly or [stop] was not the
  /// cause. Receives the underlying error, if any.
  final VncClosedCallback? onClosed;

  /// Vendor noVNC pixel format: 16 bpp RGB565, little endian.
  static const List<int> _pixelFormat = [
    0, 0, 0, 0, // message type 0 (SetPixelFormat), padding
    16, 16, 0, 1, // bits per pixel, depth, big endian, true colour
    0, 31, 0, 63, 0, 31, // max red, green, blue
    11, 5, 0, // shifts red, green, blue
    0, 0, 0, // padding
  ];

  /// Same encoding set as the vendor noVNC page, with Hextile first so the
  /// server sends compact updates. Cursor (-239) is mandatory: without it the
  /// instrument's VNC daemon crashes.
  static const List<int> encodings = [
    5, // Hextile
    2, // RRE
    0, // Raw
    1, // CopyRect
    7, // Tight (ignored by the server, kept for vendor parity)
    -260, // TightPNG pseudo-encoding
    -223, // DesktopSize pseudo-encoding
    -239, // Cursor pseudo-encoding (must not be removed)
    -26, // JPEG quality: medium
    -247, // Compression level: high
    -224, // LastRect pseudo-encoding
    -309, // xvp pseudo-encoding
  ];

  Socket? _socket;
  bool _running = false;
  bool _closing = false;
  bool _closedNotified = false;

  int _width = 0;
  int _height = 0;
  Uint16List? _framebuffer;

  bool get isRunning => _running;

  /// Checks whether a VNC server answers on [host]:[port].
  ///
  /// The probe only reads the RFB version banner and closes the socket again;
  /// it sends no encoding list, so it cannot destabilise the instrument's
  /// fragile VNC daemon.
  static Future<bool> isReachable(
    String host, {
    int port = 5900,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    Socket? socket;
    try {
      final connected = await Socket.connect(host, port, timeout: timeout);
      socket = connected;
      final banner = await _SocketReader(
        connected,
      ).readBytes(12).timeout(timeout);
      return String.fromCharCodes(banner).startsWith('RFB ');
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// Opens the session and pumps framebuffer updates until [stop] is called
  /// or the connection fails. Failures are reported through [onClosed].
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _closing = false;
    _closedNotified = false;
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 3),
      );
      if (!_running) {
        socket.destroy();
        return;
      }
      _socket = socket;
      socket.setOption(SocketOption.tcpNoDelay, true);
      final reader = _SocketReader(socket);

      await _handshake(reader, socket);
      await _pump(reader, socket);
    } catch (error) {
      if (!_closing) _notifyClosed(error);
    } finally {
      _running = false;
      _closing = false;
      _socket?.destroy();
      _socket = null;
    }
  }

  /// Ends the session without invoking [onClosed].
  void stop() {
    if (!_running && _socket == null) return;
    _closing = true;
    _running = false;
    _socket?.destroy();
    _socket = null;
  }

  void _notifyClosed(Object? error) {
    if (_closedNotified) return;
    _closedNotified = true;
    onClosed?.call(error);
  }

  Future<void> _handshake(_SocketReader reader, Socket socket) async {
    final banner = await reader.readBytes(12).timeout(
      const Duration(seconds: 5),
    );
    if (!String.fromCharCodes(banner).startsWith('RFB 003.')) {
      throw const VncScreenException('not an RFB server');
    }
    socket.add('RFB 003.008\n'.codeUnits);

    final securityTypeCount = await reader.readUint8().timeout(
      const Duration(seconds: 5),
    );
    if (securityTypeCount == 0) {
      final reasonLength = await reader.readUint32();
      final reason = await reader.readBytes(reasonLength);
      throw VncScreenException(
        'server refused connection: ${String.fromCharCodes(reason)}',
      );
    }
    final securityTypes = await reader.readBytes(securityTypeCount);
    if (!securityTypes.contains(1)) {
      throw VncScreenException(
        'unsupported security types ${securityTypes.toList()}',
      );
    }
    socket.add(const [1]); // security type None
    final securityResult = await reader.readUint32();
    if (securityResult != 0) {
      throw const VncScreenException('authentication failed');
    }

    socket.add(const [1]); // ClientInit, shared session
    final width = await reader.readUint16();
    final height = await reader.readUint16();
    await reader.readBytes(16); // server pixel format
    final nameLength = await reader.readUint32();
    await reader.readBytes(nameLength);

    if (width <= 0 || height <= 0 || width > 4096 || height > 4096) {
      throw VncScreenException('implausible framebuffer ${width}x$height');
    }
    _width = width;
    _height = height;
    _framebuffer = Uint16List(width * height);

    socket.add(_pixelFormat);
    socket.add(_encodingMessage());
  }

  static List<int> _encodingMessage() {
    final message = <int>[
      2,
      0,
      (encodings.length >> 8) & 0xFF,
      encodings.length & 0xFF,
    ];
    for (final encoding in encodings) {
      message.addAll([
        (encoding >> 24) & 0xFF,
        (encoding >> 16) & 0xFF,
        (encoding >> 8) & 0xFF,
        encoding & 0xFF,
      ]);
    }
    return message;
  }

  Future<void> _pump(_SocketReader reader, Socket socket) async {
    // Full update requests are answered even when the screen is static, which
    // keeps the timeout based liveness check below reliable. The server
    // serves them at roughly 10 fps, so no additional pacing is needed.
    _requestUpdate(socket);
    while (_running) {
      final messageType = await reader
          .readUint8()
          .timeout(const Duration(seconds: 6));
      switch (messageType) {
        case 0: // FramebufferUpdate
          await _readFramebufferUpdate(
            reader,
          ).timeout(const Duration(seconds: 6));
          _emitFrame();
          if (_running) _requestUpdate(socket);
          break;
        case 1: // SetColourMapEntries — unused for true colour servers
          await reader.readBytes(3);
          final count = await reader.readUint16();
          await reader.readBytes(count * 6);
          break;
        case 2: // Bell
          break;
        case 3: // ServerCutText
          await reader.readBytes(3);
          final length = await reader.readUint32();
          await reader.readBytes(length);
          break;
        default:
          throw VncScreenException('unexpected message type $messageType');
      }
    }
  }

  void _requestUpdate(Socket socket) {
    socket.add([
      3, // FramebufferUpdateRequest
      0, // incremental: request the full contents
      0, 0, 0, 0, // x, y
      (_width >> 8) & 0xFF, _width & 0xFF,
      (_height >> 8) & 0xFF, _height & 0xFF,
    ]);
  }

  Future<void> _readFramebufferUpdate(_SocketReader reader) async {
    await reader.readUint8(); // padding
    final rectCount = await reader.readUint16();
    for (var i = 0; i < rectCount; i++) {
      final x = await reader.readUint16();
      final y = await reader.readUint16();
      final width = await reader.readUint16();
      final height = await reader.readUint16();
      final encoding = await reader.readInt32();
      await _readRect(reader, x, y, width, height, encoding);
      if (!_running) return;
    }
  }

  Future<void> _readRect(
    _SocketReader reader,
    int x,
    int y,
    int width,
    int height,
    int encoding,
  ) async {
    final fb = _framebuffer;
    if (fb == null) throw const VncScreenException('framebuffer not ready');

    switch (encoding) {
      case 0: // Raw
        final data = await reader.readBytes(width * height * 2);
        for (var row = 0; row < height; row++) {
          final destination = (y + row) * _width + x;
          final source = row * width * 2;
          for (var column = 0; column < width; column++) {
            final offset = source + column * 2;
            fb[destination + column] = data[offset] | (data[offset + 1] << 8);
          }
        }
        break;
      case 1: // CopyRect
        final sourceX = await reader.readUint16();
        final sourceY = await reader.readUint16();
        for (var row = 0; row < height; row++) {
          final sourceRow = (sourceY + row) * _width + sourceX;
          final destinationRow = (y + row) * _width + x;
          for (var column = 0; column < width; column++) {
            fb[destinationRow + column] = fb[sourceRow + column];
          }
        }
        break;
      case 2: // RRE
        final background = await reader.readUint16LittleEndian();
        final subrectCount = await reader.readUint16();
        _fillRect(fb, x, y, width, height, background);
        for (var i = 0; i < subrectCount; i++) {
          final colour = await reader.readUint16LittleEndian();
          final subX = await reader.readUint16();
          final subY = await reader.readUint16();
          final subWidth = await reader.readUint16();
          final subHeight = await reader.readUint16();
          _fillRect(fb, x + subX, y + subY, subWidth, subHeight, colour);
        }
        break;
      case 5: // Hextile
        await _readHextile(reader, fb, x, y, width, height);
        break;
      case -239: // Cursor pseudo-encoding — not rendered
        final pixels = width * height * 2;
        final mask = ((width + 7) ~/ 8) * height;
        await reader.readBytes(pixels + mask);
        break;
      case -223: // DesktopSize
        if (width > 0 && height > 0 && width <= 4096 && height <= 4096) {
          _width = width;
          _height = height;
          _framebuffer = Uint16List(width * height);
        }
        break;
      case -224: // LastRect — marks the end of the update
        break;
      default:
        throw VncScreenException('unsupported rectangle encoding $encoding');
    }
  }

  Future<void> _readHextile(
    _SocketReader reader,
    Uint16List fb,
    int x,
    int y,
    int width,
    int height,
  ) async {
    var background = 0;
    var foreground = 0;
    for (var tileY = 0; tileY < height; tileY += 16) {
      for (var tileX = 0; tileX < width; tileX += 16) {
        final tileWidth = (16 < width - tileX) ? 16 : width - tileX;
        final tileHeight = (16 < height - tileY) ? 16 : height - tileY;
        final subencoding = await reader.readUint8();

        if ((subencoding & 0x01) != 0) {
          // Raw tile
          final data = await reader.readBytes(tileWidth * tileHeight * 2);
          for (var row = 0; row < tileHeight; row++) {
            final destination = (y + tileY + row) * _width + x + tileX;
            final source = row * tileWidth * 2;
            for (var column = 0; column < tileWidth; column++) {
              final offset = source + column * 2;
              fb[destination + column] =
                  data[offset] | (data[offset + 1] << 8);
            }
          }
          continue;
        }

        if ((subencoding & 0x02) != 0) {
          background = await reader.readUint16LittleEndian();
        }
        if ((subencoding & 0x04) != 0) {
          foreground = await reader.readUint16LittleEndian();
        }
        _fillRect(fb, x + tileX, y + tileY, tileWidth, tileHeight, background);

        if ((subencoding & 0x08) == 0) continue;
        final subrectCount = await reader.readUint8();
        for (var i = 0; i < subrectCount; i++) {
          final int colour;
          if ((subencoding & 0x10) != 0) {
            colour = await reader.readUint16LittleEndian();
          } else {
            colour = foreground;
          }
          final xy = await reader.readUint8();
          final wh = await reader.readUint8();
          final subX = xy >> 4;
          final subY = xy & 0x0F;
          final subWidth = (wh >> 4) + 1;
          final subHeight = (wh & 0x0F) + 1;
          _fillRect(
            fb,
            x + tileX + subX,
            y + tileY + subY,
            subWidth,
            subHeight,
            colour,
          );
        }
      }
    }
  }

  /// Fills a rectangle with an RGB565 colour, clipped to the framebuffer.
  void _fillRect(
    Uint16List fb,
    int x,
    int y,
    int width,
    int height,
    int colour,
  ) {
    final startX = x < 0 ? 0 : x;
    final startY = y < 0 ? 0 : y;
    final endX = (x + width > _width) ? _width : x + width;
    final endY = (y + height > _height) ? _height : y + height;
    for (var row = startY; row < endY; row++) {
      final offset = row * _width;
      for (var column = startX; column < endX; column++) {
        fb[offset + column] = colour;
      }
    }
  }

  void _emitFrame() {
    final fb = _framebuffer;
    if (fb == null || !_running) return;
    final rgba = Uint8List(_width * _height * 4);
    for (var i = 0, j = 0; i < fb.length; i++, j += 4) {
      final value = fb[i];
      final red = (value >> 11) & 0x1F;
      final green = (value >> 5) & 0x3F;
      final blue = value & 0x1F;
      rgba[j] = (red << 3) | (red >> 2);
      rgba[j + 1] = (green << 2) | (green >> 4);
      rgba[j + 2] = (blue << 3) | (blue >> 2);
      rgba[j + 3] = 0xFF;
    }
    onFrame?.call(VncFrame(width: _width, height: _height, rgba: rgba));
  }
}

/// Buffered reader over a socket stream.
class _SocketReader {
  _SocketReader(Socket socket) : _iterator = StreamIterator<Uint8List>(socket);

  final StreamIterator<Uint8List> _iterator;
  Uint8List _buffer = Uint8List(0);
  int _offset = 0;

  Future<Uint8List> readBytes(int count) async {
    await _ensure(count);
    final view = Uint8List.sublistView(_buffer, _offset, _offset + count);
    _offset += count;
    return view;
  }

  Future<int> readUint8() async => (await readBytes(1))[0];

  Future<int> readUint16() async {
    final bytes = await readBytes(2);
    return (bytes[0] << 8) | bytes[1];
  }

  Future<int> readUint16LittleEndian() async {
    final bytes = await readBytes(2);
    return bytes[0] | (bytes[1] << 8);
  }

  Future<int> readUint32() async {
    final bytes = await readBytes(4);
    return (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
  }

  Future<int> readInt32() async {
    final value = await readUint32();
    return value >= 0x80000000 ? value - 0x100000000 : value;
  }

  Future<void> _ensure(int count) async {
    if (_buffer.length - _offset >= count) return;
    if (_offset > 0) {
      _buffer = Uint8List.sublistView(_buffer, _offset);
      _offset = 0;
    }
    while (_buffer.length < count) {
      if (!await _iterator.moveNext()) {
        throw const VncScreenException('connection closed');
      }
      final chunk = _iterator.current;
      final merged = Uint8List(_buffer.length + chunk.length)
        ..setRange(0, _buffer.length, _buffer)
        ..setRange(_buffer.length, _buffer.length + chunk.length, chunk);
      _buffer = merged;
    }
  }
}
