part of 'calc_engine.dart';

// =============================================================================
// Built-in functions
// =============================================================================

extension on CalcEngine {
  CalcValue _callBuiltin(String name, List<CalcValue> arguments) {
    switch (name) {
      // ---- Powers, logarithms and rounding ----
      case 'abs':
        return _unaryQuantity(name, arguments, _absValue);
      case 'sqrt':
        return _unaryValue(name, arguments, _sqrtValue);
      case 'cbrt':
        return _unaryValue(name, arguments, _cbrtValue);
      case 'exp':
        return _unaryQuantity(name, arguments, _expValue);
      case 'ln':
        return _unaryQuantity(name, arguments, _lnValue);
      case 'log':
        return _logValue(arguments);
      case 'log10':
        return _unaryQuantity(
          name,
          arguments,
          (value) => _logBaseValue(value, 10),
        );
      case 'log2':
        return _unaryQuantity(
          name,
          arguments,
          (value) => _logBaseValue(value, 2),
        );
      case 'floor':
        return _roundingValue(
          name,
          arguments,
          (value) => value.floorToDouble(),
        );
      case 'ceil':
        return _roundingValue(name, arguments, (value) => value.ceilToDouble());
      case 'round':
        return _roundValue(arguments);
      case 'trunc':
        return _roundingValue(
          name,
          arguments,
          (value) => value.truncateToDouble(),
        );
      case 'frac':
        return _roundingValue(
          name,
          arguments,
          (value) => value - value.truncateToDouble(),
        );
      case 'sign':
        return _signValue(arguments);

      // ---- Trigonometry ----
      case 'sin':
      case 'cos':
      case 'tan':
      case 'asin':
      case 'acos':
      case 'atan':
        return _trigValue(name, arguments);
      case 'atan2':
        return _atan2Value(arguments);
      case 'sinh':
      case 'cosh':
      case 'tanh':
      case 'asinh':
      case 'acosh':
      case 'atanh':
        return _hyperbolicValue(name, arguments);

      // ---- Aggregates ----
      case 'min':
        return _minValue(_collectValues(arguments, name));
      case 'max':
        return _maxValue(_collectValues(arguments, name));
      case 'sum':
        return _sumValues(_collectValues(arguments, name));
      case 'prod':
      case 'product':
        return _productValues(_collectValues(arguments, name));
      case 'mean':
      case 'avg':
        return _meanValue(_collectValues(arguments, name));
      case 'median':
        return _medianValue(_collectValues(arguments, name));
      case 'stdev':
        return _stdevValue(_collectValues(arguments, name));
      case 'variance':
        return _varianceValue(_collectValues(arguments, name));
      case 'rms':
        return _rmsValue(_collectValues(arguments, name));
      case 'peak':
        return _peakValue(_collectValues(arguments, name));
      case 'p2p':
        return _p2pValue(_collectValues(arguments, name));
      case 'crest':
        return _crestValue(_collectValues(arguments, name));
      case 'meanabs':
        return _meanAbsValue(_collectValues(arguments, name));
      case 'count':
        return CalcQuantity.number(_collectValues(arguments, name).length);
      case 'mod':
        CalcEngine._requireArity(name, arguments, 2);
        return _modValues(arguments[0], arguments[1]);
      case 'intdiv':
        return _intDivValue(arguments);
      case 'hypot':
        return _hypotValue(arguments);
      case 'solve_quadratic':
        return _solveQuadraticValue(arguments);
      case 'clamp':
        return _clampValue(arguments);

      // ---- Integer and number theory ----
      case 'factorial':
        CalcEngine._requireArity(name, arguments, 1);
        return _factorialValue(arguments[0]);
      case 'gamma':
        return _gammaValue(arguments);
      case 'comb':
        return _combValue(arguments);
      case 'perm':
        return _permValue(arguments);
      case 'gcd':
        return _gcdValue(arguments);
      case 'lcm':
        return _lcmValue(arguments);
      case 'isprime':
        return _isPrimeValue(arguments);

      // ---- Complex numbers ----
      case 're':
        return _unaryQuantity(name, arguments, (value) => _realPart(value));
      case 'im':
        return _unaryQuantity(
          name,
          arguments,
          (value) => _imaginaryPart(value),
        );
      case 'conj':
        return _unaryQuantity(name, arguments, _conjugateValue);
      case 'arg':
      case 'phase':
        return _argValue(arguments);
      case 'polar':
        return _unaryQuantity(
          name,
          arguments,
          (value) => value.copyWith(complexForm: CalcComplexForm.polar),
        );
      case 'rect':
        return _unaryQuantity(
          name,
          arguments,
          (value) => value.copyWith(complexForm: CalcComplexForm.rectangular),
        );
      case 'complex':
        return _complexValue(arguments);
      case 'mag':
        return _unaryQuantity(name, arguments, _absValue);

      // ---- Vectors and matrices ----
      case 'dot':
        return _dotValue(
          _listArgument(name, arguments, 0),
          _listArgument(name, arguments, 1),
        );
      case 'cross':
        return _crossValue(
          _listArgument(name, arguments, 0),
          _listArgument(name, arguments, 1),
        );
      case 'matmul':
        return _matrixMultiply(
          _matrixArgument(name, arguments, 0),
          _matrixArgument(name, arguments, 1),
        );
      case 'transpose':
        return _transposeValue(_matrixArgument(name, arguments, 0));
      case 'det':
        return _determinantValue(_matrixArgument(name, arguments, 0));
      case 'inv':
        return _inverseValue(_matrixArgument(name, arguments, 0));
      case 'norm':
        CalcEngine._requireArity(name, arguments, 1);
        return _normValue(arguments[0]);
      case 'trace':
        return _traceValue(arguments);
      case 'shape':
        CalcEngine._requireArity(name, arguments, 1);
        return _shapeValue(arguments[0]);
      case 'identity':
        return _identityValue(_intArg(name, arguments, 0));
      case 'linsolve':
        return _linsolveValue(
          _matrixArgument(name, arguments, 0),
          _listArgument(name, arguments, 1),
        );
      case 'zeros':
        return _zerosBuiltin(arguments);
      case 'ones':
        return _onesBuiltin(arguments);
      case 'seq':
        return _seqBuiltin(arguments);

      // ---- Units and levels ----
      case 'to':
      case 'convert':
      case 'in':
        CalcEngine._requireArity(name, arguments, 2);
        return _convertTo(arguments[0], arguments[1]);
      case 'value':
        return _valueInUnit(arguments);
      case 'ratio':
        return _ratioBuiltin(arguments);
      case 'lin':
        return _linBuiltin(arguments);
      case 'db_value':
      case 'level':
        return _dbValueBuiltin(arguments);
      case 'db':
        return _dbLevelBuiltin(arguments, 'dB');
      case 'dbm':
        return _dbLevelBuiltin(arguments, 'dBm');
      case 'dbw':
        return _dbLevelBuiltin(arguments, 'dBW');
      case 'dbv':
        return _dbLevelBuiltin(arguments, 'dBV');
      case 'dbu':
        return _dbLevelBuiltin(arguments, 'dBu');
      case 'dbfs':
        return _dbLevelBuiltin(arguments, 'dBFS');
      case 'dbuv':
        return _dbLevelBuiltin(arguments, 'dBµV');
      case 'db10':
        return _ratioToDb(arguments, 10);
      case 'db20':
        return _ratioToDb(arguments, 20);
      case 'db_to_ratio':
        return _dbToRatioBuiltin(arguments, 10);
      case 'db_to_amp':
        return _dbToRatioBuiltin(arguments, 20);
      case 'ratio_to_db':
        return _linearToDbBuiltin(arguments, 10);
      case 'amp_to_db':
        return _linearToDbBuiltin(arguments, 20);
      case 'w_to_dbm':
        return _wToDbm(arguments);
      case 'dbm_to_w':
        return _dbmToW(arguments);
      case 'vrms_to_dbm':
        return _vrmsToDbm(arguments);
      case 'dbm_to_vrms':
        return _dbmToVrms(arguments);
      case 'dbv_to_vrms':
        return _levelToVoltage(arguments, 'dBV');
      case 'dbu_to_vrms':
        return _levelToVoltage(arguments, 'dBu');
      case 'dbuv_to_vrms':
        return _levelToVoltage(arguments, 'dBµV');
      case 'vrms_to_dbv':
        return _voltageToLevel(arguments, 'dBV');
      case 'vrms_to_dbu':
        return _voltageToLevel(arguments, 'dBu');
      case 'vrms_to_dbuv':
        return _voltageToLevel(arguments, 'dBµV');
      case 'dbfs_to_vrms':
        return _dbfsToVrms(arguments);
      case 'vrms_to_dbfs':
        return _vrmsToDbfs(arguments);

      // ---- Electronics, audio and RF ----
      case 'parallel':
        return _parallelValue(arguments);
      case 'series':
        return _seriesValue(arguments);
      case 'rc_cutoff':
        return _rcCutoff(arguments);
      case 'rl_cutoff':
        return _rlCutoff(arguments);
      case 'lc_resonance':
        return _lcResonance(arguments);
      case 'rlc_q':
        return _rlcQ(arguments);
      case 'impedance_c':
        return _impedanceC(arguments);
      case 'impedance_l':
        return _impedanceL(arguments);
      case 'impedance_r':
        return _impedanceR(arguments);
      case 'wavelength':
        return _wavelength(arguments);
      case 'fspl':
      case 'path_loss':
        return _fspl(arguments);
      case 'link_budget':
        return _linkBudget(arguments);
      case 'eirp':
        return _eirp(arguments);
      case 'vswr':
        return _vswr(arguments);
      case 'reflection':
        return _reflection(arguments);
      case 'return_loss':
        return _returnLoss(arguments);
      case 'mismatch_loss':
        return _mismatchLoss(arguments);
      case 'cable_loss':
        return _cableLoss(arguments);
      case 'thermal_noise':
        return _thermalNoise(arguments);
      case 'noise_floor_dbm':
        return _noiseFloor(arguments);
      case 'nf_cascade':
        return _nfCascade(arguments, db: false);
      case 'nf_cascade_db':
        return _nfCascade(arguments, db: true);
      case 'sensitivity_dbm':
        return _sensitivity(arguments);
      case 'dbm_per_hz':
        return _dbmPerHz(arguments);
      case 'thd':
        return _thd(arguments, db: false);
      case 'thd_db':
        return _thd(arguments, db: true);
      case 'snr_db':
        return _ratioDb(arguments);
      case 'sinad_db':
        return _ratioDb(arguments);
      case 'adc_lsb':
        return _adcLsb(arguments);
      case 'adc_snr':
        return _adcSnr(arguments);
      case 'quantization_error':
        return _quantizationError(arguments);
      case 'counts':
        return _counts(arguments);
      case 'percent_error':
        return _percentError(arguments);
      case 'tolerance':
        return _tolerance(arguments);

      // ---- Digital and embedded ----
      case 'pwm_frequency':
        return _pwmFrequency(arguments);
      case 'pwm_duty':
        return _pwmDuty(arguments);
      case 'timer_ticks':
        return _timerTicks(arguments);
      case 'uart_baud':
        return _uartBaud(arguments);
      case 'baud_error':
        return _baudError(arguments);
      case 'can_bitrate':
        return _canBitrate(arguments);
      case 'nyquist':
        return _nyquist(arguments);
      case 'fft_resolution':
        return _fftResolution(arguments);
      case 'rise_time':
        return _riseTime(arguments);
      case 'band':
      case 'bor':
      case 'bxor':
        return _bitwiseValue(name, arguments);
      case 'bnot':
        return _bnotValue(arguments);
      case 'shl':
      case 'shr':
      case 'sar':
        return _shiftValue(name, arguments);
      case 'popcount':
        return _popcountValue(arguments);
      case 'parity':
        return _parityValue(arguments);
      case 'bit':
        return _bitValue(arguments);
      case 'mask':
        return _maskValue(arguments);
      case 'to_signed':
        return _toSignedValue(arguments);
      case 'to_unsigned':
        return _toUnsignedValue(arguments);
      case 'hex':
        return _baseValue(arguments, CalcIntegerBase.hexadecimal);
      case 'bin':
        return _baseValue(arguments, CalcIntegerBase.binary);
      case 'oct':
        return _baseValue(arguments, CalcIntegerBase.octal);
      case 'dec':
        return _baseValue(arguments, CalcIntegerBase.decimal);
      case 'crc8':
        return _crc8Value(arguments);
      case 'crc16_ccitt':
        return _crc16Value(arguments);
      case 'q_format':
        return _qFormatValue(arguments);
      case 'q_to_float':
        return _qToFloatValue(arguments);

      // ---- Introspection ----
      case 'version':
        return const CalcText('SDS-Remote Engineering Calculator 1.0');
      case 'functions':
        final names = <String>{
          ...CalcEngine.builtinNames,
          ...functions.keys,
        }.toList()..sort();
        return CalcText(names.join(', '));
      case 'constants':
        return CalcText(CalcEngine.constantNames.join(', '));
      case 'units':
        return CalcText(CalcUnits.commonSymbols.join(' '));

      default:
        throw nameError('unknown function "$name"');
    }
  }

