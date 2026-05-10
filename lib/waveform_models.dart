import 'dart:typed_data';
import 'dart:ui' show Offset;

/// Raw data directly after acquisition (before conversion)
class WaveformRawData {
  final Uint8List? ch1Raw; // null if channel not active
  final Uint8List? ch2Raw;
  final double? vdivCh1;
  final double? voffsetCh1;
  final double? vdivCh2;
  final double? voffsetCh2;
  final double timebase; // TDIV in seconds
  final double trdl; // Trigger delay in seconds
  final double sampleRate; // SARA in Sa/s

  const WaveformRawData({
    this.ch1Raw,
    this.ch2Raw,
    this.vdivCh1,
    this.voffsetCh1,
    this.vdivCh2,
    this.voffsetCh2,
    required this.timebase,
    required this.trdl,
    required this.sampleRate,
  });
}

/// Converted waveform data for a single channel
class WaveformData {
  final List<(double time, double voltage)> points;

  const WaveformData({required this.points});
}

/// Device parameters for display in the right panel
class DeviceParams {
  final double? vdivCh1;
  final double? voffsetCh1;
  final double? vdivCh2;
  final double? voffsetCh2;
  final double timebase;
  final double trdl;
  final double sampleRate;

  const DeviceParams({
    this.vdivCh1,
    this.voffsetCh1,
    this.vdivCh2,
    this.voffsetCh2,
    required this.timebase,
    required this.trdl,
    required this.sampleRate,
  });
}

/// State for cursor display and positions.
///
/// Positions are stored as relative values (0.0 – 1.0) within the waveform
/// display area. 0.0 = left/bottom edge, 1.0 = right/top edge.
class CursorState {
  final bool cursorsXEnabled;
  final bool cursorsYEnabled;
  final double cursorX1;
  final double cursorX2;
  final double cursorY1;
  final double cursorY2;
  final Offset cursorInfoOffset;

  const CursorState({
    this.cursorsXEnabled = false,
    this.cursorsYEnabled = false,
    this.cursorX1 = 0.25,
    this.cursorX2 = 0.75,
    this.cursorY1 = 0.25,
    this.cursorY2 = 0.75,
    this.cursorInfoOffset = const Offset(0, 0),
  });

  CursorState copyWith({
    bool? cursorsXEnabled,
    bool? cursorsYEnabled,
    double? cursorX1,
    double? cursorX2,
    double? cursorY1,
    double? cursorY2,
    Offset? cursorInfoOffset,
  }) {
    return CursorState(
      cursorsXEnabled: cursorsXEnabled ?? this.cursorsXEnabled,
      cursorsYEnabled: cursorsYEnabled ?? this.cursorsYEnabled,
      cursorX1: cursorX1 ?? this.cursorX1,
      cursorX2: cursorX2 ?? this.cursorX2,
      cursorY1: cursorY1 ?? this.cursorY1,
      cursorY2: cursorY2 ?? this.cursorY2,
      cursorInfoOffset: cursorInfoOffset ?? this.cursorInfoOffset,
    );
  }
}

/// State for waveform zoom and pan.
///
/// [zoomFactor] ranges from 1.0 (no zoom) to 4.0 (maximum magnification).
/// [panX] and [panY] range from 0.0 to 1.0, with 0.5 being the center.
class ZoomState {
  final double zoomFactor;
  final double panX;
  final double panY;

  const ZoomState({
    this.zoomFactor = 1.0,
    this.panX = 0.5,
    this.panY = 0.5,
  });

  ZoomState copyWith({
    double? zoomFactor,
    double? panX,
    double? panY,
  }) {
    return ZoomState(
      zoomFactor: zoomFactor ?? this.zoomFactor,
      panX: panX ?? this.panX,
      panY: panY ?? this.panY,
    );
  }
}

/// Error type for acquisition errors
class AcquisitionException implements Exception {
  final String command; // affected SCPI command
  final String reason; // error reason

  const AcquisitionException(this.command, this.reason);

  @override
  String toString() => 'AcquisitionException: $command – $reason';
}
