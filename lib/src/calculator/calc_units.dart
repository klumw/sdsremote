/// Unit definitions, SI prefixes and the unit registry of the calculator.
///
/// Values are stored in coherent SI base units. A [CalcUnit] describes how a
/// displayed number maps to that base value, including affine temperature
/// scales and logarithmic level units (dB, dBm, dBV, dBu, …).
///
/// The registry is deliberately case-sensitive: `S` is siemens and `s` is
/// seconds, `T` is tesla and `t` is not a unit. Prefixes are resolved only
/// when the remaining symbol is a known prefixable unit, so `MHz` becomes
/// mega-hertz while `min` stays minute.
library;

import 'dart:math' as math;

import 'calc_dimension.dart';

/// Kind of a logarithmic unit.
enum CalcLogKind {
  decibel,
  dbi,
  dbd,
  dbfs,
  dbc,
  dbm,
  dbw,
  dbv,
  dbu,
  dbuV,
  dbspl,
}

/// One unit of the calculator.
class CalcUnit {
  const CalcUnit({
    required this.symbol,
    required this.dimension,
    this.scale = 1.0,
    this.offset = 0.0,
    this.prefixable = false,
    this.logKind,
    this.logReference,
    this.logFactor = 10,
    this.absolute = false,
    this.quantityName,
  });

  /// Canonical display symbol, e.g. `Ω`, `mV`, `dBm`.
  final String symbol;

  final CalcDimension dimension;

  /// Linear mapping to SI: `si = value * scale + offset`.
  final double scale;
  final double offset;

  /// Whether SI prefixes may be attached to [symbol].
  final bool prefixable;

  final CalcLogKind? logKind;

  /// SI value that corresponds to a level of 0 dB.
  final double? logReference;

  /// 10 for power ratios, 20 for amplitude ratios.
  final int logFactor;

  /// Absolute levels (dBm, dBW, dBV, dBu, dBµV, dBSPL) cannot be added to one
  /// another; gains and ratios (dB, dBi, dBd, dBFS, dBc) can.
  final bool absolute;

  /// Human-readable physical quantity, used in help and error messages.
  final String? quantityName;

  bool get isLog => logKind != null;

  bool get isLinear => !isLog;

  bool get isAffine => offset != 0.0;

  /// Value in coherent SI units for a linear unit.
  double toSi(double value) => value * scale + offset;

  /// Display value for a coherent SI value of a linear unit.
  double fromSi(double si) => (si - offset) / scale;

  /// SI value of a logarithmic level expressed in this unit.
  double levelToSi(double level) {
    final reference = logReference;
    if (reference == null) {
      throw UnitConversionError(
        '$symbol has no fixed reference and cannot be converted to a linear '
        'quantity without a full-scale value',
      );
    }
    return reference * math.pow(10.0, level / logFactor);
  }

  /// Logarithmic level for a coherent SI value.
  double siToLevel(double si) {
    final reference = logReference;
    if (reference == null || si <= 0) {
      throw UnitConversionError(
        'cannot express $si ${dimension.describe()} as $symbol',
      );
    }
    return logFactor * (math.log(si / reference) / math.ln10);
  }

  /// Returns a prefixed variant for a linear, prefixable unit.
  CalcUnit prefixed(String prefix, double factor) {
    if (!prefixable || isLog || isAffine) {
      throw UnitConversionError('$symbol cannot take an SI prefix');
    }
    return CalcUnit(
      symbol: '$prefix$symbol',
      dimension: dimension,
      scale: scale * factor,
      quantityName: quantityName,
    );
  }

  @override
  String toString() => symbol;
}

/// A unit conversion that is not defined.
class UnitConversionError implements Exception {
  const UnitConversionError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Registry of every unit understood by the calculator.
class CalcUnits {
  CalcUnits._();

