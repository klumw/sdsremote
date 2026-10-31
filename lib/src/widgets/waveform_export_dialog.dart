import 'package:flutter/material.dart';

import '../waveform/waveform_export.dart';

/// User selection made in [WaveformExportDialog].
class WaveformExportRequest {
  final WaveformExportFormat format;

  /// Selected channel for PWL/WAV; ignored for VCD (all channels) and
  /// clipboard.
  final String channel;

  /// Digital threshold for VCD export.
  final double thresholdVolts;

  /// Whether the PWL pairs are wrapped in `PWL(...)`.
  final bool wrapPwl;

  /// Base file name without extension.
  final String fileName;

  const WaveformExportRequest({
    required this.format,
    required this.channel,
    required this.thresholdVolts,
    required this.wrapPwl,
    required this.fileName,
  });
}

/// Dialog for exporting the current waveform in an external format.
class WaveformExportDialog extends StatefulWidget {
  /// Channels that have waveform data.
  final List<String> channels;

  const WaveformExportDialog({super.key, required this.channels});

  @override
  State<WaveformExportDialog> createState() => _WaveformExportDialogState();
}

class _WaveformExportDialogState extends State<WaveformExportDialog> {
  WaveformExportFormat _format = WaveformExportFormat.ltspicePwl;
  late String _channel;
  late final TextEditingController _fileName;
  late final TextEditingController _threshold;
  bool _wrapPwl = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _channel = widget.channels.isEmpty ? 'ch1' : widget.channels.first;
    _fileName = TextEditingController(text: 'waveform_export');
    _threshold = TextEditingController(text: '2.5');
  }

  @override
  void dispose() {
    _fileName.dispose();
    _threshold.dispose();
    super.dispose();
  }

  void _submit() {
    final fileName = _fileName.text.trim();
    if (_format != WaveformExportFormat.clipboard && fileName.isEmpty) {
      setState(() => _error = 'Enter a file name.');
      return;
    }
    double threshold = 0;
    if (_format == WaveformExportFormat.vcd) {
      final parsed = double.tryParse(
        _threshold.text.trim().replaceAll(',', '.'),
      );
      if (parsed == null || !parsed.isFinite) {
        setState(() => _error = 'Enter a valid threshold voltage.');
        return;
      }
      threshold = parsed;
    }
    Navigator.pop(
      context,
      WaveformExportRequest(
        format: _format,
        channel: _channel,
        thresholdVolts: threshold,
        wrapPwl: _wrapPwl,
        fileName: fileName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final needsFile = _format != WaveformExportFormat.clipboard;
    final needsChannel =
        _format == WaveformExportFormat.ltspicePwl ||
        _format == WaveformExportFormat.wav;

    return AlertDialog(
      backgroundColor: const Color(0xFF172A45),
      title: const Text(
        'Export Waveform',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<WaveformExportFormat>(
              initialValue: _format,
              isExpanded: true,
              dropdownColor: const Color(0xFF172A45),
              decoration: _decoration('Format'),
              items: [
                for (final format in WaveformExportFormat.values)
                  DropdownMenuItem(value: format, child: Text(_label(format))),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _format = value;
                  _error = null;
                });
              },
            ),
            if (needsChannel) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _channel,
                isExpanded: true,
                dropdownColor: const Color(0xFF172A45),
                decoration: _decoration('Channel'),
                items: [
                  for (final channel in widget.channels)
                    DropdownMenuItem(
                      value: channel,
                      child: Text(channel.toUpperCase()),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _channel = value);
                },
              ),
            ],
            if (_format == WaveformExportFormat.vcd) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _threshold,
                style: const TextStyle(color: Colors.white),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: _decoration('High threshold (V)'),
              ),
            ],
            if (_format == WaveformExportFormat.ltspicePwl) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    value: _wrapPwl,
                    activeColor: Colors.cyanAccent,
                    onChanged: (value) =>
                        setState(() => _wrapPwl = value ?? false),
                  ),
                  const Text(
                    'Wrap in PWL(...) expression',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ],
            if (needsFile) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _fileName,
                style: const TextStyle(color: Colors.white),
                decoration: _decoration('File name (without extension)'),
              ),
            ],
            if (_format == WaveformExportFormat.clipboard) ...[
              const SizedBox(height: 8),
              const Text(
                'Copies the measurement table of all acquired channels as '
                'tab-separated text.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
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
        FilledButton(
          onPressed: _submit,
          child: Text(
            _format == WaveformExportFormat.clipboard ? 'Copy' : 'Export',
          ),
        ),
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

  String _label(WaveformExportFormat format) => switch (format) {
    WaveformExportFormat.ltspicePwl => 'LTspice PWL',
    WaveformExportFormat.wav => 'WAV (16-bit PCM)',
    WaveformExportFormat.vcd => 'VCD',
    WaveformExportFormat.clipboard => 'Clipboard (TSV)',
  };
}
