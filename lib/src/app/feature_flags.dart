/// Runtime feature flags controlled by the start mode and the AI settings.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Whether the app was started in Flutter debug mode or with `--debug`.
///
/// [compileTimeDebug] is true for a `flutter run --debug` session and false
/// for profile/release builds. An explicit `--debug` argument is also
/// accepted, both from the app arguments and from the executable arguments,
/// so a release build can opt in deliberately.
bool isDebugStart(
  List<String> args, {
  bool compileTimeDebug = kDebugMode,
  List<String>? executableArguments,
}) {
  if (compileTimeDebug) return true;
  final runtimeArguments = executableArguments ?? Platform.executableArguments;
  return args.contains('--debug') || runtimeArguments.contains('--debug');
}

/// Whether the Analysis tab is available.
///
/// The tab is a debug-only feature and additionally requires a correctly
/// configured AI provider, token and model.
bool isWaveformAnalysisEnabled({
  required bool debugMode,
  required bool aiConfigured,
}) => debugMode && aiConfigured;
