/// Equipment facts gathered before planning.
library;

import 'dart:math' as math;

/// Detected signal-generator family.
enum GeneratorFamily {
  jds6600,
  fy6900;

  /// Wire value used in report details.
  String get wireName => name;
}

/// Reachability and cached readings of the oscilloscope.
class ScopeEquipment {
  const ScopeEquipment({
    required this.reachable,
    this.host,
    this.error,
    this.readableValues = const <String, Object?>{},
  });

  /// Whether an oscilloscope host is configured.
  final bool reachable;

  /// Configured VXI-11 host, if any.
  final String? host;

  /// English reason when the scope is not reachable.
  final String? error;

  /// Cached values read without measuring, for example the waveform summary.
  final Map<String, Object?> readableValues;

  Map<String, Object?> toJson() => <String, Object?>{
    'reachable': reachable,
    if (host != null) 'host': host,
    if (error != null) 'error': error,
  };
}

/// One amplitude limit band of the generator.
class AmplitudeBand {
  const AmplitudeBand({this.maxFrequencyHz, required this.maxAmplitudeVpp});

  /// Upper frequency of the band, inclusive. `null` means unlimited.
  final double? maxFrequencyHz;

  /// Maximum amplitude in Vpp inside the band.
  final double maxAmplitudeVpp;

  Map<String, Object?> toJson() => <String, Object?>{
    if (maxFrequencyHz != null) 'maxFrequencyHz': maxFrequencyHz,
    'maxAmplitudeVpp': maxAmplitudeVpp,
  };
}

/// Typed limits of the connected signal generator.
class GeneratorLimits {
  const GeneratorLimits({
    required this.minFrequencyHz,
    required this.maxFrequencyHzByWaveform,
    this.minOffsetV,
    this.maxOffsetV,
    this.minDutyPercent,
    this.maxDutyPercent,
    this.minPhaseDeg,
    this.maxPhaseDeg,
    this.amplitudeBands,
  });

  /// Lowest supported frequency in hertz.
  final double minFrequencyHz;

  /// Highest supported frequency per waveform mnemonic.
  final Map<String, double> maxFrequencyHzByWaveform;

  /// Lowest supported offset in volts.
  final double? minOffsetV;

  /// Highest supported offset in volts.
  final double? maxOffsetV;

  /// Lowest supported duty cycle in percent.
  final double? minDutyPercent;

  /// Highest supported duty cycle in percent.
  final double? maxDutyPercent;

  /// Lowest supported phase in degrees.
  final double? minPhaseDeg;

  /// Highest supported phase in degrees.
  final double? maxPhaseDeg;

  /// Amplitude limits by frequency band, when the device reports them.
  final List<AmplitudeBand>? amplitudeBands;

  /// Highest frequency for [waveform].
  ///
  /// An unknown waveform falls back to the most conservative (lowest) limit.
  double? maxFrequencyHz(String? waveform) {
    if (maxFrequencyHzByWaveform.isEmpty) return null;
    if (waveform != null) {
      final key = waveform.trim().toLowerCase();
      for (final entry in maxFrequencyHzByWaveform.entries) {
        if (entry.key.toLowerCase() == key) return entry.value;
      }
    }
    return maxFrequencyHzByWaveform.values.reduce(math.min);
  }

  /// Highest amplitude in Vpp at [frequencyHz].
  double? maxAmplitudeVpp(double frequencyHz) {
    final bands = amplitudeBands;
    if (bands == null || bands.isEmpty) return null;
    for (final band in bands) {
      final max = band.maxFrequencyHz;
      if (max == null || frequencyHz <= max) return band.maxAmplitudeVpp;
    }
    return bands.last.maxAmplitudeVpp;
  }

