/// Runtime feature flags controlled by the start mode.
library;

import 'dart:io';

/// Whether the app was started with the explicit `--debug` flag.
///
/// The flag is accepted both from the app arguments and from the executable
/// arguments, so a release build can opt in deliberately. A plain debug build
/// without the flag does not enable debug-only features.
bool isDebugStart(List<String> args, {List<String>? executableArguments}) {
  final runtimeArguments = executableArguments ?? Platform.executableArguments;
  return args.contains('--debug') || runtimeArguments.contains('--debug');
}
