/// Siglent SDS implementation of [BodeScope].
library;

import 'dart:async';
import 'dart:math' as math;

import '../core/logger.dart';
import '../instrument/dart_vxi11.dart';
import '../waveform/waveform_acquisition.dart';
import 'bode_math.dart';
import 'bode_models.dart';
import 'bode_scope.dart';
import 'waveform_phase.dart';

class Vxi11BodeScope implements BodeScope {
  Vxi11BodeScope(
    this._getInstrument, {
    this.asetSettle = const Duration(seconds: 5),
  });

  final Future<Vxi11Instrument?> Function() _getInstrument;
  final Duration asetSettle;

  /// The scope's `C1-C2:MEAD? PHA` returns `phase(C1) - phase(C2)`, i.e. the
  /// input relative to the output. The plot shows the output relative to the
  /// input (positive = lead, negative = lag), so the sign is inverted.
  /// Verified with an RC low-pass: the lagging output is displayed negative.
  static const double meadSign = -1.0;

  Vxi11Instrument? _instrument;
  String? _originalTriggerMode;
  bool _changedTriggerMode = false;
  double _attnVin = 1.0;
  double _attnVout = 1.0;
  bool _meadConfigured = false;
  bool _measurePhase = false;
  int _vinChannel = 1;
  int _voutChannel = 2;
  double? _voutVdiv;

  @override
  Future<void> prepare({
    required int vinChannel,
    required int voutChannel,
    required bool measurePhase,
  }) async {
    final instrument = await _getInstrument();
    if (instrument == null) {
      throw const BodeScopeException('Oscilloscope is not available');
    }
    _instrument = instrument;
    _vinChannel = vinChannel;
    _voutChannel = voutChannel;
    _measurePhase = measurePhase;

    _originalTriggerMode = _modeFromResponse(await _query('TRMD?'));
    _changedTriggerMode = _originalTriggerMode == 'STOP' ||
        _originalTriggerMode == 'SINGLE';
    if (_changedTriggerMode) {
      await _write('TRMD AUTO');
    }

    await _requireChannel(vinChannel);
    await _requireChannel(voutChannel);

    // ASET also re-reads the probe factors and restores the phase measurement.
    await autoSet();
  }

  @override
  Future<BodeReading> read({
    required int vinChannel,
    required int voutChannel,
    required double frequencyHz,
    required bool measurePhase,
  }) async {
    var reading = await _readOnce(
      vinChannel: vinChannel,
      voutChannel: voutChannel,
      frequencyHz: frequencyHz,
      measurePhase: measurePhase,
    );
    // The V/div applies to the scope input, before the probe attenuation.
    final scopeVout = reading.voutRms == null
        ? null
        : reading.voutRms! / _attnVout;
    if (await _autoRangeVout(scopeVout)) {
      reading = await _readOnce(
        vinChannel: vinChannel,
        voutChannel: voutChannel,
        frequencyHz: frequencyHz,
        measurePhase: measurePhase,
      );
    }
    return reading;
  }

