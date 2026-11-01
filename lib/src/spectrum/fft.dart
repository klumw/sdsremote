import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Real-input FFT backed by fftea.
///
/// Returns the squared magnitudes `|X[k]|²` of the unnormalised DFT for the
/// single-sided bins `k = 0..N/2`. Callers apply the window coherent-gain or
/// power normalisation themselves.
class SpectrumFft {
  final FFT _fft;

  SpectrumFft(int size) : _fft = FFT(size);

  int get size => _fft.size;

  /// Transforms [samples] (length `N`) and returns `|X[k]|²` for
  /// `k = 0..N/2`.
  Float64List squaredMagnitudes(Float64List samples) {
    if (samples.length != _fft.size) {
      throw ArgumentError.value(
        samples.length,
        'samples',
        'must match the FFT size ${_fft.size}',
      );
    }
    final complex = _fft.realFft(samples);
    final full = complex.squareMagnitudes();
    return Float64List.fromList(full.sublist(0, _fft.size ~/ 2 + 1));
  }
}
