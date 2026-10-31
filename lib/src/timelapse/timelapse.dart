/// Timelapse planning and frame bookkeeping.
///
/// The module is pure Dart (no I/O): it turns a requested interval and total
/// duration into a bounded frame count, renders frame file names and tracks
/// progress and abort requests for one run.
library;

/// Immutable plan for one timelapse run.
class TimelapsePlan {
  /// Delay between two screen captures.
  final Duration interval;

  /// Maximum number of frames in this run (at least 1).
  final int frameCount;

  /// File-name prefix; already sanitized by [buildTimelapsePlan].
  final String prefix;

  const TimelapsePlan({
    required this.interval,
    required this.frameCount,
    required this.prefix,
  });

  /// Wall-clock duration the run needs, including the delay after the last
  /// frame (the capture itself is not included).
  Duration get totalDuration => interval * frameCount;

  /// File name of the 1-based [frameIndex], e.g. `timelapse_0001.png`.
  String fileNameFor(int frameIndex) {
    if (frameIndex < 1 || frameIndex > frameCount) {
      throw RangeError.range(frameIndex, 1, frameCount, 'frameIndex');
    }
    return '${prefix}_${frameIndex.toString().padLeft(4, '0')}.png';
  }
}

/// Builds a plan for [interval] and [duration].
///
/// Returns null when the interval is not positive, the duration is shorter
/// than one interval, or no frame fits. The frame count is clamped to
/// [maxFrames].
TimelapsePlan? buildTimelapsePlan({
  required Duration interval,
  required Duration duration,
  String prefix = 'timelapse',
  int maxFrames = 10000,
}) {
  if (interval <= Duration.zero || duration < interval) return null;
  if (maxFrames < 1) return null;
  final frames = duration.inMilliseconds ~/ interval.inMilliseconds;
  if (frames < 1) return null;
  return TimelapsePlan(
    interval: interval,
    frameCount: frames > maxFrames ? maxFrames : frames,
    prefix: _sanitizePrefix(prefix),
  );
}

/// Sortable folder name for one run, e.g. `2026-10-31_14-30-00`.
String timelapseRunFolderName(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)}_'
      '${two(time.hour)}-${two(time.minute)}-${two(time.second)}';
}

/// Tracks captured frames and the abort request of one run.
class TimelapseSession {
  final TimelapsePlan plan;

  int _captured = 0;
  bool _aborted = false;

  TimelapseSession({required this.plan});

  /// Number of successfully written frames.
  int get captured => _captured;

  /// Whether all planned frames were written.
  bool get isComplete => _captured >= plan.frameCount;

  /// Whether the run was aborted.
  bool get isAborted => _aborted;

  /// Whether another frame should be captured.
  bool get isActive => !isComplete && !_aborted;

  /// File name for the next frame, or null when the run is finished.
  String? get nextFileName => isActive ? plan.fileNameFor(_captured + 1) : null;

  /// Records one written frame. Ignored after completion or abort.
  void recordCaptured() {
    if (!isActive) return;
    _captured++;
  }

  /// Requests the end of the run at the next loop check.
  void abort() {
    _aborted = true;
  }
}

String _sanitizePrefix(String prefix) {
  final cleaned = prefix
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? 'timelapse' : cleaned;
}