  static final CalcDimension _length = CalcDimension.base(
    CalcBaseDimension.length,
  );
  static final CalcDimension _mass = CalcDimension.base(CalcBaseDimension.mass);
  static final CalcDimension _time = CalcDimension.base(CalcBaseDimension.time);
  static final CalcDimension _current = CalcDimension.base(
    CalcBaseDimension.current,
  );
  static final CalcDimension _temperature = CalcDimension.base(
    CalcBaseDimension.temperature,
  );
  static final CalcDimension _amount = CalcDimension.base(
    CalcBaseDimension.amount,
  );
  static final CalcDimension _luminous = CalcDimension.base(
    CalcBaseDimension.luminousIntensity,
  );
  static final CalcDimension _angle = CalcDimension.base(
    CalcBaseDimension.angle,
  );
  static final CalcDimension _information = CalcDimension.base(
    CalcBaseDimension.information,
  );
  // A baud is a symbol per second; for dimension calculations it behaves
  // like a frequency. Bits and samples remain separate base quantities.
  static final CalcDimension _baud = CalcDimension.none / _time;
  static final CalcDimension _sample = CalcDimension.base(
    CalcBaseDimension.sample,
  );

  static final CalcDimension _frequency = CalcDimension.none / _time;
  static final CalcDimension _force = _mass * _length / (_time * _time);
  static final CalcDimension _pressure = _force / (_length * _length);
  static final CalcDimension _energy = _force * _length;
  static final CalcDimension _power = _energy / _time;
  static final CalcDimension _charge = _current * _time;
  static final CalcDimension _voltage = _power / _current;
  static final CalcDimension _capacitance = _charge / _voltage;
  static final CalcDimension _resistance = _voltage / _current;
  static final CalcDimension _conductance = _current / _voltage;
  static final CalcDimension _flux = _voltage * _time;
  static final CalcDimension _fluxDensity = _flux / (_length * _length);
  static final CalcDimension _inductance = _flux / _current;
  static final CalcDimension _luminousFlux = _luminous;
  static final CalcDimension _illuminance = _luminousFlux / (_length * _length);
  static final CalcDimension _dose = _energy / _mass;
  static final CalcDimension _catalytic = _amount / _time;
  static final CalcDimension _area = _length * _length;
  static final CalcDimension _volume = _area * _length;
  static final CalcDimension _speed = _length / _time;
  static final CalcDimension _acceleration = _speed / _time;
  static final CalcDimension _dataRate = _information / _time;
  static final CalcDimension _sampleRate = _sample / _time;
  static final CalcDimension _angularVelocity = _angle / _time;

  static const Map<String, double> _prefixes = {
    'da': 1e1,
    'Y': 1e24,
    'Z': 1e21,
    'E': 1e18,
    'P': 1e15,
    'T': 1e12,
    'G': 1e9,
    'M': 1e6,
    'k': 1e3,
    'h': 1e2,
    'd': 1e-1,
    'c': 1e-2,
    'm': 1e-3,
    'µ': 1e-6,
    'u': 1e-6,
    'n': 1e-9,
    'p': 1e-12,
    'f': 1e-15,
    'a': 1e-18,
    'z': 1e-21,
    'y': 1e-24,
  };

  static const List<String> _prefixOrder = [
    'da',
    'Y',
    'Z',
    'E',
    'P',
    'T',
    'G',
    'M',
    'k',
    'h',
    'd',
    'c',
    'm',
    'µ',
    'u',
    'n',
    'p',
    'f',
    'a',
    'z',
    'y',
  ];

  /// Canonical units keyed by symbol and alias.
  static final Map<String, CalcUnit> _bySymbol = _buildUnits();

  /// Preferred unit used for automatic result formatting.
  static final Map<CalcDimension, CalcUnit> _preferred = _buildPreferred();

  /// Resolves a unit symbol, alias or prefixed symbol.
  static CalcUnit? resolve(String token) {
    final direct = _bySymbol[token];
    if (direct != null) return direct;
    final normalized = token.replaceAll('μ', 'µ');
    final directNormalized = _bySymbol[normalized];
    if (directNormalized != null) return directNormalized;
    for (final prefix in _prefixOrder) {
      if (normalized.length <= prefix.length) continue;
      if (!normalized.startsWith(prefix)) continue;
      final rest = normalized.substring(prefix.length);
      final unit = _bySymbol[rest];
      if (unit == null || !unit.prefixable || unit.isLog || unit.isAffine) {
        continue;
      }
      final factor = _prefixes[prefix];
      if (factor == null) continue;
      final displayPrefix = prefix == 'u' ? 'µ' : prefix;
      return unit.prefixed(displayPrefix, factor);
    }
    return null;
  }

  /// True when [token] is exactly a unit (not merely a prefix).
  static bool isUnit(String token) => resolve(token) != null;

