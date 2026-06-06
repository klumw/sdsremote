import 'dart:typed_data';

/// Converts raw oscilloscope data bytes into physical units (voltage and time).
/// All methods are pure functions with no side effects.
class WaveformConverter {
  /// Converts a raw data byte to a signed code_wert.
  /// code_wert = byte <= 127 ? byte : byte - 255
  static int toCodeWert(int byte) => byte <= 127 ? byte : byte - 255;

  /// Calculates voltage: voltage = code_wert * (vdiv / 25) + voffset
  static double toVoltage(int byte, double vdiv, double voffset) =>
      toCodeWert(byte) * (vdiv / 25) + voffset;

  /// Converts an entire byte array to voltage values.
  static List<double> convertVoltages(
    Uint8List raw,
    double vdiv,
    double voffset,
  ) => raw.map((b) => toVoltage(b, vdiv, voffset)).toList();

  /// Calculates the time axis for [count] data points.
  ///
  /// Time values are relative to the trigger event (t = 0 at trigger).
  /// With WFSU FP=0, data starts from acquisition memory index 0, so the
  /// trigger position within that memory is needed to compute the correct
  /// offset:
  ///
  ///   T(n) = (n - triggerPosition) / sampleRate + trdl
  ///
  /// When [triggerPosition] is 0 (e.g. SANU? unavailable), falls back to
  /// the display-centric formula: T(n) = trdl - timebase*14/2 + n/sampleRate.
  static List<double> computeTimeAxis(
    int count,
    double trdl,
    double timebase,
    double sampleRate, {
    int triggerPosition = 0,
  }) {
    // Prefer the trigger-position-aware axis when the instrument provided
    // a valid `triggerPosition`. This yields physically-correct sample
    // timestamps using the reported `sampleRate` and preserves actual
    // waveform timing (important for measurements and matching the
    // instrument's on-screen waveform).
    if (triggerPosition > 0) {
      final dt = 1 / sampleRate;
      final double tStart = -(triggerPosition) / sampleRate + trdl;
      return List.generate(count, (n) => tStart + n * dt);
    }

    // Fallback: if triggerPosition is unavailable, generate a display-
    // aligned axis spanning `timebase * 14` so the waveform fills the
    // graticule like the instrument display.
    final double displaySpan = timebase * 14.0;
    final double tStart = trdl - displaySpan / 2.0;
    final double dt = displaySpan / (count > 1 ? (count - 1) : 1);
    return List.generate(count, (n) => tStart + n * dt);
  }

  /// Combines time and voltage values into a list of (time, voltage) pairs.
  static List<(double time, double voltage)> combine(
    List<double> times,
    List<double> voltages,
  ) {
    final len = times.length < voltages.length ? times.length : voltages.length;
    return List.generate(len, (i) => (times[i], voltages[i]));
  }
}
