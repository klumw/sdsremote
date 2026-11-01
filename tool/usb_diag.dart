// Diagnostic for Siglent SDS1x04X-E USBTMC transfers on Linux.
//
// Run with the SDS-Remote application closed: it claims the USB interface for
// the lifetime of the process.
//
//   dart run tool/usb_diag.dart waveform
//   dart run tool/usb_diag.dart screen
//   dart run tool/usb_diag.dart all
//   dart run tool/usb_diag.dart app
//   dart run tool/usb_diag.dart screen --cap=2032
//
// `--cap=N` overrides the 48-byte USBTMC read request limit for experiments.
//
// The waveform mode performs a chunked-read acquisition (WFSU NP=100000) and
// verifies that the instrument still answers afterwards. The screen mode
// sends SCDP and reads the bitmap. The app mode replicates the application's
// acquisition (TRMD STOP/restore, parameter queries, screen-dump timeout).
// SCDP can wedge the instrument's USB firmware; a replug or power cycle is
// then required.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:usbtmc_dart/usbtmc_dart.dart';

const int waveformPoints = 100000;
const int maxReadBytes = 16 * 1024 * 1024;
const Duration readTimeout = Duration(seconds: 60);

Future<void> main(List<String> args) async {
  final options = args.where((a) => a.startsWith('--')).toList();
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final mode = positional.isEmpty ? 'waveform' : positional.first;
  final capArg = options
      .firstWhere((a) => a.startsWith('--cap='), orElse: () => '')
      .replaceFirst('--cap=', '');
  final int? cap = capArg.isEmpty ? null : int.parse(capArg);
  final repeatArg = options
      .firstWhere((a) => a.startsWith('--repeat='), orElse: () => '')
      .replaceFirst('--repeat=', '');
  final int repeat = repeatArg.isEmpty ? 1 : int.parse(repeatArg);
  final address = _findSiglentUsbAddress();
  if (address == null) {
    stderr.writeln('No Siglent USBTMC device found.');
    exitCode = 2;
    return;
  }

  final context = UsbtmcContext();
  await context.init();

  final UsbtmcDevice device;
  try {
    device = await context.newDevice(address);
  } catch (e) {
    stdout.writeln('Open failed: $e');
    await context.close();
    exitCode = 1;
    return;
  }

  try {
    stdout.writeln('Device: $address');
    stdout.writeln('Mode: $mode');
    if (cap != null) {
      device.maxReadTransferSize = cap;
      stdout.writeln('maxReadTransferSize override: $cap');
    }
    stdout.writeln('maxReadTransferSize: ${device.maxReadTransferSize}');

    await _query(device, '*IDN?', label: 'IDN before');

    if (mode == 'waveform') {
      await _waveform(device);
    } else if (mode == 'screen') {
      for (var i = 1; i <= repeat; i++) {
        await _screen(device, label: 'SCDP #$i');
      }
    } else if (mode == 'all') {
      await _waveform(device);
      await _screen(device);
    } else if (mode == 'app') {
      await _appSequence(device);
    } else {
      stderr.writeln(
        'Unknown mode "$mode" (use waveform, screen, all or app).',
      );
      exitCode = 2;
    }
  } catch (e) {
    stdout.writeln('FATAL: $e');
    exitCode = 1;
  } finally {
    try {
      await device.close();
    } catch (_) {}
    try {
      await context.close();
    } catch (_) {}
  }
}

Future<String> _query(UsbtmcDevice device, String cmd, {String? label}) async {
  final name = label ?? cmd;
  try {
    await device.command(cmd, timeout: const Duration(seconds: 5));
    final bytes = await device.doRead(
      256,
      useTermChar: true,
      timeout: const Duration(seconds: 10),
    );
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    stdout.writeln('$name: OK, ${bytes.length} B, "$text"');
    return text;
  } catch (e) {
    stdout.writeln('$name: FAILED, $e');
    rethrow;
  }
}

