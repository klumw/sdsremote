/// Data models and deterministic mapping for extracted specifications.
///
/// The SpecAnalyst sub-agent extracts values from a specification and submits
/// them through a structured tool call. This library validates the submission,
/// normalizes units, builds the Markdown tables and maps applicable values to
/// the `analyze_waveform_faults` specification. The model never performs the
/// unit conversion or the fault-test mapping itself.
library;

import 'dart:math' as math;

import 'waveform_fault_models.dart';

/// Canonical electrical parameter categories understood by the SpecAnalyst.
///
/// The identifiers are stable and are used in the `submit_spec_analysis` tool
/// schema and in the generated prompt catalog.
enum SpecParameter {
  supplyVoltage('supply_voltage', 'Supply voltage', 'V'),
  inputVoltageRange('input_voltage_range', 'Input voltage range', 'V'),
  outputVoltageSwing('output_voltage_swing', 'Output voltage swing', 'V'),
  inputHighVoltage('input_high_voltage', 'Input high voltage (VIH)', 'V'),
  inputLowVoltage('input_low_voltage', 'Input low voltage (VIL)', 'V'),
  outputHighVoltage('output_high_voltage', 'Output high voltage (VOH)', 'V'),
  outputLowVoltage('output_low_voltage', 'Output low voltage (VOL)', 'V'),
  highLevelVoltage(
    'high_level_voltage',
    'Signal high level',
    'V',
    WaveformFaultTest.amplitude,
  ),
  lowLevelVoltage(
    'low_level_voltage',
    'Signal low level',
    'V',
    WaveformFaultTest.amplitude,
  ),
  peakToPeakVoltage(
    'peak_to_peak_voltage',
    'Peak-to-peak voltage (Vpp)',
    'V',
    WaveformFaultTest.amplitude,
  ),
  dcOffset(
    'dc_offset',
    'DC offset / mean voltage',
    'V',
    WaveformFaultTest.dcOffset,
  ),
  baselineVoltage(
    'baseline_voltage',
    'Baseline voltage',
    'V',
    WaveformFaultTest.dcOffset,
  ),
  absoluteMaxVoltage(
    'absolute_max_voltage',
    'Absolute maximum signal voltage',
    'V',
    WaveformFaultTest.clipping,
  ),
  absoluteMinVoltage(
    'absolute_min_voltage',
    'Absolute minimum signal voltage',
    'V',
    WaveformFaultTest.clipping,
  ),
  thresholdVoltage('threshold_voltage', 'Threshold voltage', 'V'),
  hysteresisVoltage('hysteresis_voltage', 'Hysteresis voltage', 'V'),
  referenceVoltage('reference_voltage', 'Reference voltage', 'V'),
  supplyCurrent('supply_current', 'Supply current', 'A'),
  outputCurrent('output_current', 'Output current', 'A'),
  leakageCurrent('leakage_current', 'Input leakage current', 'A'),
  inputCapacitance('input_capacitance', 'Input capacitance', 'F'),
  loadCapacitance('load_capacitance', 'Load capacitance', 'F'),
  outputResistance('output_resistance', 'Output resistance / impedance', 'Ω'),
  pullResistance('pull_resistance', 'Pull resistance', 'Ω'),
  frequency('frequency', 'Frequency', 'Hz', WaveformFaultTest.frequencyError),
  period('period', 'Period', 's'),
  riseTime('rise_time', 'Rise time', 's', WaveformFaultTest.edgeTimes),
  fallTime('fall_time', 'Fall time', 's', WaveformFaultTest.edgeTimes),
  pulseWidth('pulse_width', 'Pulse width', 's'),
  dutyCycle('duty_cycle', 'Duty cycle', '%', WaveformFaultTest.dutyCycle),
  propagationDelay(
    'propagation_delay',
    'Propagation delay',
    's',
    WaveformFaultTest.phaseDelay,
  ),
  setupTime('setup_time', 'Setup time', 's'),
  holdTime('hold_time', 'Hold time', 's'),
  skew('skew', 'Skew', 's'),
  jitterTime('jitter_time', 'Jitter (time)', 's', WaveformFaultTest.jitter),
  jitterPercent('jitter_percent', 'Jitter (%)', '%', WaveformFaultTest.jitter),
  slewRate('slew_rate', 'Slew rate', 'V/s'),
  settlingTime(
    'settling_time',
    'Settling time',
    's',
    WaveformFaultTest.settling,
  ),
  overshoot('overshoot', 'Overshoot', '%', WaveformFaultTest.settling),
  ringingAmplitude(
    'ringing_amplitude',
    'Ringing amplitude',
    'V',
    WaveformFaultTest.ringing,
  ),
  ringingFrequency(
    'ringing_frequency',
    'Ringing frequency',
    'Hz',
    WaveformFaultTest.ringing,
  ),
  noiseRmsVoltage(
    'noise_rms_voltage',
    'Noise (RMS voltage)',
    'V',
    WaveformFaultTest.noise,
  ),
  snr('snr', 'Signal-to-noise ratio', 'dB', WaveformFaultTest.noise),
  thd('thd', 'Total harmonic distortion', '%', WaveformFaultTest.distortion),
  crosstalkDb('crosstalk_db', 'Crosstalk', 'dB', WaveformFaultTest.crosstalk),
  crosstalkPercent(
    'crosstalk_percent',
    'Crosstalk',
    '%',
    WaveformFaultTest.crosstalk,
  ),
  spuriousLevel(
    'spurious_level',
    'Spurious level',
    'dBc',
    WaveformFaultTest.spuriousFrequencies,
  ),
  spuriousAmplitude(
    'spurious_amplitude',
    'Spurious amplitude',
    'V',
    WaveformFaultTest.spuriousFrequencies,
  ),
  amplitudeStability(
    'amplitude_stability',
    'Amplitude stability',
    '%',
    WaveformFaultTest.amplitudeStability,
  ),
  transientAmplitude(
    'transient_amplitude',
    'Transient / spike amplitude',
    'V',
    WaveformFaultTest.transients,
  ),
  transientWidth(
    'transient_width',
    'Transient / spike width',
    's',
    WaveformFaultTest.transients,
  ),
  glitchWidth('glitch_width', 'Glitch width', 's', WaveformFaultTest.glitches);

