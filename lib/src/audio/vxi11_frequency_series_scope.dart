/// VXI-11 scope adapter for the host-managed frequency series.
///
/// It enables the requested channel, sets a usable vertical scale and a
/// per-frequency timebase, reads `PAVA` levels and restores the original
/// trigger, timebase, vertical scale and trace state afterwards.
library;

import 'dart:math' as math;

import '../ai/tools/audio/audio_analysis_context.dart';
import '../bode/bode_math.dart';
import '../instrument/dart_vxi11.dart';
import 'frequency_series_service.dart';

class Vxi11FrequencySeriesScope implements FrequencySeriesScope {
  Vxi11FrequencySeriesScope(
    this._getInstrument, {
    this.timebaseSettle = const Duration(milliseconds: 150),
    this.asetSettle = const Duration(seconds: 10),
  });

  final Future<Vxi11Instrument?> Function() _getInstrument;
  final Duration timebaseSettle;

  /// Settle time after Auto Setup (ASET).
  ///
  /// ASET changes the timebase and vertical scale; the scope keeps answering
  /// PAVA queries from the previous acquisition until a new one completed.
  final Duration asetSettle;

  Vxi11Instrument? _instrument;
  int _channel = 1;
  String? _originalTriggerMode;
  bool _changedTriggerMode = false;
  bool _traceWasOff = false;
  double? _originalTdiv;
  double? _originalVdiv;
  double? _vdiv;

  @override
  Future<void> prepare({
    required int channel,
    required double amplitudeVpp,
  }) async {
    final instrument = await _getInstrument();
    if (instrument == null) {
      throw const AudioFrequencySeriesException(
        'The oscilloscope is not available.',
        code: 'SERIES_NO_SCOPE',
      );
    }
    _instrument = instrument;
    _channel = channel;

    _originalTriggerMode = _modeFromResponse(await _query('TRMD?'));
    _changedTriggerMode =
        _originalTriggerMode == 'STOP' || _originalTriggerMode == 'SINGLE';
    if (_changedTriggerMode) {
      await _write('TRMD AUTO');
    }

    final trace = await _query('C$channel:TRACE?');
    _traceWasOff = RegExp(r'\b(OFF|0)\b').hasMatch(trace.toUpperCase());
    if (_traceWasOff) {
      await _write('C$channel:TRA ON');
    }

    _originalTdiv = parseLastNumber(await _query('TDIV?'));
    _originalVdiv = parseLastNumber(await _query('C$channel:VDIV?'));
    _vdiv = _originalVdiv;

    final target = _niceVdiv(amplitudeVpp / 4);
    final current = _vdiv;
    if (current == null || (target - current).abs() / current > 0.2) {
      await _write('C$channel:VDIV ${target}V');
      _vdiv = target;
    }
  }

  @override
  Future<void> autoSet() async {
    if (_instrument == null) return;
    await _write('ASET');
    if (asetSettle > Duration.zero) {
      await Future<void>.delayed(asetSettle);
    }
    // ASET may replace the vertical scale chosen in prepare; keep the actual
    // value so the per-point auto-scaling starts from the real state.
    _vdiv = parseLastNumber(await _query('C$_channel:VDIV?')) ?? _vdiv;
  }

  @override
  Future<double?> read({
    required int channel,
    required double frequencyHz,
    required String quantity,
  }) async {
    if (_instrument == null) return null;
    await _write('TDIV ${_timebaseFor(frequencyHz)}');
    if (timebaseSettle > Duration.zero) {
      await Future<void>.delayed(timebaseSettle);
    }

    final kind = quantity == 'vrms' ? 'RMS' : 'PKPK';
    var value = _parsePava(
      await _query('C$channel:PAVA? $kind'),
      channel,
      kind,
    );
    if (value == null) return null;

    final current = _vdiv;
    if (current == null || current <= 0) return value;
    final vpp = kind == 'RMS' ? value * 2 * math.sqrt(2) : value;
    final divisions = vpp / current;
    if (divisions < 0.5 || divisions > 8) {
      final target = _niceVdiv(vpp / 4);
      if ((target - current).abs() / current >= 0.2) {
        await _write('C$channel:VDIV ${target}V');
        _vdiv = target;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        value = _parsePava(
          await _query('C$channel:PAVA? $kind'),
          channel,
          kind,
        );
      }
    }
    return value;
  }

  @override
  Future<Map<String, double?>> readMany({
    required int channel,
    required double frequencyHz,
    required List<String> quantities,
  }) async {
    if (_instrument == null) return const <String, double?>{};
    await _write('TDIV ${_timebaseFor(frequencyHz)}');
    if (timebaseSettle > Duration.zero) {
      await Future<void>.delayed(timebaseSettle);
    }

    var values = await _readPavaValues(channel, quantities);
    final pkpk = values['pkpk'];
    final current = _vdiv;
    if (pkpk != null && pkpk > 0 && current != null && current > 0) {
      final divisions = pkpk / current;
      if (divisions < 0.5 || divisions > 8) {
        final target = _niceVdiv(pkpk / 4);
        if ((target - current).abs() / current >= 0.2) {
          await _write('C$channel:VDIV ${target}V');
          _vdiv = target;
          await Future<void>.delayed(const Duration(milliseconds: 250));
          values = await _readPavaValues(channel, quantities);
        }
      }
    }
    return values;
  }