  Future<BodeReading> _readOnce({
    required int vinChannel,
    required int voutChannel,
    required double frequencyHz,
    required bool measurePhase,
  }) async {
    final vinRaw = await _query('C$vinChannel:PAVA? RMS');
    final voutRaw = await _query('C$voutChannel:PAVA? RMS');

    final vinOutOfRange = _isOutOfRange(vinRaw);
    final voutOutOfRange = _isOutOfRange(voutRaw);
    if (vinOutOfRange || voutOutOfRange) {
      return const BodeReading(
        outOfRange: true,
        error: 'Signal outside the oscilloscope measurement range',
      );
    }

    final vin = parsePavaRms(vinRaw, vinChannel);
    final vout = parsePavaRms(voutRaw, voutChannel);
    final scaledVin = vin == null ? null : vin * _attnVin;
    final scaledVout = vout == null ? null : vout * _attnVout;

    double? phaseDeg;
    var phaseSource = BodePhaseSource.none;
    String? meadRaw;

    // Below ~-30 dB the output is close to the scope's noise/crosstalk floor;
    // the scope's MEAD phase then tends to collapse toward 0°. Use the
    // waveform-crossing estimate, which is computed from the acquired traces.
    final useWaveformPhase =
        vin != null && vout != null && vout < vin * 0.03;

    if (measurePhase) {
      if (_meadConfigured && !useWaveformPhase) {
        // The scope accepts the ascending pair for the query. The pair order
        // is C1-C2 on the wire; reverse the sign when the configured input is
        // CH2 and the output is CH1.
        meadRaw = await _query('C1-C2:MEAD? PHA');
        var value = parseMeadPhase(meadRaw);
        // A physical phase lies in [-180, 180]; a larger raw value is a
        // scope measurement glitch, not something to wrap into range.
        if (value != null && value.abs() <= 180.0) {
          if (vinChannel == 2 && voutChannel == 1) value = -value;
          phaseDeg = wrapPhaseDeg(meadSign * value);
          phaseSource = BodePhaseSource.mead;
        }
      }
      if (phaseDeg == null) {
        final waveformPhase = await _waveformPhase(
          frequencyHz,
          vinChannel,
          voutChannel,
        );
        if (waveformPhase != null) {
          phaseDeg = waveformPhase;
          phaseSource = BodePhaseSource.waveform;
        }
      } else if (phaseDeg.abs() > 170.0) {
        // Near the ±180° wrap the scope occasionally locks onto the opposite
        // edge. Cross-check with the waveform; a genuine inversion agrees.
        final waveformPhase = await _waveformPhase(
          frequencyHz,
          vinChannel,
          voutChannel,
        );
        if (waveformPhase != null &&
            wrapPhaseDeg(waveformPhase - phaseDeg).abs() > 90.0) {
          phaseDeg = waveformPhase;
          phaseSource = BodePhaseSource.waveform;
        }
      }
    }

    final delaySeconds = phaseDeg == null
        ? null
        : -phaseDeg / (360.0 * frequencyHz);

    AppLogger(agentName: 'Bode', toolName: 'read').log(
      'f=${frequencyHz.toStringAsFixed(1)} vin="$vinRaw" '
      'vout="$voutRaw" mead="${meadRaw ?? ''}" '
      'gain=${scaledVin == null || scaledVout == null ? 'null' : (20 * (math.log(scaledVout / scaledVin) / math.ln10)).toStringAsFixed(2)} '
      'phase=${phaseDeg?.toStringAsFixed(2) ?? 'null'} '
      'source=${phaseSource.name}',
    );

    String? error;
    if (vin == null || vout == null) {
      error = 'Unexpected RMS response '
          '(Vin="$vinRaw", Vout="$voutRaw").';
    }

    return BodeReading(
      vinRms: scaledVin,
      voutRms: scaledVout,
      phaseDeg: phaseDeg,
      delaySeconds: delaySeconds,
      phaseSource: phaseSource,
      error: error,
    );
  }

  @override
  Future<void> autoSet() async {
    if (_instrument == null) return;
    await _write('ASET');
    if (asetSettle > Duration.zero) {
      await Future<void>.delayed(asetSettle);
    }
    _attnVin = await _queryDouble('C$_vinChannel:ATTN?') ?? _attnVin;
    _attnVout = await _queryDouble('C$_voutChannel:ATTN?') ?? _attnVout;
    _voutVdiv = await _queryDouble('C$_voutChannel:VDIV?') ?? _voutVdiv;
    // ASET can reset the measurement setup; restore phase measurement.
    if (_measurePhase) {
      await _configureMead();
    }
    await _primeMeasurements();
  }

  @override
  Future<void> restore() async {
    if (_instrument == null) return;
    if (_changedTriggerMode && _originalTriggerMode != null) {
      try {
        await _write('TRMD $_originalTriggerMode');
      } catch (_) {}
      _changedTriggerMode = false;
    }
    _instrument = null;
    _meadConfigured = false;
  }

  Future<void> _configureMead() async {
    try {
      await _write('*CLS');
      await _write('MEAD PHA,C1-C2');
      var accepted = true;
      try {
        final error = await _query('SYST:ERR?');
        accepted = parseLastNumber(error) == 0;
      } catch (_) {
        // Some firmware has no error queue; assume the documented syntax.
      }
      if (!accepted) {
        // SDS1202X-E firmware 1.3.27 rejects the source pair on the set
        // command but accepts the bare type; the query supplies the pair.
        await _write('MEAD PHA');
      }
      _meadConfigured = true;
    } catch (e) {
      _meadConfigured = false;
      AppLogger(agentName: 'Bode', toolName: 'mead')
          .log('MEAD setup failed: $e');
    }
  }

