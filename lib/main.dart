import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app/app_theme.dart';
import 'src/core/logger.dart';
import 'src/signal_generator/siggen_window_client.dart';
import 'src/signal_generator/siggen_window_protocol.dart';
import 'src/widgets/home_page.dart';
import 'src/widgets/signal_generator_window.dart';

// ===========================================================================
// Application Entry Point
// ===========================================================================

Level _getRequestedLogLevel(List<String> args) {
  // 1. Check --dart-define=loglevel=VALUE (compile-time constant).
  const dartDefineLevel = String.fromEnvironment('loglevel');
  if (dartDefineLevel.isNotEmpty) {
    return AppLogger.parseLevel(dartDefineLevel);
  }

  // 2. Check runtime CLI arguments (--loglevel=VALUE or --loglevel VALUE).
  final cliArgs = args.isNotEmpty ? args : Platform.executableArguments;
  for (var index = 0; index < cliArgs.length; index++) {
    final arg = cliArgs[index];
    if (arg.startsWith('--loglevel=')) {
      return AppLogger.parseLevel(arg.substring('--loglevel='.length));
    }
    if (arg == '--loglevel' && index + 1 < cliArgs.length) {
      return AppLogger.parseLevel(cliArgs[index + 1]);
    }
  }
  return AppLogger.parseLevel(null);
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final logLevel = _getRequestedLogLevel(args);
  AppLogger.minimumLevel = logLevel;
  Agent.loggingOptions = LoggingOptions(
    level: AppLogger.traceLevel,
    onRecord: (record) {
      final logger = AppLogger(agentName: 'AI', toolName: record.loggerName);
      final message = record.message;
      if (record.level >= Level.FINE) {
        logger.debug(message);
      } else {
        logger.trace(message);
      }
    },
  );

  AppLogger().info('SDS-Remote: application starting');

  // Every desktop_multi_window engine runs this same entry point. The child
  // engine receives its role through the window arguments.
  final windowArguments = await _currentWindowArguments();
  if (SigGenWindowArguments.isSigGenWindow(windowArguments)) {
    await _runSignalGeneratorWindow();
    return;
  }

  const windowOptions = WindowOptions(
    size: Size(1400, 900),
    minimumSize: Size(1400, 900),
    title: 'SDS-Remote',
    center: true,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const OscilloscopeApp());
}

/// Returns the arguments of the current engine, or an empty string when the
/// multi-window plugin is unavailable (normal single-window start).
Future<String> _currentWindowArguments() async {
  try {
    final controller = await WindowController.fromCurrentEngine();
    return controller.arguments;
  } catch (_) {
    return '';
  }
}

/// Starts the child engine's signal-generator window.
Future<void> _runSignalGeneratorWindow() async {
  AppLogger().info('SDS-Remote: signal generator window starting');
  const windowOptions = WindowOptions(
    size: Size(760, 600),
    minimumSize: Size(760, 600),
    title: 'Signal Generator — JDS6600',
    center: true,
  );
  try {
    // Apply size/title/position, but keep the native window hidden until the
    // first complete Flutter frame has been painted. Showing it earlier
    // produces an empty black window.
    await windowManager.waitUntilReadyToShow(windowOptions, () {});
  } catch (error) {
    AppLogger(
      agentName: 'SigGen',
      toolName: 'window',
    ).log('window_manager setup failed: $error');
  }

  final client = await DesktopSigGenWindowClient.create();
  var shown = false;
  Future<void> showWindow() async {
    if (shown) return;
    shown = true;
    final log = AppLogger(agentName: 'SigGen', toolName: 'window');
    log.log('Showing signal generator window');
    try {
      await windowManager.show();
      await windowManager.focus();
      log.log('Signal generator window shown');
    } catch (error) {
      log.log('Could not show signal generator window: $error');
    }
  }

  runApp(
    SignalGeneratorWindowApp(
      client: client,
      onReady: () => unawaited(showWindow()),
    ),
  );
  // Failsafe: show even if the child never reports readiness.
  Timer(const Duration(seconds: 3), () => unawaited(showWindow()));
}

// ===========================================================================
// Root Application Widget
// ===========================================================================

class OscilloscopeApp extends StatelessWidget {
  const OscilloscopeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SDS-Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.scaffoldBackground,
      ),
      home: const OsciHomePage(),
    );
  }
}
