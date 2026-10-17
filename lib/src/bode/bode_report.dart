/// PDF report generator for the Bode Plot feature.
///
/// Produces a formatted PDF document containing:
/// - A headline
/// - The optional report name from the sweep configuration
/// - An image of the Bode plot
/// - The sweep configuration data
/// - A short summary of the measured values
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'bode_models.dart';

/// Generates a PDF report for a completed Bode sweep.
class BodeReport {
  BodeReport._();

  /// Build a [Uint8List] containing the PDF bytes for the Bode report.
  ///
  /// [config] is the sweep configuration that was used for the measurement.
  /// [points] are the measured frequency points.
  /// [chartImageBytes] is the raw PNG bytes of the captured Bode plot.
  /// [deviceName] and [generatorIdentity] are optional device descriptions.
  static Future<Uint8List> generatePdf({
    required BodeConfig config,
    required List<BodePoint> points,
    required Uint8List chartImageBytes,
    String? deviceName,
    String? generatorIdentity,
  }) async {
    final pdf = pw.Document();
    final chartImage = pw.MemoryImage(chartImageBytes);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // ---- Headline ----
          pw.Center(
            child: pw.Text(
              'Bode Plot Report',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
          ),

          // ---- Report Name (description) ----
          if (config.reportName.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              'Report Name: ${config.reportName}',
              style: const pw.TextStyle(fontSize: 12),
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

          // ---- Sweep Configuration ----
          pw.Header(
            text: 'Sweep Configuration',
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
              1: const pw.FlexColumnWidth(3),
            },
            headers: ['Parameter', 'Value'],
            data: _buildConfigRows(config, deviceName, generatorIdentity),
          ),
          pw.SizedBox(height: 24),

          // ---- Measurement Results ----
          pw.Header(
            text: 'Measurement Results',
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
              1: const pw.FlexColumnWidth(3),
            },
            headers: ['Parameter', 'Value'],
            data: _buildResultRows(config, points),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  /// Builds the table rows describing the sweep configuration.
  static List<List<String>> _buildConfigRows(
    BodeConfig config,
    String? deviceName,
    String? generatorIdentity,
  ) {
    final rows = <List<String>>[
      ['Start Frequency', _fmtFrequency(config.startFrequencyHz)],
      ['Stop Frequency', _fmtFrequency(config.stopFrequencyHz)],
      ['Points', '${config.pointCount}'],
      [
        'Spacing',
        config.spacing == BodeSpacing.logarithmic ? 'Logarithmic' : 'Linear',
      ],
      ['Amplitude', '${_fmtNumber(config.amplitudeVpp)} Vpp'],
      ['Offset', '${_fmtNumber(config.offsetV)} V'],
      ['Waveform', config.waveform.displayName],
      ['Settling Time', '${config.settling.inMilliseconds} ms'],
      ['Phase Measurement', config.measurePhase ? 'Enabled' : 'Disabled'],
      ['Vin Channel', 'CH${config.vinChannel}'],
      ['Vout Channel', 'CH${config.voutChannel}'],
      ['Generator Channel', 'CH${config.generatorChannel}'],
    ];
    if (deviceName != null && deviceName.isNotEmpty) {
      rows.add(['Oscilloscope', deviceName]);
    }
    if (generatorIdentity != null && generatorIdentity.isNotEmpty) {
      rows.add(['Signal Generator', generatorIdentity]);
    }
    return rows;
  }

  /// Builds the table rows summarising the measured sweep values.
  static List<List<String>> _buildResultRows(
    BodeConfig config,
    List<BodePoint> points,
  ) {
    final valid = points
        .where(
          (point) =>
              point.valid && point.gainDb != null && point.gainDb!.isFinite,
        )
        .toList();

    final rows = <List<String>>[
      ['Points Measured', '${points.length}'],
      ['Valid Points', '${valid.length}'],
    ];

    final gains = valid.map((point) => point.gainDb!).toList();
    if (gains.isNotEmpty) {
      rows.add([
        'Gain Range',
        '${_fmtValue(gains.reduce(math.min), 'dB')} to '
            '${_fmtValue(gains.reduce(math.max), 'dB')}',
      ]);
    }

    if (config.measurePhase) {
      final phases = points
          .where(
            (point) =>
                point.valid &&
                point.phaseDeg != null &&
                point.phaseDeg!.isFinite,
          )
          .map((point) => point.phaseDeg!)
          .toList();
      if (phases.isNotEmpty) {
        rows.add([
          'Phase Range',
          '${_fmtValue(phases.reduce(math.min), '°')} to '
              '${_fmtValue(phases.reduce(math.max), '°')}',
        ]);
      }
    }

    return rows;
  }

  /// Format a numeric value with its [unit], leaving out trailing zeros.
  static String _fmtValue(double value, String unit) =>
      '${_fmtNumber(value)} $unit';

  /// Format a frequency value with an appropriate SI prefix.
  static String _fmtFrequency(double value) {
    if (!value.isFinite) return 'N/A';
    final abs = value.abs();
    if (abs >= 1e6) return '${_fmtNumber(value / 1e6)} MHz';
    if (abs >= 1e3) return '${_fmtNumber(value / 1e3)} kHz';
    return '${_fmtNumber(value)} Hz';
  }

  /// Format a number with up to three decimals, dropping trailing zeros.
  static String _fmtNumber(double value) {
    if (!value.isFinite) return 'N/A';
    var text = value.toStringAsFixed(3);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
    return text == '-0' ? '0' : text;
  }
}