  const SpecParameter(this.id, this.label, this.unit, [this.faultTest]);

  /// Stable identifier used in tool calls and result maps.
  final String id;

  /// Human-readable name shown in the specification table.
  final String label;

  /// Canonical unit used for the fault-analysis mapping.
  final String unit;

  /// Fault test that consumes values of this parameter, when one exists.
  final WaveformFaultTest? faultTest;

  /// Parses an [id], enum name or label (case-insensitive).
  static SpecParameter? parse(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    for (final parameter in values) {
      if (parameter.id == normalized ||
          parameter.name.toLowerCase() == normalized ||
          parameter.label.toLowerCase() == normalized) {
        return parameter;
      }
    }
    return null;
  }
}

/// One extracted specification row.
///
/// Numeric values stay in the unit printed in the document. The canonical
/// getters convert them to [SpecParameter.unit] without involving the model.
class SpecParameterRow {
  const SpecParameterRow._({
    required this.reference,
    required this.parameter,
    required this.unit,
    this.symbol,
    this.description,
    this.min,
    this.typ,
    this.max,
    this.conditions,
    this.source,
    this.note,
  });

  /// Builds a row from the structured submission of the SpecAnalyst.
  ///
  /// Throws a [FormatException] when the parameter id is missing or unknown.
  factory SpecParameterRow.fromMap(Map<String, dynamic> map) {
    final parameterId = _stringValue(map['parameter']);
    final parameter = SpecParameter.parse(parameterId);
    if (parameter == null) {
      throw FormatException(
        'Unknown parameter id "${parameterId ?? ''}". Use one of: '
        '${SpecParameter.values.map((value) => value.id).join(', ')}.',
      );
    }
    return SpecParameterRow._(
      reference: _stringValue(map['reference']) ?? 'signal',
      parameter: parameter,
      unit: _stringValue(map['unit']) ?? _defaultUnit(parameter),
      symbol: _stringValue(map['symbol']),
      description: _stringValue(map['description']),
      min: _numberValue(map['min']),
      typ: _numberValue(map['typ']),
      max: _numberValue(map['max']),
      conditions: _stringValue(map['conditions']),
      source: _stringValue(map['source']),
      note: _stringValue(map['note']),
    );
  }

