import 'dart:ui' show Offset;

import 'reference_timing.dart';
import 'waveform_compare.dart';
import 'waveform_csv_parser.dart';
import 'waveform_mask.dart';
import 'waveform_measurements.dart';
import 'waveform_models.dart';

/// Owns the loaded reference waveform, its timing metadata, and the derived
/// difference/mask analysis.
///
/// The file-picker, dialogs, and drag gestures stay in the home page; this
/// controller holds the reference state and computes the analysis from the
/// live waveform supplied through callbacks.
class ReferenceWaveformController {
  ReferenceWaveformController({
    required this.liveWaveformForChannel,
    required this.deviceParams,
    required this.acquiredMeasurements,
    required this.triggerSourceChannel,
  });

  /// Returns the live waveform of the given channel, if acquired.
  final WaveformData? Function(String channel) liveWaveformForChannel;

  /// Returns the device parameters of the current acquisition.
  final DeviceParams? Function() deviceParams;

  /// Returns all acquired measurements, regardless of channel toggles.
  final Map<String, WaveformMeasurements> Function() acquiredMeasurements;

  /// Returns the analog trigger source channel, or null.
  final String? Function() triggerSourceChannel;

  WaveformData? refWaveform;
  bool refVisible = false;
  String? refFileName;
  String? refChannelOrigin;
  WaveformCsvMetadata? refMetadata;
  double? refVdivVolts;
  double? refOffsetVolts;
  ReferenceOffset refOffset = const ReferenceOffset();
  bool refMoving = false;
  bool draggingRef = false;
  ReferenceOffset refDragAnchor = const ReferenceOffset();
  Offset refDragOriginPx = Offset.zero;
  String? dismissedReferenceTimingWarning;
  WaveformMeasurements? refMeasurements;

  bool diffVisible = false;
  WaveformData? diffTrace;
  ComparisonMetrics? comparison;
  MaskSettings maskSettings = defaultMaskSettings;
  MaskBand? maskBand;
  MaskResult? maskResult;

  double _referenceVppCache = 0;
  double _referenceDurationCache = 0;

  /// Live waveform belonging to the loaded reference channel.
  WaveformData? liveWaveform() {
    final origin = refChannelOrigin;
    return origin == null ? null : liveWaveformForChannel(origin);
  }

  double get referenceVpp => _referenceVppCache;

  double get referenceDurationSeconds => _referenceDurationCache;

  /// Timing settings in which the loaded reference differs from the current
  /// instrument settings. Empty when the reference has no timing metadata or
  /// all values match.
  List<ReferenceTimingMismatch> timingMismatches() {
    final metadata = refMetadata;
    final params = deviceParams();
    if (metadata == null || params == null || refWaveform == null) {
      return const [];
    }
    return compareReferenceTiming(
      reference: metadata,
      currentTimebase: params.timebase,
      currentTriggerDelay: params.trdl,
      currentSampleRate: params.sampleRate,
    );
  }

  /// Stable signature of one reference timing warning, used to keep a
  /// dismissed banner hidden until the warning content changes.
  String timingWarningSignature(List<ReferenceTimingMismatch> mismatches) =>
      mismatches
          .map(
            (mismatch) =>
                '${mismatch.field.name}:'
                '${mismatch.referenceValue}:${mismatch.currentValue}',
          )
          .join('|');

  /// Hint shown in the reference section when the loaded file carries no
  /// timing metadata, so a comparison is impossible.
  String? get timingNote {
    if (refWaveform == null || refMetadata?.hasTiming == true) return null;
    return 'Timing metadata is missing in this reference file. Timebase, '
        'trigger delay and sample rate cannot be compared.';
  }

  /// Recomputes the cached reference geometry and measurements after a
  /// reference change.
  void cacheGeometry() {
    final points = refWaveform?.points;
    if (points == null || points.isEmpty) {
      _referenceVppCache = 0;
      _referenceDurationCache = 0;
      refMeasurements = null;
      refMetadata = null;
      refVdivVolts = null;
      refOffsetVolts = null;
      return;
    }
    var min = double.infinity;
    var max = -double.infinity;
    for (final (_, voltage) in points) {
      if (voltage < min) min = voltage;
      if (voltage > max) max = voltage;
    }
    _referenceVppCache = max - min;
    _referenceDurationCache = points.length < 2
        ? 0
        : points.last.$1 - points.first.$1;
    // The reference is measured exactly as loaded. The manual alignment
    // offset only moves the drawn trace and does not change its shape, so it
    // is deliberately not applied here.
    refMeasurements = measureWaveform(channel: 'ref', points: points);
  }

  /// Measurement of the trigger source channel, or null when unavailable.
  WaveformMeasurements? get triggerSourceMeasurement {
    final channel = triggerSourceChannel();
    if (channel == null) return null;
    return acquiredMeasurements()[channel];
  }

  /// Period of the trigger source signal, or null when it cannot be measured.
  double? triggerSourcePeriod() {
    final measurement = triggerSourceMeasurement;
    if (measurement == null) return null;
    final period = measurement.periodSeconds;
    if (period != null && period.isFinite && period > 0) return period;
    final frequency = measurement.frequencyHz;
    if (frequency != null && frequency.isFinite && frequency > 0) {
      return 1 / frequency;
    }
    return null;
  }

  /// Whether the parameters, reference, and live waveform needed for the
  /// difference/mask analysis are available.
  bool get hasAnalysisInputs {
    final params = deviceParams();
    final reference = refWaveform;
    final live = liveWaveform();
    return params != null &&
        reference != null &&
        reference.points.isNotEmpty &&
        live != null &&
        live.points.isNotEmpty;
  }

  /// Whether any analysis result is currently stored.
  bool get hasAnalysisResults =>
      diffTrace != null ||
      comparison != null ||
      maskBand != null ||
      maskResult != null;

  /// Clears the difference trace, deviation metrics, and mask result.
  void clearAnalysis() {
    diffTrace = null;
    comparison = null;
    maskBand = null;
    maskResult = null;
  }

  /// Recomputes difference trace, deviation metrics and the mask test.
  ///
  /// The result only covers the live points that the (shifted) reference
  /// actually spans. Callers must check [hasAnalysisInputs] first.
  void computeAnalysis() {
    final params = deviceParams()!;
    final reference = refWaveform!;
    final live = liveWaveform()!;

    final referenceVdiv = params.vdivFor(refChannelOrigin) ?? 1.0;
    final trace = differenceTrace(
      live: live.points,
      reference: reference.points,
      offset: refOffset,
      timebase: params.timebase,
      referenceVdiv: referenceVdiv,
    );
    final metrics = comparisonMetrics(
      live: live.points,
      reference: reference.points,
      offset: refOffset,
      timebase: params.timebase,
      referenceVdiv: referenceVdiv,
    );

    MaskBand? band;
    MaskResult? result;
    if (maskSettings.enabled) {
      final shifted = shiftReference(
        reference.points,
        offset: refOffset,
        timebase: params.timebase,
        referenceVdiv: referenceVdiv,
      );
      final toleranceVolts = maskSettings.usePercent
          ? referenceVpp * maskSettings.toleranceValue / 100
          : maskSettings.toleranceValue;
      band = buildMaskBand(
        shifted,
        toleranceVolts: toleranceVolts,
        toleranceTime: maskSettings.timeToleranceSeconds > 0
            ? maskSettings.timeToleranceSeconds
            : null,
      );
      result = evaluateMask(live.points, band);
    }

    diffTrace = WaveformData(points: trace);
    comparison = metrics;
    maskBand = band;
    maskResult = result;
  }
}
