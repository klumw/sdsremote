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
  /// T_start = trdl - timebase * 14 / 2
  /// dt = 1 / sampleRate
  /// T(n) = T_start + n * dt
  static List<double> computeTimeAxis(
    int count,
    double trdl,
    double timebase,
    double sampleRate,
  ) {
    final tStart = trdl - timebase * 14 / 2;
    final dt = 1 / sampleRate;
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