  /// Parses the `limits` map returned by the signal-generator status provider.
  ///
  /// Returns `null` when the frequency limits are missing so the plan builder
  /// can add a limitation instead of silently skipping the check.
  static GeneratorLimits? fromStatus(Object? raw) {
    if (raw is! Map) return null;
    final minFrequency = _double(raw['min_frequency_hz']);
    final maxByWaveform = raw['max_frequency_hz_by_waveform'];
    if (minFrequency == null || maxByWaveform is! Map) return null;
    final frequencies = <String, double>{};
    for (final entry in maxByWaveform.entries) {
      final key = entry.key;
      final value = _double(entry.value);
      if (key is String && value != null) frequencies[key] = value;
    }
    if (frequencies.isEmpty) return null;

    final bandsRaw = raw['amplitude_vpp_by_frequency_band'];
    List<AmplitudeBand>? bands;
    if (bandsRaw is List) {
      final parsed = <AmplitudeBand>[];
      for (final entry in bandsRaw) {
        if (entry is! Map) continue;
        final amplitude = _double(entry['max_amplitude_vpp']);
        if (amplitude == null) continue;
        parsed.add(
          AmplitudeBand(
            maxFrequencyHz: _double(entry['max_frequency_hz']),
            maxAmplitudeVpp: amplitude,
          ),
        );
      }
      if (parsed.isNotEmpty) bands = List<AmplitudeBand>.unmodifiable(parsed);
    }

    return GeneratorLimits(
      minFrequencyHz: minFrequency,
      maxFrequencyHzByWaveform: Map<String, double>.unmodifiable(frequencies),
      minOffsetV: _double(raw['min_offset_v']),
      maxOffsetV: _double(raw['max_offset_v']),
      minDutyPercent: _double(raw['min_duty_percent']),
      maxDutyPercent: _double(raw['max_duty_percent']),
      minPhaseDeg: _double(raw['min_phase_deg']),
      maxPhaseDeg: _double(raw['max_phase_deg']),
      amplitudeBands: bands,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'minFrequencyHz': minFrequencyHz,
    'maxFrequencyHzByWaveform': maxFrequencyHzByWaveform,
    if (minOffsetV != null) 'minOffsetV': minOffsetV,
    if (maxOffsetV != null) 'maxOffsetV': maxOffsetV,
    if (minDutyPercent != null) 'minDutyPercent': minDutyPercent,
    if (maxDutyPercent != null) 'maxDutyPercent': maxDutyPercent,
    if (minPhaseDeg != null) 'minPhaseDeg': minPhaseDeg,
    if (maxPhaseDeg != null) 'maxPhaseDeg': maxPhaseDeg,
    if (amplitudeBands != null)
      'amplitudeBands': [for (final band in amplitudeBands!) band.toJson()],
  };

  static double? _double(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    return null;
  }
}

/// Reachability and settings of the signal generator.
class GeneratorEquipment {
  const GeneratorEquipment({
    required this.configured,
    required this.connected,
    this.supported = true,
    this.detected = false,
    this.device,
    this.port,
    this.model,
    this.identity,
    this.family,
    this.channelCount = 2,
    this.limits,
    this.readableValues = const <String, Object?>{},
    this.error,
    this.raw = const <String, Object?>{},
  });

  /// Whether a generator device is selected in the settings.
  final bool configured;

  /// Whether the generator is connected.
  final bool connected;

  /// Whether the configured device is supported.
  final bool supported;

  /// Whether the device was detected on a serial port.
  final bool detected;

  /// Configured device id, for example `jds6600`.
  final String? device;

  /// Serial port of the connection.
  final String? port;

  /// Reported model name.
  final String? model;

  /// Reported SCPI identity.
  final String? identity;

  /// Detected device family.
  final GeneratorFamily? family;

  /// Number of generator channels.
  final int channelCount;

  /// Device limits, when reported.
  final GeneratorLimits? limits;

  /// Current channel settings and output states.
  final Map<String, Object?> readableValues;

  /// English reason when the generator is unavailable.
  final String? error;

  /// Raw status map, for details and logging.
  final Map<String, Object?> raw;

  /// Whether a recipe that needs the generator can run.
  bool get available => configured && connected && supported;

  /// Parses the status map of the signal-generator provider.
  factory GeneratorEquipment.fromStatus(Map<String, dynamic> status) {
    final device = status['configured_device'];
    final configuredDevice = device is String ? device : null;
    final configured =
        configuredDevice != null &&
        configuredDevice.isNotEmpty &&
        configuredDevice != 'none';
    final supported = status['supported'] is bool
        ? status['supported']! as bool
        : true;
    final connected = status['connected'] == true;
    final familyRaw = status['family'];
    final family = switch (familyRaw is String ? familyRaw.toLowerCase() : '') {
      'jds6600' => GeneratorFamily.jds6600,
      'fy6900' => GeneratorFamily.fy6900,
      _ => null,
    };
    final channels = status['channels'];
    final channelCount = channels is Map && channels.isNotEmpty
        ? channels.length
        : 2;
    return GeneratorEquipment(
      configured: configured,
      connected: connected,
      supported: supported,
      detected: status['detected'] == true,
      device: configuredDevice,
      port: _string(status['port']),
      model: _string(status['model']),
      identity: _string(status['identity']),
      family: family,
      channelCount: channelCount,
      limits: GeneratorLimits.fromStatus(status['limits']),
      readableValues: <String, Object?>{
        if (status['channels'] is Map) 'channels': status['channels'],
        if (status['outputs'] is Map) 'outputs': status['outputs'],
      },
      error: _string(status['error']),
      raw: Map<String, Object?>.from(status),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'configured': configured,
    'connected': connected,
    'supported': supported,
    'detected': detected,
    if (device != null) 'device': device,
    if (port != null) 'port': port,
    if (model != null) 'model': model,
    if (identity != null) 'identity': identity,
    if (family != null) 'family': family!.wireName,
    'channelCount': channelCount,
    if (limits != null) 'limits': limits!.toJson(),
    if (error != null) 'error': error,
  };

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }
}

/// Equipment report produced by stage 2.
class EquipmentReport {
  const EquipmentReport({
    required this.scope,
    this.generator,
    required this.generatorProbed,
  });

  /// Scope reachability.
  final ScopeEquipment scope;

  /// Generator facts, when a selected recipe needed the generator.
  final GeneratorEquipment? generator;

  /// Whether the generator probe was actually called.
  final bool generatorProbed;

  Map<String, Object?> toJson() => <String, Object?>{
    'scope': scope.toJson(),
    'generatorProbed': generatorProbed,
    if (generator != null) 'generator': generator!.toJson(),
  };
}
