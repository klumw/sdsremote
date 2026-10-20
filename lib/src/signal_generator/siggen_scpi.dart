/// Small SCPI compatibility layer for the JDS6600.
///
/// This is an emulation subset, not a full SCPI implementation. It parses a
/// single command per line and delegates the hardware work to
/// [SiggenScpiTarget]. The target interface keeps the parser testable without
/// a serial port.
library;

import 'jds6600_protocol.dart';
import 'models.dart';

/// Operations the SCPI layer needs from the signal-generator service.
abstract class SiggenScpiTarget {
  Jds6600DeviceInfo? get deviceInfo;

  Future<void> refreshDeviceInfo();

  Future<void> setWaveform(int channel, Jds6600Waveform waveform);
  Future<Jds6600Waveform> readWaveform(int channel);

  Future<void> setFrequency(int channel, double hz);
  Future<double> readFrequency(int channel);

  Future<void> setAmplitude(int channel, double vpp);
  Future<double> readAmplitude(int channel);

  Future<void> setOffset(int channel, double volts);
  Future<double> readOffset(int channel);

  Future<void> setDuty(int channel, double percent);
  Future<double> readDuty(int channel);

  /// Sets or reads the phase of [channel], exposed as `SOUR<channel>:PHAS`.
  ///
  /// The JDS6600 maps both channels to its global CH2-vs-CH1 register; the
  /// FY6900 has per-channel phase.
  Future<void> setPhase(int channel, double degrees);
  Future<double> readPhase(int channel);

  Future<void> setOutput(int channel, bool enabled);
  Future<bool> readOutput(int channel);

  Future<void> resetSafeState();

  void pushError(ScpiError error);
  ScpiError? popError();
  void clearErrors();
  int get errorCount;
}

/// Parses and executes the supported SCPI subset.
class SiggenScpiInterpreter {
  SiggenScpiInterpreter(this._target);

  final SiggenScpiTarget _target;

  static const Map<String, String> _segmentAliases = {
    'SOURCE': 'SOUR',
    'OUTPUT': 'OUTP',
    'VOLTAGE': 'VOLT',
    'OFFSET': 'OFFS',
    'FUNCTION': 'FUNC',
    'DCYCLE': 'DCYC',
    'PHASE': 'PHAS',
    'STATE': 'STAT',
    'FREQUENCY': 'FREQ',
  };

  static const Map<String, double> _frequencyUnits = {
    '': 1.0,
    'HZ': 1.0,
    'KHZ': 1e3,
    'MHZ': 1e6,
  };

  static const Map<String, double> _voltageUnits = {
    '': 1.0,
    'V': 1.0,
    'VPP': 1.0,
    'MV': 1e-3,
  };

  static const Map<String, double> _percentUnits = {
    '': 1.0,
    '%': 1.0,
    'PCT': 1.0,
  };

  static const Map<String, double> _phaseUnits = {
    '': 1.0,
    'DEG': 1.0,
    'DEGREE': 1.0,
  };

  /// Executes one command line. Returns the response for queries, or null for
  /// set commands and errors.
  Future<String?> execute(String input) async {
    final line = input.trim();
    if (line.isEmpty) return null;
    if (line.contains(';')) {
      _error(-113, 'Command chaining is not supported');
      return null;
    }

    final parts = line.split(RegExp(r'\s+'));
    var header = parts.first;
    final parameterText = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    final isQuery = header.endsWith('?');
    if (isQuery) header = header.substring(0, header.length - 1);

    final segments = header
        .toUpperCase()
        .split(':')
        .map((segment) => _segmentAliases[segment] ?? segment)
        .toList();

    try {
      return await _dispatch(segments, isQuery, parameterText);
    } on _ScpiSuffixException catch (e) {
      _error(-114, e.message);
    } on _ScpiHeaderException catch (e) {
      _error(-113, e.message);
    } on _ScpiParamException catch (e) {
      _error(-224, e.message);
    } on Jds6600RangeException catch (e) {
      _error(-222, e.message);
    } on Jds6600Exception catch (e) {
      _error(-100, e.message);
    } on ArgumentError catch (e) {
      _error(-224, e.message.toString());
    } catch (e) {
      _error(-100, e.toString());
    }
    return null;
  }

