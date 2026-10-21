/// Pure math and validation for the Bode Plot.
library;

import 'dart:math' as math;

import '../data_logger/data_logger_models.dart' show computeGainDb;
import '../signal_generator/fy6900_protocol.dart';
import '../signal_generator/jds6600_protocol.dart';
import '../signal_generator/models.dart';
import 'bode_models.dart';

/// Below this input RMS voltage the gain ratio is dominated by the scope's
/// noise floor and quantisation.
const double bodeMinVinRms = 0.001;

/// Below this RMS voltage on either channel no measurement point is plotted.
const double bodeMinPlotVoltageRms = 0.005;

/// Returns a note when Vin or Vout is below [bodeMinPlotVoltageRms], or null
/// when both channels carry a usable voltage.
///
/// Missing values are not treated as "below"; they are already handled as
/// invalid measurements elsewhere.
String? bodeBelowThresholdNote(double? vinRms, double? voutRms) {
  final vinLow = vinRms != null && vinRms < bodeMinPlotVoltageRms;
  final voutLow = voutRms != null && voutRms < bodeMinPlotVoltageRms;
  if (vinLow && voutLow) return 'Vin and Vout below 5 mV';
  if (vinLow) return 'Vin below 5 mV';
  if (voutLow) return 'Vout below 5 mV';
  return null;
}

/// Builds the frequency points for a sweep.
///
/// Throws [ArgumentError] for invalid start/stop/count combinations; the UI
/// should call [validateBodeConfig] first to show a friendly message.
List<double> buildFrequencyPoints(BodeConfig config) {
  if (config.pointCount < 2) {
    throw ArgumentError.value(
      config.pointCount,
      'pointCount',
      'Must be at least 2',
    );
  }
  final start = config.startFrequencyHz;
  final stop = config.stopFrequencyHz;
  if (!start.isFinite || start <= 0) {
    throw ArgumentError.value(start, 'startFrequencyHz', 'Must be > 0');
  }
  if (!stop.isFinite || stop <= start) {
    throw ArgumentError.value(
      stop,
      'stopFrequencyHz',
      'Must be greater than startFrequencyHz',
    );
  }

  final points = <double>[];
  for (var index = 0; index < config.pointCount; index++) {
    final t = index / (config.pointCount - 1);
    final frequency = config.spacing == BodeSpacing.logarithmic
        ? start * math.pow(stop / start, t)
        : start + (stop - start) * t;
    points.add(frequency.toDouble());
  }
  return points;
}

/// Wraps an angle into (-180, 180].
double wrapPhaseDeg(double degrees) {
  if (!degrees.isFinite) return 0;
  var wrapped = degrees % 360.0;
  if (wrapped > 180.0) wrapped -= 360.0;
  return wrapped;
}

/// Phase from a time delay: positive [delaySeconds] means the measured
/// signal (Vout) lags the reference (Vin).
double phaseFromDelay(double frequencyHz, double delaySeconds) {
  if (!frequencyHz.isFinite || !delaySeconds.isFinite) return 0;
  return wrapPhaseDeg(-360.0 * frequencyHz * delaySeconds);
}

/// Gain in dB using the Data Logger's plain ratio helper.
///
/// Only Vin must clear [bodeMinVinRms]; Vout may be small in a stopband.
double? bodeGainDb(double? vinRms, double? voutRms) {
  if (vinRms == null || voutRms == null) return null;
  if (!vinRms.isFinite || !voutRms.isFinite) return null;
  if (vinRms < bodeMinVinRms) return null;
  return computeGainDb(voutRms, vinRms);
}

