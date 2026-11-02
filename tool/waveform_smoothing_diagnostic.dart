// Diagnostic: how the waveform raster smoothing changes a rendered sine.
//
//   dart run tool/waveform_smoothing_diagnostic.dart
//
// Reproduces WaveformTrace.build's resample + smooth pipeline for a dense
// sine (about 21 periods across the display) and reports the peak error and
// the width of the flat top for different smoothing widths / step limits.

// ignore_for_file: avoid_print

import 'dart:math' as math;

import 'package:sdsremote/src/waveform/waveform_interpolation.dart';

const double _width = 900;
const double _height = 510;
const double _frequency = 3007.311;
const double _duration = 0.007;
const double _sampleRate = 1e6;
const double _amplitude = 2.58;
const double _vdiv = 1.0;
const double _visibleVMin = -4;
const double _visibleVMax = 4;

void main() {
  final count = (_duration * _sampleRate).round();
  final points = <(double, double)>[
    for (var i = 0; i < count; i++)
      (
        i / _sampleRate,
        _amplitude * math.sin(2 * math.pi * _frequency * i / _sampleRate),
      ),
  ];

  final resampled = WaveformInterpolation.resample(
    count: points.length,
    columns: _width.round(),
    xAt: (i) => points[i].$1 / _duration * _width,
    yAt: (i) =>
        (_visibleVMax - points[i].$2) / (_visibleVMax - _visibleVMin) * _height,
  );
  final truePeakY =
      (_visibleVMax - _amplitude) / (_visibleVMax - _visibleVMin) * _height;
  final trueBottomY =
      (_visibleVMax + _amplitude) / (_visibleVMax - _visibleVMin) * _height;
  print(
    'true peak y=${truePeakY.toStringAsFixed(2)} '
    'bottom y=${trueBottomY.toStringAsFixed(2)}',
  );

  final adcStepPx = (_vdiv / 25.0) / (_visibleVMax - _visibleVMin) * _height;
  print('adc step=${adcStepPx.toStringAsFixed(2)} px');

  void report(String label, double smoothingWidth, double maxSteps) {
    final smoothed = smoothingWidth <= 0
        ? resampled
        : WaveformInterpolation.smooth(
            resampled,
            smoothingWidth: smoothingWidth,
            maxStep: adcStepPx * maxSteps,
          );
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (var i = 1; i < smoothed.length; i += 2) {
      if (smoothed[i] < minY) minY = smoothed[i];
      if (smoothed[i] > maxY) maxY = smoothed[i];
    }
    var longestFlat = 0;
    var currentFlat = 1;
    for (var i = 3; i < smoothed.length; i += 2) {
      if ((smoothed[i] - smoothed[i - 2]).abs() < 0.5) {
        currentFlat++;
        if (currentFlat > longestFlat) longestFlat = currentFlat;
      } else {
        currentFlat = 1;
      }
    }
    print(
      '$label width=$smoothingWidth maxSteps=$maxSteps '
      'peak=${minY.toStringAsFixed(2)} '
      '(err ${(minY - truePeakY).toStringAsFixed(2)} px) '
      'bottom=${maxY.toStringAsFixed(2)} '
      'longestFlat=${longestFlat}px',
    );
  }

  report('none', 0, 0);
  for (final width in const [2.0, 4.0, 6.0, 8.0, 10.0, 14.0]) {
    for (final steps in const [1.0, 2.0, 3.0, 6.0, double.infinity]) {
      report('smooth', width, steps);
    }
  }
}