  Future<String?> _dispatch(
    List<String> segments,
    bool isQuery,
    String parameterText,
  ) async {
    if (segments.length == 1) {
      switch (segments.first) {
        case '*IDN':
          if (!isQuery) throw const _ScpiParamException('*IDN is a query');
          var info = _target.deviceInfo;
          if (info == null) {
            await _target.refreshDeviceInfo();
            info = _target.deviceInfo;
          }
          if (info == null) {
            throw const Jds6600Exception('Device has not been identified');
          }
          return Jds6600Protocol.identify(info);
        case '*RST':
          if (isQuery) throw const _ScpiParamException('*RST is not a query');
          await _target.resetSafeState();
          return null;
        case '*CLS':
          if (isQuery) throw const _ScpiParamException('*CLS is not a query');
          _target.clearErrors();
          return null;
        case '*OPC':
          if (!isQuery) throw const _ScpiParamException('*OPC is a query');
          return '1';
      }
    }

    final head = segments.first;

    if (head == 'SYST') return _dispatchSystem(segments, isQuery);
    if (head.startsWith('SOUR')) {
      return _dispatchSource(segments, isQuery, parameterText);
    }
    if (head.startsWith('OUTP')) {
      return _dispatchOutput(segments, isQuery, parameterText);
    }
    if (head == 'MEAS' || head == 'READ' || head == 'CALC') {
      throw const _ScpiHeaderException(
        'Measurement/readback subsystem is not supported in stage 1',
      );
    }

    throw _ScpiHeaderException('Undefined header "${segments.join(':')}"');
  }

  Future<String?> _dispatchSystem(List<String> segments, bool isQuery) async {
    if (segments.length >= 2 && segments[1] == 'ERR') {
      if (!isQuery) {
        throw const _ScpiParamException('SYST:ERR is a query');
      }
      if (segments.length == 3 && segments[2] == 'COUN') {
        return '${_target.errorCount}';
      }
      final error = _target.popError();
      return (error ?? const ScpiError(0, 'No error')).toString();
    }
    if (segments.length == 2 && segments[1] == 'VERS') {
      if (!isQuery) {
        throw const _ScpiParamException('SYST:VERS is a query');
      }
      return '1999.0';
    }
    if (segments.length == 3 &&
        segments[1] == 'COMM' &&
        segments[2] == 'BAUD') {
      if (!isQuery) {
        throw const _ScpiParamException('SYST:COMM:BAUD is a query');
      }
      return '115200';
    }
    if (segments.length == 2 &&
        (segments[1] == 'LOC' || segments[1] == 'REM')) {
      return null;
    }
    throw _ScpiHeaderException('Undefined header "${segments.join(':')}"');
  }

  Future<String?> _dispatchSource(
    List<String> segments,
    bool isQuery,
    String parameterText,
  ) async {
    final channel = _parseChannel(segments.first, 'SOUR');
    if (segments.length < 2) {
      throw const _ScpiHeaderException('Missing source subsystem');
    }

    switch (segments[1]) {
      case 'FUNC':
        if (segments.length == 2) {
          if (isQuery) {
            final waveform = await _target.readWaveform(channel);
            return waveform.scpiMnemonic;
          }
          final waveform = _parseWaveform(parameterText);
          await _target.setWaveform(channel, waveform);
          return null;
        }
        if (segments.length == 4 &&
            segments[2] == 'SQU' &&
            segments[3] == 'DCYC') {
          return _duty(channel, isQuery, parameterText);
        }
        if (segments.length >= 3 && segments[2] == 'ARB') {
          throw const _ScpiHeaderException(
            'Arbitrary waveform selection is not supported in stage 1',
          );
        }
        break;

      case 'FREQ':
        if (segments.length == 2) {
          if (isQuery) {
            final hz = await _target.readFrequency(channel);
            return _formatHz(hz);
          }
          final hz = _parseNumber(
            parameterText,
            defaultUnit: 'HZ',
            units: _frequencyUnits,
            kind: 'frequency',
          );
          await _target.setFrequency(channel, hz);
          return null;
        }
        throw const _ScpiHeaderException(
          'Sweep subsystem is not supported in stage 1',
        );

      case 'VOLT':
        if (segments.length == 2) {
          if (isQuery) {
            final vpp = await _target.readAmplitude(channel);
            return _formatAmplitude(vpp);
          }
          final vpp = _parseNumber(
            parameterText,
            defaultUnit: 'V',
            units: _voltageUnits,
            kind: 'amplitude',
          );
          await _target.setAmplitude(channel, vpp);
          return null;
        }
        if (segments.length == 3 && segments[2] == 'OFFS') {
          if (isQuery) {
            final volts = await _target.readOffset(channel);
            return _formatOffset(volts);
          }
          final volts = _parseNumber(
            parameterText,
            defaultUnit: 'V',
            units: _voltageUnits,
            kind: 'offset',
          );
          await _target.setOffset(channel, volts);
          return null;
        }
        break;

      case 'PULS':
        if (segments.length == 3 && segments[2] == 'DCYC') {
          return _duty(channel, isQuery, parameterText);
        }
        throw const _ScpiHeaderException(
          'Pulse-mode parameters are not supported in stage 1',
        );

      case 'PHAS':
        if (segments.length == 2) {
          if (isQuery) {
            final degrees = await _target.readPhase(channel);
            return _formatDegrees(degrees);
          }
          final degrees = _parseNumber(
            parameterText,
            defaultUnit: 'DEG',
            units: _phaseUnits,
            kind: 'phase',
          );
          await _target.setPhase(channel, degrees);
          return null;
        }
        break;

      case 'SWE':
        throw const _ScpiHeaderException(
          'Sweep subsystem is not supported in stage 1',
        );

      case 'BURS':
        throw const _ScpiHeaderException(
          'Burst subsystem is not supported in stage 1',
        );
    }

    throw _ScpiHeaderException('Undefined header "${segments.join(':')}"');
  }

