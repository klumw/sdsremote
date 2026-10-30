import 'dart:async';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app/app_theme.dart';
import 'src/app/window_state.dart';
import 'src/calculator/calculator_controller.dart';
import 'src/calculator/calculator_window_protocol.dart';
import 'src/core/logger.dart';
import 'src/signal_generator/siggen_window_client.dart';
import 'src/signal_generator/siggen_window_protocol.dart';
import 'src/widgets/calculator_window.dart';
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
  if (CalculatorWindowArguments.isCalculatorWindow(windowArguments)) {
    await _runCalculatorWindow(windowArguments);
    return;
  }

  // Restore the size and position saved when the application last closed.
  // The position is dropped when it would no longer be visible on a connected
  // display; the window is then centered.
  final windowGeometry = await WindowStateStore.load();
  final windowOptions = WindowOptions(
    size: windowGeometry.size,
    minimumSize: WindowGeometry.minimumSize,
    title: 'SDS-Remote',
    center: windowGeometry.position == null,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    final position = windowGeometry.position;
    if (position != null) {
      try {
        await windowManager.setPosition(position);
      } catch (error) {
        AppLogger(
          agentName: 'WindowState',
          toolName: 'restore',
        ).log('Could not restore window position: $error');
      }
    }
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
    title: 'Signal Generator',
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

/// Starts the child engine's engineering-calculator window.
Future<void> _runCalculatorWindow(String windowArguments) async {
  AppLogger().info('SDS-Remote: calculator window starting');
  final targetPosition = CalculatorWindowArguments.positionFrom(
    windowArguments,
  );
  final windowOptions = WindowOptions(
    size: const Size(
      CalculatorWindowArguments.windowWidth,
      CalculatorWindowArguments.windowHeight,
    ),
    minimumSize: const Size(980, 640),
    title: 'Engineering Calculator',
    center: targetPosition == null,
  );
  try {
    await windowManager.waitUntilReadyToShow(windowOptions, () {});
  } catch (error) {
    AppLogger(
      agentName: 'Calculator',
      toolName: 'window',
    ).log('window_manager setup failed: $error');
  }

  try {
    final windowController = await WindowController.fromCurrentEngine();
    await windowController.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'positionWindow':
          final arguments = call.arguments;
          if (arguments is Map) {
            final left = arguments['left'];
            final top = arguments['top'];
            if (left is num && top is num) {
              await windowManager.setPosition(
                Offset(left.toDouble(), top.toDouble()),
              );
            }
          }
          return null;
        case 'focus':
          await windowManager.show();
          await windowManager.focus();
          return null;
        case 'closeWindow':
          await windowManager.hide();
          return null;
        default:
          throw MissingPluginException('Not implemented: ${call.method}');
      }
    });
  } catch (error) {
    AppLogger(
      agentName: 'Calculator',
      toolName: 'window',
    ).log('Could not install the window method handler: $error');
  }

  final controller = CalculatorController();
  var shown = false;
  Future<void> showWindow() async {
    if (shown) return;
    shown = true;
    final log = AppLogger(agentName: 'Calculator', toolName: 'window');
    var positioned = false;
    if (targetPosition != null) {
      try {
        await windowManager.setPosition(
          Offset(targetPosition.left, targetPosition.top),
        );
        positioned = true;
      } catch (error) {
        log.log('Could not position calculator window: $error');
      }
    }
    try {
      await windowManager.show();
      if (targetPosition != null) {
        // Repeat after showing in case the compositor ignored a move request
        // for the still-hidden window.
        try {
          await windowManager.setPosition(
            Offset(targetPosition.left, targetPosition.top),
          );
          positioned = true;
        } catch (error) {
          log.log('Could not position calculator window after showing: $error');
        }
      }
      if (!positioned) await windowManager.center();
      await windowManager.focus();
      log.log('Calculator window shown');
    } catch (error) {
      log.log('Could not show calculator window: $error');
    }
  }

  runApp(
    CalculatorWindowApp(
      controller: controller,
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