  Future<Map<String, double?>> _readPavaValues(
    int channel,
    List<String> quantities,
  ) async {
    final values = <String, double?>{};
    for (final quantity in quantities) {
      final kind = _pavaKind(quantity);
      if (kind == null) {
        values[quantity] = null;
        continue;
      }
      values[quantity] = _parsePava(
        await _query('C$channel:PAVA? $kind'),
        channel,
        kind,
      );
    }
    return values;
  }

  @override
  Future<void> restore() async {
    if (_instrument == null) return;
    final tdiv = _originalTdiv;
    if (tdiv != null) {
      try {
        await _write('TDIV ${_formatTimebase(tdiv)}');
      } catch (_) {}
    }
    final vdiv = _originalVdiv;
    if (vdiv != null) {
      try {
        await _write('C$_channel:VDIV ${vdiv}V');
      } catch (_) {}
    }
    if (_traceWasOff) {
      try {
        await _write('C$_channel:TRA OFF');
      } catch (_) {}
    }
    if (_changedTriggerMode && _originalTriggerMode != null) {
      try {
        await _write('TRMD $_originalTriggerMode');
      } catch (_) {}
    }
    _instrument = null;
    _channel = 1;
    _originalTriggerMode = null;
    _changedTriggerMode = false;
    _traceWasOff = false;
    _originalTdiv = null;
    _originalVdiv = null;
    _vdiv = null;
  }

  Future<String> _query(String command) async {
    final instrument = _instrument;
    if (instrument == null) {
      throw const AudioFrequencySeriesException(
        'The oscilloscope is not available.',
        code: 'SERIES_NO_SCOPE',
      );
    }
    return (await instrument.queryString(command)).trim();
  }

  Future<void> _write(String command) async {
    final instrument = _instrument;
    if (instrument == null) {
      throw const AudioFrequencySeriesException(
        'The oscilloscope is not available.',
        code: 'SERIES_NO_SCOPE',
      );
    }
    await instrument.writeString(command);
  }
}

const Map<String, String> _pavaKinds = <String, String>{
  'pkpk': 'PKPK',
  'max': 'MAX',
  'min': 'MIN',
  'ampl': 'AMPL',
  'top': 'TOP',
  'base': 'BASE',
  'rms': 'RMS',
  'freq': 'FREQ',
  'rise': 'RISE',
  'fall': 'FALL',
  'duty': 'DUTY',
};

String? _pavaKind(String quantity) {
  return _pavaKinds[quantity.trim().toLowerCase()];
}

double? _parsePava(String raw, int channel, String kind) {
  final match = RegExp(
    'C$channel\\s*:\\s*PAVA\\s+$kind\\s*,?\\s*'
    r'([-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)',
    caseSensitive: false,
  ).firstMatch(raw);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  return value != null && value.isFinite ? value : null;
}

String? _modeFromResponse(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return trimmed.split(RegExp(r'\s+')).last.toUpperCase();
}

/// Rounds [value] to the nearest scope 1-2-5 V/div step.
double _niceVdiv(double value) {
  if (value <= 0) return 0.0005;
  final exponent = (math.log(value) / math.ln10).floor();
  final magnitude = math.pow(10, exponent).toDouble();
  final candidates = <double>[
    for (final multiplier in const <double>[1, 2, 5]) multiplier * magnitude,
    10 * magnitude,
  ];
  return candidates.reduce(
    (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
  );
}

String _timebaseFor(double frequencyHz) {
  if (!frequencyHz.isFinite || frequencyHz <= 0) return '1MS';
  // Show about three periods across the ten-division screen.
  return _formatTimebase(0.3 / frequencyHz);
}

String _formatTimebase(double seconds) {
  final clamped = seconds.clamp(1e-9, 100.0).toDouble();
  final exponent = (math.log(clamped) / math.ln10).floor();
  final magnitude = math.pow(10, exponent).toDouble();
  final normalized = clamped / magnitude;
  final step = normalized <= 1
      ? 1.0
      : normalized <= 2
      ? 2.0
      : normalized <= 5
      ? 5.0
      : 10.0;
  final value = step * magnitude;
  if (value >= 1) return '${_trim(value)}S';
  if (value >= 1e-3) return '${_trim(value * 1e3)}MS';
  if (value >= 1e-6) return '${_trim(value * 1e6)}US';
  return '${_trim(value * 1e9)}NS';
}

String _trim(double value) {
  final text = value.toStringAsFixed(6);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}