Future<void> _waveform(UsbtmcDevice device) async {
  final active = <int>[];
  for (var ch = 1; ch <= 4; ch++) {
    final response = await _query(device, 'C$ch:TRACE?', label: 'C$ch:TRACE?');
    if (RegExp(r'\bON\b', caseSensitive: false).hasMatch(response)) {
      active.add(ch);
    }
  }
  if (active.isEmpty) {
    stdout.writeln('No active channel; skipping waveform read.');
    return;
  }

  await device.command('WFSU SP,7,NP,$waveformPoints,FP,0');
  stdout.writeln('WFSU sent: SP,7,NP,$waveformPoints,FP,0');

  for (final ch in active) {
    final sw = Stopwatch()..start();
    await device.command('C$ch:WF? DAT2');
    final raw = await device.doRead(
      maxReadBytes,
      useTermChar: false,
      timeout: readTimeout,
    );
    sw.stop();
    stdout.writeln(
      'C$ch:WF? DAT2: ${raw.length} B in ${sw.elapsedMilliseconds} ms, '
      'head=${_hex(raw, 16)}',
    );
  }

  await _query(device, '*IDN?', label: 'IDN after waveform');
}

Future<void> _screen(UsbtmcDevice device, {String label = 'SCDP'}) async {
  stdout.writeln('$label: sending screen dump request (may wedge the device)');
  final sw = Stopwatch()..start();
  await device.command('SCDP');
  final raw = await device.doRead(
    maxReadBytes,
    useTermChar: false,
    timeout: readTimeout,
  );
  sw.stop();
  stdout.writeln(
    '$label: ${raw.length} B in ${sw.elapsedMilliseconds} ms, '
    'head=${_hex(raw, 32)}',
  );
  await _query(device, '*IDN?', label: 'IDN after $label');
}

/// Replicates WaveformAcquisition.acquire() and the Control Panel's screen
/// dump: stop the trigger, query the parameters, read every active channel,
/// restore the trigger, then send SCDP with the application's 30 s timeout.
Future<void> _appSequence(UsbtmcDevice device) async {
  var trigger = (await _query(device, 'TRMD?', label: 'TRMD?')).trim();
  final space = trigger.lastIndexOf(' ');
  if (space >= 0) trigger = trigger.substring(space + 1).trim();
  var originalTrigger = trigger;
  stdout.writeln('Trigger mode: "$originalTrigger"');
  if (originalTrigger == 'STOP') {
    // A previous aborted run may have left the instrument stopped. Start from
    // a running trigger so the test takes the same stop/restore path as the
    // application.
    await device.command('TRMD AUTO');
    stdout.writeln('TRMD AUTO sent to start from a running trigger');
    originalTrigger = 'AUTO';
  }
  if (originalTrigger.isNotEmpty && originalTrigger != 'STOP') {
    await device.command('TRMD STOP');
    stdout.writeln('TRMD STOP sent');
  }

  final timebase = _floatValue(await _query(device, 'TDIV?', label: 'TDIV?'));
  await _query(device, 'TRDL?', label: 'TRDL?');
  final sampleRate = _floatValue(await _query(device, 'SARA?', label: 'SARA?'));

  const int horizontalDivisions = 14;
  final int desiredPoints = (timebase * horizontalDivisions * sampleRate)
      .ceil();
  final int points = desiredPoints.clamp(1201, waveformPoints);
  await device.command('WFSU SP,7,NP,$points,FP,0');
  stdout.writeln('WFSU sent: SP,7,NP,$points,FP,0');

  await _query(device, 'SANU? C1', label: 'SANU? C1');

  final active = <int>[];
  for (var ch = 1; ch <= 4; ch++) {
    final trace = await _query(device, 'C$ch:TRACE?', label: 'C$ch:TRACE?');
    if (RegExp(r'\bON\b', caseSensitive: false).hasMatch(trace)) {
      active.add(ch);
    }
  }
  for (final ch in active) {
    await _query(device, 'C$ch:VDIV?', label: 'C$ch:VDIV?');
    await _query(device, 'C$ch:OFST?', label: 'C$ch:OFST?');
  }

  for (final ch in active) {
    final sw = Stopwatch()..start();
    await device.command('C$ch:WF? DAT2');
    final raw = await device.doRead(
      maxReadBytes,
      useTermChar: false,
      timeout: readTimeout,
    );
    sw.stop();
    stdout.writeln(
      'C$ch:WF? DAT2: ${raw.length} B in ${sw.elapsedMilliseconds} ms',
    );
  }

  if (originalTrigger.isNotEmpty && originalTrigger != 'STOP') {
    await device.command('TRMD $originalTrigger');
    stdout.writeln('TRMD $originalTrigger sent');
  }

  await _query(device, '*IDN?', label: 'IDN after acquisition');

  stdout.writeln('Waiting 5 s before the screen dump...');
  await Future<void>.delayed(const Duration(seconds: 5));

  // The application reads screen dumps with a 30 s per-transfer timeout.
  final sw = Stopwatch()..start();
  await device.command('SCDP');
  final raw = await device.doRead(
    maxReadBytes,
    useTermChar: false,
    timeout: const Duration(seconds: 30),
  );
  sw.stop();
  stdout.writeln(
    'SCDP: ${raw.length} B in ${sw.elapsedMilliseconds} ms, '
    'head=${_hex(raw, 32)}',
  );
  await _query(device, '*IDN?', label: 'IDN after SCDP');
}

