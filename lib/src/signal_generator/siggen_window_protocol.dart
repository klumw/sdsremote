/// Wire protocol shared by the main-window host and the signal-generator
/// window client.
///
/// This library is deliberately free of Flutter and plugin imports so it can
/// be unit-tested and used in both Flutter engines.
library;

import 'dart:convert';

import 'models.dart';

/// Unidirectional method channel handled by the main window.
const String sigGenControlChannel = 'sdsremote/siggen/control';

/// Value of the `type` field that identifies the signal-generator window.
const String sigGenWindowType = 'siggen-panel';

/// Method names understood by [SigGenWindowHost].
class SigGenWindowMethods {
  const SigGenWindowMethods._();

  static const String getSnapshot = 'getSnapshot';
  static const String refreshGenerator = 'refreshGenerator';
  static const String setWaveform = 'setWaveform';
  static const String setFrequency = 'setFrequency';
  static const String setAmplitude = 'setAmplitude';
  static const String setOffset = 'setOffset';
  static const String setDuty = 'setDuty';
  static const String setPhase = 'setPhase';
  static const String setOutput = 'setOutput';
}

/// Arguments passed to `WindowController.create` for the child window.
class SigGenWindowArguments {
  const SigGenWindowArguments._();

  /// JSON string used as the window argument.
  static String toArguments() => jsonEncode({'type': sigGenWindowType});

  /// Returns true when [raw] contains the signal-generator window marker.
  static bool isSigGenWindow(String raw) {
    if (raw.trim().isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map && decoded['type'] == sigGenWindowType;
    } on FormatException {
      return false;
    }
  }
}

/// Confirmed state of one generator channel.
class SigGenChannelSnapshot {
  const SigGenChannelSnapshot({
    required this.waveform,
    required this.frequencyHz,
    required this.amplitudeVpp,
    required this.offsetV,
    required this.dutyPercent,
  });

  /// Conservative defaults matching `Jds6600ChannelState`.
  const SigGenChannelSnapshot.defaults()
    : waveform = Jds6600Waveform.sine,
      frequencyHz = 1000.0,
      amplitudeVpp = 1.0,
      offsetV = 0.0,
      dutyPercent = 50.0;

  factory SigGenChannelSnapshot.fromChannelState(Jds6600ChannelState state) {
    return SigGenChannelSnapshot(
      waveform: state.waveform,
      frequencyHz: state.frequencyHz,
      amplitudeVpp: state.amplitudeVpp,
      offsetV: state.offsetV,
      dutyPercent: state.dutyPercent,
    );
  }

  factory SigGenChannelSnapshot.fromJson(Map<String, dynamic> json) {
    final name = json['waveform'] as String?;
    final waveform = name == null
        ? Jds6600Waveform.sine
        : Jds6600Waveform.values.firstWhere(
            (value) => value.name == name,
            orElse: () => Jds6600Waveform.sine,
          );
    return SigGenChannelSnapshot(
      waveform: waveform,
      frequencyHz: _asDouble(json['frequencyHz'], 1000.0),
      amplitudeVpp: _asDouble(json['amplitudeVpp'], 1.0),
      offsetV: _asDouble(json['offsetV'], 0.0),
      dutyPercent: _asDouble(json['dutyPercent'], 50.0),
    );
  }

  final Jds6600Waveform waveform;
  final double frequencyHz;
  final double amplitudeVpp;
  final double offsetV;
  final double dutyPercent;

  Map<String, dynamic> toJson() => {
    'waveform': waveform.name,
    'frequencyHz': frequencyHz,
    'amplitudeVpp': amplitudeVpp,
    'offsetV': offsetV,
    'dutyPercent': dutyPercent,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SigGenChannelSnapshot &&
          other.waveform == waveform &&
          other.frequencyHz == frequencyHz &&
          other.amplitudeVpp == amplitudeVpp &&
          other.offsetV == offsetV &&
          other.dutyPercent == dutyPercent;

  @override
  int get hashCode =>
      Object.hash(waveform, frequencyHz, amplitudeVpp, offsetV, dutyPercent);
}

/// Confirmed generator state plus capability flags for the child window.
class SigGenGeneratorSnapshot {
  const SigGenGeneratorSnapshot({
    this.configured = false,
    this.connected = false,
    this.busy = false,
    this.mutable = false,
    this.port,
    this.modelName,
    this.isLite,
    this.modelMHz,
    this.ch1 = const SigGenChannelSnapshot.defaults(),
    this.ch2 = const SigGenChannelSnapshot.defaults(),
    this.ch1Output = false,
    this.ch2Output = false,
    this.phaseDeg = 0.0,
    this.lastError,
    this.lastRefresh,
  });

