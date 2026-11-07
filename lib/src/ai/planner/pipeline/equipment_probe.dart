/// Injected device seam of the deterministic planner.
///
/// The pipeline never talks to hardware directly. Production wires the
/// existing `vxi11Host` and `read_signal_generator_status` providers into
/// [CallbackEquipmentProbe]; tests use a fake probe.
library;

import 'equipment_report.dart';

/// Reads the current waveform summary, or returns `null` when none exists.
typedef WaveformSummaryReader = Map<String, dynamic>? Function();

/// Reads the signal-generator status map.
typedef GeneratorStatusReader = Future<Map<String, dynamic>> Function();

/// Device seams used by stage 2.
abstract interface class EquipmentProbe {
  /// Probes the oscilloscope.
  Future<ScopeEquipment> probeScope();

  /// Probes the signal generator.
  Future<GeneratorEquipment> probeGenerator();
}

/// Production adapter around the existing host providers.
class CallbackEquipmentProbe implements EquipmentProbe {
  CallbackEquipmentProbe({
    required this.vxi11Host,
    this.readGeneratorStatus,
    this.readWaveformSummary,
  });

  /// Configured VXI-11 host, or `null` when no scope is configured.
  final String? vxi11Host;

  /// Signal-generator status provider.
  final GeneratorStatusReader? readGeneratorStatus;

  /// Cached waveform summary provider.
  final WaveformSummaryReader? readWaveformSummary;

  @override
  Future<ScopeEquipment> probeScope() async {
    final host = vxi11Host?.trim();
    final reachable = host != null && host.isNotEmpty;
    if (!reachable) {
      return const ScopeEquipment(
        reachable: false,
        error: 'No oscilloscope host is configured.',
      );
    }
    final readable = <String, Object?>{};
    final reader = readWaveformSummary;
    if (reader != null) {
      try {
        final summary = reader();
        if (summary != null) readable['waveformSummary'] = summary;
      } on Object {
        // A missing acquisition must not block planning; the plan can still
        // ask the sub-agent to acquire a fresh waveform.
      }
    }
    return ScopeEquipment(
      reachable: true,
      host: host,
      readableValues: readable,
    );
  }

  @override
  Future<GeneratorEquipment> probeGenerator() async {
    final reader = readGeneratorStatus;
    if (reader == null) {
      return const GeneratorEquipment(
        configured: false,
        connected: false,
        supported: false,
        error: 'Signal generator status is not available in this context.',
      );
    }
    try {
      final status = await reader();
      return GeneratorEquipment.fromStatus(status);
    } on Object catch (error) {
      return GeneratorEquipment(
        configured: false,
        connected: false,
        supported: false,
        error: 'The signal generator could not be probed ($error).',
      );
    }
  }
}
