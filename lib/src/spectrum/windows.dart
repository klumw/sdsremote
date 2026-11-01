import 'dart:math' as math;
import 'dart:typed_data';

/// Window functions supported by the spectrum analysis.
enum SpectrumWindow { rectangular, hann, hamming, blackmanHarris, flatTop }

/// Precomputed coefficients and correction factors for one window and size.
class SpectrumWindowInfo {
  final SpectrumWindow window;
  final int size;
  final Float64List coefficients;

  /// Sum of all window coefficients, `Σ w[n]`.
  final double sum;

  /// Sum of the squared window coefficients, `Σ w[n]²`.
  final double sumSquares;

  /// Coherent gain, `Σ w[n] / N`. The amplitude correction is
  /// `1 / coherentGain`.
  final double coherentGain;

  /// Equivalent noise bandwidth in bins, `N·Σw² / (Σw)²`.
  final double enbwBins;

  /// Approximate full main-lobe width in bins.
  final int mainLobeBins;

  const SpectrumWindowInfo({
    required this.window,
    required this.size,
    required this.coefficients,
    required this.sum,
    required this.sumSquares,
    required this.coherentGain,
    required this.enbwBins,
    required this.mainLobeBins,
  });

  /// Half of the main-lobe width, used to integrate a component's power.
  int get halfMainLobeBins => (mainLobeBins + 1) ~/ 2;
}

final Map<SpectrumWindow, Map<int, SpectrumWindowInfo>> _windowCache = {};

/// Returns the coefficients and correction factors for [window] at [size].
///
/// Results are cached per window/size combination; callers must not modify
/// the returned [SpectrumWindowInfo.coefficients].
SpectrumWindowInfo buildWindow(SpectrumWindow window, int size) {
  if (size <= 0) {
    throw ArgumentError.value(size, 'size', 'must be positive');
  }
  final perWindow = _windowCache.putIfAbsent(window, () => {});
  final cached = perWindow[size];
  if (cached != null) return cached;

  final coefficients = Float64List(size);
  var sum = 0.0;
  var sumSquares = 0.0;
  for (var n = 0; n < size; n++) {
    final value = _coefficient(window, n, size);
    coefficients[n] = value;
    sum += value;
    sumSquares += value * value;
  }

  final info = SpectrumWindowInfo(
    window: window,
    size: size,
    coefficients: coefficients,
    sum: sum,
    sumSquares: sumSquares,
    coherentGain: sum / size,
    enbwBins: size * sumSquares / (sum * sum),
    mainLobeBins: _mainLobeBins(window),
  );
  perWindow[size] = info;
  return info;
}

double _coefficient(SpectrumWindow window, int n, int size) {
  if (size <= 1 || window == SpectrumWindow.rectangular) return 1.0;
  final x = 2.0 * math.pi * n / (size - 1);
  switch (window) {
    case SpectrumWindow.rectangular:
      return 1.0;
    case SpectrumWindow.hann:
      return 0.5 - 0.5 * math.cos(x);
    case SpectrumWindow.hamming:
      return 0.54 - 0.46 * math.cos(x);
    case SpectrumWindow.blackmanHarris:
      return 0.35875 -
          0.48829 * math.cos(x) +
          0.14128 * math.cos(2 * x) -
          0.01168 * math.cos(3 * x);
    case SpectrumWindow.flatTop:
      return 0.21557895 -
          0.41663158 * math.cos(x) +
          0.277263158 * math.cos(2 * x) -
          0.083578947 * math.cos(3 * x) +
          0.006947368 * math.cos(4 * x);
  }
}

int _mainLobeBins(SpectrumWindow window) {
  switch (window) {
    case SpectrumWindow.rectangular:
      return 2;
    case SpectrumWindow.hann:
      return 4;
    case SpectrumWindow.hamming:
      return 4;
    case SpectrumWindow.blackmanHarris:
      return 8;
    case SpectrumWindow.flatTop:
      return 10;
  }
}