  /// Rail, pin or signal the values apply to, for example `VDD` or `SDA`.
  final String reference;

  final SpecParameter parameter;

  /// Unit exactly as printed in the specification.
  final String unit;

  /// Symbol printed in the specification, for example `t_r` or `V_OH`.
  final String? symbol;

  /// Short English description when the symbol is ambiguous.
  final String? description;

  final double? min;
  final double? typ;
  final double? max;

  /// Electrical test conditions that belong to the row.
  final String? conditions;

  /// Page, table or section reference from the document.
  final String? source;

  /// Caveat, formula or rating note.
  final String? note;

  bool get hasValues => min != null || typ != null || max != null;

  double? get minCanonical => _canonicalValue(parameter, min, unit);

  double? get typCanonical => _canonicalValue(parameter, typ, unit);

  double? get maxCanonical => _canonicalValue(parameter, max, unit);

  bool get hasValidUnit => _unitScale(parameter, unit) != null;

  /// Explains why the row cannot be mapped, or returns null when it is valid.
  String? get unitError {
    if (!hasValues) return null;
    if (unit.trim().isEmpty) {
      return 'No unit supplied; expected ${parameter.unit}.';
    }
    if (_unitScale(parameter, unit) == null) {
      return 'Unit "$unit" is not valid for ${parameter.label} '
          '(expected ${parameter.unit}).';
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
    'reference': reference,
    'parameter': parameter.id,
    'label': parameter.label,
    if (symbol != null) 'symbol': symbol,
    if (description != null) 'description': description,
    if (min != null) 'min': min,
    if (typ != null) 'typ': typ,
    if (max != null) 'max': max,
    if (unit.isNotEmpty) 'unit': unit,
    if (conditions != null) 'conditions': conditions,
    if (source != null) 'source': source,
    if (note != null) 'note': note,
    if (unitError != null) 'unitError': unitError,
  };
}

/// One field of the generated fault-analysis specification.
class SpecMappingEntry {
  const SpecMappingEntry({
    required this.testId,
    required this.field,
    required this.value,
    required this.unit,
    required this.basis,
  });

  /// Stable fault-test id, for example `edge_times`.
  final String testId;

  /// Field inside the fault-test specification, for example
  /// `maxRiseTimeSeconds`.
  final String field;

  /// Value in [unit], ready for `analyze_waveform_faults`.
  final double value;

  final String unit;

  /// Human-readable explanation of how the value was derived.
  final String basis;
}

/// Result of the deterministic fault-test mapping for one reference.
class FaultSpecificationMapping {
  const FaultSpecificationMapping({
    required this.specification,
    required this.entries,
    required this.warnings,
  });

  /// Specification map in the format expected by `analyze_waveform_faults`.
  final Map<String, dynamic> specification;

  final List<SpecMappingEntry> entries;