  Future<String?> _duty(int channel, bool isQuery, String parameterText) async {
    if (isQuery) {
      final percent = await _target.readDuty(channel);
      return _formatPercent(percent);
    }
    final percent = _parseNumber(
      parameterText,
      defaultUnit: '%',
      units: _percentUnits,
      kind: 'duty cycle',
    );
    await _target.setDuty(channel, percent);
    return null;
  }

  Future<String?> _dispatchOutput(
    List<String> segments,
    bool isQuery,
    String parameterText,
  ) async {
    if (segments.first == 'OUTP' &&
        segments.length == 2 &&
        segments[1] == 'ALL') {
      if (isQuery) {
        final ch1 = await _target.readOutput(1);
        final ch2 = await _target.readOutput(2);
        return (ch1 && ch2) ? '1' : '0';
      }
      final enabled = _parseOnOff(parameterText);
      await _target.setOutput(1, enabled);
      await _target.setOutput(2, enabled);
      return null;
    }

    final channel = _parseChannel(segments.first, 'OUTP');
    if (segments.length > 2 ||
        (segments.length == 2 && segments[1] != 'STAT')) {
      throw _ScpiHeaderException('Undefined header "${segments.join(':')}"');
    }

    if (isQuery) {
      final enabled = await _target.readOutput(channel);
      return enabled ? '1' : '0';
    }
    final enabled = _parseOnOff(parameterText);
    await _target.setOutput(channel, enabled);
    return null;
  }

  int _parseChannel(String segment, String prefix) {
    final match = RegExp('^$prefix([12])\$').firstMatch(segment);
    if (match == null) {
      throw _ScpiSuffixException('Invalid channel header "$segment"');
    }
    return int.parse(match.group(1)!);
  }

  Jds6600Waveform _parseWaveform(String text) {
    final waveform = Jds6600Waveform.fromScpi(text);
    if (waveform == null) {
      throw _ScpiParamException('Unknown waveform "$text"');
    }
    if (waveform == Jds6600Waveform.arbitrary) {
      throw const _ScpiHeaderException(
        'Arbitrary waveform selection is not supported in stage 1',
      );
    }
    return waveform;
  }

  double _parseNumber(
    String text, {
    required String defaultUnit,
    required Map<String, double> units,
    required String kind,
  }) {
    final match = RegExp(
      r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*([A-Za-z%]*)$',
    ).firstMatch(text.trim());
    if (match == null) {
      throw _ScpiParamException('Invalid $kind "$text"');
    }
    final value = double.tryParse(match.group(1)!);
    if (value == null) {
      throw _ScpiParamException('Invalid $kind "$text"');
    }
    final unit = match.group(2)!.toUpperCase();
    final factor = unit.isEmpty ? units[defaultUnit] : units[unit];
    if (factor == null) {
      throw _ScpiParamException('Unsupported unit "$unit" for $kind');
    }
    return value * factor;
  }

  bool _parseOnOff(String text) {
    switch (text.trim().toUpperCase()) {
      case 'ON':
      case '1':
        return true;
      case 'OFF':
      case '0':
        return false;
    }
    throw _ScpiParamException('Expected ON/OFF/1/0, got "$text"');
  }

  String _formatHz(double hz) => hz.toStringAsFixed(2);
  String _formatAmplitude(double vpp) => vpp.toStringAsFixed(3);
  String _formatOffset(double volts) => volts.toStringAsFixed(2);
  String _formatPercent(double percent) => percent.toStringAsFixed(1);
  String _formatDegrees(double degrees) => degrees.toStringAsFixed(1);

  void _error(int code, String message) {
    _target.pushError(ScpiError(code, message));
  }
}

class _ScpiParamException implements Exception {
  const _ScpiParamException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Undefined or unsupported header (-113).
class _ScpiHeaderException extends _ScpiParamException {
  const _ScpiHeaderException(super.message);
}

/// Invalid channel suffix (-114).
class _ScpiSuffixException extends _ScpiParamException {
  const _ScpiSuffixException(super.message);
}
