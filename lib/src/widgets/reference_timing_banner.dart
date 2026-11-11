import 'package:flutter/material.dart';

import '../instrument/measurement.dart' show formatMeasurementValue;
import '../waveform/clock_detection.dart' show formatTimebase;
import '../waveform/reference_timing.dart';

/// Persistent warning floating over the bottom edge of the waveform chart
/// when the loaded reference was recorded with different timing settings than
/// the current acquisition.
///
/// The banner covers the timebase, trigger delay and sample rate; settings
/// that match are not listed. Its background is semi-transparent so the chart
/// remains visible underneath. It disappears automatically once all values
/// match again. When [onDismiss] is set, a close button at the right edge
/// hides the banner until the warning content changes.
class ReferenceTimingBanner extends StatelessWidget {
  final List<ReferenceTimingMismatch> mismatches;

  /// Called when the close button is pressed; null hides the button.
  final VoidCallback? onDismiss;

  const ReferenceTimingBanner({
    super.key,
    required this.mismatches,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (mismatches.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        // Semi-transparent so the chart underneath stays visible.
        color: const Color(0xFF3A2E0A).withValues(alpha: 0.7),
        border: Border.all(color: Colors.amber, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: Colors.amber,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reference settings differ from the current instrument '
                  'settings',
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                for (final mismatch in mismatches)
                  Text(
                    '${mismatch.field.label}: '
                    '${_formatValue(mismatch.field, mismatch.referenceValue)} '
                    '(REF) ↔ '
                    '${_formatValue(mismatch.field, mismatch.currentValue)} '
                    '(current)',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (onDismiss != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Dismiss warning',
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 16, color: Colors.amber),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }

  String _formatValue(ReferenceTimingField field, double value) =>
      switch (field) {
        ReferenceTimingField.timebase => formatTimebase(value),
        ReferenceTimingField.triggerDelay => formatMeasurementValue(value, 's'),
        ReferenceTimingField.sampleRate => formatMeasurementValue(
          value,
          'Sa/s',
        ),
      };
}