  final List<String> warnings;
}

/// Maps extracted rows of one reference to the fault-analysis specification.
///
/// Only values whose fault test has a matching field are mapped. Everything
/// else stays in the parameter table as information for the Waveform Agent.
FaultSpecificationMapping buildFaultSpecification(List<SpecParameterRow> rows) {
  final specification = <String, Map<String, dynamic>>{};
  final entries = <SpecMappingEntry>[];
  final warnings = <String>[];

  void setValue({
    required String testId,
    required String field,
    required double? value,
    required String unit,
    required String basis,
  }) {
    if (value == null || !value.isFinite) return;
    final block = specification.putIfAbsent(testId, () => <String, dynamic>{});
    final existing = block[field];
    if (existing is num) {
      if (existing.toDouble() != value) {
        warnings.add(
          'Conflicting values for $testId.$field: '
          '${_formatNumber(existing.toDouble())} and '
          '${_formatNumber(value)}; the first value was kept.',
        );
      }
      return;
    }
    block[field] = value;
    entries.add(
      SpecMappingEntry(
        testId: testId,
        field: field,
        value: value,
        unit: unit,
        basis: basis,
      ),
    );
  }

  void setRangeWithTolerance({
    required String testId,
    required String expectedField,
    required String toleranceField,
    required SpecParameterRow row,
    required String unit,
    required String basis,
  }) {
    final min = row.minCanonical;
    final typ = row.typCanonical;
    final max = row.maxCanonical;
    if (typ != null && (min != null || max != null)) {
      final deviations = <double>[
        if (min != null) (typ - min).abs(),
        if (max != null) (max - typ).abs(),
      ];
      setValue(
        testId: testId,
        field: expectedField,
        value: typ,
        unit: unit,
        basis: '$basis: typical value',
      );
      setValue(
        testId: testId,
        field: toleranceField,
        value: deviations.reduce(math.max),
        unit: unit,
        basis: '$basis: maximum deviation from typical',
      );
      return;
    }
    if (min != null && max != null) {
      setValue(
        testId: testId,
        field: expectedField,
        value: (min + max) / 2,
        unit: unit,
        basis: '$basis: range midpoint',
      );
      setValue(
        testId: testId,
        field: toleranceField,
        value: (max - min) / 2,
        unit: unit,
        basis: '$basis: half of the specified range',
      );
    }
  }

  for (final row in rows) {
    switch (row.parameter) {
      case SpecParameter.peakToPeakVoltage:
        setValue(
          testId: 'amplitude',
          field: 'minVppVolts',
          value: row.minCanonical,
          unit: 'V',
          basis: 'specified minimum Vpp',
        );
        setValue(
          testId: 'amplitude',
          field: 'maxVppVolts',
          value: row.maxCanonical,
          unit: 'V',
          basis: 'specified maximum Vpp',
        );
      case SpecParameter.highLevelVoltage:
        setRangeWithTolerance(
          testId: 'amplitude',
          expectedField: 'expectedVmaxVolts',
          toleranceField: 'toleranceVolts',
          row: row,
          unit: 'V',
          basis: 'signal high level',
        );
      case SpecParameter.lowLevelVoltage:
        setRangeWithTolerance(
          testId: 'amplitude',
          expectedField: 'expectedVminVolts',
          toleranceField: 'toleranceVolts',
          row: row,
          unit: 'V',
          basis: 'signal low level',
        );
      case SpecParameter.dcOffset:
        setRangeWithTolerance(
          testId: 'dc_offset',
          expectedField: 'expectedMeanVolts',
          toleranceField: 'toleranceVolts',
          row: row,
          unit: 'V',
          basis: 'DC offset / mean voltage',
        );
      case SpecParameter.baselineVoltage:
        setRangeWithTolerance(
          testId: 'dc_offset',
          expectedField: 'expectedBaselineVolts',
          toleranceField: 'toleranceVolts',
          row: row,
          unit: 'V',
          basis: 'baseline voltage',
        );
      case SpecParameter.absoluteMaxVoltage:
        setValue(
          testId: 'clipping',
          field: 'allowedMaxVolts',
          value: row.maxCanonical,
          unit: 'V',
          basis: 'absolute maximum signal voltage',
        );
      case SpecParameter.absoluteMinVoltage:
        setValue(
          testId: 'clipping',
          field: 'allowedMinVolts',
          value: row.minCanonical,
          unit: 'V',
          basis: 'absolute minimum signal voltage',
        );
      case SpecParameter.frequency:
        setRangeWithTolerance(
          testId: 'frequency_error',
          expectedField: 'expectedFrequencyHz',
          toleranceField: 'toleranceHz',
          row: row,
          unit: 'Hz',
          basis: 'frequency',
        );
      case SpecParameter.riseTime:
        setValue(
          testId: 'edge_times',
          field: 'maxRiseTimeSeconds',
          value: row.maxCanonical,
          unit: 's',
          basis: 'maximum rise time',
        );
      case SpecParameter.fallTime:
        setValue(
          testId: 'edge_times',
          field: 'maxFallTimeSeconds',
          value: row.maxCanonical,
          unit: 's',
          basis: 'maximum fall time',
        );
      case SpecParameter.dutyCycle:
        setRangeWithTolerance(
          testId: 'duty_cycle',
          expectedField: 'expectedDutyPercent',
          toleranceField: 'tolerancePercent',
          row: row,
          unit: '%',
          basis: 'duty cycle',
        );
      case SpecParameter.propagationDelay:
        setRangeWithTolerance(
          testId: 'phase_delay',
          expectedField: 'expectedDelaySeconds',
          toleranceField: 'toleranceDelaySeconds',
          row: row,
          unit: 's',
          basis: 'propagation delay',
        );
      case SpecParameter.jitterTime:
        setValue(
          testId: 'jitter',
          field: 'maxJitterSeconds',
          value: row.maxCanonical,
          unit: 's',
          basis: 'maximum jitter',
        );
      case SpecParameter.jitterPercent:
        setValue(
          testId: 'jitter',
          field: 'maxJitterPercent',
          value: row.maxCanonical,
          unit: '%',
          basis: 'maximum jitter',
        );
      case SpecParameter.settlingTime:
        setValue(
          testId: 'settling',
          field: 'maxSettlingTimeSeconds',
          value: row.maxCanonical,
          unit: 's',
          basis: 'maximum settling time',
        );
      case SpecParameter.overshoot:
        setValue(
          testId: 'settling',
          field: 'maxOvershootPercent',
          value: row.maxCanonical,
          unit: '%',
          basis: 'maximum overshoot',
        );
      case SpecParameter.ringingAmplitude:
        setValue(
          testId: 'ringing',
          field: 'ringingThresholdVolts',
          value: row.maxCanonical,
          unit: 'V',
          basis: 'maximum allowed ringing amplitude',
        );
      case SpecParameter.ringingFrequency:
        setValue(
          testId: 'ringing',
          field: 'minRingingFrequencyHz',
          value: row.minCanonical,
          unit: 'Hz',
          basis: 'minimum ringing frequency',
        );
        setValue(
          testId: 'ringing',
          field: 'maxRingingFrequencyHz',
          value: row.maxCanonical,
          unit: 'Hz',
          basis: 'maximum ringing frequency',
        );
      case SpecParameter.noiseRmsVoltage:
        setValue(
          testId: 'noise',
          field: 'maxNoiseRmsVolts',
          value: row.maxCanonical,
          unit: 'V',
          basis: 'maximum noise RMS voltage',
        );
      case SpecParameter.snr:
        setValue(
          testId: 'noise',
          field: 'minSnrDb',
          value: row.minCanonical,
          unit: 'dB',
          basis: 'minimum SNR',
        );
      case SpecParameter.thd:
        setValue(
          testId: 'distortion',
          field: 'maxThdPercent',
          value: row.maxCanonical,
          unit: '%',
          basis: 'maximum THD',
        );
      case SpecParameter.crosstalkDb:
        setValue(
          testId: 'crosstalk',
          field: 'maxCrosstalkDb',
          value: row.maxCanonical,
          unit: 'dB',
          basis: 'maximum crosstalk',
        );
      case SpecParameter.crosstalkPercent:
        setValue(
          testId: 'crosstalk',
          field: 'maxCrosstalkPercent',
          value: row.maxCanonical,
          unit: '%',
          basis: 'maximum crosstalk',
        );
      case SpecParameter.spuriousLevel:
        setValue(
          testId: 'spurious_frequencies',
          field: 'minSpuriousLevelDbc',
          value: row.maxCanonical,
          unit: 'dBc',
          basis: 'spurious level limit',
        );
      case SpecParameter.spuriousAmplitude:
        setValue(
          testId: 'spurious_frequencies',
          field: 'minSpuriousAmplitudeVolts',
          value: row.maxCanonical,
          unit: 'V',
          basis: 'spurious amplitude limit',
        );
      case SpecParameter.amplitudeStability:
        setValue(
          testId: 'amplitude_stability',
          field: 'maxAmplitudeVariationPercent',
          value: row.maxCanonical,
          unit: '%',
          basis: 'maximum amplitude variation',
        );
      case SpecParameter.transientAmplitude:
        setValue(
          testId: 'transients',
          field: 'spikeThresholdVolts',
          value: row.maxCanonical,
          unit: 'V',
          basis: 'maximum transient amplitude',
        );
      case SpecParameter.transientWidth:
        setValue(
          testId: 'transients',
          field: 'maxSpikeDurationSeconds',
          value: row.maxCanonical,
          unit: 's',
          basis: 'maximum transient width',
        );
      case SpecParameter.glitchWidth:
        setValue(
          testId: 'glitches',
          field: 'minPulseWidthSeconds',
          value: row.maxCanonical,
          unit: 's',
          basis: 'minimum valid pulse width',
        );
      case SpecParameter.supplyVoltage:
      case SpecParameter.inputVoltageRange:
      case SpecParameter.outputVoltageSwing:
      case SpecParameter.inputHighVoltage:
      case SpecParameter.inputLowVoltage:
      case SpecParameter.outputHighVoltage:
      case SpecParameter.outputLowVoltage:
      case SpecParameter.thresholdVoltage:
      case SpecParameter.hysteresisVoltage:
      case SpecParameter.referenceVoltage:
      case SpecParameter.supplyCurrent:
      case SpecParameter.outputCurrent:
      case SpecParameter.leakageCurrent:
      case SpecParameter.inputCapacitance:
      case SpecParameter.loadCapacitance:
      case SpecParameter.outputResistance:
      case SpecParameter.pullResistance:
      case SpecParameter.period:
      case SpecParameter.pulseWidth:
      case SpecParameter.setupTime:
      case SpecParameter.holdTime:
      case SpecParameter.skew:
      case SpecParameter.slewRate:
        break;
    }
  }

  final cleaned = <String, dynamic>{
    for (final entry in specification.entries)
      if (entry.value.isNotEmpty) entry.key: entry.value,
  };
  return FaultSpecificationMapping(
    specification: cleaned,
    entries: entries,
    warnings: warnings,
  );
}

/// Validated result of one SpecAnalyst submission.
class SpecAnalysis {
  SpecAnalysis._({
    required this.rows,
    required this.summary,
    required this.warnings,
  });