  /// Preferred display unit for [dimension], or null when the dimension has
  /// no named unit and must be rendered from base dimensions.
  static CalcUnit? preferredUnitFor(CalcDimension dimension) =>
      _preferred[dimension];

  /// All canonical units, for pickers and documentation.
  static List<CalcUnit> get allUnits {
    final seen = <String>{};
    final units = <CalcUnit>[];
    for (final unit in _bySymbol.values) {
      if (seen.add(unit.symbol)) units.add(unit);
    }
    units.sort((a, b) => a.symbol.compareTo(b.symbol));
    return units;
  }

  /// Common prefixed forms offered by the unit picker.
  static List<String> get commonSymbols {
    const prefixes = ['p', 'n', 'µ', 'm', 'k', 'M', 'G'];
    const base = [
      'V',
      'A',
      'Ω',
      'F',
      'H',
      'Hz',
      's',
      'W',
      'J',
      'C',
      'S',
      'm',
      'g',
      'L',
      'Wh',
      'Ah',
      'bit',
      'B',
      'bps',
      'Bd',
      'Sa',
      'Wb',
      'T',
    ];
    final symbols = <String>{...base};
    for (final prefix in prefixes) {
      for (final symbol in base) {
        final resolved = resolve('$prefix$symbol');
        if (resolved != null) symbols.add(resolved.symbol);
      }
    }
    const special = [
      '°C',
      '°F',
      'K',
      'min',
      'h',
      'day',
      'rad',
      'deg',
      '°',
      'grad',
      'rev',
      'rpm',
      '%',
      'ppm',
      'ppb',
      'dB',
      'dBi',
      'dBd',
      'dBm',
      'dBW',
      'dBV',
      'dBu',
      'dBµV',
      'dBFS',
      'dBc',
      'dBSPL',
      'in',
      'ft',
      'yd',
      'mi',
      'nmi',
      'bar',
      'atm',
      'psi',
      'Torr',
      'eV',
      'cal',
    ];
    symbols.addAll(special);
    final list = symbols.toList()..sort();
    return list;
  }