double _floatValue(String response) {
  final parts = response.trim().split(RegExp(r'\s+'));
  final numeric = parts.last.replaceAll(RegExp(r'[^0-9eE+\-.]'), '');
  return double.parse(numeric);
}

String _hex(Uint8List data, int limit) {
  final length = data.length < limit ? data.length : limit;
  return data
      .sublist(0, length)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join(' ');
}

String? _findSiglentUsbAddress() {
  final devicesDir = Directory('/sys/bus/usb/devices');
  if (!devicesDir.existsSync()) return null;

  for (final entity in devicesDir.listSync(followLinks: true)) {
    final path = entity.path;
    final name = path.split('/').last;
    if (!name.contains(':')) continue;

    final classFile = File('$path/bInterfaceClass');
    final subClassFile = File('$path/bInterfaceSubClass');
    final protocolFile = File('$path/bInterfaceProtocol');
    if (!classFile.existsSync() ||
        !subClassFile.existsSync() ||
        !protocolFile.existsSync()) {
      continue;
    }

    final cls = classFile.readAsStringSync().trim();
    final subcls = subClassFile.readAsStringSync().trim();
    final proto = protocolFile.readAsStringSync().trim();
    final isUsbtmc =
        (cls == 'fe' || cls == '254') &&
        (subcls == '03' || subcls == '3') &&
        (proto == '01' || proto == '1');
    if (!isUsbtmc) continue;

    final devName = name.split(':').first;
    final usbDir = Directory('/sys/bus/usb/devices/$devName');
    final vendorFile = File('${usbDir.path}/idVendor');
    final productFile = File('${usbDir.path}/idProduct');
    if (!vendorFile.existsSync() || !productFile.existsSync()) continue;

    final vendor = vendorFile.readAsStringSync().trim();
    if (vendor != 'f4ec' && vendor != 'f4ed') continue;
    final product = productFile.readAsStringSync().trim();
    final serialFile = File('${usbDir.path}/serial');
    final serial = serialFile.existsSync()
        ? serialFile.readAsStringSync().trim()
        : '';

    return serial.isNotEmpty
        ? 'USB0::0x$vendor::0x$product::$serial::INSTR'
        : 'USB0::0x$vendor::0x$product::INSTR';
  }
  return null;
}