  /// Builds the analysis from the raw `submit_spec_analysis` arguments.
  ///
  /// Invalid rows are skipped with a warning so a single malformed entry does
  /// not discard the complete extraction.
  factory SpecAnalysis.fromSubmission(Map<String, dynamic> submission) {
    final rows = <SpecParameterRow>[];
    final warnings = <String>[];
    final rawParameters = submission['parameters'];
    if (rawParameters is List) {
      for (final raw in rawParameters) {
        if (raw is! Map) {
          warnings.add('Ignored a parameter entry that is not an object.');
          continue;
        }
        try {
          final row = SpecParameterRow.fromMap(Map<String, dynamic>.from(raw));
          rows.add(row);
          final unitError = row.unitError;
          if (unitError != null) {
            warnings.add('${row.reference} ${row.parameter.id}: $unitError');
          }
          final min = row.minCanonical;
          final max = row.maxCanonical;
          if (min != null && max != null && min > max) {
            warnings.add(
              '${row.reference} ${row.parameter.id}: minimum '
              '${_formatNumber(min)} ${row.parameter.unit} is greater than '
              'maximum ${_formatNumber(max)} ${row.parameter.unit}.',
            );
          }
        } on FormatException catch (error) {
          warnings.add('Ignored an invalid parameter entry: ${error.message}');
        }
      }
    } else {
      warnings.add('The submission does not contain a parameter list.');
    }

    if (rows.length > maxParameterRows) {
      warnings.add(
        'The submission contained ${rows.length} parameters; only the first '
        '$maxParameterRows were kept.',
      );
      rows.removeRange(maxParameterRows, rows.length);
    }
    if (rows.isEmpty) {
      warnings.add('No electrical parameters were extracted.');
    }

    final duplicateKeys = <String>{};
    for (final row in rows) {
      final key = '${row.reference.toLowerCase()}\u0000${row.parameter.id}';
      if (!duplicateKeys.add(key)) {
        warnings.add(
          'Duplicate entry for ${row.reference} ${row.parameter.id}; the '
          'values are mapped in order and conflicts are reported.',
        );
      }
    }

    final rawWarnings = submission['warnings'];
    if (rawWarnings is List) {
      for (final warning in rawWarnings) {
        final text = warning?.toString().trim();
        if (text != null && text.isNotEmpty) warnings.add(text);
      }
    }

    return SpecAnalysis._(
      rows: rows,
      summary: _stringValue(submission['summary']),
      warnings: warnings,
    );
  }