  // -------------------------------------------------------------------------
  // Argument helpers
  // -------------------------------------------------------------------------

  CalcQuantity _quantityArg(String name, List<CalcValue> arguments, int index) {
    if (index >= arguments.length) {
      throw argumentError('$name is missing argument ${index + 1}');
    }
    return CalcEngine._quantityArgument(name, arguments, index);
  }

  CalcList _listArgument(String name, List<CalcValue> arguments, int index) {
    final value = arguments[index];
    if (value is CalcList) {
      if (value.isMatrix) {
        throw argumentError('$name expects a vector, not a matrix');
      }
      return value;
    }
    throw argumentError('$name argument ${index + 1} must be a vector');
  }

  CalcList _matrixArgument(String name, List<CalcValue> arguments, int index) {
    final value = arguments[index];
    if (value is CalcList && value.isMatrix) return value;
    throw argumentError('$name argument ${index + 1} must be a matrix');
  }

  int _intArg(String name, List<CalcValue> arguments, int index) {
    return CalcEngine._integerArgument(
      _quantityArg(name, arguments, index),
      '$name argument ${index + 1}',
    );
  }

  CalcValue _unaryValue(
    String name,
    List<CalcValue> arguments,
    CalcValue Function(CalcValue) operation,
  ) {
    CalcEngine._requireArity(name, arguments, 1);
    return operation(arguments[0]);
  }

  CalcValue _unaryQuantity(
    String name,
    List<CalcValue> arguments,
    CalcQuantity Function(CalcQuantity) operation,
  ) {
    CalcEngine._requireArity(name, arguments, 1);
    final value = arguments[0];
    if (value is CalcList) {
      return CalcList(
        value.items
            .map((item) => _unaryQuantity(name, [item], operation))
            .toList(growable: false),
      );
    }
    if (value is! CalcQuantity) {
      throw argumentError('$name requires a number');
    }
    return operation(value);
  }

  // -------------------------------------------------------------------------
  // Powers, logarithms, rounding
  // -------------------------------------------------------------------------

  CalcQuantity _absValue(CalcQuantity value) {
    if (value.isLogDisplay) {
      throw unitError('abs is not defined for logarithmic levels');
    }
    return value.copyWith(
      si: CalcComplex.real(value.si.magnitude),
      complexForm: CalcComplexForm.rectangular,
    );
  }

  CalcQuantity _expValue(CalcQuantity value) {
    _requireDimensionless(value, 'exp');
    if (value.isLogDisplay) {
      throw unitError('convert a level to a linear value before exp');
    }
    return CalcQuantity(si: value.si.exp(), dimension: CalcDimension.none);
  }

  CalcQuantity _lnValue(CalcQuantity value) {
    _requireDimensionless(value, 'ln');
    if (value.isLogDisplay) {
      throw unitError('convert a level to a linear value before ln');
    }
    return CalcQuantity(si: value.si.ln(), dimension: CalcDimension.none);
  }

