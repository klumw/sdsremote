/// Horizontal frequency viewport of the spectrum chart.
///
/// The viewport is stored as a zoom factor and a normalised centre position so
/// it survives channel changes, FFT-size changes and switching between linear
/// and logarithmic frequency axes.
library;

import 'dart:math' as math;

import 'spectrum_models.dart';

/// Full frequency range of a set of spectrum traces.
class SpectrumAxisRange {
  /// Lowest displayed frequency (0 for a linear axis, the first positive bin
  /// for a logarithmic axis).
  final double min;

  /// Highest displayed frequency (Nyquist of the widest trace).
  final double max;

  /// Whether the axis is logarithmic.
  final bool log;

  const SpectrumAxisRange({
    required this.min,
    required this.max,
    required this.log,
  });

  bool get isValid => min.isFinite && max.isFinite && max > min;
}

/// Computes the full frequency axis of [traces].
SpectrumAxisRange spectrumAxisRange(
  List<SpectrumTrace> traces,
  bool logFrequency,
) {
  if (traces.isEmpty) {
    return const SpectrumAxisRange(min: 0, max: 0, log: false);
  }
  var nyquist = 0.0;
  var minPositive = double.infinity;
  for (final trace in traces) {
    final traceNyquist = trace.sampleRate / 2;
    if (traceNyquist.isFinite && traceNyquist > nyquist) {
      nyquist = traceNyquist;
    }
    for (final frequency in trace.frequenciesHz) {
      if (frequency.isFinite && frequency > 0 && frequency < minPositive) {
        minPositive = frequency;
      }
    }
  }
  final useLog =
      logFrequency &&
      minPositive.isFinite &&
      minPositive > 0 &&
      nyquist > minPositive;
  return SpectrumAxisRange(
    min: useLog ? minPositive : 0.0,
    max: nyquist,
    log: useLog,
  );
}

/// Zoom and pan state of the spectrum's horizontal frequency axis.
class SpectrumViewport {
  static const double minZoom = 1;
  static const double maxZoom = 1000;

  /// Visible fraction of the full axis is `1 / zoom`.
  final double zoom;

  /// Centre of the visible range as a fraction of the full axis (0..1).
  final double centerFraction;

  const SpectrumViewport({this.zoom = minZoom, this.centerFraction = 0.5});

  bool get isZoomed => zoom > minZoom + 1e-6;

  /// Label for the zoom controls, e.g. `2.0x`.
  String get zoomLabel {
    if (zoom < 10) return '${zoom.toStringAsFixed(1)}x';
    return '${zoom.toStringAsFixed(0)}x';
  }

  /// Returns the visible `(min, max)` frequencies.
  (double, double) visibleRange({
    required double fullMin,
    required double fullMax,
    required bool log,
  }) {
    if (!fullMin.isFinite || !fullMax.isFinite || fullMax <= fullMin) {
      return (fullMin, fullMax);
    }
    final effectiveZoom = zoom.clamp(minZoom, maxZoom).toDouble();
    final half = 0.5 / effectiveZoom;
    final center = centerFraction.clamp(half, 1 - half);
    if (log && fullMin > 0) {
      final logMin = math.log(fullMin);
      final logMax = math.log(fullMax);
      final logSpan = logMax - logMin;
      final logCenter = logMin + center * logSpan;
      final logHalf = logSpan * half;
      return (math.exp(logCenter - logHalf), math.exp(logCenter + logHalf));
    }
    final span = fullMax - fullMin;
    final centerFrequency = fullMin + center * span;
    final halfSpan = span * half;
    return (
      math.max(fullMin, centerFrequency - halfSpan),
      math.min(fullMax, centerFrequency + halfSpan),
    );
  }

  /// Zooms by [factor] around the current centre.
  SpectrumViewport zoomBy(double factor) {
    if (!factor.isFinite || factor <= 0) return this;
    final newZoom = (zoom * factor).clamp(minZoom, maxZoom).toDouble();
    return SpectrumViewport(
      zoom: newZoom,
      centerFraction: _clampCenter(centerFraction, newZoom),
    );
  }

  /// Zooms to [newZoom] while keeping the frequency at [fraction] (0 = left
  /// edge, 1 = right edge of the plot) under the pointer.
  SpectrumViewport zoomAt({
    required double newZoom,
    required double fraction,
    required double fullMin,
    required double fullMax,
    required bool log,
  }) {
    if (!newZoom.isFinite ||
        newZoom <= 0 ||
        fullMax <= fullMin ||
        !fullMin.isFinite ||
        !fullMax.isFinite) {
      return this;
    }
    final targetZoom = newZoom.clamp(minZoom, maxZoom).toDouble();
    final anchor = fraction.clamp(0.0, 1.0);
    final (visibleMin, visibleMax) = visibleRange(
      fullMin: fullMin,
      fullMax: fullMax,
      log: log,
    );
    double newCenter;
    if (log && fullMin > 0 && visibleMin > 0) {
      final logMin = math.log(fullMin);
      final logMax = math.log(fullMax);
      final logSpan = logMax - logMin;
      final logVisibleMin = math.log(visibleMin);
      final logVisibleMax = math.log(visibleMax);
      final logAnchor =
          logVisibleMin + anchor * (logVisibleMax - logVisibleMin);
      final logNewCenter = logAnchor + (0.5 - anchor) * logSpan / targetZoom;
      newCenter = (logNewCenter - logMin) / logSpan;
    } else {
      final anchorFrequency = visibleMin + anchor * (visibleMax - visibleMin);
      final newSpan = (fullMax - fullMin) / targetZoom;
      final centerFrequency = anchorFrequency + (0.5 - anchor) * newSpan;
      newCenter = (centerFrequency - fullMin) / (fullMax - fullMin);
    }
    return SpectrumViewport(
      zoom: targetZoom,
      centerFraction: _clampCenter(newCenter, targetZoom),
    );
  }

  /// Pans by [visibleFractionDelta] of the visible width.
  ///
  /// A positive value moves the visible window towards higher frequencies.
  SpectrumViewport panBy(double visibleFractionDelta) {
    if (!visibleFractionDelta.isFinite || !isZoomed) return this;
    final newCenter = centerFraction + visibleFractionDelta / zoom;
    return SpectrumViewport(
      zoom: zoom,
      centerFraction: _clampCenter(newCenter, zoom),
    );
  }

  SpectrumViewport reset() => const SpectrumViewport();

  static double _clampCenter(double center, double zoom) {
    final half = 0.5 / zoom.clamp(minZoom, maxZoom);
    return center.clamp(half, 1 - half).toDouble();
  }

  @override
  bool operator ==(Object other) =>
      other is SpectrumViewport &&
      other.zoom == zoom &&
      other.centerFraction == centerFraction;

  @override
  int get hashCode => Object.hash(zoom, centerFraction);
}
