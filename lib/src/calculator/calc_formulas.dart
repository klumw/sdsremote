/// Formula library of the engineering calculator.
///
/// Every entry is an ordinary calculator expression with named inputs, so it
/// runs through the same parser, unit checker and formatter as typed input.
/// The default values make every formula immediately runnable; the UI and the
/// AI tool can override them.
library;

/// One input of a formula.
class CalcFormulaInput {
  const CalcFormulaInput({
    required this.name,
    required this.label,
    required this.defaultExpression,
    this.hint = '',
  });

  /// Variable name used by the formula expression.
  final String name;

  /// Label shown in the formula dialog.
  final String label;

  /// Default value as a calculator expression, e.g. `10 kΩ`.
  final String defaultExpression;

  /// Optional explanation of the expected quantity or unit.
  final String hint;
}

/// A named engineering formula with defaults and assumptions.
class CalcFormula {
  const CalcFormula({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.expression,
    required this.inputs,
    this.assumptions = const [],
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final String expression;
  final List<CalcFormulaInput> inputs;

  /// Modelling assumptions the result depends on, shown with the result.
  final List<String> assumptions;
}

/// Categories in display order.
class CalcFormulaCategories {
  const CalcFormulaCategories._();

  static const String basic = 'Basic Electrical';
  static const String filters = 'Filters and Analog';
  static const String measurement = 'Measurement and Uncertainty';
  static const String audio = 'Audio and DSP';
  static const String digital = 'Digital and Embedded';
  static const String rf = 'RF and Antennas';
  static const String math = 'Math and Numerical';

  static const List<String> all = [
    basic,
    filters,
    measurement,
    audio,
    digital,
    rf,
    math,
  ];
}

/// The built-in formula library.
class CalcFormulaLibrary {
  CalcFormulaLibrary._();

  static CalcFormula? find(String id) {
    for (final formula in formulas) {
      if (formula.id == id) return formula;
    }
    return null;
  }

  static List<CalcFormula> inCategory(String category) =>
      formulas.where((formula) => formula.category == category).toList();

  static List<CalcFormula> search(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return formulas;
    return formulas
        .where(
          (formula) =>
              formula.name.toLowerCase().contains(lower) ||
              formula.description.toLowerCase().contains(lower) ||
              formula.id.toLowerCase().contains(lower) ||
              formula.category.toLowerCase().contains(lower),
        )
        .toList();
  }

  static const List<CalcFormula> formulas = [
    // =======================================================================
    // Basic Electrical
    // =======================================================================
    CalcFormula(
      id: 'ohm_voltage',
      name: "Ohm's law: voltage",
      category: CalcFormulaCategories.basic,
      description: 'Voltage across a resistance carrying a current.',
      expression: 'i * r',
      inputs: [
        CalcFormulaInput(
          name: 'i',
          label: 'Current',
          defaultExpression: '1 mA',
        ),
        CalcFormulaInput(
          name: 'r',
          label: 'Resistance',
          defaultExpression: '1 kΩ',
        ),
      ],
    ),
    CalcFormula(
      id: 'ohm_current',
      name: "Ohm's law: current",
      category: CalcFormulaCategories.basic,
      description: 'Current through a resistance for a given voltage.',
      expression: 'v / r',
      inputs: [
        CalcFormulaInput(name: 'v', label: 'Voltage', defaultExpression: '5 V'),
        CalcFormulaInput(
          name: 'r',
          label: 'Resistance',
          defaultExpression: '1 kΩ',
        ),
      ],
    ),
    CalcFormula(
      id: 'ohm_resistance',
      name: "Ohm's law: resistance",
      category: CalcFormulaCategories.basic,
      description: 'Resistance from voltage and current.',
      expression: 'v / i',
      inputs: [
        CalcFormulaInput(name: 'v', label: 'Voltage', defaultExpression: '5 V'),
        CalcFormulaInput(
          name: 'i',
          label: 'Current',
          defaultExpression: '1 mA',
        ),
      ],
    ),
    CalcFormula(
      id: 'power_vi',
      name: 'Power from voltage and current',
      category: CalcFormulaCategories.basic,
      description: 'DC power in an electrical branch.',
      expression: 'v * i',
      inputs: [
        CalcFormulaInput(name: 'v', label: 'Voltage', defaultExpression: '5 V'),
        CalcFormulaInput(
          name: 'i',
          label: 'Current',
          defaultExpression: '100 mA',
        ),
      ],
    ),
    CalcFormula(
      id: 'power_i2r',
      name: 'Power from current and resistance',
      category: CalcFormulaCategories.basic,
      description: 'Joule heating in a resistor.',
      expression: 'i^2 * r',
      inputs: [
        CalcFormulaInput(
          name: 'i',
          label: 'Current',
          defaultExpression: '100 mA',
        ),
        CalcFormulaInput(
          name: 'r',
          label: 'Resistance',
          defaultExpression: '100 Ω',
        ),
      ],
    ),
    CalcFormula(
      id: 'power_v2r',
      name: 'Power from voltage and resistance',
      category: CalcFormulaCategories.basic,
      description: 'Power dissipated by a resistor for a known voltage.',
      expression: 'v^2 / r',
      inputs: [
        CalcFormulaInput(
          name: 'v',
          label: 'Voltage',
          defaultExpression: '12 V',
        ),
        CalcFormulaInput(
          name: 'r',
          label: 'Resistance',
          defaultExpression: '1 kΩ',
        ),
      ],
    ),
    CalcFormula(
      id: 'energy_charge',
      name: 'Energy from charge and voltage',
      category: CalcFormulaCategories.basic,
      description: 'Energy stored or moved by a charge at a potential.',
      expression: 'q * v',
      inputs: [
        CalcFormulaInput(name: 'q', label: 'Charge', defaultExpression: '1 mC'),
        CalcFormulaInput(name: 'v', label: 'Voltage', defaultExpression: '5 V'),
      ],
    ),
    CalcFormula(
      id: 'charge_current_time',
      name: 'Charge from current and time',
      category: CalcFormulaCategories.basic,
      description: 'Charge moved by a constant current.',
      expression: 'i * t',
      inputs: [
        CalcFormulaInput(
          name: 'i',
          label: 'Current',
          defaultExpression: '100 mA',
        ),
        CalcFormulaInput(name: 't', label: 'Time', defaultExpression: '1 s'),
      ],
    ),
    CalcFormula(
      id: 'voltage_divider',
      name: 'Resistive voltage divider',
      category: CalcFormulaCategories.basic,
      description: 'Output voltage of an unloaded resistive divider.',
      expression: 'vin * r2 / (r1 + r2)',
      inputs: [
        CalcFormulaInput(
          name: 'vin',
          label: 'Input voltage',
          defaultExpression: '12 V',
        ),
        CalcFormulaInput(
          name: 'r1',
          label: 'Upper resistor',
          defaultExpression: '10 kΩ',
        ),
        CalcFormulaInput(
          name: 'r2',
          label: 'Lower resistor',
          defaultExpression: '4.7 kΩ',
        ),
      ],
      assumptions: ['The output is unloaded.'],
    ),
    CalcFormula(
      id: 'current_divider',
      name: 'Resistive current divider',
      category: CalcFormulaCategories.basic,
      description: 'Current through r1 in a two-resistor divider.',
      expression: 'iin * r2 / (r1 + r2)',
      inputs: [
        CalcFormulaInput(
          name: 'iin',
          label: 'Total current',
          defaultExpression: '10 mA',
        ),
        CalcFormulaInput(
          name: 'r1',
          label: 'Branch resistance',
          defaultExpression: '1 kΩ',
        ),
        CalcFormulaInput(
          name: 'r2',
          label: 'Other branch resistance',
          defaultExpression: '2 kΩ',
        ),
      ],
      assumptions: ['The expression returns the current through r1.'],
    ),
    CalcFormula(
      id: 'series_resistance',
      name: 'Series resistances',
      category: CalcFormulaCategories.basic,
      description: 'Sum of two series resistances.',
      expression: 'r1 + r2',
      inputs: [
        CalcFormulaInput(name: 'r1', label: 'R1', defaultExpression: '1 kΩ'),
        CalcFormulaInput(name: 'r2', label: 'R2', defaultExpression: '2.2 kΩ'),
      ],
    ),
    CalcFormula(
      id: 'parallel_resistance',
      name: 'Parallel resistances',
      category: CalcFormulaCategories.basic,
      description: 'Equivalent resistance of two parallel resistors.',
      expression: 'parallel(r1, r2)',
      inputs: [
        CalcFormulaInput(name: 'r1', label: 'R1', defaultExpression: '1 kΩ'),
        CalcFormulaInput(name: 'r2', label: 'R2', defaultExpression: '2.2 kΩ'),
      ],
    ),
    CalcFormula(
      id: 'series_capacitance',
      name: 'Series capacitances',
      category: CalcFormulaCategories.basic,
      description: 'Equivalent capacitance of two capacitors in series.',
      expression: '1 / (1/c1 + 1/c2)',
      inputs: [
        CalcFormulaInput(name: 'c1', label: 'C1', defaultExpression: '100 nF'),
        CalcFormulaInput(name: 'c2', label: 'C2', defaultExpression: '220 nF'),
      ],
    ),
    CalcFormula(
      id: 'parallel_capacitance',
      name: 'Parallel capacitances',
      category: CalcFormulaCategories.basic,
      description: 'Equivalent capacitance of two parallel capacitors.',
      expression: 'c1 + c2',
      inputs: [
        CalcFormulaInput(name: 'c1', label: 'C1', defaultExpression: '100 nF'),
        CalcFormulaInput(name: 'c2', label: 'C2', defaultExpression: '220 nF'),
      ],
    ),
    CalcFormula(
      id: 'series_inductance',
      name: 'Series inductances',
      category: CalcFormulaCategories.basic,
      description: 'Sum of two series inductances.',
      expression: 'l1 + l2',
      inputs: [
        CalcFormulaInput(name: 'l1', label: 'L1', defaultExpression: '10 µH'),
        CalcFormulaInput(name: 'l2', label: 'L2', defaultExpression: '22 µH'),
      ],
    ),
    CalcFormula(
      id: 'parallel_inductance',
      name: 'Parallel inductances',
      category: CalcFormulaCategories.basic,
      description: 'Equivalent inductance of two parallel inductors.',
      expression: 'parallel(l1, l2)',
      inputs: [
        CalcFormulaInput(name: 'l1', label: 'L1', defaultExpression: '10 µH'),
        CalcFormulaInput(name: 'l2', label: 'L2', defaultExpression: '22 µH'),
      ],
    ),
    CalcFormula(
      id: 'rc_time_constant',
      name: 'RC time constant',
      category: CalcFormulaCategories.basic,
      description: 'Time constant of an RC network.',
      expression: 'r * c',
      inputs: [
        CalcFormulaInput(
          name: 'r',
          label: 'Resistance',
          defaultExpression: '10 kΩ',
        ),
        CalcFormulaInput(
          name: 'c',
          label: 'Capacitance',
          defaultExpression: '100 nF',
        ),
      ],
    ),
    CalcFormula(
      id: 'rl_time_constant',
      name: 'RL time constant',
      category: CalcFormulaCategories.basic,
      description: 'Time constant of an RL network.',
      expression: 'l / r',
      inputs: [
        CalcFormulaInput(
          name: 'l',
          label: 'Inductance',
          defaultExpression: '1 mH',
        ),
        CalcFormulaInput(
          name: 'r',
          label: 'Resistance',
          defaultExpression: '100 Ω',
        ),
      ],
    ),
    CalcFormula(
      id: 'rc_cutoff',
      name: 'RC cutoff frequency',
      category: CalcFormulaCategories.basic,
      description: 'Corner frequency of a first-order RC filter.',
      expression: '1 / (2*pi*r*c)',
      inputs: [
        CalcFormulaInput(
          name: 'r',
          label: 'Resistance',
          defaultExpression: '10 kΩ',
        ),
        CalcFormulaInput(
          name: 'c',
          label: 'Capacitance',
          defaultExpression: '100 nF',
        ),
      ],
    ),
    CalcFormula(
      id: 'rl_cutoff',
      name: 'RL cutoff frequency',
      category: CalcFormulaCategories.basic,
      description: 'Corner frequency of a first-order RL filter.',
      expression: 'r / (2*pi*l)',
      inputs: [
        CalcFormulaInput(
          name: 'r',
          label: 'Resistance',
          defaultExpression: '100 Ω',
        ),
        CalcFormulaInput(
          name: 'l',
          label: 'Inductance',
          defaultExpression: '1 mH',
        ),
      ],
    ),
    CalcFormula(
      id: 'lc_resonance',
      name: 'LC resonance frequency',
      category: CalcFormulaCategories.basic,
      description: 'Resonant frequency of an ideal LC tank.',
      expression: '1 / (2*pi*sqrt(l*c))',
      inputs: [
        CalcFormulaInput(
          name: 'l',
          label: 'Inductance',
          defaultExpression: '100 µH',
        ),
        CalcFormulaInput(
          name: 'c',
          label: 'Capacitance',
          defaultExpression: '100 nF',
        ),
      ],
    ),
    CalcFormula(
      id: 'rlc_q',
      name: 'Series RLC quality factor',
      category: CalcFormulaCategories.basic,
      description: 'Quality factor of a series RLC circuit at resonance.',
      expression: 'sqrt(l/c) / r',
      inputs: [
        CalcFormulaInput(
          name: 'r',
          label: 'Resistance',
          defaultExpression: '10 Ω',
        ),
        CalcFormulaInput(
          name: 'l',
          label: 'Inductance',
          defaultExpression: '100 µH',
        ),
        CalcFormulaInput(
          name: 'c',
          label: 'Capacitance',
          defaultExpression: '100 nF',
        ),
      ],
    ),
    CalcFormula(
      id: 'impedance_c',
      name: 'Capacitive impedance',
      category: CalcFormulaCategories.basic,
      description: 'Complex impedance of a capacitor.',
      expression: '1 / (j*2*pi*f*c)',
      inputs: [
        CalcFormulaInput(
          name: 'c',
          label: 'Capacitance',
          defaultExpression: '100 nF',
        ),
        CalcFormulaInput(
          name: 'f',
          label: 'Frequency',
          defaultExpression: '10 kHz',
        ),
      ],
    ),
    CalcFormula(
      id: 'impedance_l',
      name: 'Inductive impedance',
      category: CalcFormulaCategories.basic,
      description: 'Complex impedance of an inductor.',
      expression: 'j*2*pi*f*l',
      inputs: [
        CalcFormulaInput(
          name: 'l',
          label: 'Inductance',
          defaultExpression: '1 mH',
        ),
        CalcFormulaInput(
          name: 'f',
          label: 'Frequency',
          defaultExpression: '10 kHz',
        ),
      ],
    ),
    CalcFormula(
      id: 'complex_power',
      name: 'Complex AC power',
      category: CalcFormulaCategories.basic,
      description: 'Complex power from RMS voltage and conjugate current.',
      expression: 'v * conj(i)',
      inputs: [
        CalcFormulaInput(
          name: 'v',
          label: 'RMS voltage',
          defaultExpression: '230 V',
        ),
        CalcFormulaInput(
          name: 'i',
          label: 'RMS current',
          defaultExpression: '2 A',
        ),
      ],
    ),
    CalcFormula(
      id: 'power_factor',
      name: 'Power factor',
      category: CalcFormulaCategories.basic,
      description:
          'Power factor from the phase angle between voltage and current.',
      expression: 'cos(phi)',
      inputs: [
        CalcFormulaInput(
          name: 'phi',
          label: 'Phase angle',
          defaultExpression: '30°',
        ),
      ],
    ),
    CalcFormula(
      id: 'real_power',
      name: 'Real AC power',
      category: CalcFormulaCategories.basic,
      description: 'Active power from RMS voltage, RMS current and phase.',
      expression: 'vrms * irms * cos(phi)',
      inputs: [
        CalcFormulaInput(
          name: 'vrms',
          label: 'RMS voltage',
          defaultExpression: '230 V',
        ),
        CalcFormulaInput(
          name: 'irms',
          label: 'RMS current',
          defaultExpression: '2 A',
        ),
        CalcFormulaInput(
          name: 'phi',
          label: 'Phase angle',
          defaultExpression: '30°',
        ),
      ],
    ),
    CalcFormula(
      id: 'reactive_power',
      name: 'Reactive AC power',
      category: CalcFormulaCategories.basic,
      description: 'Reactive power from RMS voltage, RMS current and phase.',
      expression: 'vrms * irms * sin(phi)',
      inputs: [
        CalcFormulaInput(
          name: 'vrms',
          label: 'RMS voltage',
          defaultExpression: '230 V',
        ),
        CalcFormulaInput(
          name: 'irms',
          label: 'RMS current',
          defaultExpression: '2 A',
        ),
        CalcFormulaInput(
          name: 'phi',
          label: 'Phase angle',
          defaultExpression: '30°',
        ),
      ],
    ),
    CalcFormula(
      id: 'apparent_power',
      name: 'Apparent power',
      category: CalcFormulaCategories.basic,
      description: 'Apparent power from RMS voltage and RMS current.',
      expression: 'vrms * irms',
      inputs: [
        CalcFormulaInput(
          name: 'vrms',
          label: 'RMS voltage',
          defaultExpression: '230 V',
        ),
        CalcFormulaInput(
          name: 'irms',
          label: 'RMS current',
          defaultExpression: '2 A',
        ),
      ],
    ),
    CalcFormula(
      id: 'sine_rms',
      name: 'Sine RMS from peak',
      category: CalcFormulaCategories.basic,
      description: 'RMS value of a sine wave from its peak value.',
      expression: 'vpeak / sqrt(2)',
      inputs: [
        CalcFormulaInput(
          name: 'vpeak',
          label: 'Peak voltage',
          defaultExpression: '325 V',
        ),
      ],
      assumptions: ['The waveform is a pure sine.'],
    ),
    CalcFormula(
      id: 'sine_peak',
      name: 'Sine peak from RMS',
      category: CalcFormulaCategories.basic,
      description: 'Peak value of a sine wave from its RMS value.',
      expression: 'vrms * sqrt(2)',
      inputs: [
        CalcFormulaInput(
          name: 'vrms',
          label: 'RMS voltage',
          defaultExpression: '230 V',
        ),
      ],
      assumptions: ['The waveform is a pure sine.'],
    ),
    CalcFormula(
      id: 'sine_vpp_to_rms',
      name: 'Sine RMS from peak-to-peak',
      category: CalcFormulaCategories.basic,
      description: 'RMS value of a sine wave from its peak-to-peak value.',
      expression: 'vpp / (2*sqrt(2))',
      inputs: [
        CalcFormulaInput(
          name: 'vpp',
          label: 'Peak-to-peak voltage',
          defaultExpression: '10 V',
        ),
      ],
      assumptions: ['The waveform is a pure sine.'],
    ),

    // =======================================================================
    // Filters and Analog
    // =======================================================================
    CalcFormula(
      id: 'rc_lowpass_magnitude',
      name: 'RC low-pass magnitude',
      category: CalcFormulaCategories.filters,
      description: 'Magnitude of a first-order RC low-pass transfer function.',
      expression: 'abs(1 / (1 + j*2*pi*f*r*c))',
      inputs: [
        CalcFormulaInput(
          name: 'r',
          label: 'Resistance',
          defaultExpression: '10 kΩ',
        ),
        CalcFormulaInput(
          name: 'c',
          label: 'Capacitance',
          defaultExpression: '100 nF',
        ),
        CalcFormulaInput(
          name: 'f',
          label: 'Frequency',
          defaultExpression: '100 Hz',
        ),
      ],
    ),
    CalcFormula(
      id: 'rc_lowpass_db',
      name: 'RC low-pass gain in dB',
      category: CalcFormulaCategories.filters,
      description: 'Gain of a first-order RC low-pass in dB.',
      expression: 'db20(abs(1 / (1 + j*2*pi*f*r*c)))',
      inputs: [
        CalcFormulaInput(
          name: 'r',
          label: 'Resistance',
          defaultExpression: '10 kΩ',
        ),
        CalcFormulaInput(
          name: 'c',
          label: 'Capacitance',
          defaultExpression: '100 nF',
        ),
        CalcFormulaInput(
          name: 'f',
          label: 'Frequency',
          defaultExpression: '1 kHz',
        ),
      ],
    ),
    CalcFormula(
      id: 'rc_highpass_magnitude',
      name: 'RC high-pass magnitude',
      category: CalcFormulaCategories.filters,
      description: 'Magnitude of a first-order RC high-pass transfer function.',
      expression: 'abs((j*2*pi*f*r*c) / (1 + j*2*pi*f*r*c))',
      inputs: [
        CalcFormulaInput(
          name: 'r',
          label: 'Resistance',
          defaultExpression: '10 kΩ',
        ),
        CalcFormulaInput(
          name: 'c',
          label: 'Capacitance',
          defaultExpression: '100 nF',
        ),
        CalcFormulaInput(
          name: 'f',
          label: 'Frequency',
          defaultExpression: '1 kHz',
        ),
      ],
    ),
    CalcFormula(
      id: 'opamp_non_inverting',
      name: 'Non-inverting op-amp gain',
      category: CalcFormulaCategories.filters,
      description: 'Closed-loop gain of a non-inverting amplifier.',
      expression: '1 + rf / rg',
      inputs: [
        CalcFormulaInput(
          name: 'rf',
          label: 'Feedback resistor',
          defaultExpression: '10 kΩ',
        ),
        CalcFormulaInput(
          name: 'rg',
          label: 'Ground resistor',
          defaultExpression: '1 kΩ',
        ),
      ],
      assumptions: ['Ideal op-amp with very high open-loop gain.'],
    ),
    CalcFormula(
      id: 'opamp_inverting',
      name: 'Inverting op-amp gain',
      category: CalcFormulaCategories.filters,
      description: 'Closed-loop gain of an inverting amplifier.',
      expression: '-rf / rin',
      inputs: [
        CalcFormulaInput(
          name: 'rf',
          label: 'Feedback resistor',
          defaultExpression: '10 kΩ',
        ),
        CalcFormulaInput(
          name: 'rin',
          label: 'Input resistor',
          defaultExpression: '1 kΩ',
        ),
      ],
      assumptions: ['Ideal op-amp with very high open-loop gain.'],
    ),
    CalcFormula(
      id: 'resistor_noise',
      name: 'Resistor thermal noise voltage',
      category: CalcFormulaCategories.filters,
      description: 'RMS thermal noise voltage of a resistor in a bandwidth.',
      expression: 'sqrt(4*k_B*t*r*bw)',
      inputs: [
        CalcFormulaInput(
          name: 'r',
          label: 'Resistance',
          defaultExpression: '10 kΩ',
        ),
        CalcFormulaInput(
          name: 't',
          label: 'Temperature',
          defaultExpression: '290 K',
        ),
        CalcFormulaInput(
          name: 'bw',
          label: 'Noise bandwidth',
          defaultExpression: '1 MHz',
        ),
      ],
    ),
    CalcFormula(
      id: 'snr_power',
      name: 'SNR from powers',
      category: CalcFormulaCategories.filters,
      description: 'Signal-to-noise ratio in dB from two powers.',
      expression: 'db10(signal / noise)',
      inputs: [
        CalcFormulaInput(
          name: 'signal',
          label: 'Signal power',
          defaultExpression: '1 mW',
        ),
        CalcFormulaInput(
          name: 'noise',
          label: 'Noise power',
          defaultExpression: '1 µW',
        ),
      ],
    ),
    CalcFormula(
      id: 'dynamic_range',
      name: 'Dynamic range',
      category: CalcFormulaCategories.filters,
      description: 'Dynamic range in dB from maximum and minimum powers.',
      expression: 'db10(maximum / minimum)',
      inputs: [
        CalcFormulaInput(
          name: 'maximum',
          label: 'Maximum signal',
          defaultExpression: '1 W',
        ),
        CalcFormulaInput(
          name: 'minimum',
          label: 'Minimum signal',
          defaultExpression: '1 nW',
        ),
      ],
    ),
    CalcFormula(
      id: 'thd_percent',
      name: 'THD from harmonics',
      category: CalcFormulaCategories.filters,
      description: 'Total harmonic distortion from fundamental and harmonics.',
      expression: 'thd(fundamental, [h2, h3, h4])',
      inputs: [
        CalcFormulaInput(
          name: 'fundamental',
          label: 'Fundamental RMS voltage',
          defaultExpression: '1 V',
        ),
        CalcFormulaInput(
          name: 'h2',
          label: '2nd harmonic',
          defaultExpression: '10 mV',
        ),
        CalcFormulaInput(
          name: 'h3',
          label: '3rd harmonic',
          defaultExpression: '5 mV',
        ),
        CalcFormulaInput(
          name: 'h4',
          label: '4th harmonic',
          defaultExpression: '2 mV',
        ),
      ],
    ),
    CalcFormula(
      id: 'opamp_gain_db',
      name: 'Non-inverting gain in dB',
      category: CalcFormulaCategories.filters,
      description: 'Closed-loop gain of a non-inverting amplifier in dB.',
      expression: 'db20(1 + rf / rg)',
      inputs: [
        CalcFormulaInput(
          name: 'rf',
          label: 'Feedback resistor',
          defaultExpression: '10 kΩ',
        ),
        CalcFormulaInput(
          name: 'rg',
          label: 'Ground resistor',
          defaultExpression: '1 kΩ',
        ),
      ],
    ),

    // =======================================================================
    // Measurement and Uncertainty
    // =======================================================================
    CalcFormula(
      id: 'adc_lsb',
      name: 'ADC LSB size',
      category: CalcFormulaCategories.measurement,
      description: 'Voltage represented by one LSB of an ADC.',
      expression: 'vref / 2^bits',
      inputs: [
        CalcFormulaInput(
          name: 'bits',
          label: 'Resolution in bits',
          defaultExpression: '12',
        ),
        CalcFormulaInput(
          name: 'vref',
          label: 'Reference voltage',
          defaultExpression: '3.3 V',
        ),
      ],
    ),
    CalcFormula(
      id: 'adc_snr',
      name: 'Ideal ADC SNR',
      category: CalcFormulaCategories.measurement,
      description:
          'Signal-to-noise ratio of an ideal ADC with a full-scale sine.',
      expression: 'adc_snr(bits)',
      inputs: [
        CalcFormulaInput(
          name: 'bits',
          label: 'Resolution in bits',
          defaultExpression: '12',
        ),
      ],
      assumptions: ['Ideal quantizer and a full-scale sine input.'],
    ),
    CalcFormula(
      id: 'quantization_rms',
      name: 'Quantization noise RMS',
      category: CalcFormulaCategories.measurement,
      description: 'RMS quantization noise for a uniform ADC.',
      expression: 'adc_lsb(bits, vref) / sqrt(12)',
      inputs: [
        CalcFormulaInput(
          name: 'bits',
          label: 'Resolution in bits',
          defaultExpression: '12',
        ),
        CalcFormulaInput(
          name: 'vref',
          label: 'Reference voltage',
          defaultExpression: '3.3 V',
        ),
      ],
      assumptions: ['The quantization error is uniformly distributed.'],
    ),
    CalcFormula(
      id: 'relative_error',
      name: 'Relative measurement error',
      category: CalcFormulaCategories.measurement,
      description: 'Signed relative error of a measurement in percent.',
      expression: 'to((measured - reference) / reference, %)',
      inputs: [
        CalcFormulaInput(
          name: 'measured',
          label: 'Measured value',
          defaultExpression: '10.2 V',
        ),
        CalcFormulaInput(
          name: 'reference',
          label: 'Reference value',
          defaultExpression: '10 V',
        ),
      ],
    ),
    CalcFormula(
      id: 'multimeter_accuracy',
      name: 'Multimeter accuracy',
      category: CalcFormulaCategories.measurement,
      description:
          'Worst-case reading error from percent-of-reading plus digits.',
      expression: '(percent / 100) * reading + digits * resolution',
      inputs: [
        CalcFormulaInput(
          name: 'reading',
          label: 'Reading',
          defaultExpression: '10 V',
        ),
        CalcFormulaInput(
          name: 'percent',
          label: 'Percent of reading',
          defaultExpression: '0.5',
          hint: 'Enter 0.5 for 0.5 %.',
        ),
        CalcFormulaInput(
          name: 'digits',
          label: 'Counts (digits)',
          defaultExpression: '2',
        ),
        CalcFormulaInput(
          name: 'resolution',
          label: 'Resolution per count',
          defaultExpression: '1 mV',
        ),
      ],
    ),
    CalcFormula(
      id: 'worst_case_tolerance',
      name: 'Worst-case tolerance',
      category: CalcFormulaCategories.measurement,
      description:
          'Upper limit of a component value for a symmetric tolerance.',
      expression: 'nominal * (1 + tolerance / 100)',
      inputs: [
        CalcFormulaInput(
          name: 'nominal',
          label: 'Nominal value',
          defaultExpression: '10 kΩ',
        ),
        CalcFormulaInput(
          name: 'tolerance',
          label: 'Tolerance in percent',
          defaultExpression: '1',
        ),
      ],
    ),
    CalcFormula(
      id: 'rss_tolerance',
      name: 'RSS tolerance chain',
      category: CalcFormulaCategories.measurement,
      description: 'Root-sum-square tolerance of three contributions.',
      expression: 'nominal * sqrt((t1/100)^2 + (t2/100)^2 + (t3/100)^2)',
      inputs: [
        CalcFormulaInput(
          name: 'nominal',
          label: 'Nominal value',
          defaultExpression: '10 kΩ',
        ),
        CalcFormulaInput(
          name: 't1',
          label: 'Tolerance 1 in percent',
          defaultExpression: '1',
        ),
        CalcFormulaInput(
          name: 't2',
          label: 'Tolerance 2 in percent',
          defaultExpression: '0.5',
        ),
        CalcFormulaInput(
          name: 't3',
          label: 'Tolerance 3 in percent',
          defaultExpression: '0.2',
        ),
      ],
      assumptions: ['Independent, normally distributed tolerances.'],
    ),
    CalcFormula(
      id: 'uncertainty_sum',
      name: 'Combined uncertainty of a sum',
      category: CalcFormulaCategories.measurement,
      description:
          'Root-sum-square combination of two independent uncertainties.',
      expression: 'sqrt(u1^2 + u2^2)',
      inputs: [
        CalcFormulaInput(
          name: 'u1',
          label: 'Uncertainty 1',
          defaultExpression: '1 mV',
        ),
        CalcFormulaInput(
          name: 'u2',
          label: 'Uncertainty 2',
          defaultExpression: '2 mV',
        ),
      ],
      assumptions: ['Independent and uncorrelated contributions.'],
    ),
    CalcFormula(
      id: 'uncertainty_product',
      name: 'Relative uncertainty of a product',
      category: CalcFormulaCategories.measurement,
      description: 'Relative uncertainty from two measured factors.',
      expression: 'sqrt((u1/x1)^2 + (u2/x2)^2)',
      inputs: [
        CalcFormulaInput(
          name: 'x1',
          label: 'Value 1',
          defaultExpression: '10 V',
        ),
        CalcFormulaInput(
          name: 'u1',
          label: 'Uncertainty 1',
          defaultExpression: '0.1 V',
        ),
        CalcFormulaInput(
          name: 'x2',
          label: 'Value 2',
          defaultExpression: '2 A',
        ),
        CalcFormulaInput(
          name: 'u2',
          label: 'Uncertainty 2',
          defaultExpression: '0.02 A',
        ),
      ],
      assumptions: ['Independent and uncorrelated contributions.'],
    ),
    CalcFormula(
      id: 'sample_mean',
      name: 'Mean of samples',
      category: CalcFormulaCategories.measurement,
      description: 'Arithmetic mean of a list of measured values.',
      expression: 'mean(data)',
      inputs: [
        CalcFormulaInput(
          name: 'data',
          label: 'Samples',
          defaultExpression: '[1 V, 2 V, 3 V, 4 V]',
        ),
      ],
    ),
    CalcFormula(
      id: 'sample_rms',
      name: 'RMS of samples',
      category: CalcFormulaCategories.measurement,
      description: 'Root-mean-square value of a list of samples.',
      expression: 'rms(data)',
      inputs: [
        CalcFormulaInput(
          name: 'data',
          label: 'Samples',
          defaultExpression: '[1 V, -1 V, 1 V, -1 V]',
        ),
      ],
    ),
    CalcFormula(
      id: 'sample_stdev',
      name: 'Standard deviation',
      category: CalcFormulaCategories.measurement,
      description: 'Sample standard deviation of a list of values.',
      expression: 'stdev(data)',
      inputs: [
        CalcFormulaInput(
          name: 'data',
          label: 'Samples',
          defaultExpression: '[1 V, 2 V, 3 V, 4 V]',
        ),
      ],
      assumptions: ['Sample standard deviation (n-1 denominator).'],
    ),
    CalcFormula(
      id: 'sample_crest',
      name: 'Crest factor of samples',
      category: CalcFormulaCategories.measurement,
      description: 'Peak value divided by RMS value.',
      expression: 'crest(data)',
      inputs: [
        CalcFormulaInput(
          name: 'data',
          label: 'Samples',
          defaultExpression: '[0 V, 1 V, 0 V, -1 V]',
        ),
      ],
    ),
    CalcFormula(
      id: 'scope_record_time',
      name: 'Oscilloscope record time',
      category: CalcFormulaCategories.measurement,
      description: 'Time represented by the acquired record.',
      expression: 'record_length / sample_rate',
      inputs: [
        CalcFormulaInput(
          name: 'record_length',
          label: 'Record length',
          defaultExpression: '14 MSa',
        ),
        CalcFormulaInput(
          name: 'sample_rate',
          label: 'Sample rate',
          defaultExpression: '1 GSa/s',
        ),
      ],
    ),
    CalcFormula(
      id: 'scope_nyquist',
      name: 'Nyquist frequency',
      category: CalcFormulaCategories.measurement,
      description:
          'Highest frequency that can be represented at a sample rate.',
      expression: 'sample_rate / 2',
      inputs: [
        CalcFormulaInput(
          name: 'sample_rate',
          label: 'Sample rate',
          defaultExpression: '1 GSa/s',
        ),
      ],
    ),
    CalcFormula(
      id: 'scope_fft_bin',
      name: 'FFT bin width',
      category: CalcFormulaCategories.measurement,
      description: 'Frequency resolution of an FFT record.',
      expression: 'sample_rate / record_length',
      inputs: [
        CalcFormulaInput(
          name: 'sample_rate',
          label: 'Sample rate',
          defaultExpression: '1 GSa/s',
        ),
        CalcFormulaInput(
          name: 'record_length',
          label: 'Record length',
          defaultExpression: '1 MSa',
        ),
      ],
    ),
    CalcFormula(
      id: 'scope_rise_time',
      name: 'Bandwidth-limited rise time',
      category: CalcFormulaCategories.measurement,
      description: 'Approximate 10-90 % rise time from bandwidth.',
      expression: '0.35 / bandwidth',
      inputs: [
        CalcFormulaInput(
          name: 'bandwidth',
          label: 'Bandwidth',
          defaultExpression: '100 MHz',
        ),
      ],
      assumptions: ['Single-pole Gaussian response, 10-90 % transition.'],
    ),
    CalcFormula(
      id: 'probe_loading',
      name: 'Probe loading corner',
      category: CalcFormulaCategories.measurement,
      description:
          'Low-pass corner formed by probe resistance and capacitance.',
      expression: '1 / (2*pi*f*r_probe*c_probe)',
      inputs: [
        CalcFormulaInput(
          name: 'f',
          label: 'Frequency',
          defaultExpression: '10 MHz',
        ),
        CalcFormulaInput(
          name: 'r_probe',
          label: 'Probe resistance',
          defaultExpression: '10 MΩ',
        ),
        CalcFormulaInput(
          name: 'c_probe',
          label: 'Probe capacitance',
          defaultExpression: '15 pF',
        ),
      ],
    ),

    // =======================================================================
    // Audio and DSP
    // =======================================================================
    CalcFormula(
      id: 'dbu_to_vrms',
      name: 'dBu to RMS voltage',
      category: CalcFormulaCategories.audio,
      description: 'RMS voltage for a level in dBu (0 dBu = 0.775 V).',
      expression: 'dbu_to_vrms(level)',
      inputs: [
        CalcFormulaInput(
          name: 'level',
          label: 'Level',
          defaultExpression: '0 dBu',
        ),
      ],
    ),
    CalcFormula(
      id: 'vrms_to_dbu',
      name: 'RMS voltage to dBu',
      category: CalcFormulaCategories.audio,
      description: 'Level in dBu for an RMS voltage.',
      expression: 'vrms_to_dbu(voltage)',
      inputs: [
        CalcFormulaInput(
          name: 'voltage',
          label: 'RMS voltage',
          defaultExpression: '0.775 V',
        ),
      ],
    ),
    CalcFormula(
      id: 'dbv_to_vrms',
      name: 'dBV to RMS voltage',
      category: CalcFormulaCategories.audio,
      description: 'RMS voltage for a level in dBV (0 dBV = 1 V).',
      expression: 'dbv_to_vrms(level)',
      inputs: [
        CalcFormulaInput(
          name: 'level',
          label: 'Level',
          defaultExpression: '0 dBV',
        ),
      ],
    ),
    CalcFormula(
      id: 'vrms_to_dbv',
      name: 'RMS voltage to dBV',
      category: CalcFormulaCategories.audio,
      description: 'Level in dBV for an RMS voltage.',
      expression: 'vrms_to_dbv(voltage)',
      inputs: [
        CalcFormulaInput(
          name: 'voltage',
          label: 'RMS voltage',
          defaultExpression: '1 V',
        ),
      ],
    ),
    CalcFormula(
      id: 'dbfs_to_vrms',
      name: 'dBFS to RMS voltage',
      category: CalcFormulaCategories.audio,
      description:
          'RMS voltage for a digital level and a full-scale reference.',
      expression: 'dbfs_to_vrms(level, full_scale)',
      inputs: [
        CalcFormulaInput(
          name: 'level',
          label: 'Level',
          defaultExpression: '-6 dBFS',
        ),
        CalcFormulaInput(
          name: 'full_scale',
          label: 'Full-scale RMS voltage',
          defaultExpression: '1 V',
        ),
      ],
    ),
    CalcFormula(
      id: 'vrms_to_dbfs',
      name: 'RMS voltage to dBFS',
      category: CalcFormulaCategories.audio,
      description:
          'Digital level for an RMS voltage and a full-scale reference.',
      expression: 'vrms_to_dbfs(voltage, full_scale)',
      inputs: [
        CalcFormulaInput(
          name: 'voltage',
          label: 'RMS voltage',
          defaultExpression: '0.5 V',
        ),
        CalcFormulaInput(
          name: 'full_scale',
          label: 'Full-scale RMS voltage',
          defaultExpression: '1 V',
        ),
      ],
    ),
    CalcFormula(
      id: 'audio_power_level',
      name: 'Audio power in dB',
      category: CalcFormulaCategories.audio,
      description:
          'Power level of an RMS voltage into a load relative to a reference.',
      expression: 'db10((vrms^2 / load) / reference_power)',
      inputs: [
        CalcFormulaInput(
          name: 'vrms',
          label: 'RMS voltage',
          defaultExpression: '1 V',
        ),
        CalcFormulaInput(
          name: 'load',
          label: 'Load resistance',
          defaultExpression: '8 Ω',
        ),
        CalcFormulaInput(
          name: 'reference_power',
          label: 'Reference power',
          defaultExpression: '1 mW',
        ),
      ],
    ),
    CalcFormula(
      id: 'fft_resolution',
      name: 'FFT frequency resolution',
      category: CalcFormulaCategories.audio,
      description: 'Spacing between FFT bins.',
      expression: 'sample_rate / fft_size',
      inputs: [
        CalcFormulaInput(
          name: 'sample_rate',
          label: 'Sample rate',
          defaultExpression: '48 kHz',
        ),
        CalcFormulaInput(
          name: 'fft_size',
          label: 'FFT size',
          defaultExpression: '1024',
        ),
      ],
    ),
    CalcFormula(
      id: 'oversampling_snr',
      name: 'Oversampling SNR gain',
      category: CalcFormulaCategories.audio,
      description: 'SNR improvement from oversampling by a factor.',
      expression: 'db(6.02 * log2(osr))',
      inputs: [
        CalcFormulaInput(
          name: 'osr',
          label: 'Oversampling ratio',
          defaultExpression: '4',
        ),
      ],
      assumptions: ['Ideal quantizer with a full-scale sine input.'],
    ),
    CalcFormula(
      id: 'decimation_ratio',
      name: 'Decimation ratio',
      category: CalcFormulaCategories.audio,
      description: 'Input-to-output rate ratio of a decimator.',
      expression: 'input_rate / output_rate',
      inputs: [
        CalcFormulaInput(
          name: 'input_rate',
          label: 'Input rate',
          defaultExpression: '48 kHz',
        ),
        CalcFormulaInput(
          name: 'output_rate',
          label: 'Output rate',
          defaultExpression: '8 kHz',
        ),
      ],
    ),
    CalcFormula(
      id: 'interpolation_ratio',
      name: 'Interpolation ratio',
      category: CalcFormulaCategories.audio,
      description: 'Output-to-input rate ratio of an interpolator.',
      expression: 'output_rate / input_rate',
      inputs: [
        CalcFormulaInput(
          name: 'output_rate',
          label: 'Output rate',
          defaultExpression: '48 kHz',
        ),
        CalcFormulaInput(
          name: 'input_rate',
          label: 'Input rate',
          defaultExpression: '8 kHz',
        ),
      ],
    ),
    CalcFormula(
      id: 'alias_frequency',
      name: 'Aliased frequency',
      category: CalcFormulaCategories.audio,
      description:
          'Frequency after sampling, folded into the first Nyquist zone.',
      expression: 'abs(f - round(f / sample_rate) * sample_rate)',
      inputs: [
        CalcFormulaInput(
          name: 'f',
          label: 'Input frequency',
          defaultExpression: '30 kHz',
        ),
        CalcFormulaInput(
          name: 'sample_rate',
          label: 'Sample rate',
          defaultExpression: '48 kHz',
        ),
      ],
    ),
    CalcFormula(
      id: 'quantization_step',
      name: 'Quantization step',
      category: CalcFormulaCategories.audio,
      description: 'Step size of a uniform quantizer.',
      expression: 'full_scale / 2^bits',
      inputs: [
        CalcFormulaInput(
          name: 'full_scale',
          label: 'Full-scale voltage',
          defaultExpression: '1 V',
        ),
        CalcFormulaInput(
          name: 'bits',
          label: 'Resolution in bits',
          defaultExpression: '16',
        ),
      ],
    ),
    CalcFormula(
      id: 'bit_depth_range',
      name: 'Bit-depth dynamic range',
      category: CalcFormulaCategories.audio,
      description: 'Theoretical SNR of a uniform quantizer.',
      expression: 'db(6.02 * bits + 1.76)',
      inputs: [
        CalcFormulaInput(
          name: 'bits',
          label: 'Resolution in bits',
          defaultExpression: '16',
        ),
      ],
      assumptions: ['Ideal quantizer with a full-scale sine input.'],
    ),

    // =======================================================================
    // Digital and Embedded
    // =======================================================================
    CalcFormula(
      id: 'timer_tick',
      name: 'Timer tick period',
      category: CalcFormulaCategories.digital,
      description: 'Duration of one timer tick after the prescaler.',
      expression: 'prescaler / clock',
      inputs: [
        CalcFormulaInput(
          name: 'prescaler',
          label: 'Prescaler',
          defaultExpression: '72',
        ),
        CalcFormulaInput(
          name: 'clock',
          label: 'Timer clock',
          defaultExpression: '72 MHz',
        ),
      ],
    ),
    CalcFormula(
      id: 'timer_overflow',
      name: 'Timer overflow period',
      category: CalcFormulaCategories.digital,
      description: 'Time between timer overflow events.',
      expression: '((top + 1) * prescaler) / clock',
      inputs: [
        CalcFormulaInput(
          name: 'top',
          label: 'Auto-reload value',
          defaultExpression: '999',
        ),
        CalcFormulaInput(
          name: 'prescaler',
          label: 'Prescaler',
          defaultExpression: '72',
        ),
        CalcFormulaInput(
          name: 'clock',
          label: 'Timer clock',
          defaultExpression: '72 MHz',
        ),
      ],
    ),
    CalcFormula(
      id: 'pwm_frequency',
      name: 'PWM frequency',
      category: CalcFormulaCategories.digital,
      description: 'PWM frequency from clock, prescaler and period register.',
      expression: 'pwm_frequency(clock, prescaler, top)',
      inputs: [
        CalcFormulaInput(
          name: 'clock',
          label: 'Timer clock',
          defaultExpression: '72 MHz',
        ),
        CalcFormulaInput(
          name: 'prescaler',
          label: 'Prescaler',
          defaultExpression: '72',
        ),
        CalcFormulaInput(
          name: 'top',
          label: 'Period register',
          defaultExpression: '999',
        ),
      ],
    ),
    CalcFormula(
      id: 'pwm_duty',
      name: 'PWM duty cycle',
      category: CalcFormulaCategories.digital,
      description: 'Duty cycle from compare and period registers.',
      expression: 'to(compare / (top + 1), %)',
      inputs: [
        CalcFormulaInput(
          name: 'compare',
          label: 'Compare value',
          defaultExpression: '250',
        ),
        CalcFormulaInput(
          name: 'top',
          label: 'Period register',
          defaultExpression: '999',
        ),
      ],
    ),
    CalcFormula(
      id: 'uart_divisor',
      name: 'UART divisor',
      category: CalcFormulaCategories.digital,
      description: 'Divider value for a target baud rate.',
      expression: 'clock / (oversampling * baud)',
      inputs: [
        CalcFormulaInput(
          name: 'clock',
          label: 'Peripheral clock',
          defaultExpression: '72 MHz',
        ),
        CalcFormulaInput(
          name: 'oversampling',
          label: 'Oversampling',
          defaultExpression: '16',
        ),
        CalcFormulaInput(
          name: 'baud',
          label: 'Target baud rate',
          defaultExpression: '115200 Bd',
        ),
      ],
    ),
    CalcFormula(
      id: 'uart_baud',
      name: 'UART actual baud rate',
      category: CalcFormulaCategories.digital,
      description: 'Actual baud rate for a divider value.',
      expression: 'uart_baud(clock, oversampling, divisor)',
      inputs: [
        CalcFormulaInput(
          name: 'clock',
          label: 'Peripheral clock',
          defaultExpression: '72 MHz',
        ),
        CalcFormulaInput(
          name: 'oversampling',
          label: 'Oversampling',
          defaultExpression: '16',
        ),
        CalcFormulaInput(
          name: 'divisor',
          label: 'Divider value',
          defaultExpression: '39',
        ),
      ],
    ),
    CalcFormula(
      id: 'baud_error',
      name: 'UART baud error',
      category: CalcFormulaCategories.digital,
      description: 'Relative baud-rate error in percent.',
      expression: 'baud_error(actual, desired)',
      inputs: [
        CalcFormulaInput(
          name: 'actual',
          label: 'Actual baud rate',
          defaultExpression: '115384 Bd',
        ),
        CalcFormulaInput(
          name: 'desired',
          label: 'Desired baud rate',
          defaultExpression: '115200 Bd',
        ),
      ],
    ),
    CalcFormula(
      id: 'can_bitrate',
      name: 'CAN bit rate',
      category: CalcFormulaCategories.digital,
      description: 'Bit rate from clock, prescaler and segment times.',
      expression: 'can_bitrate(clock, prescaler, tseg1, tseg2)',
      inputs: [
        CalcFormulaInput(
          name: 'clock',
          label: 'CAN clock',
          defaultExpression: '48 MHz',
        ),
        CalcFormulaInput(
          name: 'prescaler',
          label: 'Prescaler',
          defaultExpression: '4',
        ),
        CalcFormulaInput(
          name: 'tseg1',
          label: 'TSEG1 in time quanta',
          defaultExpression: '13',
        ),
        CalcFormulaInput(
          name: 'tseg2',
          label: 'TSEG2 in time quanta',
          defaultExpression: '2',
        ),
      ],
    ),
    CalcFormula(
      id: 'can_sample_point',
      name: 'CAN sample point',
      category: CalcFormulaCategories.digital,
      description: 'Sample point position in percent.',
      expression: 'to((1 + tseg1) / (1 + tseg1 + tseg2), %)',
      inputs: [
        CalcFormulaInput(
          name: 'tseg1',
          label: 'TSEG1 in time quanta',
          defaultExpression: '13',
        ),
        CalcFormulaInput(
          name: 'tseg2',
          label: 'TSEG2 in time quanta',
          defaultExpression: '2',
        ),
      ],
    ),
    CalcFormula(
      id: 'spi_clock',
      name: 'SPI clock',
      category: CalcFormulaCategories.digital,
      description: 'SPI clock from peripheral clock and divider.',
      expression: 'clock / prescaler',
      inputs: [
        CalcFormulaInput(
          name: 'clock',
          label: 'Peripheral clock',
          defaultExpression: '72 MHz',
        ),
        CalcFormulaInput(
          name: 'prescaler',
          label: 'Clock divider',
          defaultExpression: '16',
        ),
      ],
    ),
    CalcFormula(
      id: 'i2c_rise_time',
      name: 'I2C rise time',
      category: CalcFormulaCategories.digital,
      description:
          'Approximate bus rise time from pull-up and bus capacitance.',
      expression: '0.8473 * r * c',
      inputs: [
        CalcFormulaInput(
          name: 'r',
          label: 'Pull-up resistance',
          defaultExpression: '4.7 kΩ',
        ),
        CalcFormulaInput(
          name: 'c',
          label: 'Bus capacitance',
          defaultExpression: '100 pF',
        ),
      ],
      assumptions: ['Fast-mode I2C rise-time approximation.'],
    ),
    CalcFormula(
      id: 'q_format_scale',
      name: 'Q-format scale',
      category: CalcFormulaCategories.digital,
      description: 'Integer scale factor for a fractional bit count.',
      expression: '2^fractional_bits',
      inputs: [
        CalcFormulaInput(
          name: 'fractional_bits',
          label: 'Fractional bits',
          defaultExpression: '15',
        ),
      ],
    ),
    CalcFormula(
      id: 'q_format_max',
      name: 'Q-format maximum',
      category: CalcFormulaCategories.digital,
      description: 'Largest signed value in a Q format.',
      expression: '(2^(total_bits - 1) - 1) / 2^fractional_bits',
      inputs: [
        CalcFormulaInput(
          name: 'total_bits',
          label: 'Total bits',
          defaultExpression: '16',
        ),
        CalcFormulaInput(
          name: 'fractional_bits',
          label: 'Fractional bits',
          defaultExpression: '15',
        ),
      ],
    ),
    CalcFormula(
      id: 'adc_code',
      name: 'ADC code from voltage',
      category: CalcFormulaCategories.digital,
      description: 'Ideal ADC code for an input voltage.',
      expression: 'round(vin / vref * 2^bits)',
      inputs: [
        CalcFormulaInput(
          name: 'vin',
          label: 'Input voltage',
          defaultExpression: '1.65 V',
        ),
        CalcFormulaInput(
          name: 'vref',
          label: 'Reference voltage',
          defaultExpression: '3.3 V',
        ),
        CalcFormulaInput(
          name: 'bits',
          label: 'Resolution in bits',
          defaultExpression: '12',
        ),
      ],
    ),
    CalcFormula(
      id: 'adc_voltage',
      name: 'ADC voltage from code',
      category: CalcFormulaCategories.digital,
      description: 'Input voltage for an ideal ADC code.',
      expression: 'code * vref / 2^bits',
      inputs: [
        CalcFormulaInput(
          name: 'code',
          label: 'ADC code',
          defaultExpression: '2048',
        ),
        CalcFormulaInput(
          name: 'vref',
          label: 'Reference voltage',
          defaultExpression: '3.3 V',
        ),
        CalcFormulaInput(
          name: 'bits',
          label: 'Resolution in bits',
          defaultExpression: '12',
        ),
      ],
    ),
    CalcFormula(
      id: 'bitmask',
      name: 'Bit mask',
      category: CalcFormulaCategories.digital,
      description: 'Mask with a given number of low bits set.',
      expression: 'mask(width)',
      inputs: [
        CalcFormulaInput(
          name: 'width',
          label: 'Width in bits',
          defaultExpression: '8',
        ),
      ],
    ),
    CalcFormula(
      id: 'two_complement',
      name: 'Two-complement conversion',
      category: CalcFormulaCategories.digital,
      description: 'Signed value of an unsigned two-complement word.',
      expression: 'to_signed(value, bits)',
      inputs: [
        CalcFormulaInput(
          name: 'value',
          label: 'Unsigned value',
          defaultExpression: '65535',
        ),
        CalcFormulaInput(
          name: 'bits',
          label: 'Word width',
          defaultExpression: '16',
        ),
      ],
    ),

    // =======================================================================
    // RF and Antennas
    // =======================================================================
    CalcFormula(
      id: 'wavelength',
      name: 'Free-space wavelength',
      category: CalcFormulaCategories.rf,
      description: 'Wavelength of a frequency in free space.',
      expression: 'c_0 / f',
      inputs: [
        CalcFormulaInput(
          name: 'f',
          label: 'Frequency',
          defaultExpression: '2.4 GHz',
        ),
      ],
    ),
    CalcFormula(
      id: 'frequency_wavelength',
      name: 'Frequency from wavelength',
      category: CalcFormulaCategories.rf,
      description: 'Free-space frequency for a wavelength.',
      expression: 'c_0 / lambda',
      inputs: [
        CalcFormulaInput(
          name: 'lambda',
          label: 'Wavelength',
          defaultExpression: '125 mm',
        ),
      ],
    ),
    CalcFormula(
      id: 'fspl',
      name: 'Free-space path loss',
      category: CalcFormulaCategories.rf,
      description: 'Free-space path loss in dB for distance and frequency.',
      expression: 'fspl(d, f)',
      inputs: [
        CalcFormulaInput(
          name: 'd',
          label: 'Distance',
          defaultExpression: '1 km',
        ),
        CalcFormulaInput(
          name: 'f',
          label: 'Frequency',
          defaultExpression: '2.4 GHz',
        ),
      ],
      assumptions: ['Far field, isotropic antennas, free-space propagation.'],
    ),
    CalcFormula(
      id: 'fspl_range',
      name: 'FSPL range from path loss',
      category: CalcFormulaCategories.rf,
      description: 'Distance that produces a given free-space path loss.',
      expression:
          '10^(db_value(p_tx + g_tx + g_rx - p_rx - l_tx - l_rx) / 20) * c_0 / (4*pi*f)',
      inputs: [
        CalcFormulaInput(
          name: 'p_tx',
          label: 'Transmit power',
          defaultExpression: '20 dBm',
        ),
        CalcFormulaInput(
          name: 'g_tx',
          label: 'Transmit antenna gain',
          defaultExpression: '2 dBi',
        ),
        CalcFormulaInput(
          name: 'g_rx',
          label: 'Receive antenna gain',
          defaultExpression: '5 dBi',
        ),
        CalcFormulaInput(
          name: 'p_rx',
          label: 'Receiver sensitivity',
          defaultExpression: '-80 dBm',
        ),
        CalcFormulaInput(
          name: 'l_tx',
          label: 'Transmit losses',
          defaultExpression: '0 dB',
        ),
        CalcFormulaInput(
          name: 'l_rx',
          label: 'Receive losses',
          defaultExpression: '0 dB',
        ),
        CalcFormulaInput(
          name: 'f',
          label: 'Frequency',
          defaultExpression: '2.4 GHz',
        ),
      ],
      assumptions: [
        'Free-space path loss model, far field, isotropic reference.',
      ],
    ),
    CalcFormula(
      id: 'eirp',
      name: 'EIRP',
      category: CalcFormulaCategories.rf,
      description: 'Effective isotropic radiated power.',
      expression: 'p_tx + g_tx',
      inputs: [
        CalcFormulaInput(
          name: 'p_tx',
          label: 'Transmit power',
          defaultExpression: '20 dBm',
        ),
        CalcFormulaInput(
          name: 'g_tx',
          label: 'Antenna gain',
          defaultExpression: '2 dBi',
        ),
      ],
    ),
    CalcFormula(
      id: 'erp',
      name: 'ERP',
      category: CalcFormulaCategories.rf,
      description: 'Effective radiated power relative to a half-wave dipole.',
      expression: 'p_tx + g_tx - 2.15 dB',
      inputs: [
        CalcFormulaInput(
          name: 'p_tx',
          label: 'Transmit power',
          defaultExpression: '20 dBm',
        ),
        CalcFormulaInput(
          name: 'g_tx',
          label: 'Antenna gain in dBi',
          defaultExpression: '2 dBi',
        ),
      ],
      assumptions: ['ERP is 2.15 dB below EIRP.'],
    ),
    CalcFormula(
      id: 'link_budget',
      name: 'Link budget',
      category: CalcFormulaCategories.rf,
      description: 'Received power from transmit power, gains and losses.',
      expression: 'p_tx + g_tx + g_rx - l_path - l_tx - l_rx',
      inputs: [
        CalcFormulaInput(
          name: 'p_tx',
          label: 'Transmit power',
          defaultExpression: '20 dBm',
        ),
        CalcFormulaInput(
          name: 'g_tx',
          label: 'Transmit antenna gain',
          defaultExpression: '2 dBi',
        ),
        CalcFormulaInput(
          name: 'g_rx',
          label: 'Receive antenna gain',
          defaultExpression: '5 dBi',
        ),
        CalcFormulaInput(
          name: 'l_path',
          label: 'Path loss',
          defaultExpression: '100 dB',
        ),
        CalcFormulaInput(
          name: 'l_tx',
          label: 'Transmit losses',
          defaultExpression: '0 dB',
        ),
        CalcFormulaInput(
          name: 'l_rx',
          label: 'Receive losses',
          defaultExpression: '0 dB',
        ),
      ],
    ),
    CalcFormula(
      id: 'friis_received_power',
      name: 'Received power with FSPL',
      category: CalcFormulaCategories.rf,
      description: 'Received power using the Friis equation in dB form.',
      expression: 'p_tx + g_tx + g_rx - fspl(d, f)',
      inputs: [
        CalcFormulaInput(
          name: 'p_tx',
          label: 'Transmit power',
          defaultExpression: '20 dBm',
        ),
        CalcFormulaInput(
          name: 'g_tx',
          label: 'Transmit antenna gain',
          defaultExpression: '2 dBi',
        ),
        CalcFormulaInput(
          name: 'g_rx',
          label: 'Receive antenna gain',
          defaultExpression: '5 dBi',
        ),
        CalcFormulaInput(
          name: 'd',
          label: 'Distance',
          defaultExpression: '1 km',
        ),
        CalcFormulaInput(
          name: 'f',
          label: 'Frequency',
          defaultExpression: '2.4 GHz',
        ),
      ],
      assumptions: ['Free-space path loss model, far field.'],
    ),
    CalcFormula(
      id: 'antenna_aperture',
      name: 'Effective antenna aperture',
      category: CalcFormulaCategories.rf,
      description: 'Effective aperture from antenna gain and wavelength.',
      expression: 'ratio(gain) * lambda^2 / (4*pi)',
      inputs: [
        CalcFormulaInput(
          name: 'gain',
          label: 'Antenna gain',
          defaultExpression: '2 dBi',
        ),
        CalcFormulaInput(
          name: 'lambda',
          label: 'Wavelength',
          defaultExpression: '125 mm',
        ),
      ],
    ),
    CalcFormula(
      id: 'near_field_distance',
      name: 'Antenna near-field boundary',
      category: CalcFormulaCategories.rf,
      description: 'Fraunhofer distance from aperture and wavelength.',
      expression: '2 * d^2 / lambda',
      inputs: [
        CalcFormulaInput(
          name: 'd',
          label: 'Largest antenna dimension',
          defaultExpression: '0.3 m',
        ),
        CalcFormulaInput(
          name: 'lambda',
          label: 'Wavelength',
          defaultExpression: '125 mm',
        ),
      ],
      assumptions: ['Far-field boundary 2D²/λ.'],
    ),
    CalcFormula(
      id: 'vswr',
      name: 'VSWR from reflection coefficient',
      category: CalcFormulaCategories.rf,
      description: 'Voltage standing-wave ratio from |Γ|.',
      expression: 'vswr(gamma)',
      inputs: [
        CalcFormulaInput(
          name: 'gamma',
          label: 'Reflection coefficient',
          defaultExpression: '0.2',
        ),
      ],
    ),
    CalcFormula(
      id: 'reflection_coefficient',
      name: 'Reflection coefficient',
      category: CalcFormulaCategories.rf,
      description: 'Load reflection coefficient from load and line impedance.',
      expression: '(z_load - z0) / (z_load + z0)',
      inputs: [
        CalcFormulaInput(
          name: 'z_load',
          label: 'Load impedance',
          defaultExpression: '75 Ω',
        ),
        CalcFormulaInput(
          name: 'z0',
          label: 'Line impedance',
          defaultExpression: '50 Ω',
        ),
      ],
    ),
    CalcFormula(
      id: 'return_loss',
      name: 'Return loss',
      category: CalcFormulaCategories.rf,
      description: 'Return loss in dB from the reflection coefficient.',
      expression: 'return_loss(gamma)',
      inputs: [
        CalcFormulaInput(
          name: 'gamma',
          label: 'Reflection coefficient',
          defaultExpression: '0.1',
        ),
      ],
    ),
    CalcFormula(
      id: 'mismatch_loss',
      name: 'Mismatch loss',
      category: CalcFormulaCategories.rf,
      description: 'Power lost through an impedance mismatch in dB.',
      expression: 'mismatch_loss(gamma)',
      inputs: [
        CalcFormulaInput(
          name: 'gamma',
          label: 'Reflection coefficient',
          defaultExpression: '0.2',
        ),
      ],
    ),
    CalcFormula(
      id: 'vswr_from_impedance',
      name: 'VSWR from impedances',
      category: CalcFormulaCategories.rf,
      description: 'VSWR for a load on a transmission line.',
      expression: 'vswr((z_load - z0) / (z_load + z0))',
      inputs: [
        CalcFormulaInput(
          name: 'z_load',
          label: 'Load impedance',
          defaultExpression: '75 Ω',
        ),
        CalcFormulaInput(
          name: 'z0',
          label: 'Line impedance',
          defaultExpression: '50 Ω',
        ),
      ],
    ),
    CalcFormula(
      id: 'cable_loss',
      name: 'Cable loss',
      category: CalcFormulaCategories.rf,
      description: 'Total cable loss from loss per metre and length.',
      expression: 'cable_loss(loss_per_m, length)',
      inputs: [
        CalcFormulaInput(
          name: 'loss_per_m',
          label: 'Loss per metre in dB',
          defaultExpression: '0.2',
        ),
        CalcFormulaInput(
          name: 'length',
          label: 'Length in metres',
          defaultExpression: '10',
        ),
      ],
    ),
    CalcFormula(
      id: 'noise_floor',
      name: 'Noise floor',
      category: CalcFormulaCategories.rf,
      description:
          'Thermal noise floor in dBm for a bandwidth and noise figure.',
      expression: 'noise_floor_dbm(bw, nf_db)',
      inputs: [
        CalcFormulaInput(
          name: 'bw',
          label: 'Bandwidth',
          defaultExpression: '1 MHz',
        ),
        CalcFormulaInput(
          name: 'nf_db',
          label: 'Noise figure',
          defaultExpression: '3 dB',
        ),
      ],
      assumptions: ['Reference temperature 290 K.'],
    ),
    CalcFormula(
      id: 'receiver_sensitivity',
      name: 'Receiver sensitivity',
      category: CalcFormulaCategories.rf,
      description: 'Sensitivity from noise figure, bandwidth and required SNR.',
      expression: 'sensitivity_dbm(nf_db, bw, snr_db)',
      inputs: [
        CalcFormulaInput(
          name: 'nf_db',
          label: 'Noise figure',
          defaultExpression: '3 dB',
        ),
        CalcFormulaInput(
          name: 'bw',
          label: 'Bandwidth',
          defaultExpression: '1 MHz',
        ),
        CalcFormulaInput(
          name: 'snr_db',
          label: 'Required SNR',
          defaultExpression: '10 dB',
        ),
      ],
      assumptions: ['Reference temperature 290 K.'],
    ),
    CalcFormula(
      id: 'thermal_noise_power',
      name: 'Thermal noise power',
      category: CalcFormulaCategories.rf,
      description: 'Available thermal noise power in a bandwidth.',
      expression: 'thermal_noise(bw, temperature)',
      inputs: [
        CalcFormulaInput(
          name: 'bw',
          label: 'Bandwidth',
          defaultExpression: '1 MHz',
        ),
        CalcFormulaInput(
          name: 'temperature',
          label: 'Temperature',
          defaultExpression: '290 K',
        ),
      ],
    ),
    CalcFormula(
      id: 'noise_figure_cascade',
      name: 'Cascaded noise figure',
      category: CalcFormulaCategories.rf,
      description: 'Friis cascade of two stages with linear factors and gains.',
      expression: 'nf_cascade([f1, f2], [g1, g2])',
      inputs: [
        CalcFormulaInput(
          name: 'f1',
          label: 'Stage 1 noise factor',
          defaultExpression: '2',
        ),
        CalcFormulaInput(
          name: 'g1',
          label: 'Stage 1 gain',
          defaultExpression: '10',
        ),
        CalcFormulaInput(
          name: 'f2',
          label: 'Stage 2 noise factor',
          defaultExpression: '3',
        ),
        CalcFormulaInput(
          name: 'g2',
          label: 'Stage 2 gain',
          defaultExpression: '20',
        ),
      ],
      assumptions: ['Linear noise factors and power gains, not dB values.'],
    ),
    CalcFormula(
      id: 'dbm_to_vrms',
      name: 'dBm to RMS voltage',
      category: CalcFormulaCategories.rf,
      description: 'RMS voltage of a power level into a load.',
      expression: 'dbm_to_vrms(power, z0)',
      inputs: [
        CalcFormulaInput(
          name: 'power',
          label: 'Power level',
          defaultExpression: '20 dBm',
        ),
        CalcFormulaInput(
          name: 'z0',
          label: 'Load impedance',
          defaultExpression: '50 Ω',
        ),
      ],
    ),
    CalcFormula(
      id: 'vrms_to_dbm',
      name: 'RMS voltage to dBm',
      category: CalcFormulaCategories.rf,
      description: 'Power level of an RMS voltage into a load.',
      expression: 'vrms_to_dbm(voltage, z0)',
      inputs: [
        CalcFormulaInput(
          name: 'voltage',
          label: 'RMS voltage',
          defaultExpression: '1 V',
        ),
        CalcFormulaInput(
          name: 'z0',
          label: 'Load impedance',
          defaultExpression: '50 Ω',
        ),
      ],
    ),

    // =======================================================================
    // Math and Numerical
    // =======================================================================
    CalcFormula(
      id: 'quadratic_roots',
      name: 'Quadratic roots',
      category: CalcFormulaCategories.math,
      description: 'Both roots of a x^2 + b x + c = 0, complex if needed.',
      expression: 'solve_quadratic(a, b, c)',
      inputs: [
        CalcFormulaInput(
          name: 'a',
          label: 'Coefficient a',
          defaultExpression: '1',
        ),
        CalcFormulaInput(
          name: 'b',
          label: 'Coefficient b',
          defaultExpression: '-3',
        ),
        CalcFormulaInput(
          name: 'c',
          label: 'Coefficient c',
          defaultExpression: '2',
        ),
      ],
      assumptions: ['Coefficients are dimensionless.'],
    ),
    CalcFormula(
      id: 'linear_interpolation',
      name: 'Linear interpolation',
      category: CalcFormulaCategories.math,
      description: 'Interpolated y value between two points.',
      expression: 'y1 + (x - x1) * (y2 - y1) / (x2 - x1)',
      inputs: [
        CalcFormulaInput(name: 'x', label: 'x', defaultExpression: '2.5'),
        CalcFormulaInput(name: 'x1', label: 'x1', defaultExpression: '1'),
        CalcFormulaInput(name: 'y1', label: 'y1', defaultExpression: '10'),
        CalcFormulaInput(name: 'x2', label: 'x2', defaultExpression: '3'),
        CalcFormulaInput(name: 'y2', label: 'y2', defaultExpression: '20'),
      ],
    ),
    CalcFormula(
      id: 'percent_change',
      name: 'Percent change',
      category: CalcFormulaCategories.math,
      description: 'Relative change from an old to a new value in percent.',
      expression: 'to((new_value - old_value) / old_value, %)',
      inputs: [
        CalcFormulaInput(
          name: 'old_value',
          label: 'Old value',
          defaultExpression: '10',
        ),
        CalcFormulaInput(
          name: 'new_value',
          label: 'New value',
          defaultExpression: '12',
        ),
      ],
    ),
    CalcFormula(
      id: 'ratio_to_db',
      name: 'Ratio to dB',
      category: CalcFormulaCategories.math,
      description: 'Power ratio expressed in dB.',
      expression: 'db10(ratio)',
      inputs: [
        CalcFormulaInput(
          name: 'ratio',
          label: 'Power ratio',
          defaultExpression: '2',
        ),
      ],
    ),
    CalcFormula(
      id: 'db_to_ratio',
      name: 'dB to power ratio',
      category: CalcFormulaCategories.math,
      description: 'Linear power ratio for a level in dB.',
      expression: '10^(level / 10)',
      inputs: [
        CalcFormulaInput(
          name: 'level',
          label: 'Level in dB',
          defaultExpression: '3',
        ),
      ],
    ),
    CalcFormula(
      id: 'db_to_voltage_ratio',
      name: 'dB to voltage ratio',
      category: CalcFormulaCategories.math,
      description: 'Linear amplitude ratio for a level in dB.',
      expression: '10^(level / 20)',
      inputs: [
        CalcFormulaInput(
          name: 'level',
          label: 'Level in dB',
          defaultExpression: '6',
        ),
      ],
    ),
  ];
}
