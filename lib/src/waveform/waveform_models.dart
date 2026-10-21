import 'dart:typed_data';
import 'dart:ui' show Color, Offset;

/// Plot colours of CH1–CH4, shared by the waveform painter, the Device
/// Parameters panel and the reference dialog.
const List<Color> waveformChannelColors = [
  Color(0xFFFFEB3B), // CH1 — yellow
  Color(0xFFFF20FF), // CH2 — magenta
  Color(0xFF4FC3F7), // CH3 — light blue
  Color(0xFF66BB6A), // CH4 — green
];

/// Plot colour for a channel name (`'ch1'` … `'ch4'`).
Color waveformChannelColor(String channel) => switch (channel) {
  'ch1' => waveformChannelColors[0],
  'ch2' => waveformChannelColors[1],
  'ch3' => waveformChannelColors[2],
  'ch4' => waveformChannelColors[3],
  _ => const Color(0xFFFFFFFF),
};

/// Raw data directly after acquisition (before conversion)
class WaveformRawData {
  final Uint8List? ch1Raw; // null if channel not active
  final Uint8List? ch2Raw;
  final Uint8List? ch3Raw;
  final Uint8List? ch4Raw;
  final double? vdivCh1;
  final double? voffsetCh1;
  final double? vdivCh2;
  final double? voffsetCh2;
  final double? vdivCh3;
  final double? voffsetCh3;
  final double? vdivCh4;
  final double? voffsetCh4;
  final double timebase; // TDIV in seconds
  final double trdl; // Trigger delay in seconds
  final double sampleRate; // SARA in Sa/s
  final int triggerPosition; // Sample index of trigger in acquisition memory

  const WaveformRawData({
    this.ch1Raw,
    this.ch2Raw,
    this.ch3Raw,
    this.ch4Raw,
    this.vdivCh1,
    this.voffsetCh1,
    this.vdivCh2,
    this.voffsetCh2,
    this.vdivCh3,
    this.voffsetCh3,
    this.vdivCh4,
    this.voffsetCh4,
    required this.timebase,
    required this.trdl,
    required this.sampleRate,
    this.triggerPosition = 0,
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
  final double? vdivCh3;
  final double? voffsetCh3;
  final double? vdivCh4;
  final double? voffsetCh4;
  final double timebase;
  final double trdl;
  final double sampleRate;

  const DeviceParams({
    this.vdivCh1,
    this.voffsetCh1,
    this.vdivCh2,
    this.voffsetCh2,
    this.vdivCh3,
    this.voffsetCh3,
    this.vdivCh4,
    this.voffsetCh4,
    required this.timebase,
    required this.trdl,
    required this.sampleRate,
  });

  /// V/div of [channel] (`'ch1'` … `'ch4'`), or null when it was not
  /// acquired.
  double? vdivFor(String? channel) => switch (channel) {
    'ch1' => vdivCh1,
    'ch2' => vdivCh2,
    'ch3' => vdivCh3,
    'ch4' => vdivCh4,
    _ => null,
  };

  /// Vertical offset of [channel] (`'ch1'` … `'ch4'`), or null when it was
  /// not acquired.
  double? voffsetFor(String? channel) => switch (channel) {
    'ch1' => voffsetCh1,
    'ch2' => voffsetCh2,
    'ch3' => voffsetCh3,
    'ch4' => voffsetCh4,
    _ => null,
  };
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

/// Manual alignment offset of the loaded reference waveform, expressed in
/// oscilloscope divisions.
///
/// One division is [DeviceParams.timebase] seconds horizontally and the V/div
/// of the channel the reference was loaded from vertically — the same
/// division the graticule shows at zoom 1.0. Because the offset is stored in
/// divisions rather than in seconds/volts it reads the way the user counts on
/// the grid, and because it is kept next to the reference instead of being
/// added to its points, it can be reset and read out, and repeated dragging
/// cannot accumulate rounding errors in the data.
class ReferenceOffset {
  /// Horizontal shift in divisions; positive moves the reference to the
  /// right, i.e. to a later time.
  final double dxDiv;

  /// Vertical shift in divisions; positive moves the reference up, i.e. to a
  /// higher voltage.
  final double dyDiv;

  const ReferenceOffset({this.dxDiv = 0.0, this.dyDiv = 0.0});

  bool get isZero => dxDiv == 0.0 && dyDiv == 0.0;

  /// Horizontal shift in seconds at the given horizontal scale (s/div).
  double timeShiftSeconds(double timebase) => dxDiv * timebase;

  /// Vertical shift in volts at the given vertical scale (V/div).
  double voltageShiftVolts(double vdiv) => dyDiv * vdiv;

  ReferenceOffset copyWith({double? dxDiv, double? dyDiv}) {
    return ReferenceOffset(
      dxDiv: dxDiv ?? this.dxDiv,
      dyDiv: dyDiv ?? this.dyDiv,
    );
  }

  /// Both components rounded to the nearest multiple of [stepDiv] — the
  /// "snap to grid" used while dragging with Shift held. The step is passed
  /// in because the grid the user sees shrinks with the zoom factor.
  ReferenceOffset snappedTo(double stepDiv) {
    if (stepDiv <= 0) return this;
    return ReferenceOffset(
      dxDiv: (dxDiv / stepDiv).roundToDouble() * stepDiv,
      dyDiv: (dyDiv / stepDiv).roundToDouble() * stepDiv,
    );
  }

  /// Both components limited to ±[maxDivX] and ±[maxDivY], so that the
  /// reference cannot be dragged out of reach.
  ReferenceOffset clampedTo({
    required double maxDivX,
    required double maxDivY,
  }) {
    return ReferenceOffset(
      dxDiv: dxDiv.clamp(-maxDivX, maxDivX),
      dyDiv: dyDiv.clamp(-maxDivY, maxDivY),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReferenceOffset &&
      other.dxDiv == dxDiv &&
      other.dyDiv == dyDiv;

  @override
  int get hashCode => Object.hash(dxDiv, dyDiv);

  @override
  String toString() =>
      'ReferenceOffset(${dxDiv.toStringAsFixed(2)} div, '
      '${dyDiv.toStringAsFixed(2)} div)';
}

/// Formats one component of a [ReferenceOffset] for display, e.g. `+0.20 div`.
String formatOffsetDivisions(double div) {
  // Keep a component that rounds away to zero from showing up as "-0.00".
  final value = div.abs() < 0.005 ? 0.0 : div;
  return '${value > 0 ? '+' : ''}${value.toStringAsFixed(2)} div';
}

/// State for waveform zoom and pan.
///
/// [zoomFactor] ranges from 1.0 (no zoom) to 4.0 (maximum magnification).
/// [panX] and [panY] range from 0.0 to 1.0, with 0.5 being the center.
class ZoomState {
  final double zoomFactor;
  final double panX;
  final double panY;

  const ZoomState({this.zoomFactor = 1.0, this.panX = 0.5, this.panY = 0.5});

  ZoomState copyWith({double? zoomFactor, double? panX, double? panY}) {
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
