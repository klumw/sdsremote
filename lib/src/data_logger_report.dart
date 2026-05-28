/// PDF report generator for the Data Logger feature.
///
/// Produces a formatted multi-page PDF document containing:
/// - A headline
/// - An image of the recorded data logging chart
/// - Start and end values for all selected measurement parameters
/// - Total recording time with automatic unit scaling (s / min / h)

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'data_logger_models.dart';

/// Generates a PDF report for a completed Data Logger recording session.
class DataLoggerReport {
  DataLoggerReport._();

  /// Build a [Uint8List] containing the PDF bytes for the data logger report.
  ///
  /// [points] must contain at least two data points.
  /// [config] is the active configuration that was used for the recording.
  /// [chartImageBytes] is the raw PNG bytes of the captured chart widget.
  static Future<Uint8List> generatePdf({
    required List<DataLoggerPoint> points,
    required DataLoggerConfig config,
    required Uint8List chartImageBytes,
  }) async {
    final pdf = pw.Document();
    final chartImage = pw.MemoryImage(chartImageBytes);

    final first = points.first;
    final last = points.last;

    // Build the measurement rows for all enabled parameters.
    final measurementRows = _buildMeasurementRows(config, points, first, last);

    // Format total recording time.
    final totalSeconds = config.durationMinutes * 60.0;
    final timeStr = _formatDuration(totalSeconds);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // ---- Headline ----
          pw.Center(
            child: pw.Text(
              'Data Logger Report',
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),

          // ---- Report Name (description) ----
          if (config.description.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              'Report Name: ${config.description}',
              style: const pw.TextStyle(
                fontSize: 12,
              ),
            ),
          ],
          pw.SizedBox(height: 20),

          // ---- Chart Image ----
          pw.Center(
            child: pw.Container(
              width: double.infinity,
              constraints: const pw.BoxConstraints(maxHeight: 400),
              child: pw.Image(chartImage, fit: pw.BoxFit.contain),
            ),
          ),
          pw.SizedBox(height: 24),

          // ---- Measurement Values Table ----
          pw.Header(
            text: 'Measurement Values',
            level: 1,
            textStyle: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerAlignment: pw.Alignment.centerLeft,
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.2),
            },
            headers: ['Parameter', 'Start', 'End', 'Min', 'Max'],
            data: measurementRows,
          ),
          pw.SizedBox(height: 24),

          // ---- Total Recording Time ----
          pw.Text(
            'Total Recording Time: $timeStr',
            style: pw.TextStyle(fontSize: 14),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Builds the table data rows for the enabled measurement parameters.
  ///
  /// Each row contains: Parameter, Start, End, Min, Max.
  static List<List<String>> _buildMeasurementRows(
    DataLoggerConfig config,
    List<DataLoggerPoint> points,
    DataLoggerPoint first,
    DataLoggerPoint last,
  ) {
    final rows = <List<String>>[];

    if (config.ch1VppEnabled) {
      rows.add([
        'CH1 Vpp',
        _fmtValue(first.ch1Vpp, 'V'),
        _fmtValue(last.ch1Vpp, 'V'),
        _fmtValue(_minValue(points.map((p) => p.ch1Vpp)), 'V'),
        _fmtValue(_maxValue(points.map((p) => p.ch1Vpp)), 'V'),
      ]);
    }
    if (config.ch1MeanEnabled) {
      rows.add([
        'CH1 Mean',
        _fmtValue(first.ch1Mean, 'V'),
        _fmtValue(last.ch1Mean, 'V'),
        _fmtValue(_minValue(points.map((p) => p.ch1Mean)), 'V'),
        _fmtValue(_maxValue(points.map((p) => p.ch1Mean)), 'V'),
      ]);
    }
    if (config.ch1RmsEnabled) {
      rows.add([
        'CH1 Rms',
        _fmtValue(first.ch1Rms, 'V'),
        _fmtValue(last.ch1Rms, 'V'),
        _fmtValue(_minValue(points.map((p) => p.ch1Rms)), 'V'),
        _fmtValue(_maxValue(points.map((p) => p.ch1Rms)), 'V'),
      ]);
    }
    if (config.ch1DutyEnabled) {
      rows.add([
        'CH1 Duty',
        _fmtDuty(first.ch1Duty),
        _fmtDuty(last.ch1Duty),
        _fmtDuty(_minValue(points.map((p) => p.ch1Duty))),
        _fmtDuty(_maxValue(points.map((p) => p.ch1Duty))),
      ]);
    }
    if (config.ch1FreqEnabled) {
      rows.add([
        'CH1 Freq',
        _fmtFreq(first.ch1Freq),
        _fmtFreq(last.ch1Freq),
        _fmtFreq(_minValue(points.map((p) => p.ch1Freq))),
        _fmtFreq(_maxValue(points.map((p) => p.ch1Freq))),
      ]);
    }
    if (config.ch2VppEnabled) {
      rows.add([
        'CH2 Vpp',
        _fmtValue(first.ch2Vpp, 'V'),
        _fmtValue(last.ch2Vpp, 'V'),
        _fmtValue(_minValue(points.map((p) => p.ch2Vpp)), 'V'),
        _fmtValue(_maxValue(points.map((p) => p.ch2Vpp)), 'V'),
      ]);
    }
    if (config.ch2MeanEnabled) {
      rows.add([
        'CH2 Mean',
        _fmtValue(first.ch2Mean, 'V'),
        _fmtValue(last.ch2Mean, 'V'),
        _fmtValue(_minValue(points.map((p) => p.ch2Mean)), 'V'),
        _fmtValue(_maxValue(points.map((p) => p.ch2Mean)), 'V'),
      ]);
    }
    if (config.ch2RmsEnabled) {
      rows.add([
        'CH2 Rms',
        _fmtValue(first.ch2Rms, 'V'),
        _fmtValue(last.ch2Rms, 'V'),
        _fmtValue(_minValue(points.map((p) => p.ch2Rms)), 'V'),
        _fmtValue(_maxValue(points.map((p) => p.ch2Rms)), 'V'),
      ]);
    }
    if (config.ch2DutyEnabled) {
      rows.add([
        'CH2 Duty',
        _fmtDuty(first.ch2Duty),
        _fmtDuty(last.ch2Duty),
        _fmtDuty(_minValue(points.map((p) => p.ch2Duty))),
        _fmtDuty(_maxValue(points.map((p) => p.ch2Duty))),
      ]);
    }
    if (config.ch2FreqEnabled) {
      rows.add([
        'CH2 Freq',
        _fmtFreq(first.ch2Freq),
        _fmtFreq(last.ch2Freq),
        _fmtFreq(_minValue(points.map((p) => p.ch2Freq))),
        _fmtFreq(_maxValue(points.map((p) => p.ch2Freq))),
      ]);
    }

    return rows;
  }

  /// Returns the minimum non-null double from the iterable, or null if empty.
  static double? _minValue(Iterable<double?> values) {
    double? min;
    for (final v in values) {
      if (v != null && (min == null || v < min)) min = v;
    }
    return min;
  }

  /// Returns the maximum non-null double from the iterable, or null if empty.
  static double? _maxValue(Iterable<double?> values) {
    double? max;
    for (final v in values) {
      if (v != null && (max == null || v > max)) max = v;
    }
    return max;
  }

  /// Format a voltage value, returning "N/A" if null.
  static String _fmtValue(double? value, String unit) {
    if (value == null) return 'N/A';
    return '${value.toStringAsFixed(3)} $unit';
  }

  /// Format a duty cycle value, returning "N/A" if null.
  static String _fmtDuty(double? value) {
    if (value == null) return 'N/A';
    return '${value.toStringAsFixed(1)} %';
  }

  /// Format a frequency value with SI prefix, returning "N/A" if null.
  static String _fmtFreq(double? value) {
    if (value == null) return 'N/A';
    final abs = value.abs();
    if (abs >= 1e6) return '${(value / 1e6).toStringAsFixed(2)} MHz';
    if (abs >= 1e3) return '${(value / 1e3).toStringAsFixed(2)} kHz';
    return '${value.toStringAsFixed(1)} Hz';
  }

  /// Formats a duration in seconds to a human-readable string.
  ///
  /// - Less than 120 seconds → "X seconds"
  /// - Less than 7200 seconds (2 hours) → "X min Y s"
  /// - 7200 seconds or more → "X h Y min"
  static String _formatDuration(double totalSeconds) {
    final s = totalSeconds.round();
    if (s < 120) {
      return '$s seconds';
    } else if (s < 7200) {
      final min = s ~/ 60;
      final sec = s % 60;
      if (sec == 0) return '$min min';
      return '$min min $sec s';
    } else {
      final h = s ~/ 3600;
      final min = (s % 3600) ~/ 60;
      if (min == 0) return '$h h';
      return '$h h $min min';
    }
  }
}