  CalcValue _logValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('log', arguments, 1, 2);
    final value = _quantityArg('log', arguments, 0);
    final base = arguments.length == 2
        ? CalcEngine._realArgument(
            _quantityArg('log', arguments, 1),
            'log base',
          )
        : 10.0;
    if (base <= 0 || base == 1) {
      throw domainError('the logarithm base must be positive and not 1');
    }
    return _logBaseValue(value, base);
  }

  CalcQuantity _logBaseValue(CalcQuantity value, double base) {
    _requireDimensionless(value, 'log');
    if (value.isLogDisplay) {
      throw unitError('convert a level to a linear value before log');
    }
    final result = value.si.ln() / CalcComplex.real(math.log(base));
    return CalcQuantity(si: result, dimension: CalcDimension.none);
  }

  CalcValue _roundingValue(
    String name,
    List<CalcValue> arguments,
    double Function(double) operation,
  ) {
    CalcEngine._requireArity(name, arguments, 1);
    return _unaryQuantity(
      name,
      arguments,
      (value) => _mapDisplayValue(value, operation),
    );
  }

  CalcValue _roundValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('round', arguments, 1, 2);
    final value = _quantityArg('round', arguments, 0);
    final digits = arguments.length == 2
        ? CalcEngine._integerArgument(
            _quantityArg('round', arguments, 1),
            'digits',
          )
        : 0;
    return _mapDisplayValue(value, (real) {
      final factor = math.pow(10.0, digits).toDouble();
      return (real * factor).roundToDouble() / factor;
    });
  }

  CalcQuantity _mapDisplayValue(
    CalcQuantity value,
    double Function(double) operation,
  ) {
    if (value.isLogDisplay) {
      throw unitError('convert a level to a linear value before rounding');
    }
    final real = CalcEngine._realArgument(value, 'value');
    final unit = value.displayUnit;
    if (unit != null) {
      final display = unit.fromSi(real);
      final mapped = operation(display);
      return CalcQuantity(
        si: CalcComplex(unit.toSi(mapped), 0),
        dimension: value.dimension,
        displayUnit: unit,
      );
    }
    return CalcQuantity(
      si: CalcComplex(operation(real), 0),
      dimension: value.dimension,
    );
  }

  CalcValue _signValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('sign', arguments, 1);
    final value = _quantityArg('sign', arguments, 0);
    final real = CalcEngine._realArgument(value, 'sign argument');
    if (real > 0) return CalcQuantity.number(1);
    if (real < 0) return CalcQuantity.number(-1);
    return CalcQuantity.number(0);
  }

  // -------------------------------------------------------------------------
  // Trigonometry
  // -------------------------------------------------------------------------

  CalcValue _trigValue(String name, List<CalcValue> arguments) {
    CalcEngine._requireArity(name, arguments, 1);
    final value = _quantityArg(name, arguments, 0);
    if (value.isLogDisplay) {
      throw unitError('convert a level to a linear value before $name');
    }

    if (name == 'asin' || name == 'acos' || name == 'atan') {
      if (!value.isDimensionless) {
        throw dimensionError('$name requires a dimensionless number');
      }
      if (!value.si.isReal) {
        throw unsupportedError('$name is only defined for real arguments');
      }
      final real = value.si.re;
      if (name == 'asin' || name == 'acos') {
        if (real < -1 || real > 1) {
          throw domainError('$name argument must be between -1 and 1');
        }
      }
      final radians = switch (name) {
        'asin' => math.asin(real),
        'acos' => math.acos(real),
        _ => math.atan(real),
      };
      return _angleFromRadians(radians);
    }

    if (!value.si.isReal) {
      // Complex trigonometric functions are evaluated in radians. Applying
      // the DEG/RAD mode to a complex argument has no well-defined meaning.
      final argument = value.si;
      final CalcComplex complexResult = switch (name) {
        'sin' => argument.sin(),
        'cos' => argument.cos(),
        _ => argument.tan(),
      };
      return CalcQuantity(si: complexResult, dimension: CalcDimension.none);
    }

    final radians = _angleToRadians(value);
    final result = switch (name) {
      'sin' => math.sin(radians),
      'cos' => math.cos(radians),
      _ => math.tan(radians),
    };
    return CalcQuantity.number(result);
  }

  CalcValue _atan2Value(List<CalcValue> arguments) {
    CalcEngine._requireArity('atan2', arguments, 2);
    final y = _quantityArg('atan2', arguments, 0);
    final x = _quantityArg('atan2', arguments, 1);
    if (!y.dimension.isCompatibleWith(x.dimension)) {
      throw dimensionError('atan2 arguments must have the same dimension');
    }
    final yReal = CalcEngine._realArgument(y, 'atan2 y');
    final xReal = CalcEngine._realArgument(x, 'atan2 x');
    return _angleFromRadians(math.atan2(yReal, xReal));
  }

  CalcValue _hyperbolicValue(String name, List<CalcValue> arguments) {
    CalcEngine._requireArity(name, arguments, 1);
    final value = _quantityArg(name, arguments, 0);
    _requireDimensionless(value, name);
    _requireReal(value, name);
    final real = value.si.re;
    final double result;
    switch (name) {
      case 'sinh':
        result = (math.exp(real) - math.exp(-real)) / 2;
      case 'cosh':
        result = (math.exp(real) + math.exp(-real)) / 2;
      case 'tanh':
        final positive = math.exp(real);
        final negative = math.exp(-real);
        result = (positive - negative) / (positive + negative);
      case 'asinh':
        result = math.log(real + math.sqrt(real * real + 1));
      case 'acosh':
        if (real < 1) {
          throw domainError('acosh argument must be at least 1');
        }
        result = math.log(real + math.sqrt(real * real - 1));
      default:
        if (real <= -1 || real >= 1) {
          throw domainError('atanh argument must be between -1 and 1');
        }
        result = 0.5 * math.log((1 + real) / (1 - real));
    }
    return CalcQuantity.number(result);
  }

  double _angleToRadians(CalcQuantity value) {
    if (value.isLogDisplay) {
      throw unitError('a logarithmic level is not an angle');
    }
    if (!value.si.isReal) {
      throw unsupportedError('an angle must be real');
    }
    if (value.dimension.isCompatibleWith(CalcDimension.base('rad'))) {
      return value.si.re;
    }
    if (value.isDimensionless) {
      return switch (settings.angleMode) {
        CalcAngleMode.degrees => value.si.re * math.pi / 180,
        CalcAngleMode.radians => value.si.re,
        CalcAngleMode.gradians => value.si.re * math.pi / 200,
      };
    }
    throw dimensionError(
      'expected an angle, got ${value.dimension.describe()}',
    );
  }

  CalcValue _angleFromRadians(double radians) {
    final value = switch (settings.angleMode) {
      CalcAngleMode.degrees => radians * 180 / math.pi,
      CalcAngleMode.radians => radians,
      CalcAngleMode.gradians => radians * 200 / math.pi,
    };
    return CalcQuantity.number(value);
  }

  // -------------------------------------------------------------------------
  // Integer helpers
  // -------------------------------------------------------------------------

  CalcValue _intDivValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('intdiv', arguments, 2);
    final a = CalcEngine._integerArgument(
      _quantityArg('intdiv', arguments, 0),
      'intdiv a',
    );
    final b = CalcEngine._integerArgument(
      _quantityArg('intdiv', arguments, 1),
      'intdiv b',
    );
    if (b == 0) throw divisionByZero('integer division by zero');
    return CalcQuantity.number(a ~/ b);
  }

  CalcValue _hypotValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('hypot', arguments, 2);
    final a = _quantityArg('hypot', arguments, 0);
    final b = _quantityArg('hypot', arguments, 1);
    if (!a.dimension.isCompatibleWith(b.dimension)) {
      throw dimensionError('hypot arguments must have the same dimension');
    }
    final sum = _addValues(_multiplyValues(a, a), _multiplyValues(b, b));
    return _sqrtValue(sum);
  }

  CalcValue _solveQuadraticValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('solve_quadratic', arguments, 3);
    final a = _quantityArg('solve_quadratic', arguments, 0);
    final b = _quantityArg('solve_quadratic', arguments, 1);
    final c = _quantityArg('solve_quadratic', arguments, 2);
    for (final value in [a, b, c]) {
      _requireDimensionless(value, 'solve_quadratic');
      _requireReal(value, 'solve_quadratic');
    }
    if (a.si.re == 0) {
      throw divisionByZero('quadratic coefficient a must not be zero');
    }
    final discriminant = b.si.re * b.si.re - 4 * a.si.re * c.si.re;
    final root = CalcComplex.real(discriminant).sqrt();
    final denominator = CalcComplex.real(2 * a.si.re);
    final first = (CalcComplex.real(-b.si.re) + root) / denominator;
    final second = (CalcComplex.real(-b.si.re) - root) / denominator;
    return CalcList([
      CalcQuantity(si: first, dimension: CalcDimension.none),
      CalcQuantity(si: second, dimension: CalcDimension.none),
    ]);
  }

  CalcValue _clampValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('clamp', arguments, 3);
    final value = _quantityArg('clamp', arguments, 0);
    final low = _quantityArg('clamp', arguments, 1);
    final high = _quantityArg('clamp', arguments, 2);
    if (!value.dimension.isCompatibleWith(low.dimension) ||
        !value.dimension.isCompatibleWith(high.dimension)) {
      throw dimensionError('clamp arguments must have the same dimension');
    }
    final real = CalcEngine._realArgument(value, 'clamp value');
    final lowValue = CalcEngine._realArgument(low, 'clamp lower bound');
    final highValue = CalcEngine._realArgument(high, 'clamp upper bound');
    if (lowValue > highValue) {
      throw argumentError('clamp lower bound exceeds the upper bound');
    }
    final clamped = real < lowValue
        ? lowValue
        : (real > highValue ? highValue : real);
    return CalcQuantity(
      si: CalcComplex.real(clamped),
      dimension: value.dimension,
      displayUnit: value.displayUnit,
    );
  }

  CalcValue _gammaValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('gamma', arguments, 1);
    final value = _quantityArg('gamma', arguments, 0);
    _requireDimensionless(value, 'gamma');
    final real = CalcEngine._realArgument(value, 'gamma argument');
    final result = _gammaFunction(real);
    if (!result.isFinite) {
      throw overflowError('gamma overflows the double range');
    }
    return CalcQuantity.number(result);
  }

  CalcValue _combValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('comb', arguments, 2);
    final n = _intArg('comb', arguments, 0);
    final k = _intArg('comb', arguments, 1);
    if (n < 0 || k < 0 || k > n) {
      throw domainError('comb requires 0 <= k <= n');
    }
    var result = 1.0;
    final smaller = math.min(k, n - k);
    for (var index = 1; index <= smaller; index++) {
      result = result * (n - smaller + index) / index;
    }
    if (!result.isFinite || result > 9.007199254740992e15) {
      throw overflowError('comb result is too large');
    }
    return CalcQuantity.number(result.roundToDouble());
  }

  CalcValue _permValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('perm', arguments, 2);
    final n = _intArg('perm', arguments, 0);
    final k = _intArg('perm', arguments, 1);
    if (n < 0 || k < 0 || k > n) {
      throw domainError('perm requires 0 <= k <= n');
    }
    var result = 1.0;
    for (var index = 0; index < k; index++) {
      result *= n - index;
    }
    if (!result.isFinite || result > 9.007199254740992e15) {
      throw overflowError('perm result is too large');
    }
    return CalcQuantity.number(result);
  }

  CalcValue _gcdValue(List<CalcValue> arguments) {
    if (arguments.isEmpty) throw argumentError('gcd requires values');
    var result = 0;
    for (var index = 0; index < arguments.length; index++) {
      result = _gcd(result, _intArg('gcd', arguments, index).abs());
    }
    return CalcQuantity.number(result);
  }

  CalcValue _lcmValue(List<CalcValue> arguments) {
    if (arguments.isEmpty) throw argumentError('lcm requires values');
    var result = 1;
    for (var index = 0; index < arguments.length; index++) {
      final value = _intArg('lcm', arguments, index).abs();
      if (value == 0) return CalcQuantity.number(0);
      result = (result ~/ _gcd(result, value)) * value;
    }
    return CalcQuantity.number(result);
  }

  static int _gcd(int a, int b) {
    var left = a;
    var right = b;
    while (right != 0) {
      final temporary = right;
      right = left % right;
      left = temporary;
    }
    return left;
  }

  CalcValue _isPrimeValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('isprime', arguments, 1);
    final value = _intArg('isprime', arguments, 0);
    if (value < 2) return const CalcBool(false);
    if (value == 2) return const CalcBool(true);
    if (value.isEven) return const CalcBool(false);
    for (var divisor = 3; divisor * divisor <= value; divisor += 2) {
      if (value % divisor == 0) return const CalcBool(false);
    }
    return const CalcBool(true);
  }

  // -------------------------------------------------------------------------
  // Complex helpers
  // -------------------------------------------------------------------------

  CalcQuantity _realPart(CalcQuantity value) => value.copyWith(
    si: CalcComplex.real(value.si.re),
    complexForm: CalcComplexForm.rectangular,
  );

  CalcQuantity _imaginaryPart(CalcQuantity value) => value.copyWith(
    si: CalcComplex.real(value.si.im),
    complexForm: CalcComplexForm.rectangular,
  );

  CalcQuantity _conjugateValue(CalcQuantity value) =>
      value.copyWith(si: value.si.conjugate());

  CalcValue _argValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('arg', arguments, 1);
    final value = _quantityArg('arg', arguments, 0);
    if (value.isLogDisplay) {
      throw unitError('a logarithmic level has no phase');
    }
    return _angleFromRadians(value.si.phase);
  }

  CalcValue _complexValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('complex', arguments, 2);
    final real = _quantityArg('complex', arguments, 0);
    final imaginary = _quantityArg('complex', arguments, 1);
    if (!real.dimension.isCompatibleWith(imaginary.dimension)) {
      throw dimensionError('complex components must have the same dimension');
    }
    if (!real.si.isReal || !imaginary.si.isReal) {
      throw argumentError('complex components must be real');
    }
    return CalcQuantity(
      si: CalcComplex(real.si.re, imaginary.si.re),
      dimension: real.dimension,
    );
  }

  // -------------------------------------------------------------------------
  // Unit and level helpers
  // -------------------------------------------------------------------------

  void _requireDimensionless(CalcQuantity value, String name) {
    if (!value.isDimensionless) {
      throw dimensionError(
        '$name requires a dimensionless value, got '
        '${value.dimension.describe()}',
      );
    }
  }

  void _requireReal(CalcQuantity value, String name) {
    if (!value.si.isReal) {
      throw unsupportedError('$name requires a real value');
    }
  }

  CalcValue _valueInUnit(List<CalcValue> arguments) {
    CalcEngine._requireArity('value', arguments, 2);
    final value = arguments[0];
    final target = arguments[1];
    if (value is! CalcQuantity) {
      throw argumentError('value requires a number as its first argument');
    }
    if (target is! CalcQuantity ||
        !target.unitMarker ||
        target.displayUnit == null) {
      throw unitError('value requires a unit as its second argument');
    }
    final unit = target.displayUnit!;
    if (!value.dimension.isCompatibleWith(unit.dimension)) {
      throw dimensionError(
        'cannot express ${value.dimension.describe()} in ${unit.symbol}',
      );
    }
    if (unit.isLog) {
      if (!value.si.isReal) {
        throw unsupportedError('a logarithmic value must be real');
      }
      final level = unit.siToLevel(value.si.re);
      return CalcQuantity.number(level);
    }
    final real = unit.fromSi(value.si.re);
    final imaginary = value.si.im / unit.scale;
    return CalcQuantity(
      si: CalcComplex(real, imaginary),
      dimension: CalcDimension.none,
    );
  }

  CalcValue _ratioBuiltin(List<CalcValue> arguments) {
    CalcEngine._requireArity('ratio', arguments, 1);
    final value = arguments[0];
    if (value is! CalcQuantity) {
      throw argumentError('ratio requires a number');
    }
    if (!value.isDimensionless) {
      throw dimensionError('ratio requires a dimensionless value');
    }
    if (value.isLogDisplay) {
      return CalcQuantity(si: value.si, dimension: CalcDimension.none);
    }
    return CalcQuantity(si: value.si, dimension: CalcDimension.none);
  }

  CalcValue _linBuiltin(List<CalcValue> arguments) {
    CalcEngine._requireArity('lin', arguments, 1);
    final value = arguments[0];
    if (value is! CalcQuantity) {
      throw argumentError('lin requires a number');
    }
    return CalcQuantity(si: value.si, dimension: CalcDimension.none);
  }

  CalcValue _dbValueBuiltin(List<CalcValue> arguments) {
    CalcEngine._requireArity('db_value', arguments, 1);
    final value = _quantityArg('db_value', arguments, 0);
    if (!value.isLogDisplay) {
      throw argumentError('db_value requires a value with a dB unit');
    }
    return CalcQuantity.number(value.levelValue);
  }

  CalcValue _dbLevelBuiltin(List<CalcValue> arguments, String symbol) {
    CalcEngine._requireArity('db', arguments, 1);
    final level = CalcEngine._realArgument(
      _quantityArg('db', arguments, 0),
      'level',
    );
    return _levelQuantity(level, symbol);
  }

  CalcQuantity _levelQuantity(double level, String symbol) {
    final unit = CalcUnits.resolve(symbol);
    if (unit == null || !unit.isLog) {
      throw StateError('calculator log unit $symbol is missing');
    }
    if (!level.isFinite) {
      throw overflowError('level is not finite');
    }
    return CalcQuantity(
      si: CalcComplex(unit.levelToSi(level), 0),
      dimension: unit.dimension,
      displayUnit: unit,
    );
  }

  CalcValue _ratioToDb(List<CalcValue> arguments, int factor) {
    CalcEngine._requireArity('db$factor', arguments, 1);
    final ratio = _ratioNumber(
      _quantityArg('db$factor', arguments, 0),
      'ratio',
    );
    if (ratio <= 0) {
      throw domainError('a ratio must be greater than zero');
    }
    final level = factor * math.log(ratio) / math.ln10;
    return _levelQuantity(level, 'dB');
  }

  CalcValue _dbToRatioBuiltin(List<CalcValue> arguments, int factor) {
    CalcEngine._requireArity('db_to_ratio', arguments, 1);
    final value = _quantityArg('db_to_ratio', arguments, 0);
    final level = _dBValue(value);
    final ratio = math.pow(10.0, level / factor).toDouble();
    if (!ratio.isFinite) {
      throw overflowError('ratio overflows the double range');
    }
    return CalcQuantity.number(ratio);
  }

  CalcValue _linearToDbBuiltin(List<CalcValue> arguments, int factor) {
    CalcEngine._requireArity('ratio_to_db', arguments, 1);
    final value = _quantityArg('ratio_to_db', arguments, 0);
    final ratio = _ratioNumber(value, 'ratio');
    if (ratio <= 0) {
      throw domainError('a ratio must be greater than zero');
    }
    final level = factor * math.log(ratio) / math.ln10;
    return _levelQuantity(level, 'dB');
  }

  double _dBValue(CalcQuantity value) {
    if (value.isLogDisplay) return value.levelValue;
    if (value.isDimensionless) return CalcEngine._realArgument(value, 'level');
    throw argumentError('expected a dB value or a plain number');
  }

  double _ratioNumber(CalcQuantity value, String label) {
    if (!value.isDimensionless) {
      throw dimensionError('$label must be dimensionless');
    }
    final real = CalcEngine._realArgument(value, label);
    if (real <= 0) {
      throw domainError('$label must be greater than zero');
    }
    return real;
  }

  CalcValue _wToDbm(List<CalcValue> arguments) {
    CalcEngine._requireArity('w_to_dbm', arguments, 1);
    final power = _quantityArg('w_to_dbm', arguments, 0);
    _requireDimension(power, 'W', 'w_to_dbm');
    return power.copyWith(
      displayUnit: CalcUnits.resolve('dBm'),
      complexForm: CalcComplexForm.rectangular,
    );
  }

  CalcValue _dbmToW(List<CalcValue> arguments) {
    CalcEngine._requireArity('dbm_to_w', arguments, 1);
    final value = _quantityArg('dbm_to_w', arguments, 0);
    final power = _asPower(value, 'dbm_to_w');
    return power.copyWith(displayUnit: CalcUnits.resolve('W'));
  }

  CalcQuantity _asPower(CalcQuantity value, String name) {
    if (value.isLogDisplay) {
      if (!value.dimension.isCompatibleWith(
        CalcUnits.resolve('W')!.dimension,
      )) {
        throw dimensionError('$name expects a power level');
      }
      return value;
    }
    if (value.isDimensionless) {
      return _levelQuantity(CalcEngine._realArgument(value, name), 'dBm');
    }
    _requireDimension(value, 'W', name);
    return value;
  }

  CalcQuantity _asVoltage(CalcQuantity value, String name) {
    final volt = CalcUnits.resolve('V')!;
    if (value.isLogDisplay) {
      if (!value.dimension.isCompatibleWith(volt.dimension)) {
        throw dimensionError('$name expects a voltage level');
      }
      return value.copyWith(displayUnit: volt);
    }
    if (value.isDimensionless && value.displayUnit == null) {
      // A bare number is interpreted as volts, not as a dBV level.
      return CalcQuantity(
        si: value.si,
        dimension: volt.dimension,
        displayUnit: volt,
      );
    }
    _requireDimension(value, 'V', name);
    return value;
  }

  void _requireDimension(CalcQuantity value, String symbol, String name) {
    final unit = CalcUnits.resolve(symbol);
    if (unit == null) throw StateError('unit $symbol is missing');
    if (!value.dimension.isCompatibleWith(unit.dimension)) {
      throw dimensionError(
        '$name expects ${unit.quantityName ?? symbol}, got '
        '${value.dimension.describe()}',
      );
    }
  }

  CalcValue _vrmsToDbm(List<CalcValue> arguments) {
    CalcEngine._requireArity('vrms_to_dbm', arguments, 2);
    final rawVoltage = _quantityArg('vrms_to_dbm', arguments, 0);
    final voltage = rawVoltage.isDimensionless && rawVoltage.displayUnit == null
        ? CalcQuantity(
            si: rawVoltage.si,
            dimension: CalcUnits.resolve('V')!.dimension,
            displayUnit: CalcUnits.resolve('V'),
          )
        : rawVoltage;
    final resistance = _quantityArg('vrms_to_dbm', arguments, 1);
    _requireDimension(voltage, 'V', 'vrms_to_dbm');
    _requireDimension(resistance, 'Ω', 'vrms_to_dbm');
    final power =
        _divideValues(_multiplyValues(voltage, voltage), resistance)
            as CalcQuantity;
    return power.copyWith(displayUnit: CalcUnits.resolve('dBm'));
  }

  CalcValue _dbmToVrms(List<CalcValue> arguments) {
    CalcEngine._requireArity('dbm_to_vrms', arguments, 2);
    final level = _asPower(
      _quantityArg('dbm_to_vrms', arguments, 0),
      'dbm_to_vrms',
    );
    final resistance = _quantityArg('dbm_to_vrms', arguments, 1);
    _requireDimension(resistance, 'Ω', 'dbm_to_vrms');
    final power = level.copyWith(displayUnit: CalcUnits.resolve('W'));
    final voltage = _sqrtValue(_multiplyValues(power, resistance));
    return (voltage as CalcQuantity).copyWith(
      displayUnit: CalcUnits.resolve('V'),
    );
  }

  CalcValue _levelToVoltage(List<CalcValue> arguments, String symbol) {
    CalcEngine._requireArity('level_to_voltage', arguments, 1);
    final value = _quantityArg('level_to_voltage', arguments, 0);
    final unit = CalcUnits.resolve(symbol)!;
    final linear = CalcQuantity(
      si: CalcComplex(
        unit.levelToSi(
          value.isLogDisplay
              ? value.levelValue
              : CalcEngine._realArgument(value, 'level'),
        ),
        0,
      ),
      dimension: unit.dimension,
      displayUnit: CalcUnits.resolve('V'),
    );
    return linear;
  }

  CalcValue _voltageToLevel(List<CalcValue> arguments, String symbol) {
    CalcEngine._requireArity('voltage_to_level', arguments, 1);
    final value = _asVoltage(
      _quantityArg('voltage_to_level', arguments, 0),
      'voltage_to_level',
    );
    final unit = CalcUnits.resolve(symbol)!;
    final voltage = value.si.re.abs();
    if (voltage == 0) {
      throw domainError('0 V has no finite $symbol level');
    }
    final level = unit.siToLevel(voltage);
    return _levelQuantity(level, symbol);
  }

  CalcValue _dbfsToVrms(List<CalcValue> arguments) {
    CalcEngine._requireArity('dbfs_to_vrms', arguments, 2);
    final level = _quantityArg('dbfs_to_vrms', arguments, 0);
    final fullScale = _quantityArg('dbfs_to_vrms', arguments, 1);
    _requireDimension(fullScale, 'V', 'dbfs_to_vrms');
    final value = level.isLogDisplay
        ? level.levelValue
        : CalcEngine._realArgument(level, 'dBFS level');
    final ratio = math.pow(10.0, value / 20).toDouble();
    final voltage = CalcQuantity(
      si: fullScale.si * CalcComplex.real(ratio),
      dimension: fullScale.dimension,
      displayUnit: CalcUnits.resolve('V'),
    );
    return voltage;
  }

  CalcValue _vrmsToDbfs(List<CalcValue> arguments) {
    CalcEngine._requireArity('vrms_to_dbfs', arguments, 2);
    final voltage = _quantityArg('vrms_to_dbfs', arguments, 0);
    final fullScale = _quantityArg('vrms_to_dbfs', arguments, 1);
    _requireDimension(voltage, 'V', 'vrms_to_dbfs');
    _requireDimension(fullScale, 'V', 'vrms_to_dbfs');
    if (fullScale.si.re == 0) {
      throw divisionByZero('full-scale voltage must not be zero');
    }
    final ratio = voltage.si.re / fullScale.si.re;
    if (ratio <= 0) {
      throw domainError('voltage ratio must be greater than zero');
    }
    final level = 20 * math.log(ratio) / math.ln10;
    return _levelQuantity(level, 'dBFS');
  }

  // -------------------------------------------------------------------------
  // Electronics, audio and RF
  // -------------------------------------------------------------------------

  CalcValue _parallelValue(List<CalcValue> arguments) {
    final values = _collectValues(arguments, 'parallel');
    if (values.isEmpty) {
      throw argumentError('parallel requires at least one value');
    }
    CalcValue? reciprocalSum;
    for (final value in values) {
      final reciprocal = _divideValues(CalcQuantity.number(1), value);
      reciprocalSum = reciprocalSum == null
          ? reciprocal
          : _addValues(reciprocalSum, reciprocal);
    }
    return _divideValues(CalcQuantity.number(1), reciprocalSum!);
  }

  CalcValue _seriesValue(List<CalcValue> arguments) =>
      _sumValues(_collectValues(arguments, 'series'));

  CalcValue _rcCutoff(List<CalcValue> arguments) {
    CalcEngine._requireArity('rc_cutoff', arguments, 2);
    final resistance = _quantityArg('rc_cutoff', arguments, 0);
    final capacitance = _quantityArg('rc_cutoff', arguments, 1);
    _requireDimension(resistance, 'Ω', 'rc_cutoff');
    _requireDimension(capacitance, 'F', 'rc_cutoff');
    return _divideValues(
      CalcQuantity.number(1),
      _multiplyValues(
        _multiplyValues(CalcQuantity.number(2 * math.pi), resistance),
        capacitance,
      ),
    );
  }

  CalcValue _rlCutoff(List<CalcValue> arguments) {
    CalcEngine._requireArity('rl_cutoff', arguments, 2);
    final resistance = _quantityArg('rl_cutoff', arguments, 0);
    final inductance = _quantityArg('rl_cutoff', arguments, 1);
    _requireDimension(resistance, 'Ω', 'rl_cutoff');
    _requireDimension(inductance, 'H', 'rl_cutoff');
    return _divideValues(
      resistance,
      _multiplyValues(CalcQuantity.number(2 * math.pi), inductance),
    );
  }

  CalcValue _lcResonance(List<CalcValue> arguments) {
    CalcEngine._requireArity('lc_resonance', arguments, 2);
    final inductance = _quantityArg('lc_resonance', arguments, 0);
    final capacitance = _quantityArg('lc_resonance', arguments, 1);
    _requireDimension(inductance, 'H', 'lc_resonance');
    _requireDimension(capacitance, 'F', 'lc_resonance');
    return _divideValues(
      CalcQuantity.number(1),
      _multiplyValues(
        CalcQuantity.number(2 * math.pi),
        _sqrtValue(_multiplyValues(inductance, capacitance)),
      ),
    );
  }

  CalcValue _rlcQ(List<CalcValue> arguments) {
    CalcEngine._requireArity('rlc_q', arguments, 3);
    final resistance = _quantityArg('rlc_q', arguments, 0);
    final inductance = _quantityArg('rlc_q', arguments, 1);
    final capacitance = _quantityArg('rlc_q', arguments, 2);
    _requireDimension(resistance, 'Ω', 'rlc_q');
    _requireDimension(inductance, 'H', 'rlc_q');
    _requireDimension(capacitance, 'F', 'rlc_q');
    return _divideValues(
      _sqrtValue(_divideValues(inductance, capacitance)),
      resistance,
    );
  }

  CalcValue _impedanceC(List<CalcValue> arguments) {
    CalcEngine._requireArity('impedance_c', arguments, 2);
    final capacitance = _quantityArg('impedance_c', arguments, 0);
    final frequency = _quantityArg('impedance_c', arguments, 1);
    _requireDimension(capacitance, 'F', 'impedance_c');
    _requireDimension(frequency, 'Hz', 'impedance_c');
    return _divideValues(
      CalcQuantity.number(1),
      _multiplyValues(
        _multiplyValues(
          CalcEngine._constants['j']!,
          CalcQuantity.number(2 * math.pi),
        ),
        _multiplyValues(frequency, capacitance),
      ),
    );
  }

  CalcValue _impedanceL(List<CalcValue> arguments) {
    CalcEngine._requireArity('impedance_l', arguments, 2);
    final inductance = _quantityArg('impedance_l', arguments, 0);
    final frequency = _quantityArg('impedance_l', arguments, 1);
    _requireDimension(inductance, 'H', 'impedance_l');
    _requireDimension(frequency, 'Hz', 'impedance_l');
    return _multiplyValues(
      _multiplyValues(
        _multiplyValues(
          CalcEngine._constants['j']!,
          CalcQuantity.number(2 * math.pi),
        ),
        frequency,
      ),
      inductance,
    );
  }

  CalcValue _impedanceR(List<CalcValue> arguments) {
    CalcEngine._requireArity('impedance_r', arguments, 1, 2);
    final resistance = _quantityArg('impedance_r', arguments, 0);
    _requireDimension(resistance, 'Ω', 'impedance_r');
    return resistance;
  }

  CalcValue _wavelength(List<CalcValue> arguments) {
    CalcEngine._requireArity('wavelength', arguments, 1);
    final frequency = _quantityArg('wavelength', arguments, 0);
    _requireDimension(frequency, 'Hz', 'wavelength');
    return _divideValues(CalcEngine._constants['c_0']!, frequency);
  }

  CalcValue _fspl(List<CalcValue> arguments) {
    CalcEngine._requireArity('fspl', arguments, 2);
    final distance = _quantityArg('fspl', arguments, 0);
    final frequency = _quantityArg('fspl', arguments, 1);
    _requireDimension(distance, 'm', 'fspl');
    _requireDimension(frequency, 'Hz', 'fspl');
    final ratio = _divideValues(
      _multiplyValues(
        _multiplyValues(CalcQuantity.number(4 * math.pi), distance),
        frequency,
      ),
      CalcEngine._constants['c_0']!,
    );
    final squared = _multiplyValues(ratio, ratio) as CalcQuantity;
    return _ratioToDb([squared], 10);
  }

  CalcValue _linkBudget(List<CalcValue> arguments) {
    CalcEngine._requireArity('link_budget', arguments, 4, 6);
    var budget = _addValues(
      _asDbmLink(_quantityArg('link_budget', arguments, 0)),
      _asDbValue(_quantityArg('link_budget', arguments, 1)),
    );
    budget = _addValues(
      budget,
      _asDbValue(_quantityArg('link_budget', arguments, 2)),
    );
    budget = _subtractValues(
      budget,
      _asDbValue(_quantityArg('link_budget', arguments, 3)),
    );
    if (arguments.length > 4) {
      budget = _subtractValues(
        budget,
        _asDbValue(_quantityArg('link_budget', arguments, 4)),
      );
    }
    if (arguments.length > 5) {
      budget = _subtractValues(
        budget,
        _asDbValue(_quantityArg('link_budget', arguments, 5)),
      );
    }
    return budget;
  }

  CalcQuantity _asDbmLink(CalcQuantity value) {
    if (value.isLogDisplay) return value;
    if (value.isDimensionless) {
      return _levelQuantity(CalcEngine._realArgument(value, 'power'), 'dBm');
    }
    _requireDimension(value, 'W', 'link_budget');
    return value.copyWith(displayUnit: CalcUnits.resolve('dBm'));
  }

  CalcQuantity _asDbValue(CalcQuantity value) {
    if (value.isLogDisplay) return value;
    if (value.isDimensionless) {
      return _levelQuantity(
        CalcEngine._realArgument(value, 'gain or loss'),
        'dB',
      );
    }
    throw dimensionError('gains and losses must be in dB');
  }

  CalcValue _eirp(List<CalcValue> arguments) {
    CalcEngine._requireArity('eirp', arguments, 2);
    return _addValues(
      _asDbmLink(_quantityArg('eirp', arguments, 0)),
      _asDbValue(_quantityArg('eirp', arguments, 1)),
    );
  }

  CalcValue _vswr(List<CalcValue> arguments) {
    CalcEngine._requireArity('vswr', arguments, 1);
    final gamma = _quantityArg('vswr', arguments, 0);
    _requireDimensionless(gamma, 'vswr');
    final magnitude = gamma.si.magnitude;
    if (magnitude >= 1) {
      throw domainError('VSWR requires |Γ| < 1');
    }
    return CalcQuantity.number((1 + magnitude) / (1 - magnitude));
  }

  CalcValue _reflection(List<CalcValue> arguments) {
    CalcEngine._requireArity('reflection', arguments, 2);
    final load = _quantityArg('reflection', arguments, 0);
    final reference = _quantityArg('reflection', arguments, 1);
    if (!load.dimension.isCompatibleWith(reference.dimension)) {
      throw dimensionError('impedances must have the same dimension');
    }
    final denominator = _addValues(load, reference);
    final numerator = _subtractValues(load, reference);
    return _divideValues(numerator, denominator);
  }

  CalcValue _returnLoss(List<CalcValue> arguments) {
    CalcEngine._requireArity('return_loss', arguments, 1);
    final gamma = _quantityArg('return_loss', arguments, 0);
    _requireDimensionless(gamma, 'return_loss');
    final magnitude = gamma.si.magnitude;
    if (magnitude == 0) {
      throw domainError('a perfect match has infinite return loss');
    }
    return _ratioToDb([CalcQuantity.number(1 / magnitude)], 20);
  }

  CalcValue _mismatchLoss(List<CalcValue> arguments) {
    CalcEngine._requireArity('mismatch_loss', arguments, 1);
    final gamma = _quantityArg('mismatch_loss', arguments, 0);
    _requireDimensionless(gamma, 'mismatch_loss');
    final squared = gamma.si.magnitudeSquared;
    if (squared >= 1) {
      throw domainError('mismatch loss requires |Γ| < 1');
    }
    return _ratioToDb([CalcQuantity.number(1 / (1 - squared))], 10);
  }

  CalcValue _cableLoss(List<CalcValue> arguments) {
    CalcEngine._requireArity('cable_loss', arguments, 2);
    final loss = CalcEngine._realArgument(
      _quantityArg('cable_loss', arguments, 0),
      'loss per metre',
    );
    final length = CalcEngine._realArgument(
      _quantityArg('cable_loss', arguments, 1),
      'length in metres',
    );
    return _levelQuantity(loss * length, 'dB');
  }

  CalcValue _thermalNoise(List<CalcValue> arguments) {
    CalcEngine._requireArity('thermal_noise', arguments, 1, 2);
    final bandwidth = _quantityArg('thermal_noise', arguments, 0);
    _requireDimension(bandwidth, 'Hz', 'thermal_noise');
    final temperature = arguments.length > 1
        ? _quantityArg('thermal_noise', arguments, 1)
        : CalcQuantity.fromUnit(290, CalcUnits.resolve('K')!);
    _requireDimension(temperature, 'K', 'thermal_noise');
    return _multiplyValues(
      _multiplyValues(CalcEngine._constants['k_B']!, temperature),
      bandwidth,
    );
  }

  CalcValue _noiseFloor(List<CalcValue> arguments) {
    CalcEngine._requireArity('noise_floor_dbm', arguments, 1, 2);
    final noise = _thermalNoise([arguments[0]]) as CalcQuantity;
    var result = _wToDbm([noise]) as CalcQuantity;
    if (arguments.length > 1) {
      result =
          _addValues(
                result,
                _asDbValue(_quantityArg('noise_floor_dbm', arguments, 1)),
              )
              as CalcQuantity;
    }
    return result;
  }

  CalcValue _nfCascade(List<CalcValue> arguments, {required bool db}) {
    CalcEngine._requireArity('nf_cascade', arguments, 2);
    final factors = _collectValues([arguments[0]], 'nf_cascade');
    final gains = _collectValues([arguments[1]], 'nf_cascade');
    if (factors.length != gains.length) {
      throw argumentError('noise factors and gains must have equal length');
    }
    if (factors.isEmpty) {
      throw argumentError('nf_cascade requires at least one stage');
    }
    var total = 0.0;
    var cumulativeGain = 1.0;
    for (var index = 0; index < factors.length; index++) {
      final factorQuantity = _requireQuantityValue(factors[index]);
      final gainQuantity = _requireQuantityValue(gains[index]);
      final factorLinear = db
          ? math.pow(10.0, _dBValue(factorQuantity) / 10).toDouble()
          : _ratioNumber(factorQuantity, 'noise factor');
      final gainLinear = db
          ? math.pow(10.0, _dBValue(gainQuantity) / 10).toDouble()
          : _ratioNumber(gainQuantity, 'gain');
      if (gainLinear <= 0) {
        throw domainError('stage gain must be greater than zero');
      }
      if (index == 0) {
        total = factorLinear;
      } else {
        total += (factorLinear - 1) / cumulativeGain;
      }
      cumulativeGain *= gainLinear;
    }
    return db
        ? _ratioToDb([CalcQuantity.number(total)], 10)
        : CalcQuantity.number(total);
  }

  CalcValue _sensitivity(List<CalcValue> arguments) {
    CalcEngine._requireArity('sensitivity_dbm', arguments, 3);
    final noiseFigure = _dBValue(_quantityArg('sensitivity_dbm', arguments, 0));
    final bandwidth = _quantityArg('sensitivity_dbm', arguments, 1);
    _requireDimension(bandwidth, 'Hz', 'sensitivity_dbm');
    final snr = _dBValue(_quantityArg('sensitivity_dbm', arguments, 2));
    final bandwidthDb = 10 * math.log(bandwidth.si.re.abs()) / math.ln10;
    final level = -174.0 + bandwidthDb + noiseFigure + snr;
    return _levelQuantity(level, 'dBm');
  }

  CalcValue _dbmPerHz(List<CalcValue> arguments) {
    CalcEngine._requireArity('dbm_per_hz', arguments, 2);
    final power = _asPower(
      _quantityArg('dbm_per_hz', arguments, 0),
      'dbm_per_hz',
    );
    final bandwidth = _quantityArg('dbm_per_hz', arguments, 1);
    final bandwidthHz =
        bandwidth.dimension.isCompatibleWith(CalcUnits.resolve('Hz')!.dimension)
        ? bandwidth.si.re.abs()
        : (bandwidth.isDimensionless
              ? CalcEngine._realArgument(bandwidth, 'bandwidth')
              : throw dimensionError('bandwidth must be in Hz'));
    if (bandwidthHz <= 0) {
      throw domainError('bandwidth must be greater than zero');
    }
    final bandwidthDb = 10 * math.log(bandwidthHz) / math.ln10;
    final powerDbm = power.isLogDisplay
        ? power
        : power.copyWith(displayUnit: CalcUnits.resolve('dBm'));
    final level = powerDbm.levelValue - bandwidthDb;
    return _levelQuantity(level, 'dBm');
  }

  CalcValue _thd(List<CalcValue> arguments, {required bool db}) {
    CalcEngine._requireArity('thd', arguments, 2);
    final fundamental = _quantityArg('thd', arguments, 0);
    _requireDimension(fundamental, 'V', 'thd');
    final harmonics = arguments.length == 2 && arguments[1] is CalcList
        ? (arguments[1] as CalcList).items
        : arguments.sublist(1);
    if (harmonics.isEmpty) {
      throw argumentError('thd requires at least one harmonic');
    }
    CalcValue? squares;
    for (final item in harmonics) {
      final harmonic = _requireQuantityValue(item);
      _requireDimension(harmonic, 'V', 'thd');
      final square = _multiplyValues(harmonic, harmonic);
      squares = squares == null ? square : _addValues(squares, square);
    }
    final magnitude = _sqrtValue(squares!);
    final ratio = _divideValues(magnitude, fundamental) as CalcQuantity;
    if (db) return _ratioToDb([ratio], 20);
    return CalcQuantity(
      si: ratio.si,
      dimension: CalcDimension.none,
      displayUnit: CalcUnits.resolve('%'),
    );
  }

  CalcValue _ratioDb(List<CalcValue> arguments) {
    CalcEngine._requireArity('snr_db', arguments, 2);
    final signal = _quantityArg('snr_db', arguments, 0);
    final noise = _quantityArg('snr_db', arguments, 1);
    if (!signal.dimension.isCompatibleWith(noise.dimension)) {
      throw dimensionError('signal and noise must have the same dimension');
    }
    final ratio = _divideValues(signal, noise) as CalcQuantity;
    return _ratioToDb([ratio], 10);
  }

  CalcValue _adcLsb(List<CalcValue> arguments) {
    CalcEngine._requireArity('adc_lsb', arguments, 2);
    final bits = _intArg('adc_lsb', arguments, 0);
    final reference = _quantityArg('adc_lsb', arguments, 1);
    if (bits <= 0 || bits > 52) {
      throw domainError('ADC resolution must be between 1 and 52 bits');
    }
    return _divideValues(
      reference,
      CalcQuantity.number(math.pow(2.0, bits).toDouble()),
    );
  }

  CalcValue _adcSnr(List<CalcValue> arguments) {
    CalcEngine._requireArity('adc_snr', arguments, 1);
    final bits = _intArg('adc_snr', arguments, 0);
    if (bits <= 0) throw domainError('ADC resolution must be positive');
    final level = 6.020599913279624 * bits + 1.7609125905568123;
    return _levelQuantity(level, 'dB');
  }

  CalcValue _quantizationError(List<CalcValue> arguments) {
    CalcEngine._requireArity('quantization_error', arguments, 1);
    final lsb = _quantityArg('quantization_error', arguments, 0);
    return _divideValues(lsb, _sqrtValue(CalcQuantity.number(12)));
  }

  CalcValue _counts(List<CalcValue> arguments) {
    CalcEngine._requireArity('counts', arguments, 1);
    final bits = _intArg('counts', arguments, 0);
    if (bits < 0 || bits > 52) {
      throw domainError('counts requires 0 to 52 bits');
    }
    return CalcQuantity.number(math.pow(2.0, bits).toDouble());
  }

  CalcValue _percentError(List<CalcValue> arguments) {
    CalcEngine._requireArity('percent_error', arguments, 2);
    final measured = _quantityArg('percent_error', arguments, 0);
    final expected = _quantityArg('percent_error', arguments, 1);
    if (!measured.dimension.isCompatibleWith(expected.dimension)) {
      throw dimensionError(
        'measured and expected must have the same dimension',
      );
    }
    if (expected.si.re == 0) {
      throw divisionByZero('expected value must not be zero');
    }
    final ratio = (measured.si.re - expected.si.re) / expected.si.re;
    return CalcQuantity(
      si: CalcComplex(ratio, 0),
      dimension: CalcDimension.none,
      displayUnit: CalcUnits.resolve('%'),
    );
  }

  CalcValue _tolerance(List<CalcValue> arguments) {
    CalcEngine._requireArity('tolerance', arguments, 2);
    final nominal = _quantityArg('tolerance', arguments, 0);
    final percent = _quantityArg('tolerance', arguments, 1);
    final double fraction;
    if (percent.displayUnit?.symbol == '%') {
      fraction = percent.si.re;
    } else if (percent.isDimensionless) {
      fraction = percent.si.re / 100;
    } else {
      throw dimensionError('tolerance must be a percentage');
    }
    return _multiplyValues(nominal, CalcQuantity.number(fraction));
  }

  // -------------------------------------------------------------------------
  // Digital and embedded
  // -------------------------------------------------------------------------

  CalcValue _pwmFrequency(List<CalcValue> arguments) {
    CalcEngine._requireArity('pwm_frequency', arguments, 3);
    final clock = _quantityArg('pwm_frequency', arguments, 0);
    final prescaler = _quantityArg('pwm_frequency', arguments, 1);
    final top = _quantityArg('pwm_frequency', arguments, 2);
    final divisor = _multiplyValues(
      prescaler,
      _addValues(top, CalcQuantity.number(1)),
    );
    return _divideValues(clock, divisor);
  }

  CalcValue _pwmDuty(List<CalcValue> arguments) {
    CalcEngine._requireArity('pwm_duty', arguments, 2);
    final compare = CalcEngine._realArgument(
      _quantityArg('pwm_duty', arguments, 0),
      'compare',
    );
    final top = CalcEngine._realArgument(
      _quantityArg('pwm_duty', arguments, 1),
      'top',
    );
    if (top < 0) throw domainError('top must not be negative');
    return CalcQuantity(
      si: CalcComplex(compare / (top + 1), 0),
      dimension: CalcDimension.none,
      displayUnit: CalcUnits.resolve('%'),
    );
  }

  CalcValue _timerTicks(List<CalcValue> arguments) {
    CalcEngine._requireArity('timer_ticks', arguments, 3);
    final duration = _quantityArg('timer_ticks', arguments, 0);
    final clock = _quantityArg('timer_ticks', arguments, 1);
    final prescaler = _quantityArg('timer_ticks', arguments, 2);
    return _divideValues(_multiplyValues(duration, clock), prescaler);
  }

  CalcValue _uartBaud(List<CalcValue> arguments) {
    CalcEngine._requireArity('uart_baud', arguments, 3);
    final clock = _quantityArg('uart_baud', arguments, 0);
    final oversampling = _quantityArg('uart_baud', arguments, 1);
    final divisor = _quantityArg('uart_baud', arguments, 2);
    return _divideValues(clock, _multiplyValues(oversampling, divisor));
  }

  CalcValue _baudError(List<CalcValue> arguments) {
    CalcEngine._requireArity('baud_error', arguments, 2);
    final actual = _quantityArg('baud_error', arguments, 0);
    final desired = _quantityArg('baud_error', arguments, 1);
    if (!actual.dimension.isCompatibleWith(desired.dimension)) {
      throw dimensionError('baud rates must have the same dimension');
    }
    if (desired.si.re == 0) {
      throw divisionByZero('desired baud rate must not be zero');
    }
    final ratio = (actual.si.re - desired.si.re) / desired.si.re;
    return CalcQuantity(
      si: CalcComplex(ratio, 0),
      dimension: CalcDimension.none,
      displayUnit: CalcUnits.resolve('%'),
    );
  }

  CalcValue _canBitrate(List<CalcValue> arguments) {
    CalcEngine._requireArity('can_bitrate', arguments, 4);
    final clock = _quantityArg('can_bitrate', arguments, 0);
    final prescaler = _quantityArg('can_bitrate', arguments, 1);
    final tseg1 = _quantityArg('can_bitrate', arguments, 2);
    final tseg2 = _quantityArg('can_bitrate', arguments, 3);
    final total = _addValues(_addValues(tseg1, tseg2), CalcQuantity.number(1));
    return _divideValues(clock, _multiplyValues(prescaler, total));
  }

  CalcValue _nyquist(List<CalcValue> arguments) {
    CalcEngine._requireArity('nyquist', arguments, 1);
    return _divideValues(
      _quantityArg('nyquist', arguments, 0),
      CalcQuantity.number(2),
    );
  }

  CalcValue _fftResolution(List<CalcValue> arguments) {
    CalcEngine._requireArity('fft_resolution', arguments, 2);
    final sampleRate = _quantityArg('fft_resolution', arguments, 0);
    final samples = _quantityArg('fft_resolution', arguments, 1);
    return _divideValues(sampleRate, samples);
  }

  CalcValue _riseTime(List<CalcValue> arguments) {
    CalcEngine._requireArity('rise_time', arguments, 1);
    final bandwidth = _quantityArg('rise_time', arguments, 0);
    _requireDimension(bandwidth, 'Hz', 'rise_time');
    return _divideValues(CalcQuantity.number(0.35), bandwidth);
  }

  CalcValue _bitwiseValue(String name, List<CalcValue> arguments) {
    if (arguments.length < 2) {
      throw argumentError('$name requires at least two integers');
    }
    var result = _intArg(name, arguments, 0);
    for (var index = 1; index < arguments.length; index++) {
      final value = _intArg(name, arguments, index);
      result = switch (name) {
        'band' => result & value,
        'bor' => result | value,
        _ => result ^ value,
      };
    }
    return _integerResult(result);
  }

  CalcValue _bnotValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('bnot', arguments, 1, 2);
    final value = _intArg('bnot', arguments, 0);
    if (arguments.length == 1) {
      return _integerResult(~value);
    }
    final bits = _intArg('bnot', arguments, 1);
    if (bits <= 0 || bits > 52) {
      throw domainError('bit width must be between 1 and 52');
    }
    final mask = (1 << bits) - 1;
    return _integerResult((~value) & mask);
  }

  CalcValue _shiftValue(String name, List<CalcValue> arguments) {
    CalcEngine._requireArity(name, arguments, 2);
    final value = _intArg(name, arguments, 0);
    final amount = _intArg(name, arguments, 1);
    if (amount < 0 || amount > 52) {
      throw domainError('shift amount must be between 0 and 52');
    }
    final result = switch (name) {
      'shl' => value << amount,
      'shr' => _logicalShiftRight(value, amount),
      _ => value >> amount,
    };
    return _integerResult(result);
  }

  static int _logicalShiftRight(int value, int amount) {
    if (amount == 0) return value;
    if (value >= 0) return value >> amount;
    final unsigned = value.toUnsigned(64);
    return (unsigned >> amount) & ((1 << (64 - amount)) - 1);
  }

  CalcValue _popcountValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('popcount', arguments, 1);
    final value = _intArg('popcount', arguments, 0);
    var count = 0;
    var remaining = value.toUnsigned(64);
    while (remaining != 0) {
      count += remaining & 1;
      remaining >>= 1;
    }
    return CalcQuantity.number(count);
  }

  CalcValue _parityValue(List<CalcValue> arguments) {
    final result = _popcountValue(arguments) as CalcQuantity;
    return CalcQuantity.number(result.si.re.toInt() & 1);
  }

  CalcValue _bitValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('bit', arguments, 2);
    final value = _intArg('bit', arguments, 0);
    final index = _intArg('bit', arguments, 1);
    if (index < 0 || index > 63) {
      throw domainError('bit index must be between 0 and 63');
    }
    return CalcQuantity.number((value >> index) & 1);
  }

  CalcValue _maskValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('mask', arguments, 1);
    final bits = _intArg('mask', arguments, 0);
    if (bits < 0 || bits > 52) {
      throw domainError('mask width must be between 0 and 52');
    }
    return CalcQuantity.number((1 << bits) - 1);
  }

  CalcValue _toSignedValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('to_signed', arguments, 2);
    final value = _intArg('to_signed', arguments, 0);
    final bits = _intArg('to_signed', arguments, 1);
    if (bits <= 0 || bits > 52) {
      throw domainError('bit width must be between 1 and 52');
    }
    final unsigned = value & ((1 << bits) - 1);
    final signBit = 1 << (bits - 1);
    return CalcQuantity.number(
      unsigned >= signBit ? unsigned - (1 << bits) : unsigned,
    );
  }

  CalcValue _toUnsignedValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('to_unsigned', arguments, 2);
    final value = _intArg('to_unsigned', arguments, 0);
    final bits = _intArg('to_unsigned', arguments, 1);
    if (bits <= 0 || bits > 52) {
      throw domainError('bit width must be between 1 and 52');
    }
    return CalcQuantity.number(value & ((1 << bits) - 1));
  }

  CalcQuantity _integerResult(int value) {
    if (value.abs() > 9.007199254740992e15) {
      throw overflowError('integer result exceeds the exact double range');
    }
    return CalcQuantity.number(value);
  }

  CalcValue _baseValue(List<CalcValue> arguments, CalcIntegerBase base) {
    CalcEngine._requireArity('base', arguments, 1);
    final value = _quantityArg('base', arguments, 0);
    if (!value.isDimensionless) {
      throw dimensionError('base conversion requires a dimensionless number');
    }
    final real = CalcEngine._realArgument(value, 'base conversion');
    if (real != real.roundToDouble()) {
      throw argumentError('base conversion requires an integer');
    }
    return CalcQuantity(
      si: CalcComplex(real, 0),
      dimension: CalcDimension.none,
      forcedBase: base,
    );
  }

  CalcValue _crc8Value(List<CalcValue> arguments) {
    CalcEngine._requireArity('crc8', arguments, 1, 3);
    final bytes = _byteList(arguments[0], 'crc8');
    final polynomial = arguments.length > 1
        ? _intArg('crc8', arguments, 1)
        : 0x07;
    var crc = arguments.length > 2 ? _intArg('crc8', arguments, 2) : 0x00;
    for (final byte in bytes) {
      crc ^= byte;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 0x80) != 0
            ? ((crc << 1) ^ polynomial) & 0xFF
            : (crc << 1) & 0xFF;
      }
    }
    return CalcQuantity.number(crc & 0xFF);
  }

  CalcValue _crc16Value(List<CalcValue> arguments) {
    CalcEngine._requireArity('crc16_ccitt', arguments, 1, 2);
    final bytes = _byteList(arguments[0], 'crc16_ccitt');
    var crc = arguments.length > 1
        ? _intArg('crc16_ccitt', arguments, 1)
        : 0xFFFF;
    for (final byte in bytes) {
      crc ^= byte << 8;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 0x8000) != 0
            ? ((crc << 1) ^ 0x1021) & 0xFFFF
            : (crc << 1) & 0xFFFF;
      }
    }
    return CalcQuantity.number(crc & 0xFFFF);
  }

  List<int> _byteList(CalcValue value, String name) {
    if (value is CalcList) {
      return value.items
          .map(
            (item) => CalcEngine._integerArgument(
              _requireQuantityValue(item),
              '$name byte',
            ),
          )
          .toList(growable: false);
    }
    if (value is CalcQuantity) {
      return [CalcEngine._integerArgument(value, '$name byte')];
    }
    throw argumentError('$name requires a list of byte values');
  }

  CalcValue _qFormatValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('q_format', arguments, 2);
    final value = CalcEngine._realArgument(
      _quantityArg('q_format', arguments, 0),
      'value',
    );
    final fractionalBits = _intArg('q_format', arguments, 1);
    if (fractionalBits < 0 || fractionalBits > 52) {
      throw domainError('fractional bits must be between 0 and 52');
    }
    return CalcQuantity.number(
      (value * math.pow(2.0, fractionalBits)).roundToDouble(),
    );
  }

  CalcValue _qToFloatValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('q_to_float', arguments, 2);
    final raw = CalcEngine._realArgument(
      _quantityArg('q_to_float', arguments, 0),
      'raw value',
    );
    final fractionalBits = _intArg('q_to_float', arguments, 1);
    if (fractionalBits < 0 || fractionalBits > 52) {
      throw domainError('fractional bits must be between 0 and 52');
    }
    return CalcQuantity.number(raw / math.pow(2.0, fractionalBits));
  }

  // -------------------------------------------------------------------------
  // Remaining helpers used by the switch above
  // -------------------------------------------------------------------------

  CalcValue _traceValue(List<CalcValue> arguments) {
    CalcEngine._requireArity('trace', arguments, 1);
    final matrix = _matrixArgument('trace', arguments, 0);
    CalcValue? sum;
    for (var index = 0; index < matrix.items.length; index++) {
      final value = matrix.row(index).items[index];
      sum = sum == null ? value : _addValues(sum, value);
    }
    return sum ?? CalcQuantity.number(0);
  }

  CalcValue _zerosBuiltin(List<CalcValue> arguments) {
    if (arguments.isEmpty || arguments.length > 2) {
      throw argumentError('zeros expects one or two dimensions');
    }
    final rows = _intArg('zeros', arguments, 0);
    if (rows < 0) throw domainError('zeros dimension must not be negative');
    if (arguments.length == 2) {
      final columns = _intArg('zeros', arguments, 1);
      if (columns < 0) {
        throw domainError('zeros dimension must not be negative');
      }
      return _zerosValue(rows, columns);
    }
    return _zerosValue(rows);
  }

  CalcValue _onesBuiltin(List<CalcValue> arguments) {
    if (arguments.isEmpty || arguments.length > 2) {
      throw argumentError('ones expects one or two dimensions');
    }
    final rows = _intArg('ones', arguments, 0);
    if (rows < 0) throw domainError('ones dimension must not be negative');
    if (arguments.length == 2) {
      final columns = _intArg('ones', arguments, 1);
      if (columns < 0) {
        throw domainError('ones dimension must not be negative');
      }
      return _onesValue(rows, columns);
    }
    return _onesValue(rows);
  }

  CalcValue _seqBuiltin(List<CalcValue> arguments) {
    if (arguments.length < 2 || arguments.length > 3) {
      throw argumentError('seq expects (start, stop) or (start, stop, step)');
    }
    return _seqValue(arguments);
  }
}

// Lanczos approximation of the gamma function. Kept as a top-level helper so
// both factorial() and gamma() can share it across the part files.
double _gammaFunction(double value) {
  if (value == value.roundToDouble() && value <= 0) {
    throw domainError('gamma is not defined at non-positive integers');
  }
  if (value < 0.5) {
    return math.pi / (math.sin(math.pi * value) * _gammaFunction(1 - value));
  }
  const coefficients = [
    0.99999999999980993,
    676.5203681218851,
    -1259.1392167224028,
    771.32342877765313,
    -176.61502916214059,
    12.507343278686905,
    -0.13857109526572012,
    9.9843695780195716e-6,
    1.5056327351493116e-7,
  ];
  final x = value - 1;
  var a = coefficients[0];
  final t = x + 7.5;
  for (var index = 1; index < coefficients.length; index++) {
    a += coefficients[index] / (x + index);
  }
  return math.sqrt(2 * math.pi) * math.pow(t, value - 0.5) * math.exp(-t) * a;
}