  /// Discards the first RMS measurement after ASET.
  ///
  /// The scope can return a partial value for the first PAVA query while the
  /// auto-setup is still settling, which produces a bogus first gain point.
  Future<void> _primeMeasurements() async {
    try {
      await _query('C$_vinChannel:PAVA? RMS');
      await _query('C$_voutChannel:PAVA? RMS');
      if (_measurePhase && _meadConfigured) {
        // The first MEAD query after setup can return the previous/default
        // value (often ±180°); discard it before the first sweep point.
        await _query('C1-C2:MEAD? PHA');
      }
    } catch (e) {
      AppLogger(agentName: 'Bode', toolName: 'prime')
          .log('Priming measurement failed: $e');
    }
  }

  Future<void> _requireChannel(int channel) async {
    final response = await _query('C$channel:TRACE?');
    final normalized = response.toUpperCase();
    if (RegExp(r'\b(OFF|0)\b').hasMatch(normalized)) {
      throw BodeScopeException(
        'Enable CH$channel on the oscilloscope for the Bode sweep.',
      );
    }
  }

  Future<String> _query(String command) async {
    final instrument = _instrument;
    if (instrument == null) {
      throw const BodeScopeException('Oscilloscope is not available');
    }
    return (await instrument.queryString(command)).trim();
  }

  Future<void> _write(String command) async {
    final instrument = _instrument;
    if (instrument == null) {
      throw const BodeScopeException('Oscilloscope is not available');
    }
    await instrument.writeString(command);
  }

  Future<double?> _queryDouble(String command) async {
    return parseLastNumber(await _query(command));
  }

  /// Adjusts the output channel's V/div when the signal uses less than one
  /// division (noise/quantisation dominate) or more than six divisions.
  ///
  /// At 200 mV/div the SDS1202X-E has a ~5.6 mV RMS noise floor; an RC
  /// low-pass output of 5.4 mV at 100 kHz is lost in it. At 20 mV/div the
  /// floor drops below 1 mV.
  Future<bool> _autoRangeVout(double? voutRms) async {
    if (voutRms == null || voutRms <= 0 || _instrument == null) return false;
    final current = _voutVdiv;
    if (current == null || current <= 0) return false;

    // Sine crest factor; good enough for scale selection with other shapes.
    final vpp = voutRms * 2 * math.sqrt(2);
    final divisions = vpp / current;
    if (divisions >= 1.0 && divisions <= 6.0) return false;

    final target = _niceVdiv(vpp / 3.0).clamp(0.0005, 10.0).toDouble();
    if ((target - current).abs() / current < 0.2) return false;

    try {
      await _write('C$_voutChannel:VDIV ${target}V');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      _voutVdiv = target;
      AppLogger(agentName: 'Bode', toolName: 'range').log(
        'Vout=${voutRms.toStringAsFixed(5)} V: '
        'CH$_voutChannel VDIV $current -> $target',
      );
      return true;
    } catch (e) {
      AppLogger(agentName: 'Bode', toolName: 'range')
          .log('V/div change failed: $e');
      return false;
    }
  }

  /// Rounds [value] to the nearest scope 1-2-5 V/div step.
  double _niceVdiv(double value) {
    if (value <= 0) return 0.0005;
    final exponent = (math.log(value) / math.ln10).floor();
    final magnitude = math.pow(10, exponent).toDouble();
    final candidates = [
      for (final multiplier in const [1.0, 2.0, 5.0]) multiplier * magnitude,
      10 * magnitude,
    ];
    return candidates.reduce(
      (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
    );
  }

  Future<double?> _waveformPhase(
    double frequencyHz,
    int vinChannel,
    int voutChannel,
  ) async {
    final instrument = _instrument;
    if (instrument == null) return null;
    try {
      final raw = await WaveformAcquisition('').acquire(
        ch1: vinChannel == 1 || voutChannel == 1,
        ch2: vinChannel == 2 || voutChannel == 2,
        instr: instrument,
      );
      return estimatePhaseFromRaw(
        raw: raw,
        frequencyHz: frequencyHz,
        vinChannel: vinChannel,
        voutChannel: voutChannel,
      );
    } catch (_) {
      return null;
    }
  }
}

String? _modeFromResponse(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final parts = trimmed.split(RegExp(r'\s+'));
  return parts.last.toUpperCase();
}

bool _isOutOfRange(String raw) => raw.contains('***');
