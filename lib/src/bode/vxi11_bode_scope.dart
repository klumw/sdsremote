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
    // ASET changes the timebase and vertical scale. The scope keeps answering
    // PAVA queries from the previous acquisition until a new acquisition has
    // completed; with a slow auto-set timebase this takes longer than 5 s.
    this.asetSettle = const Duration(seconds: 10),
  });

  final Future<Vxi11Instrument?> Function() _getInstrument;
  final Duration asetSettle;

  /// Switches the generator drive off/on around input V/div changes.
  ///
  /// The SDS1104X-E freezes the input channel when a SCPI V/div write happens
  /// while the channel carries the generator signal: MAX and MIN collapse to
  /// a constant rail, PKPK reads 0 and the trace disappears. With the drive
  /// paused during the write the channel stays usable. Wired by
  /// [BodePlotService] for amplitude sweeps.
  Future<void> Function(bool enabled)? pauseSignal;

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
  double? _vinVdiv;
  double? _voutVdiv;

  /// Whether the next input-scale preparation keeps the scale ASET chose.
  ///
  /// ASET has just fitted both channels to the current signal. Re-applying a
  /// computed V/div immediately afterwards can freeze the input channel on
  /// the SDS1104X-E, so the first read after ASET uses its scale as-is.
  bool _skipVinPrepare = false;

  /// Whether the input V/div stays fixed for the whole sweep.
  ///
  /// Amplitude sweeps set it once from the largest amplitude; changing it per
  /// point can freeze the input channel (see [pauseSignal]).
  bool lockInputScale = false;

  /// Whether each selected channel trace was off before [prepare].
  final Map<int, bool> _originalTraceOff = <int, bool>{};

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
    _changedTriggerMode =
        _originalTriggerMode == 'STOP' || _originalTriggerMode == 'SINGLE';
    if (_changedTriggerMode) {
      await _write('TRMD AUTO');
    }

    await _ensureChannelEnabled(vinChannel);
    await _ensureChannelEnabled(voutChannel);

    // ASET is orchestrated by BodePlotService after this preparation. The
    // generator is already switched on and configured there, so the sweep
    // always starts with a fresh auto-set for the actual signal.
  }

  /// Current input V/div in volts per division, or null until it is read.
  double? get inputVdiv => _vinVdiv;

  /// Reads the probe attenuation and vertical scale without changing them.
  Future<void> _readScaleSettings() async {
    _attnVin = await _queryDouble('C$_vinChannel:ATTN?') ?? _attnVin;
    _attnVout = await _queryDouble('C$_voutChannel:ATTN?') ?? _attnVout;
    _vinVdiv = await _queryDouble('C$_vinChannel:VDIV?') ?? _vinVdiv;
    _voutVdiv = await _queryDouble('C$_voutChannel:VDIV?') ?? _voutVdiv;
  }

  @override
  Future<BodeReading> read({
    required int vinChannel,
    required int voutChannel,
    required double frequencyHz,
    required bool measurePhase,
    bool measureVpp = false,
    double? expectedVinVpp,
    double? expectedVoutVpp,
  }) async {
    // An amplitude sweep raises the input level point by point. Scale the
    // input channel for the expected generator amplitude before reading so a
    // previously selected V/div cannot clip the measurement.
    if (measureVpp && expectedVinVpp != null && expectedVinVpp > 0) {
      await _prepareVinVdiv(expectedVinVpp / _attnVin);
    }
    // The output channel follows the level predicted from the previous
    // point. Without this, a signal that outgrows its V/div during the step
    // is clipped and can report a plausible peak-to-peak value, so the
    // post-reading range check would accept the clipped scale.
    if (measureVpp && expectedVoutVpp != null && expectedVoutVpp > 0) {
      await _prepareVoutVdiv(expectedVoutVpp / _attnVout);
    }
    var reading = await _readOnce(
      vinChannel: vinChannel,
      voutChannel: voutChannel,
      frequencyHz: frequencyHz,
      measurePhase: measurePhase,
      measureVpp: measureVpp,
      expectedVinVpp: expectedVinVpp,
    );
    // The first reading after ASET can still come from the previous
    // acquisition and therefore report a clipped, too-small Vout. Adjust the
    // V/div as often as needed instead of only once: a single adjustment
    // based on a clipped value can still leave the trace off-screen and the
    // point would be recorded at the wrong level.
    const maxRangeAdjustments = 4;
    for (var attempt = 0; attempt < maxRangeAdjustments; attempt++) {
      var adjusted = false;
      if (measureVpp) {
        // The V/div applies to the scope input, before the probe attenuation.
        if (reading.vinVpp != null) {
          adjusted =
              await _autoRangeVppChannel(
                _vinChannel,
                reading.vinVpp! / _attnVin,
                _vinVdiv,
              ) ||
              adjusted;
        }
        if (reading.voutVpp != null) {
          adjusted =
              await _autoRangeVppChannel(
                _voutChannel,
                reading.voutVpp! / _attnVout,
                _voutVdiv,
              ) ||
              adjusted;
        }
      } else {
        final scopeVout = reading.voutRms == null
            ? null
            : reading.voutRms! / _attnVout;
        adjusted = await _autoRangeVout(scopeVout);
      }
      if (!adjusted) break;
      reading = await _readOnce(
        vinChannel: vinChannel,
        voutChannel: voutChannel,
        frequencyHz: frequencyHz,
        measurePhase: measurePhase,
        measureVpp: measureVpp,
        expectedVinVpp: expectedVinVpp,
      );
    }
    return reading;
  }

  Future<BodeReading> _readOnce({
    required int vinChannel,
    required int voutChannel,
    required double frequencyHz,
    required bool measurePhase,
    bool measureVpp = false,
    double? expectedVinVpp,
  }) async {
    final vinRaw = await _query('C$vinChannel:PAVA? RMS');
    final voutRaw = await _query('C$voutChannel:PAVA? RMS');
    final vinVppRaw = measureVpp
        ? await _query('C$vinChannel:PAVA? PKPK')
        : null;
    final voutVppRaw = measureVpp
        ? await _query('C$voutChannel:PAVA? PKPK')
        : null;

    final vinOutOfRange =
        _isOutOfRange(vinRaw) ||
        (vinVppRaw != null && _isOutOfRange(vinVppRaw));
    final voutOutOfRange =
        _isOutOfRange(voutRaw) ||
        (voutVppRaw != null && _isOutOfRange(voutVppRaw));
    if (vinOutOfRange || voutOutOfRange) {
      return const BodeReading(
        outOfRange: true,
        error: 'Signal outside the oscilloscope measurement range',
      );
    }

    final vin = parsePavaRms(vinRaw, vinChannel);
    final vout = parsePavaRms(voutRaw, voutChannel);
    final vinVpp = vinVppRaw == null
        ? null
        : parsePavaValue(vinVppRaw, vinChannel, 'PKPK');
    final voutVpp = voutVppRaw == null
        ? null
        : parsePavaValue(voutVppRaw, voutChannel, 'PKPK');

    // An amplitude sweep drives the input channel with the generator, so its
    // trace can never be flat while the expected level is visible on the
    // current scale. The SDS1104X-E occasionally freezes the input channel
    // after a SCPI V/div change: MAX and MIN collapse to a constant value,
    // PKPK reads 0 and the trace is no longer drawn, while the other channel
    // keeps measuring. Only a new auto-set restores the channel. Report the
    // reading as out of range so the sweep re-initialises the scope instead
    // of recording a bogus gain from the frozen level. A signal below the
    // fixed scale's resolution legitimately reads 0 and is not a freeze.
    final double? expectedDivisions =
        expectedVinVpp != null && _vinVdiv != null && _vinVdiv! > 0
        ? expectedVinVpp / _vinVdiv!
        : null;
    final bool inputFrozen =
        measureVpp &&
        vinVpp != null &&
        vinVpp <= 0 &&
        (expectedDivisions == null || expectedDivisions >= 1.0);
    if (inputFrozen) {
      AppLogger(agentName: 'Bode', toolName: 'read').warning(
        'Input channel frozen after the scale change '
        '($vinVppRaw at VDIV ${_vinVdiv ?? '?'} V/div); '
        'auto-set required',
      );
      return const BodeReading(
        outOfRange: true,
        error: 'Input channel lost after the oscilloscope scale change',
      );
    }

    final scaledVin = vin == null ? null : vin * _attnVin;
    final scaledVout = vout == null ? null : vout * _attnVout;
    final scaledVinVpp = vinVpp == null ? null : vinVpp * _attnVin;
    final scaledVoutVpp = voutVpp == null ? null : voutVpp * _attnVout;

    double? phaseDeg;
    var phaseSource = BodePhaseSource.none;
    String? meadRaw;

    // Below ~-30 dB the output is close to the scope's noise/crosstalk floor;
    // the scope's MEAD phase then tends to collapse toward 0°. Use the
    // waveform-crossing estimate, which is computed from the acquired traces.
    final useWaveformPhase = vin != null && vout != null && vout < vin * 0.03;

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
      'vout="$voutRaw" '
      '${measureVpp ? 'vinVpp="$vinVppRaw" voutVpp="$voutVppRaw" ' : ''}'
      'mead="${meadRaw ?? ''}" '
      'gain=${scaledVin == null || scaledVout == null ? 'null' : (20 * (math.log(scaledVout / scaledVin) / math.ln10)).toStringAsFixed(2)} '
      'phase=${phaseDeg?.toStringAsFixed(2) ?? 'null'} '
      'source=${phaseSource.name}',
    );

    String? error;
    if (vin == null || vout == null) {
      error =
          'Unexpected RMS response '
          '(Vin="$vinRaw", Vout="$voutRaw").';
    } else if (measureVpp && (vinVpp == null || voutVpp == null)) {
      error =
          'Unexpected peak-to-peak response '
          '(Vin="$vinVppRaw", Vout="$voutVppRaw").';
    }

    return BodeReading(
      vinRms: scaledVin,
      voutRms: scaledVout,
      vinVpp: scaledVinVpp,
      voutVpp: scaledVoutVpp,
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
    await _readScaleSettings();
    _skipVinPrepare = true;
    // ASET can reset the measurement setup; restore phase measurement.
    if (_measurePhase) {
      await _configureMead();
    }
    await _primeMeasurements();
  }

  @override
  Future<void> restore() async {
    if (_instrument == null) return;
    for (final entry in _originalTraceOff.entries) {
      if (!entry.value) continue;
      try {
        await _write('C${entry.key}:TRA OFF');
      } catch (_) {}
    }
    _originalTraceOff.clear();
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
      AppLogger(
        agentName: 'Bode',
        toolName: 'mead',
      ).error('MEAD setup failed: $e');
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
      AppLogger(
        agentName: 'Bode',
        toolName: 'prime',
      ).error('Priming measurement failed: $e');
    }
  }

  /// Enables the channel trace when it is off and remembers the original
  /// state so [restore] can turn it off again.
  Future<void> _ensureChannelEnabled(int channel) async {
    final response = await _query('C$channel:TRACE?');
    final normalized = response.toUpperCase();
    final wasOff = RegExp(r'\b(OFF|0)\b').hasMatch(normalized);
    _originalTraceOff.putIfAbsent(channel, () => wasOff);
    if (wasOff) {
      await _write('C$channel:TRA ON');
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

  /// Scales the input channel for the expected generator amplitude.
  ///
  /// Amplitude sweeps change the input level by more than an order of
  /// magnitude; using only the measured value would keep a clipped reading
  /// clipped because it never reports the real level. A scale that already
  /// shows the expected level between one and seven divisions is kept.
  /// Otherwise the scale is changed through the front-panel knob emulation:
  /// the SDS1104X-E freezes the input channel on SCPI V/div writes at large
  /// scales (MAX and MIN collapse to a constant rail, PKPK reads 0 and the
  /// trace disappears), while turning the vertical knob always leaves the
  /// channel usable.
  Future<void> _prepareVinVdiv(double scopeVpp) async {
    if (lockInputScale) return;
    if (_instrument == null || scopeVpp <= 0) return;
    // ASET has just picked a scale for the current signal; do not override it
    // with a second V/div change right away.
    if (_skipVinPrepare) {
      _skipVinPrepare = false;
      return;
    }
    var current = _vinVdiv;
    if (current == null || current <= 0) {
      current = await _queryDouble('C$_vinChannel:VDIV?');
      _vinVdiv = current;
    }
    if (current == null || current <= 0) return;

    final divisions = scopeVpp / current;
    if (divisions >= 1.0 && divisions <= 7.0) return;

    final target = _niceVdiv(scopeVpp / 3.0).clamp(0.0005, 10.0).toDouble();
    if ((target - current).abs() / current < 0.2) return;
    await _changeVinVdiv(target);
  }

  /// Scales the output channel for the level predicted from the previous
  /// amplitude-sweep point.
  ///
  /// A signal that outgrows its V/div between two points is clipped, and a
  /// clipped trace can still report a peak-to-peak value that looks usable
  /// (about five divisions). Scaling before the reading keeps the output
  /// channel between one and five divisions instead of relying on the
  /// post-reading range check, which cannot distinguish a clipped reading
  /// from a correct one.
  Future<void> _prepareVoutVdiv(double scopeVpp) async {
    if (_instrument == null || scopeVpp <= 0) return;
    var current = _voutVdiv;
    if (current == null || current <= 0) {
      current = await _queryDouble('C$_voutChannel:VDIV?');
      _voutVdiv = current;
    }
    if (current == null || current <= 0) return;

    final divisions = scopeVpp / current;
    if (divisions >= 1.0 && divisions <= 5.0) return;

    final target = _niceVdiv(scopeVpp / 3.0).clamp(0.0005, 10.0).toDouble();
    if ((target - current).abs() / current < 0.2) return;
    try {
      await _write('C$_voutChannel:VDIV ${target}V');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      _voutVdiv = target;
      AppLogger(agentName: 'Bode', toolName: 'range').log(
        'CH$_voutChannel VDIV -> ${target.toStringAsFixed(4)} V/div '
        '(expected ${scopeVpp.toStringAsFixed(4)} Vpp)',
      );
    } catch (e) {
      AppLogger(
        agentName: 'Bode',
        toolName: 'range',
      ).error('Vout V/div change failed: $e');
    }
  }

  /// Changes the input V/div while the generator drive is paused.
  ///
  /// A SCPI V/div write during an active drive can freeze the input channel
  /// of the SDS1104X-E (see [pauseSignal]); pausing the drive around the
  /// write keeps the channel usable.
  Future<void> _changeVinVdiv(double target) async {
    final pause = pauseSignal;
    try {
      if (pause != null) {
        await pause(false);
        // The probe/DUT network can hold the input level for a moment; the
        // V/div write is only safe once the drive has really decayed.
        await Future<void>.delayed(const Duration(milliseconds: 1000));
      }
      await _write('C$_vinChannel:VDIV ${target}V');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _vinVdiv = target;
      AppLogger(agentName: 'Bode', toolName: 'range').log(
        'CH$_vinChannel VDIV -> ${target.toStringAsFixed(4)} V/div '
        '(generator paused: ${pause != null})',
      );
    } finally {
      if (pause != null) {
        await pause(true);
        // Let the generator output settle before the next measurement.
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    }
  }

  /// Locks the input channel to [vdiv] for the whole amplitude sweep.
  ///
  /// The scale is stepped through the 1-2-5 grid with the generator drive
  /// paused: a single large V/div jump can freeze the input channel on the
  /// SDS1104X-E, single steps are safe. If a step is lost anyway, the scope
  /// is re-initialised with ASET and its resulting scale is kept.
  Future<void> lockInputScaleFor(double vdiv, {double? verifyVpp}) async {
    lockInputScale = true;
    var current = _vinVdiv ?? await _queryDouble('C$_vinChannel:VDIV?');
    if (current == null || current <= 0) current = 1.0;
    final target = vdiv.clamp(0.0005, 10.0).toDouble();
    final path = _vdDivPath(current, target);
    if (path.isEmpty) {
      _vinVdiv = current;
      return;
    }

    final pause = pauseSignal;
    try {
      if (pause != null) {
        await pause(false);
        await Future<void>.delayed(const Duration(milliseconds: 1000));
      }
      for (final step in path) {
        await _write('C$_vinChannel:VDIV ${step}V');
        await Future<void>.delayed(const Duration(milliseconds: 500));
        _vinVdiv = step;
      }
    } finally {
      if (pause != null) {
        await pause(true);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    }
    // Only check the channel when the current signal is visible at the new
    // scale; a signal below its resolution legitimately reads 0 and must not
    // trigger an unnecessary ASET (which would pick a very fine scale).
    final canVerify =
        verifyVpp == null || (target > 0 && verifyVpp / target >= 0.5);
    final vpp = canVerify
        ? await _queryDouble('C$_vinChannel:PAVA? PKPK')
        : null;
    if (vpp != null && vpp <= 0) {
      AppLogger(agentName: 'Bode', toolName: 'range').warning(
        'Input channel did not survive the initial V/div write; using ASET',
      );
      await autoSet();
    }
    _vinVdiv = await _queryDouble('C$_vinChannel:VDIV?') ?? target;
    AppLogger(agentName: 'Bode', toolName: 'range').log(
      'Input scale locked at ${_vinVdiv?.toStringAsFixed(4)} V/div '
      '(target ${target.toStringAsFixed(4)})',
    );
  }

  /// 1-2-5 V/div values between [from] and [to], target included.
  List<double> _vdDivPath(double from, double to) {
    final values = <double>[];
    for (var exponent = -4; exponent <= 1; exponent++) {
      final magnitude = math.pow(10, exponent).toDouble();
      for (final multiplier in const [1.0, 2.0, 5.0]) {
        values.add(multiplier * magnitude);
      }
    }
    values.add(10.0);
    values.sort();
    final path = <double>[];
    if (to > from) {
      for (final value in values) {
        if (value > from * 1.01 && value <= to * 1.01) path.add(value);
      }
    } else {
      for (final value in values.reversed) {
        if (value < from * 0.99 && value >= to * 0.99) path.add(value);
      }
    }
    return path;
  }

  /// Adjusts [channel] when the measured peak-to-peak value uses less than
  /// one division (noise/quantisation dominate) or more than seven divisions
  /// (near the eight-division screen edge).
  Future<bool> _autoRangeVppChannel(
    int channel,
    double? scopeVpp,
    double? current,
  ) async {
    if (scopeVpp == null || scopeVpp <= 0 || _instrument == null) return false;
    if (current == null || current <= 0) return false;
    if (channel == _vinChannel && lockInputScale) return false;

    final divisions = scopeVpp / current;
    if (divisions >= 1.0 && divisions <= 7.0) return false;

    final target = _niceVdiv(scopeVpp / 3.0).clamp(0.0005, 10.0).toDouble();
    if ((target - current).abs() / current < 0.2) return false;

    if (channel == _vinChannel) {
      // A V/div write during an active drive can freeze the input channel;
      // pause the generator around it (see [_changeVinVdiv]).
      await _changeVinVdiv(target);
      return true;
    }

    try {
      await _write('C$channel:VDIV ${target}V');
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (channel == _voutChannel) {
        _voutVdiv = target;
      }
      AppLogger(agentName: 'Bode', toolName: 'range').log(
        '${channel == _vinChannel ? 'Vin' : 'Vout'}='
        '${scopeVpp.toStringAsFixed(5)} Vpp: '
        'CH$channel VDIV $current -> $target',
      );
      return true;
    } catch (e) {
      AppLogger(
        agentName: 'Bode',
        toolName: 'range',
      ).error('V/div change failed: $e');
      return false;
    }
  }

  /// Adjusts the output channel's V/div from an RMS reading.
  ///
  /// At 200 mV/div the SDS1202X-E has a ~5.6 mV RMS noise floor; an RC
  /// low-pass output of 5.4 mV at 100 kHz is lost in it. At 20 mV/div the
  /// floor drops below 1 mV.
  Future<bool> _autoRangeVout(double? voutRms) async {
    if (voutRms == null || voutRms <= 0) return false;
    // Sine crest factor; good enough for scale selection with other shapes.
    final vpp = voutRms * 2 * math.sqrt(2);
    return _autoRangeVppChannel(_voutChannel, vpp, _voutVdiv);
  }

  /// Measures the input channel's peak-to-peak noise floor at the locked
  /// scale, with the generator drive paused.
  ///
  /// The median of several readings is used so a single noise spike does not
  /// set the floor. Returns null when the scope cannot be read.
  Future<double?> measureVinNoiseVpp() async {
    final pause = pauseSignal;
    final samples = <double>[];
    try {
      if (pause != null) {
        await pause(false);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      for (var i = 0; i < 5; i++) {
        final raw = await _query('C$_vinChannel:PAVA? PKPK');
        final vpp = parsePavaValue(raw, _vinChannel, 'PKPK');
        if (vpp != null && vpp >= 0) samples.add(vpp);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } catch (error) {
      AppLogger(
        agentName: 'Bode',
        toolName: 'noise',
      ).warning('Vin noise measurement failed: $error');
    } finally {
      if (pause != null) {
        await pause(true);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
    }
    if (samples.isEmpty) return null;
    samples.sort();
    final median = samples[samples.length ~/ 2];
    AppLogger(agentName: 'Bode', toolName: 'noise').log(
      'Vin PKPK noise at ${_vinVdiv?.toStringAsFixed(4) ?? '?'} V/div: '
      '${median.toStringAsFixed(4)} Vpp',
    );
    return median;
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
