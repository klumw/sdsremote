import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../timelapse/timelapse.dart';

/// Dialog that collects the settings for a timelapse screen capture.
///
/// It returns a [TimelapsePlan] through `Navigator.pop`; the capture loop and
/// file writing live in the home page.
class TimelapseDialog extends StatefulWidget {
  /// Base directory the frames are written to (display only).
  final String targetDirectory;

  const TimelapseDialog({super.key, required this.targetDirectory});

  @override
  State<TimelapseDialog> createState() => _TimelapseDialogState();
}

class _TimelapseDialogState extends State<TimelapseDialog> {
  late final TextEditingController _interval;
  late final TextEditingController _frames;
  late final TextEditingController _prefix;
  String? _error;

  @override
  void initState() {
    super.initState();
    _interval = TextEditingController(text: '10');
    _frames = TextEditingController(text: '60');
    _prefix = TextEditingController(text: 'timelapse');
  }

  @override
  void dispose() {
    _interval.dispose();
    _frames.dispose();
    _prefix.dispose();
    super.dispose();
  }

  /// Largest accepted interval (24 hours).
  static const int _maxIntervalSeconds = 86400;

  /// Largest accepted frame count.
  static const int _maxFrames = 10000;

  void _submit() {
    final seconds = int.tryParse(_interval.text.trim());
    final frames = int.tryParse(_frames.text.trim());
    if (seconds == null || seconds < 1 || seconds > _maxIntervalSeconds) {
      setState(
        () => _error =
            'Enter a positive whole number of seconds (1–$_maxIntervalSeconds).',
      );
      return;
    }
    if (frames == null || frames < 1 || frames > _maxFrames) {
      setState(
        () =>
            _error = 'Enter a positive whole number of frames (1–$_maxFrames).',
      );
      return;
    }
    final interval = Duration(seconds: seconds);
    final plan = buildTimelapsePlan(
      interval: interval,
      duration: interval * frames,
      prefix: _prefix.text,
      maxFrames: _maxFrames,
    );
    if (plan == null || plan.frameCount != frames) {
      setState(
        () => _error =
            'Enter a positive whole number of seconds (1–$_maxIntervalSeconds).',
      );
      return;
    }
    Navigator.pop(context, plan);
  }

  String get _summary {
    final seconds = int.tryParse(_interval.text.trim());
    final frames = int.tryParse(_frames.text.trim());
    if (seconds == null ||
        seconds < 1 ||
        seconds > _maxIntervalSeconds ||
        frames == null ||
        frames < 1 ||
        frames > _maxFrames) {
      return '';
    }
    final total = Duration(seconds: seconds * frames);
    return '$frames frames every ${_formatDuration(Duration(seconds: seconds))} '
        '(${_formatDuration(total)} total)';
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      final minutes = duration.inMinutes.remainder(60);
      return '${duration.inHours} h $minutes min';
    }
    if (duration.inMinutes > 0) {
      final seconds = duration.inSeconds.remainder(60);
      return '${duration.inMinutes} min $seconds s';
    }
    return '${duration.inSeconds} s';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF172A45),
      title: const Text('Timelapse', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Captures the oscilloscope screen at a fixed interval and writes '
              'the frames as PNG files. Auto capture and the live screen are '
              'stopped while the timelapse runs.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('timelapse_interval'),
                    controller: _interval,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() => _error = null),
                    decoration: _decoration('Interval (s)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: const ValueKey('timelapse_frames'),
                    controller: _frames,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() => _error = null),
                    decoration: _decoration('Frames'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('timelapse_prefix'),
              controller: _prefix,
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => setState(() => _error = null),
              decoration: _decoration('File name prefix'),
            ),
            const SizedBox(height: 12),
            Text(
              _summary,
              style: const TextStyle(color: Colors.cyanAccent, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              'Folder: ${widget.targetDirectory}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Start')),
      ],
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
    enabledBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: Colors.white24),
    ),
    focusedBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: Colors.cyanAccent),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  );
}