  static Map<String, CalcUnit> _buildUnits() {
    final units = <String, CalcUnit>{};
    void add(CalcUnit unit, [List<String> aliases = const []]) {
      units[unit.symbol] = unit;
      for (final alias in aliases) {
        units[alias] = unit;
      }
    }

    // ---- SI base quantities ----
    add(
      CalcUnit(
        symbol: 'm',
        dimension: _length,
        prefixable: true,
        quantityName: 'length',
      ),
      ['meter', 'meters', 'metre', 'metres'],
    );
    add(
      CalcUnit(
        symbol: 'g',
        dimension: _mass,
        scale: 1e-3,
        prefixable: true,
        quantityName: 'mass',
      ),
      ['gram', 'grams'],
    );
    add(
      CalcUnit(
        symbol: 's',
        dimension: _time,
        prefixable: true,
        quantityName: 'time',
      ),
      ['second', 'seconds', 'sec'],
    );
    add(
      CalcUnit(
        symbol: 'A',
        dimension: _current,
        prefixable: true,
        quantityName: 'current',
      ),
      ['ampere', 'amperes', 'amp', 'amps'],
    );
    add(
      CalcUnit(
        symbol: 'K',
        dimension: _temperature,
        prefixable: true,
        quantityName: 'temperature',
      ),
      ['kelvin'],
    );
    add(
      CalcUnit(
        symbol: 'mol',
        dimension: _amount,
        prefixable: true,
        quantityName: 'amount of substance',
      ),
      ['mole', 'moles'],
    );
    add(
      CalcUnit(
        symbol: 'cd',
        dimension: _luminous,
        quantityName: 'luminous intensity',
      ),
      ['candela'],
    );

    // ---- Angles ----
    add(
      CalcUnit(
        symbol: 'rad',
        dimension: _angle,
        prefixable: true,
        quantityName: 'angle',
      ),
      ['radian', 'radians'],
    );
    add(
      CalcUnit(
        symbol: '°',
        dimension: _angle,
        scale: math.pi / 180,
        quantityName: 'angle',
      ),
      ['deg', 'degree', 'degrees'],
    );
    add(
      CalcUnit(
        symbol: 'grad',
        dimension: _angle,
        scale: math.pi / 200,
        quantityName: 'angle',
      ),
      ['gon'],
    );
    add(
      CalcUnit(
        symbol: 'rev',
        dimension: _angle,
        scale: 2 * math.pi,
        quantityName: 'angle',
      ),
      ['turn', 'turns', 'revolution', 'revolutions'],
    );
    add(
      CalcUnit(
        symbol: 'rpm',
        dimension: _angularVelocity,
        scale: 2 * math.pi / 60,
        quantityName: 'angular velocity',
      ),
    );

    // ---- Temperature scales ----
    add(
      CalcUnit(
        symbol: '°C',
        dimension: _temperature,
        offset: 273.15,
        quantityName: 'temperature',
      ),
      ['degC', 'celsius'],
    );
    add(
      CalcUnit(
        symbol: '°F',
        dimension: _temperature,
        scale: 5 / 9,
        offset: 255.3722222222222,
        quantityName: 'temperature',
      ),
      ['degF', 'fahrenheit'],
    );

    // ---- Derived SI units ----
    add(
      CalcUnit(
        symbol: 'Hz',
        dimension: _frequency,
        prefixable: true,
        quantityName: 'frequency',
      ),
      ['hertz'],
    );
    add(
      CalcUnit(
        symbol: 'N',
        dimension: _force,
        prefixable: true,
        quantityName: 'force',
      ),
      ['newton'],
    );
    add(
      CalcUnit(
        symbol: 'Pa',
        dimension: _pressure,
        prefixable: true,
        quantityName: 'pressure',
      ),
      ['pascal'],
    );
    add(
      CalcUnit(
        symbol: 'J',
        dimension: _energy,
        prefixable: true,
        quantityName: 'energy',
      ),
      ['joule'],
    );
    add(
      CalcUnit(
        symbol: 'W',
        dimension: _power,
        prefixable: true,
        quantityName: 'power',
      ),
      ['watt', 'watts'],
    );
    add(
      CalcUnit(
        symbol: 'C',
        dimension: _charge,
        prefixable: true,
        quantityName: 'charge',
      ),
      ['coulomb'],
    );
    add(
      CalcUnit(
        symbol: 'V',
        dimension: _voltage,
        prefixable: true,
        quantityName: 'voltage',
      ),
      ['volt', 'volts'],
    );
    add(
      CalcUnit(
        symbol: 'F',
        dimension: _capacitance,
        prefixable: true,
        quantityName: 'capacitance',
      ),
      ['farad'],
    );
    add(
      CalcUnit(
        symbol: 'Ω',
        dimension: _resistance,
        prefixable: true,
        quantityName: 'resistance',
      ),
      ['ohm', 'ohms', 'Ohm'],
    );
    add(
      CalcUnit(
        symbol: 'S',
        dimension: _conductance,
        prefixable: true,
        quantityName: 'conductance',
      ),
      ['siemens'],
    );
    add(
      CalcUnit(
        symbol: 'Wb',
        dimension: _flux,
        prefixable: true,
        quantityName: 'magnetic flux',
      ),
      ['weber'],
    );
    add(
      CalcUnit(
        symbol: 'T',
        dimension: _fluxDensity,
        prefixable: true,
        quantityName: 'magnetic flux density',
      ),
      ['tesla'],
    );
    add(
      CalcUnit(
        symbol: 'H',
        dimension: _inductance,
        prefixable: true,
        quantityName: 'inductance',
      ),
      ['henry', 'henries'],
    );
    add(
      CalcUnit(
        symbol: 'lm',
        dimension: _luminousFlux,
        quantityName: 'luminous flux',
      ),
      ['lumen'],
    );
    add(
      CalcUnit(
        symbol: 'lx',
        dimension: _illuminance,
        quantityName: 'illuminance',
      ),
      ['lux'],
    );
    add(
      CalcUnit(
        symbol: 'Bq',
        dimension: _frequency,
        quantityName: 'radioactivity',
      ),
      ['becquerel'],
    );
    add(
      CalcUnit(symbol: 'Gy', dimension: _dose, quantityName: 'absorbed dose'),
      ['gray'],
    );
    add(
      CalcUnit(symbol: 'Sv', dimension: _dose, quantityName: 'equivalent dose'),
      ['sievert'],
    );
    add(
      CalcUnit(
        symbol: 'kat',
        dimension: _catalytic,
        quantityName: 'catalytic activity',
      ),
      ['katal'],
    );

    // ---- Dimensionless ratios ----
    add(CalcUnit(symbol: '%', dimension: CalcDimension.none, scale: 1e-2), [
      'percent',
    ]);
    add(CalcUnit(symbol: 'ppm', dimension: CalcDimension.none, scale: 1e-6), [
      'partspermillion',
    ]);
    add(CalcUnit(symbol: 'ppb', dimension: CalcDimension.none, scale: 1e-9), [
      'partsperbillion',
    ]);
    add(CalcUnit(symbol: 'count', dimension: CalcDimension.none), [
      'counts',
      'pcs',
    ]);

    // ---- Common non-SI units ----
    add(
      CalcUnit(
        symbol: 'min',
        dimension: _time,
        scale: 60,
        quantityName: 'time',
      ),
      ['minute', 'minutes'],
    );
    add(
      CalcUnit(
        symbol: 'h',
        dimension: _time,
        scale: 3600,
        quantityName: 'time',
      ),
      ['hour', 'hours', 'hr'],
    );
    add(
      CalcUnit(
        symbol: 'day',
        dimension: _time,
        scale: 86400,
        quantityName: 'time',
      ),
      ['days'],
    );
    add(
      CalcUnit(
        symbol: 'L',
        dimension: _volume,
        scale: 1e-3,
        prefixable: true,
        quantityName: 'volume',
      ),
      ['liter', 'liters', 'litre', 'litres'],
    );
    add(
      CalcUnit(
        symbol: 'in',
        dimension: _length,
        scale: 0.0254,
        quantityName: 'length',
      ),
      ['inch', 'inches'],
    );
    add(
      CalcUnit(
        symbol: 'ft',
        dimension: _length,
        scale: 0.3048,
        quantityName: 'length',
      ),
      ['foot', 'feet'],
    );
    add(
      CalcUnit(
        symbol: 'yd',
        dimension: _length,
        scale: 0.9144,
        quantityName: 'length',
      ),
      ['yard', 'yards'],
    );
    add(
      CalcUnit(
        symbol: 'mi',
        dimension: _length,
        scale: 1609.344,
        quantityName: 'length',
      ),
      ['mile', 'miles'],
    );
    add(
      CalcUnit(
        symbol: 'nmi',
        dimension: _length,
        scale: 1852,
        quantityName: 'length',
      ),
      ['nauticalmile'],
    );
    add(
      CalcUnit(
        symbol: 'mil',
        dimension: _length,
        scale: 2.54e-5,
        quantityName: 'length',
      ),
      ['thou'],
    );
    add(
      CalcUnit(
        symbol: 'Å',
        dimension: _length,
        scale: 1e-10,
        quantityName: 'length',
      ),
      ['angstrom'],
    );
    add(
      CalcUnit(
        symbol: 'Wh',
        dimension: _energy,
        scale: 3600,
        prefixable: true,
        quantityName: 'energy',
      ),
    );
    add(
      CalcUnit(
        symbol: 'Ah',
        dimension: _charge,
        scale: 3600,
        prefixable: true,
        quantityName: 'charge',
      ),
    );
    add(
      CalcUnit(
        symbol: 'eV',
        dimension: _energy,
        scale: 1.602176634e-19,
        prefixable: true,
        quantityName: 'energy',
      ),
    );
    add(
      CalcUnit(
        symbol: 'cal',
        dimension: _energy,
        scale: 4.184,
        prefixable: true,
        quantityName: 'energy',
      ),
    );
    add(
      CalcUnit(
        symbol: 'hp',
        dimension: _power,
        scale: 745.6998715822702,
        quantityName: 'power',
      ),
      ['horsepower'],
    );
    add(
      CalcUnit(
        symbol: 'VA',
        dimension: _power,
        prefixable: true,
        quantityName: 'apparent power',
      ),
    );
    add(
      CalcUnit(
        symbol: 'bar',
        dimension: _pressure,
        scale: 1e5,
        prefixable: true,
        quantityName: 'pressure',
      ),
    );
    add(
      CalcUnit(
        symbol: 'atm',
        dimension: _pressure,
        scale: 101325,
        quantityName: 'pressure',
      ),
      ['atmosphere'],
    );
    add(
      CalcUnit(
        symbol: 'psi',
        dimension: _pressure,
        scale: 6894.757293168,
        quantityName: 'pressure',
      ),
    );
    add(
      CalcUnit(
        symbol: 'Torr',
        dimension: _pressure,
        scale: 133.32236842105263,
        quantityName: 'pressure',
      ),
      ['mmHg'],
    );

    // ---- Information, data rate and sample rate ----
    add(
      CalcUnit(
        symbol: 'bit',
        dimension: _information,
        prefixable: true,
        quantityName: 'information',
      ),
      ['bits'],
    );
    add(
      CalcUnit(
        symbol: 'B',
        dimension: _information,
        scale: 8,
        prefixable: true,
        quantityName: 'information',
      ),
      ['byte', 'bytes'],
    );
    add(
      CalcUnit(
        symbol: 'bps',
        dimension: _dataRate,
        prefixable: true,
        quantityName: 'data rate',
      ),
      ['bit/s'],
    );
    add(
      CalcUnit(
        symbol: 'Bps',
        dimension: _dataRate,
        scale: 8,
        prefixable: true,
        quantityName: 'data rate',
      ),
      ['byte/s'],
    );
    add(
      CalcUnit(
        symbol: 'Bd',
        dimension: _baud,
        prefixable: true,
        quantityName: 'symbol rate',
      ),
      ['baud'],
    );
    add(
      CalcUnit(
        symbol: 'Sa',
        dimension: _sample,
        prefixable: true,
        quantityName: 'sample count',
      ),
      ['sample', 'samples'],
    );
    add(
      CalcUnit(
        symbol: 'Sa/s',
        dimension: _sampleRate,
        quantityName: 'sample rate',
      ),
      ['sample/s', 'samples/s', 'S/s'],
    );

    // ---- Compound display units for automatic formatting ----
    add(CalcUnit(symbol: 'm²', dimension: _area, quantityName: 'area'));
    add(CalcUnit(symbol: 'm³', dimension: _volume, quantityName: 'volume'));
    add(CalcUnit(symbol: 'm/s', dimension: _speed, quantityName: 'speed'));
    add(
      CalcUnit(
        symbol: 'm/s²',
        dimension: _acceleration,
        quantityName: 'acceleration',
      ),
    );
    add(
      CalcUnit(
        symbol: 'rad/s',
        dimension: _angularVelocity,
        quantityName: 'angular velocity',
      ),
    );
    add(
      CalcUnit(
        symbol: 'bit/s',
        dimension: _dataRate,
        quantityName: 'data rate',
      ),
    );
    add(
      CalcUnit(
        symbol: 'kg/m³',
        dimension: _mass / _volume,
        quantityName: 'density',
      ),
    );
    // Squared units commonly produced by variance and RMS calculations.
    add(CalcUnit(symbol: 'V²', dimension: _voltage * _voltage));
    add(CalcUnit(symbol: 'A²', dimension: _current * _current));
    add(CalcUnit(symbol: 'W²', dimension: _power * _power));
    add(CalcUnit(symbol: 'Ω²', dimension: _resistance * _resistance));
    add(CalcUnit(symbol: 'F²', dimension: _capacitance * _capacitance));
    add(CalcUnit(symbol: 'H²', dimension: _inductance * _inductance));
    add(CalcUnit(symbol: 'J²', dimension: _energy * _energy));
    add(CalcUnit(symbol: 'Hz²', dimension: _frequency * _frequency));
    add(CalcUnit(symbol: 'C²', dimension: _charge * _charge));
    add(CalcUnit(symbol: 's²', dimension: _time * _time));
    add(CalcUnit(symbol: 'K²', dimension: _temperature * _temperature));
    add(CalcUnit(symbol: 'g²', dimension: _mass * _mass));

    // ---- Logarithmic units ----
    add(
      CalcUnit(
        symbol: 'dB',
        dimension: CalcDimension.none,
        logKind: CalcLogKind.decibel,
        logReference: 1,
        logFactor: 10,
        quantityName: 'level ratio',
      ),
    );
    add(
      CalcUnit(
        symbol: 'dBi',
        dimension: CalcDimension.none,
        logKind: CalcLogKind.dbi,
        logReference: 1,
        logFactor: 10,
        quantityName: 'antenna gain',
      ),
    );
    add(
      CalcUnit(
        symbol: 'dBd',
        dimension: CalcDimension.none,
        logKind: CalcLogKind.dbd,
        logReference: 1.6405885748689646,
        logFactor: 10,
        quantityName: 'antenna gain',
      ),
    );
    add(
      CalcUnit(
        symbol: 'dBFS',
        dimension: CalcDimension.none,
        logKind: CalcLogKind.dbfs,
        logReference: 1,
        logFactor: 20,
        quantityName: 'full-scale level',
      ),
      ['dbfs'],
    );
    add(
      CalcUnit(
        symbol: 'dBc',
        dimension: CalcDimension.none,
        logKind: CalcLogKind.dbc,
        logReference: 1,
        logFactor: 10,
        quantityName: 'carrier ratio',
      ),
    );
    add(
      CalcUnit(
        symbol: 'dBm',
        dimension: _power,
        logKind: CalcLogKind.dbm,
        logReference: 1e-3,
        logFactor: 10,
        absolute: true,
        quantityName: 'power level',
      ),
    );
    add(
      CalcUnit(
        symbol: 'dBW',
        dimension: _power,
        logKind: CalcLogKind.dbw,
        logReference: 1,
        logFactor: 10,
        absolute: true,
        quantityName: 'power level',
      ),
    );
    add(
      CalcUnit(
        symbol: 'dBV',
        dimension: _voltage,
        logKind: CalcLogKind.dbv,
        logReference: 1,
        logFactor: 20,
        absolute: true,
        quantityName: 'voltage level',
      ),
    );
    add(
      CalcUnit(
        symbol: 'dBu',
        dimension: _voltage,
        logKind: CalcLogKind.dbu,
        logReference: math.sqrt(0.6),
        logFactor: 20,
        absolute: true,
        quantityName: 'voltage level',
      ),
    );
    add(
      CalcUnit(
        symbol: 'dBµV',
        dimension: _voltage,
        logKind: CalcLogKind.dbuV,
        logReference: 1e-6,
        logFactor: 20,
        absolute: true,
        quantityName: 'voltage level',
      ),
      ['dBuV', 'dBμV'],
    );
    add(
      CalcUnit(
        symbol: 'dBSPL',
        dimension: _pressure,
        logKind: CalcLogKind.dbspl,
        logReference: 20e-6,
        logFactor: 20,
        absolute: true,
        quantityName: 'sound pressure level',
      ),
    );

    return units;
  }