  /// Safety limit against runaway submissions.
  static const int maxParameterRows = 500;

  final List<SpecParameterRow> rows;
  final String? summary;
  final List<String> warnings;

  /// Builds the tool result consumed by the Waveform Agent.
  ///
  /// [requestedReference] selects the rail, pin or signal whose specification
  /// is placed in the top-level `specification`. Without a selection, the tool
  /// selects the only reference automatically; with several references it
  /// returns the per-reference entries in `groups` and a warning.
  Map<String, dynamic> toToolResult({String? requestedReference}) {
    final grouped = <String, List<SpecParameterRow>>{};
    final displayNames = <String, String>{};
    for (final row in rows) {
      final key = row.reference.trim().toLowerCase();
      final display = displayNames.putIfAbsent(key, () => row.reference.trim());
      grouped.putIfAbsent(display, () => <SpecParameterRow>[]).add(row);
    }

    final resultWarnings = [...warnings];
    String? selected;
    final requested = requestedReference?.trim();
    if (requested != null && requested.isNotEmpty) {
      selected = displayNames[requested.toLowerCase()];
      if (selected == null) {
        resultWarnings.add(
          'Reference "$requested" was not found. Available references: '
          '${grouped.keys.join(', ')}.',
        );
      }
    } else if (grouped.length == 1) {
      selected = grouped.keys.first;
    } else if (grouped.length > 1) {
      resultWarnings.add(
        'The specification contains multiple references '
        '(${grouped.keys.join(', ')}). Pass one in `reference` to build a '
        'fault-analysis specification, or use the per-reference entries in '
        '`groups`.',
      );
    }

    final mappings = <String, FaultSpecificationMapping>{
      for (final entry in grouped.entries)
        entry.key: buildFaultSpecification(entry.value),
    };
    final selectedMapping = selected == null ? null : mappings[selected];
    if (selectedMapping != null && selectedMapping.entries.isEmpty) {
      resultWarnings.add(
        'No parameter of reference "$selected" could be mapped to the '
        'fault-analysis specification. Use the parameter table for the '
        'available values.',
      );
    }
    for (final warning in selectedMapping?.warnings ?? const <String>[]) {
      resultWarnings.add(warning);
    }

    final references = grouped.keys.toList();
    final summaryText =
        summary ??
        'Extracted ${rows.length} electrical parameter(s) across '
            '${references.length} reference(s).';

    return <String, dynamic>{
      'ok': true,
      'summary': summaryText,
      'parameterCount': rows.length,
      'references': references,
      if (selected != null) 'reference': selected,
      'table': buildParameterTable(rows),
      if (selectedMapping != null)
        'mappingTable': buildMappingTable(selectedMapping),
      'specification': selectedMapping?.specification ?? <String, dynamic>{},
      'mappedFieldCount': selectedMapping?.entries.length ?? 0,
      'groups': [
        for (final entry in grouped.entries)
          {
            'reference': entry.key,
            'parameterCount': entry.value.length,
            'specification': mappings[entry.key]!.specification,
            'mappedFieldCount': mappings[entry.key]!.entries.length,
          },
      ],
      'parameters': [for (final row in rows) row.toMap()],
      if (resultWarnings.isNotEmpty) 'warnings': resultWarnings,
    };
  }
}

/// Builds the Markdown table of all extracted parameters.
String buildParameterTable(List<SpecParameterRow> rows) {
  if (rows.isEmpty) return 'No electrical parameters were extracted.';

  final buffer = StringBuffer()
    ..writeln(
      '| Reference | Parameter | Symbol | Min | Typ | Max | Unit | '
      'Fault test | Conditions | Source |',
    )
    ..writeln('|:---|:---|:---|:---|:---|:---|:---|:---|:---|:---|');
  for (final row in rows) {
    buffer.writeln(
      '| ${_cell(row.reference)} '
      '| ${_cell(row.parameter.label)} '
      '| ${_cell(row.symbol)} '
      '| ${_cell(_number(row.min))} '
      '| ${_cell(_number(row.typ))} '
      '| ${_cell(_number(row.max))} '
      '| ${_cell(row.unit.isEmpty ? null : row.unit)} '
      '| ${_cell(row.parameter.faultTest?.id)} '
      '| ${_cell(row.conditions)} '
      '| ${_cell(row.source)} |',
    );
  }

  final rowsWithNotes = [
    for (final row in rows)
      if (row.note != null || row.unitError != null) row,
  ];
  if (rowsWithNotes.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Notes:');
    for (final row in rowsWithNotes) {
      final notes = <String>[
        if (row.note != null) row.note!,
        if (row.unitError != null) row.unitError!,
      ];
      buffer.writeln(
        '- ${row.reference} ${row.parameter.label}: ${notes.join(' ')}',
      );
    }
  }
  return buffer.toString().trimRight();
}

/// Builds the Markdown table of the generated fault-analysis fields.
String buildMappingTable(FaultSpecificationMapping mapping) {
  if (mapping.entries.isEmpty) {
    return 'No extracted parameter could be mapped to a fault-analysis field.';
  }
  final buffer = StringBuffer()
    ..writeln('| Fault test | Field | Value | Unit | Basis |')
    ..writeln('|:---|:---|---:|:---|:---|');
  for (final entry in mapping.entries) {
    buffer.writeln(
      '| ${_cell(entry.testId)} '
      '| ${_cell(entry.field)} '
      '| ${_cell(_formatNumber(entry.value))} '
      '| ${_cell(entry.unit)} '
      '| ${_cell(entry.basis)} |',
    );
  }
  return buffer.toString().trimRight();
}

String _cell(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return '—';
  return text.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

String? _number(double? value) => value == null ? null : _formatNumber(value);

String _formatNumber(double value) {
  if (!value.isFinite) return '—';
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toStringAsFixed(0);
  }
  final magnitude = value.abs();
  if (magnitude != 0 && (magnitude >= 1e6 || magnitude < 1e-4)) {
    return value
        .toStringAsExponential(4)
        .replaceFirst(RegExp(r'0+e'), 'e')
        .replaceFirst(RegExp(r'\.e'), 'e');
  }
  return value
      .toStringAsFixed(6)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String? _stringValue(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double? _numberValue(Object? value) {
  if (value is num) {
    final result = value.toDouble();
    return result.isFinite ? result : null;
  }
  if (value is String) {
    final result = double.tryParse(value.trim().replaceAll(',', '.'));
    return result != null && result.isFinite ? result : null;
  }
  return null;
}

String _defaultUnit(SpecParameter parameter) {
  if (parameter.unit == '%' ||
      parameter.unit == 'dB' ||
      parameter.unit == 'dBc') {
    return parameter.unit;
  }
  return '';
}

double? _canonicalValue(SpecParameter parameter, double? value, String unit) {
  if (value == null) return null;
  final scale = _unitScale(parameter, unit);
  return scale == null ? null : value * scale;
}

double? _unitScale(SpecParameter parameter, String unit) {
  final normalized = _normalizeUnit(unit);
  if (normalized.isEmpty) return null;
  return _unitScales[parameter.unit]?[normalized];
}

String _normalizeUnit(String unit) {
  return unit.trim().replaceAll('μ', 'µ').replaceAll(' ', '');
}

const Map<String, Map<String, double>> _unitScales = {
  'V': {'V': 1, 'mV': 1e-3, 'µV': 1e-6, 'uV': 1e-6, 'kV': 1e3},
  'A': {'A': 1, 'mA': 1e-3, 'µA': 1e-6, 'uA': 1e-6, 'nA': 1e-9, 'pA': 1e-12},
  's': {
    's': 1,
    'ms': 1e-3,
    'µs': 1e-6,
    'us': 1e-6,
    'ns': 1e-9,
    'ps': 1e-12,
    'fs': 1e-15,
  },
  'Hz': {'Hz': 1, 'kHz': 1e3, 'MHz': 1e6, 'GHz': 1e9},
  'F': {'F': 1, 'mF': 1e-3, 'µF': 1e-6, 'uF': 1e-6, 'nF': 1e-9, 'pF': 1e-12},
  'Ω': {
    'Ω': 1,
    'ohm': 1,
    'ohms': 1,
    'mΩ': 1e-3,
    'mohm': 1e-3,
    'kΩ': 1e3,
    'kohm': 1e3,
    'MΩ': 1e6,
    'Mohm': 1e6,
  },
  '%': {'%': 1, 'percent': 1, 'pct': 1},
  'dB': {'dB': 1, 'dBc': 1},
  'dBc': {'dBc': 1, 'dB': 1},
  'V/s': {'V/s': 1, 'V/ms': 1e3, 'V/µs': 1e6, 'V/us': 1e6, 'V/ns': 1e9},
};
