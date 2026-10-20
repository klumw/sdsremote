import 'package:sdsremote/src/signal_generator/fy6900_transport.dart';

/// In-memory FY6900 transport for unit tests.
///
/// It implements the vendor command set closely enough to exercise the real
/// codec: decimal-Hz frequency reads, 0.1 mV amplitude reads, 1 mV offset
/// reads (including the unsigned 32-bit negative encoding), 0.001 % duty
/// reads and 0.001 degree phase reads.
class FakeFy6900Transport implements Fy6900Transport {
  FakeFy6900Transport({
    this.model = 'FY6900-60M',
    this.instrumentId = '1234567890123',
  }) {
    _channels[1] = FakeFy6900Channel();
    _channels[2] = FakeFy6900Channel();
  }

  final String model;
  final String instrumentId;
  final Map<int, FakeFy6900Channel> _channels = <int, FakeFy6900Channel>{};
  final List<String> sentCommands = <String>[];

  bool opened = false;
  Object? errorOnOpen;
  Object? errorOnTransact;
  Duration? delay;

  /// Whether decimal-Hz writes are applied. Set to `false` to emulate older
  /// firmware that only accepts the microhertz format.
  bool acceptDecimalFrequency = true;

  /// Whether legacy microhertz writes are applied.
  bool acceptMicroFrequency = true;

  /// Number of accepted-but-dropped frequency writes, to exercise the
  /// readback check and the format fallback.
  int dropFrequencyWrites = 0;

  /// Constant offset added to frequency readbacks, emulating the FY6900
  /// firmware's ~0.066 Hz high-word rounding error.
  double frequencyReadbackErrorHz = 0;

  /// Forces `RMF`/`RFF` to report 0 Hz, emulating a failed write.
  bool forceZeroFrequencyReadback = false;

  FakeFy6900Channel channel(int channel) => _channels[channel]!;

  @override
  bool get isOpen => opened;

  @override
  Future<void> open() async {
    if (errorOnOpen != null) throw errorOnOpen!;
    opened = true;
  }

  @override
  Future<void> close() async {
    opened = false;
  }

  @override
  Future<List<String>> transactMany(
    String command, {
    required int count,
    Duration timeout = const Duration(milliseconds: 1000),
    bool Function(String line)? accept,
  }) async {
    sentCommands.add(command.trim());
    if (delay != null) await Future<void>.delayed(delay!);
    if (errorOnTransact != null) throw errorOnTransact!;

    final trimmed = command.trim();
    if (trimmed == 'UMO') return <String>[model];
    if (trimmed == 'UID') return <String>[instrumentId];

    final match = RegExp(r'^([WR])([MF])([WFAODPN])(.*)$').firstMatch(trimmed);
    if (match == null) {
      throw StateError('Unhandled command: $command');
    }
    final isWrite = match.group(1) == 'W';
    final channel = match.group(2) == 'M' ? 1 : 2;
    final parameter = match.group(3)!;
    final payload = match.group(4)!;

    if (!isWrite) {
      return <String>[_readValue(channel, parameter)];
    }
    _writeValue(channel, parameter, payload);
    // The FY6900 acknowledges a write with a bare line feed.
    return <String>[''];
  }

  @override
  Future<String> transact(
    String command, {
    Duration timeout = const Duration(milliseconds: 1000),
    bool Function(String line)? accept,
  }) async {
    final lines = await transactMany(
      command,
      count: 1,
      timeout: timeout,
      accept: accept,
    );
    return lines.single;
  }

  String _readValue(int channel, String parameter) {
    final state = _channels[channel]!;
    switch (parameter) {
      case 'W':
        return '${state.waveform}';
      case 'F':
        if (forceZeroFrequencyReadback) return '0.000000';
        return (state.frequencyHz + frequencyReadbackErrorHz).toStringAsFixed(
          6,
        );
      case 'A':
        return '${(state.amplitudeVpp * 10000).round()}';
      case 'O':
        final millivolts = (state.offsetV * 1000).round();
        final raw = millivolts < 0 ? millivolts + 0x100000000 : millivolts;
        return '$raw';
      case 'D':
        return '${(state.dutyPercent * 1000).round()}';
      case 'P':
        return '${(state.phaseDeg * 1000).round()}';
      case 'N':
        return state.output ? '255' : '0';
    }
    throw StateError('Unhandled read parameter: $parameter');
  }

  void _writeValue(int channel, String parameter, String payload) {
    final state = _channels[channel]!;
    switch (parameter) {
      case 'W':
        state.waveform = int.parse(payload);
      case 'F':
        final previous = state.frequencyHz;
        if (payload.contains('.')) {
          if (!acceptDecimalFrequency) return;
          state.frequencyHz = double.parse(payload);
        } else {
          if (!acceptMicroFrequency) return;
          state.frequencyHz = int.parse(payload) / 1e6;
        }
        if (dropFrequencyWrites > 0) {
          dropFrequencyWrites--;
          state.frequencyHz = previous;
        }
      case 'A':
        state.amplitudeVpp = double.parse(payload);
      case 'O':
        state.offsetV = double.parse(payload);
      case 'D':
        state.dutyPercent = double.parse(payload);
      case 'P':
        state.phaseDeg = double.parse(payload);
      case 'N':
        state.output = payload.trim() == '1';
      default:
        throw StateError('Unhandled write parameter: $parameter');
    }
  }
}

/// Mutable per-channel state exposed to tests.
class FakeFy6900Channel {
  int waveform = 0;
  double frequencyHz = 1000;
  double amplitudeVpp = 1;
  double offsetV = 0;
  double dutyPercent = 50;
  double phaseDeg = 0;
  bool output = false;
}