  static Map<CalcDimension, CalcUnit> _buildPreferred() {
    CalcUnit canonical(String symbol) => _bySymbol[symbol]!;
    return {
      _voltage: canonical('V'),
      _current: canonical('A'),
      _resistance: canonical('Ω'),
      _conductance: canonical('S'),
      _capacitance: canonical('F'),
      _inductance: canonical('H'),
      _frequency: canonical('Hz'),
      _time: canonical('s'),
      _power: canonical('W'),
      _energy: canonical('J'),
      _charge: canonical('C'),
      _temperature: canonical('K'),
      _length: canonical('m'),
      _mass: canonical('g'),
      _angle: canonical('rad'),
      _information: canonical('bit'),
      _dataRate: canonical('bit/s'),
      _sampleRate: canonical('Sa/s'),
      _pressure: canonical('Pa'),
      _force: canonical('N'),
      _flux: canonical('Wb'),
      _fluxDensity: canonical('T'),
      _luminousFlux: canonical('lm'),
      _illuminance: canonical('lx'),
      _dose: canonical('Gy'),
      _catalytic: canonical('kat'),
      _area: canonical('m²'),
      _volume: canonical('m³'),
      _speed: canonical('m/s'),
      _acceleration: canonical('m/s²'),
      _angularVelocity: canonical('rad/s'),
      _mass / _volume: canonical('kg/m³'),
      _voltage * _voltage: canonical('V²'),
      _current * _current: canonical('A²'),
      _power * _power: canonical('W²'),
      _resistance * _resistance: canonical('Ω²'),
      _capacitance * _capacitance: canonical('F²'),
      _inductance * _inductance: canonical('H²'),
      _energy * _energy: canonical('J²'),
      _frequency * _frequency: canonical('Hz²'),
      _charge * _charge: canonical('C²'),
      _time * _time: canonical('s²'),
      _temperature * _temperature: canonical('K²'),
      _mass * _mass: canonical('g²'),
    };
  }
}
