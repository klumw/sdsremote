import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calibration/sensor_calibration.dart';

/// Supplies measured sensor values from the last Data Logger recording.
typedef CalibrationPrefill = List<(String label, double value)> Function();

/// Dialog for a two-point (or multi-point) linear sensor calibration.
///
/// The user enters measured values (for example the scope's mean voltage) and
/// the known reference values. The dialog fits `reference = slope * measured +
/// intercept`, reports R² and offers an Arduino/ESP32 correction snippet.
class SensorCalibrationDialog extends StatefulWidget {
  /// Optional source of measured values from the Data Logger. When null, the
  /// "Add from Data Logger" button is hidden.
  final CalibrationPrefill? readLoggerValues;

  const SensorCalibrationDialog({super.key, this.readLoggerValues});

  @override
  State<SensorCalibrationDialog> createState() =>
      _SensorCalibrationDialogState();
}

class _CalibrationRow {
  final TextEditingController measured;
  final TextEditingController reference;
  final String? label;

  _CalibrationRow({String measured = '', this.label})
    : measured = TextEditingController(text: measured),
      reference = TextEditingController();

  void dispose() {
    measured.dispose();
    reference.dispose();
  }
}

class _SensorCalibrationDialogState extends State<SensorCalibrationDialog> {
  final List<_CalibrationRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _rows
      ..add(_CalibrationRow())
      ..add(_CalibrationRow());
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _addRow({String measured = '', String? label}) {
    setState(
      () => _rows.add(_CalibrationRow(measured: measured, label: label)),
    );
  }

  void _removeRow(int index) {
    setState(() {
      _rows.removeAt(index).dispose();
    });
  }

  Future<void> _addFromDataLogger() async {
    final reader = widget.readLoggerValues;
    if (reader == null) return;
    final values = reader();
    if (values.isEmpty) {
      _showMessage('The last Data Logger recording has no statistics.');
      return;
    }
    final selected = await showDialog<(String, double)>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xFF172A45),
        title: const Text(
          'Add measured value from Data Logger',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        children: [
          for (final entry in values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, entry),
              child: Text(
                '${entry.$1}: ${_formatValue(entry.$2)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    _addRow(measured: _formatValue(selected.$2), label: selected.$1);
  }

  String _formatValue(double value) {
    final text = value.abs() >= 1000 || (value != 0 && value.abs() < 0.01)
        ? value.toStringAsExponential(4)
        : value.toStringAsFixed(4);
    return text;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  /// Parses the rows; returns the valid pairs or an error message.
  ({List<(double, double)> points, String? error}) _parseRows() {
    final points = <(double, double)>[];
    for (final row in _rows) {
      final measuredText = row.measured.text.trim();
      final referenceText = row.reference.text.trim();
      if (measuredText.isEmpty && referenceText.isEmpty) continue;
      final measured = double.tryParse(measuredText.replaceAll(',', '.'));
      final reference = double.tryParse(referenceText.replaceAll(',', '.'));
      if (measured == null ||
          !measured.isFinite ||
          reference == null ||
          !reference.isFinite) {
        return (
          points: const [],
          error: 'Complete every used row with two numbers.',
        );
      }
      points.add((measured, reference));
    }
    if (points.length < 2) {
      return (
        points: const [],
        error: 'Enter at least two calibration points.',
      );
    }
    return (points: points, error: null);
  }

  Future<void> _copySnippet(CalibrationResult result) async {
    await Clipboard.setData(ClipboardData(text: buildArduinoSnippet(result)));
    _showMessage('Calibration snippet copied to the clipboard.');
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parseRows();
    final result = parsed.error == null
        ? linearCalibration(parsed.points)
        : null;
    final error =
        parsed.error ??
        (result == null ? 'The measured values must differ.' : null);

    return AlertDialog(
      backgroundColor: const Color(0xFF172A45),
      title: const Text(
        'Sensor Calibration',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the measured sensor output and the known reference '
                'value for each calibration point. The fit maps measured '
                'values to reference values.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Measured',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Reference',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
              const SizedBox(height: 4),
              for (var index = 0; index < _rows.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildRow(index),
                ),
              Text(
                error ?? '',
                style: TextStyle(
                  color: error == null ? Colors.transparent : Colors.redAccent,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton.icon(
                    key: const ValueKey('add_calibration_point'),
                    onPressed: _addRow,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add point'),
                  ),
                  if (widget.readLoggerValues != null) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      key: const ValueKey('add_calibration_logger'),
                      onPressed: _addFromDataLogger,
                      icon: const Icon(Icons.logo_dev, size: 16),
                      label: const Text('From Data Logger'),
                    ),
                  ],
                ],
              ),
              if (result != null) ...[
                const SizedBox(height: 12),
                _buildResult(result),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: result == null ? null : () => _copySnippet(result),
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy snippet'),
        ),
      ],
    );
  }

  Widget _buildRow(int index) {
    final row = _rows[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The optional Data Logger label spans the whole row. Keeping it out
        // of the measured column prevents it from pushing that field down and
        // keeps Measured and Reference vertically aligned.
        if (row.label != null) ...[
          Text(
            row.label!,
            style: const TextStyle(color: Colors.cyanAccent, fontSize: 10),
          ),
          const SizedBox(height: 2),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: ValueKey('measured_$index'),
                controller: row.measured,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: _decoration('Measured'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: ValueKey('reference_$index'),
                controller: row.reference,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: _decoration('Reference'),
              ),
            ),
            IconButton(
              tooltip: 'Remove point',
              onPressed: _rows.length > 1 ? () => _removeRow(index) : null,
              icon: const Icon(Icons.delete_outline, size: 18),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResult(CalibrationResult result) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1B33),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Slope: ${result.slope.toStringAsFixed(6)}   '
            'Intercept: ${result.intercept.toStringAsFixed(6)}   '
            'R²: ${result.rSquared.toStringAsFixed(4)}   '
            'Points: ${result.pointCount}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SelectableText(
            buildArduinoSnippet(result),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontFamily: 'monospace',
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
    enabledBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: Colors.white24),
    ),
    focusedBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: Colors.cyanAccent),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    isDense: true,
  );
}
