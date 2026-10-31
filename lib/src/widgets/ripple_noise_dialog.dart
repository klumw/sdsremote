import 'package:flutter/material.dart';

/// Runs the ripple/noise measurement and returns the formatted result text.
///
/// The implementation lives in the home page because it needs the instrument
/// connection; the dialog only collects the settings and shows the result.
typedef RippleNoiseMeasurement =
    Future<String> Function({
      required int channel,
      required double vdiv,
      required double offset,
      required bool bandwidthLimit,
      required bool restore,
    });

/// Dialog for the AC-coupled, bandwidth-limited ripple/noise measurement.
///
/// The preset switches the selected channel to AC coupling, optionally enables
/// the 20 MHz bandwidth limit, sets V/div and offset, reads RMS and Vpp and
/// restores the previous settings afterwards.
class RippleNoiseDialog extends StatefulWidget {
  /// Executes the measurement for the selected settings.
  final RippleNoiseMeasurement run;

  /// Channels offered in the picker.
  final List<int> channels;

  const RippleNoiseDialog({
    super.key,
    required this.run,
    this.channels = const [1, 2, 3, 4],
  });

  @override
  State<RippleNoiseDialog> createState() => _RippleNoiseDialogState();
}

class _RippleNoiseDialogState extends State<RippleNoiseDialog> {
  late int _channel;
  late final TextEditingController _vdiv;
  late final TextEditingController _offset;
  bool _bandwidthLimit = true;
  bool _restore = true;
  bool _measuring = false;
  String? _error;
  String? _result;

  @override
  void initState() {
    super.initState();
    _channel = widget.channels.isEmpty ? 1 : widget.channels.first;
    _vdiv = TextEditingController(text: '0.05');
    _offset = TextEditingController(text: '0');
  }

  @override
  void dispose() {
    _vdiv.dispose();
    _offset.dispose();
    super.dispose();
  }

  Future<void> _measure() async {
    final vdiv = double.tryParse(_vdiv.text.trim().replaceAll(',', '.'));
    final offset = double.tryParse(_offset.text.trim().replaceAll(',', '.'));
    if (vdiv == null || !vdiv.isFinite || vdiv <= 0) {
      setState(() => _error = 'Enter a positive V/div value.');
      return;
    }
    if (offset == null || !offset.isFinite) {
      setState(() => _error = 'Enter a valid offset voltage.');
      return;
    }

    setState(() {
      _error = null;
      _result = null;
      _measuring = true;
    });
    try {
      final result = await widget.run(
        channel: _channel,
        vdiv: vdiv,
        offset: offset,
        bandwidthLimit: _bandwidthLimit,
        restore: _restore,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _measuring = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Measurement failed: $e';
        _measuring = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF172A45),
      title: const Text(
        'Ripple & Noise',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Measures the supply ripple with AC coupling and the 20 MHz '
                'bandwidth limit. The previous channel settings are restored '
                'after the reading.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _channel,
                dropdownColor: const Color(0xFF172A45),
                decoration: _decoration('Channel'),
                items: [
                  for (final channel in widget.channels)
                    DropdownMenuItem(value: channel, child: Text('CH$channel')),
                ],
                onChanged: _measuring
                    ? null
                    : (value) {
                        if (value != null) setState(() => _channel = value);
                      },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _vdiv,
                      enabled: !_measuring,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _decoration('V/div'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _offset,
                      enabled: !_measuring,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: _decoration('Offset (V)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _bandwidthLimit,
                activeColor: Colors.cyanAccent,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  '20 MHz bandwidth limit',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                onChanged: _measuring
                    ? null
                    : (value) =>
                          setState(() => _bandwidthLimit = value ?? false),
              ),
              CheckboxListTile(
                value: _restore,
                activeColor: Colors.cyanAccent,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Restore previous channel settings',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                onChanged: _measuring
                    ? null
                    : (value) => setState(() => _restore = value ?? true),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
              if (_result != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B1B33),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: SelectableText(
                    _result!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _measuring ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _measuring ? null : _measure,
          child: Text(_measuring ? 'Measuring...' : 'Measure'),
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
}