  factory SigGenGeneratorSnapshot.fromJson(Map<String, dynamic> json) {
    return SigGenGeneratorSnapshot(
      configured: json['configured'] as bool? ?? false,
      connected: json['connected'] as bool? ?? false,
      busy: json['busy'] as bool? ?? false,
      mutable: json['mutable'] as bool? ?? false,
      port: json['port'] as String?,
      modelName: json['modelName'] as String?,
      isLite: json['isLite'] as bool?,
      modelMHz: (json['modelMHz'] as num?)?.toInt(),
      ch1: SigGenChannelSnapshot.fromJson(_asMap(json['ch1'])),
      ch2: SigGenChannelSnapshot.fromJson(_asMap(json['ch2'])),
      ch1Output: json['ch1Output'] as bool? ?? false,
      ch2Output: json['ch2Output'] as bool? ?? false,
      phaseDeg: _asDouble(json['phaseDeg'], 0.0),
      lastError: json['lastError'] as String?,
      lastRefresh: _asDate(json['lastRefresh']),
    );
  }

  final bool configured;
  final bool connected;
  final bool busy;
  final bool mutable;
  final String? port;
  final String? modelName;
  final bool? isLite;
  final int? modelMHz;
  final SigGenChannelSnapshot ch1;
  final SigGenChannelSnapshot ch2;
  final bool ch1Output;
  final bool ch2Output;
  final double phaseDeg;
  final String? lastError;
  final DateTime? lastRefresh;

  SigGenChannelSnapshot channel(int channel) => channel == 2 ? ch2 : ch1;

  bool outputFor(int channel) => channel == 2 ? ch2Output : ch1Output;

  Map<String, dynamic> toJson() => {
    'configured': configured,
    'connected': connected,
    'busy': busy,
    'mutable': mutable,
    'port': port,
    'modelName': modelName,
    'isLite': isLite,
    'modelMHz': modelMHz,
    'ch1': ch1.toJson(),
    'ch2': ch2.toJson(),
    'ch1Output': ch1Output,
    'ch2Output': ch2Output,
    'phaseDeg': phaseDeg,
    'lastError': lastError,
    'lastRefresh': lastRefresh?.toIso8601String(),
  };
}

/// Complete snapshot pushed to the signal-generator window.
class SigGenWindowState {
  const SigGenWindowState({this.generator = const SigGenGeneratorSnapshot()});

  factory SigGenWindowState.fromJson(Map<String, dynamic> json) {
    return SigGenWindowState(
      generator: SigGenGeneratorSnapshot.fromJson(_asMap(json['generator'])),
    );
  }

  final SigGenGeneratorSnapshot generator;

  Map<String, dynamic> toJson() => {'generator': generator.toJson()};
}

/// Result of one command handled in the main window.
class SigGenCommandResult {
  const SigGenCommandResult({
    required this.ok,
    required this.state,
    this.error,
    this.errorType,
  });

  factory SigGenCommandResult.success(SigGenWindowState state) =>
      SigGenCommandResult(ok: true, state: state);

  factory SigGenCommandResult.failure(
    SigGenWindowState state,
    String error, {
    String errorType = 'error',
  }) {
    return SigGenCommandResult(
      ok: false,
      state: state,
      error: error,
      errorType: errorType,
    );
  }

  factory SigGenCommandResult.fromJson(Map<String, dynamic> json) {
    return SigGenCommandResult(
      ok: json['ok'] as bool? ?? false,
      state: SigGenWindowState.fromJson(_asMap(json['state'])),
      error: json['error'] as String?,
      errorType: json['errorType'] as String?,
    );
  }

  final bool ok;
  final SigGenWindowState state;
  final String? error;
  final String? errorType;

  Map<String, dynamic> toJson() => {
    'ok': ok,
    'state': state.toJson(),
    if (error != null) 'error': error,
    if (errorType != null) 'errorType': errorType,
  };
}

/// Maps a driver exception to a stable wire error type.
String sigGenErrorType(Object error) {
  if (error is Jds6600RangeException) return 'range';
  if (error is Jds6600TimeoutException) return 'timeout';
  if (error is Jds6600ProtocolException) return 'protocol';
  if (error is Jds6600DisconnectedException) return 'disconnected';
  if (error is Jds6600OpenException) return 'disconnected';
  return 'error';
}

/// Parses a channel argument, accepting only 1 or 2.
int sigGenChannelFromArgs(Object? value) {
  final channel = value is num ? value.toInt() : (int.tryParse('$value') ?? -1);
  if (channel != 1 && channel != 2) {
    throw ArgumentError.value(value, 'channel', 'Channel must be 1 or 2');
  }
  return channel;
}

/// Parses a waveform argument by enum name.
Jds6600Waveform sigGenWaveformFromArgs(Object? value) {
  final name = '$value';
  for (final waveform in Jds6600Waveform.values) {
    if (waveform.name == name) return waveform;
  }
  throw ArgumentError.value(value, 'waveform', 'Unknown waveform');
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return const <String, dynamic>{};
}

double _asDouble(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

DateTime? _asDate(Object? value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}