/// Returns a human-readable validation error, or null when the config is valid.
String? validateBodeConfig(BodeConfig config, Jds6600DeviceInfo? info) {
  final start = config.startFrequencyHz;
  final stop = config.stopFrequencyHz;

  if (!start.isFinite || start <= 0) {
    return 'Start frequency must be greater than 0 Hz.';
  }
  if (!stop.isFinite || stop <= start) {
    return 'Stop frequency must be greater than the start frequency.';
  }
  if (config.pointCount < 2 || config.pointCount > 500) {
    return 'Point count must be between 2 and 500.';
  }
  if (!config.amplitudeVpp.isFinite || config.amplitudeVpp < 0) {
    return 'Amplitude must not be negative.';
  }
  final limits = info?.limits ?? SiggenLimits.jds6600;
  if (!config.offsetV.isFinite ||
      config.offsetV < limits.minOffsetV ||
      config.offsetV > limits.maxOffsetV) {
    return 'Offset must be between '
        '${limits.minOffsetV} and ${limits.maxOffsetV} V.';
  }
  if (config.settling.isNegative) {
    return 'Settling time must not be negative.';
  }
  if (config.waveform == Jds6600Waveform.arbitrary) {
    return 'Arbitrary waveforms are not supported for a Bode sweep.';
  }
  if (config.vinChannel != 1 && config.vinChannel != 2) {
    return 'Input channel must be CH1 or CH2.';
  }
  if (config.voutChannel != 1 && config.voutChannel != 2) {
    return 'Output channel must be CH1 or CH2.';
  }
  if (config.vinChannel == config.voutChannel) {
    return 'Input and output channels must be different.';
  }
  if (config.generatorChannel != 1 && config.generatorChannel != 2) {
    return 'Generator channel must be CH1 or CH2.';
  }

  if (info != null) {
    if (start < info.limits.minFrequencyHz) {
      return 'Start frequency (${formatFrequencyHz(start)}) is below the '
          '${info.modelName} minimum of '
          '${info.limits.minFrequencyHz.toStringAsFixed(6)} Hz.';
    }
    final maxFrequency = info.maxFrequencyHz(config.waveform);
    if (stop > maxFrequency) {
      return 'Stop frequency (${formatFrequencyHz(stop)}) exceeds the '
          '${config.waveform.displayName} limit of '
          '${formatFrequencyHz(maxFrequency)} for ${info.modelName}.';
    }
    try {
      if (info.family == SiggenFamily.fy6900) {
        Fy6900Protocol.validateAmplitude(info, stop, config.amplitudeVpp);
        Fy6900Protocol.validateOffsetAtFrequency(info, stop, config.offsetV);
      } else {
        Jds6600Protocol.validateAmplitude(info, stop, config.amplitudeVpp);
        Jds6600Protocol.validateOffset(config.offsetV);
      }
    } on Jds6600RangeException catch (e) {
      return e.message;
    }
  }
  return null;
}

/// Effective per-point settle time: configured value, at least three periods
/// and at least 800 ms, capped at 5 s.
Duration effectiveSettling(BodeConfig config, double frequencyHz) {
  final configured = config.settling.inMilliseconds / 1000.0;
  final cycles = frequencyHz > 0 ? 3.0 / frequencyHz : 0.0;
  final seconds = math.min(5.0, math.max(configured, math.max(cycles, 0.8)));
  return Duration(milliseconds: (seconds * 1000).round());
}

/// Extracts the last finite number from a scope response.
///
/// Used for PAVA/MEAD replies, whose exact echo prefixes vary; the Data
/// Logger uses the same last-number convention.
double? parseLastNumber(String raw) {
  final matches = RegExp(r'[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?').allMatches(raw);
  if (matches.isEmpty) return null;
  final value = double.tryParse(matches.last.group(0)!);
  if (value == null || !value.isFinite) return null;
  return value;
}

/// Extracts the RMS value belonging to [channel] from a PAVA response.
///
/// The response format is e.g. `C1:PAVA RMS,3.424000E-01V`. Requiring the
/// channel and measurement in the response prevents stale or foreign
/// responses from being interpreted as a voltage.
double? parsePavaRms(String raw, int channel) {
  final match = RegExp(
    'C$channel\\s*:\\s*PAVA\\s+RMS\\s*,?\\s*'
    r'([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  return value != null && value.isFinite ? value : null;
}

/// Extracts the phase value from `C1-C2:MEAD? PHA` responses.
///
/// Expected format: `C1-C2:MEAD PHA,5.760000E-03degree`. The MEAD/PHA markers
/// are required so that an IDN string or an SCPI error is never mistaken for
/// a phase value.
double? parseMeadPhase(String raw) {
  final upper = raw.toUpperCase();
  if (!upper.contains('MEAD') || !upper.contains('PHA')) return null;
  final match = RegExp(
    r'([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)\s*(?:DEGREE|DEG|°)',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  return value != null && value.isFinite ? value : null;
}

/// Compact SI frequency label, e.g. `1.2 kHz`.
String formatFrequencyHz(double hz) {
  if (!hz.isFinite) return '—';
  if (hz >= 1e6) return '${_trim(hz / 1e6)} MHz';
  if (hz >= 1e3) return '${_trim(hz / 1e3)} kHz';
  return '${_trim(hz)} Hz';
}

String _trim(double value) {
  var text = value.toStringAsFixed(value.abs() >= 100 ? 0 : 3);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}
