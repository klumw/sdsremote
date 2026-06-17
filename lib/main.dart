import 'dart:io';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:window_manager/window_manager.dart';

import 'logger.dart';
import 'src/app_theme.dart';
import 'src/home_page.dart';

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
