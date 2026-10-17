import 'package:sdsremote/src/signal_generator/jds6600_transport.dart';

/// In-memory JDS6600 transport for unit tests.
class FakeJds6600Transport implements Jds6600Transport {
  FakeJds6600Transport({this.deviceType = 15, this.serialNumber = 12345}) {
    registers[0] = [deviceType];
    registers[1] = [serialNumber];
    registers[20] = [0, 0];
    registers[21] = [0];
    registers[22] = [0];
    registers[23] = [100000, 0];
    registers[24] = [100000, 0];
    registers[25] = [1000];
    registers[26] = [1000];
    registers[27] = [1000];
    registers[28] = [1000];
    registers[29] = [500];
    registers[30] = [500];
    registers[31] = [0];
    registers[32] = [0, 0, 0, 0];
  }

  final int deviceType;
  final int serialNumber;
  final Map<int, List<int>> registers = <int, List<int>>{};
  final List<String> sentCommands = <String>[];

  bool opened = false;
  Object? errorOnOpen;
  Object? errorOnTransact;
  Duration? delay;

  /// Number of register-23 writes to acknowledge without applying.
  int dropFrequencyWrites = 0;

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
    final write = RegExp(r'^:w0*(\d+)=(.*)\.$').firstMatch(trimmed);
    if (write != null) {
      final register = int.parse(write.group(1)!);
      if (register == 23 && dropFrequencyWrites > 0) {
        dropFrequencyWrites--;
        return <String>[':ok'];
      }
      registers[register] = _parseValues(write.group(2)!);
      return <String>[':ok'];
    }

    final read = RegExp(r'^:r0*(\d+)=(\d+)\.$').firstMatch(trimmed);
    if (read != null) {
      final start = int.parse(read.group(1)!);
      final lines = int.parse(read.group(2)!) + 1;
      final result = <String>[];
      for (var index = 0; index < lines; index++) {
        final register = start + index;
        final values = registers[register] ?? const <int>[0];
        result.add(
          ':r${register.toString().padLeft(2, '0')}=${values.join(',')}.',
        );
      }
      return result;
    }

    throw StateError('Unhandled command: $command');
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

  List<int> _parseValues(String payload) => payload
      .split(',')
      .where((part) => part.trim().isNotEmpty)
      .map((part) => int.parse(part.trim()))
      .toList();
}
