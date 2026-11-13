import 'dart:async';

import '../signal_generator/signal_generator_detector.dart';
import '../signal_generator/signal_generator_service.dart';
import 'bode_models.dart';
import 'bode_plot_service.dart';

/// Owns the Bode sweep session state and the saved plot data.
///
/// The Bode panel itself performs the sweep; this controller tracks whether a
/// sweep is running, pauses the generator detection while it does, and keeps
/// the last saved points/config/status so the panel can be reopened.
class BodeSessionController {
  BodeSessionController({
    required this.readSignalGenerator,
    required this.readDetector,
    required this.isGeneratorDetected,
    required this.isPanelOpen,
    required this.onChanged,
  });

  /// Returns the currently configured signal generator service.
  final SignalGeneratorService? Function() readSignalGenerator;

  /// Returns the signal generator detector, if configured.
  final SignalGeneratorDetector? Function() readDetector;

  /// Whether a signal generator is currently detected.
  final bool Function() isGeneratorDetected;

  /// Whether the signal generator's child window is open.
  final bool Function() isPanelOpen;

  /// Called after the running state changed.
  final void Function() onChanged;

  bool isRunning = false;
  BodePlotService? service;
  List<BodePoint>? savedPoints;
  BodeConfig? savedConfig;
  BodeStatus? savedStatus;

  /// Applies a running-state change from the Bode panel.
  void setRunning(bool running) {
    isRunning = running;
    readDetector()?.setPaused(running);
    readSignalGenerator()?.setPanelActive(isPanelOpen() && !running);
    onChanged();
  }

  /// Stores the saved plot state reported by the Bode panel.
  void saveState(
    List<BodePoint>? points,
    BodeConfig? config,
    BodeStatus? status,
  ) {
    savedPoints = points;
    savedConfig = config;
    savedStatus = status;
  }

  /// Stops a running sweep and resumes the generator detection.
  void stop() {
    if (isRunning) {
      unawaited(service?.stop());
      isRunning = false;
    }
    final detector = readDetector();
    detector?.setPaused(false);
    if (!isGeneratorDetected()) detector?.start();
    readSignalGenerator()?.setPanelActive(isPanelOpen());
  }
}
