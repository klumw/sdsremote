import 'data_logger_models.dart';
import 'data_logger_service.dart';

/// Owns the Data Logger session state and the saved plot data.
///
/// The panel performs the recording; this controller tracks whether it is
/// running and keeps the last points/config/status/hidden lines so the panel
/// can be reopened and a report can be saved.
class DataLoggerSessionController {
  DataLoggerSessionController({required this.onChanged});

  /// Called after the running state or the saved plot data changed.
  final void Function() onChanged;

  bool isRunning = false;
  DataLoggerService? service;
  List<DataLoggerPoint>? savedPoints;
  DataLoggerConfig? savedConfig;
  DataLoggerStatus? savedStatus;
  Set<String>? savedHiddenLines;

  /// Applies a running-state change from the Data Logger panel.
  void setRunning(bool running) {
    isRunning = running;
    onChanged();
  }

  /// Stores the saved plot state reported by the Data Logger panel.
  void saveState(
    List<DataLoggerPoint>? points,
    DataLoggerConfig? config,
    DataLoggerStatus? status,
    Set<String>? hiddenLines,
  ) {
    savedPoints = points;
    savedConfig = config;
    savedStatus = status;
    savedHiddenLines = hiddenLines;
  }

  /// Applies the final state after a recording finished.
  void recordingFinished(
    List<DataLoggerPoint>? points,
    DataLoggerConfig? config,
  ) {
    savedPoints = points;
    savedConfig = config;
    savedStatus = DataLoggerStatus.stopped;
    onChanged();
  }

  /// Closes the panel: clears the running flag.
  void close() {
    isRunning = false;
    onChanged();
  }

  /// Stops the recording and its background service without notifying.
  void stop() {
    isRunning = false;
    service?.stop();
  }
}
