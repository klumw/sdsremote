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

import '../signal_generator/models.dart';
import 'bode_analysis.dart';
import 'bode_models.dart';

/// Table cell carrying its numeric value and validity so the renderer can
/// highlight the per-column maximum and minimum.
class _PointCell {
  const _PointCell(this.text, this.value, {required this.valid});

  final String text;
  final double? value;
  final bool valid;

  @override
  String toString() => text;
}

/// Generates a PDF report for a completed Bode sweep.
class BodeReport {
  BodeReport._();

  /// Build a [Uint8List] containing the PDF bytes for the Bode report.
  ///
  /// [config] is the sweep configuration that was used for the measurement.
  /// [points] are the measured frequency points.
  /// [chartImageBytes] is the raw PNG bytes of the captured Bode plot.
  /// [deviceName] and [generatorIdentity] are optional device descriptions.
  /// [generatorFamily] selects the device-specific waveform label.
  static Future<Uint8List> generatePdf({
    required BodeConfig config,
    required List<BodePoint> points,
    required Uint8List chartImageBytes,
    String? deviceName,
    String? generatorIdentity,
    SiggenFamily? generatorFamily,
  }) async {
    final pdf = pw.Document();
    final chartImage = pw.MemoryImage(chartImageBytes);
    final analysis = analyzeBode(points);
    final pointExtrema = _columnExtrema(config, points);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // ---- Headline ----
          pw.Center(
            child: pw.Text(
              config.mode == BodeMode.amplitudeSweep
                  ? 'Bode Plot Report - Amplitude Sweep'
                  : 'Bode Plot Report',
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
            data: _buildConfigRows(
              config,
              deviceName,
              generatorIdentity,
              generatorFamily,
            ),
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
          pw.SizedBox(height: 24),

          // ---- Measurement Points ----
          pw.Header(
            text: 'Measurement Points',
            level: 1,
            textStyle: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          if (points.isEmpty)
            pw.Text('No measurement points.')
          else
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 7,
              ),
              cellStyle: const pw.TextStyle(fontSize: 7),
              headerAlignment: pw.Alignment.centerLeft,
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 2,
                vertical: 2,
              ),
              defaultColumnWidth: const pw.FlexColumnWidth(1),
              columnWidths: _pointColumnWidths(config),
              textStyleBuilder: (column, data, rowNum) =>
                  _pointCellStyle(column, data, pointExtrema),
              headers: _buildPointHeaders(config),
              data: _buildPointRows(config, points),
            ),
          pw.SizedBox(height: 24),

          // ---- Automatic Analysis ----
          // The frequency-domain analysis (peak, -3 dB, bandwidth, Q factor)
          // only applies to a frequency sweep.
          if (config.mode == BodeMode.frequencySweep) ...[
            pw.Header(
              text: 'Analysis',
              level: 1,
              textStyle: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 12),
            if (analysis.hasData)
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerAlignment: pw.Alignment.centerLeft,
                cellAlignment: pw.Alignment.centerLeft,
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(3),
                },
                headers: ['Parameter', 'Value'],
                data: _buildAnalysisRows(analysis),
              )
            else
              pw.Text('No valid gain points for an automatic analysis.'),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  /// Column widths of the per-point detail table.
  static Map<int, pw.TableColumnWidth> _pointColumnWidths(BodeConfig config) {
    final columnCount = _buildPointHeaders(config).length;
    return {
      0: const pw.FlexColumnWidth(0.4),
      columnCount - 2: const pw.FlexColumnWidth(0.7),
      columnCount - 1: const pw.FlexColumnWidth(3),
    };
  }

  /// Column headers of the per-point detail table.
  static List<String> _buildPointHeaders(BodeConfig config) {
    if (config.mode == BodeMode.amplitudeSweep) {
      return const [
        '#',
        'Amplitude (Vpp)',
        'Gain (dB)',
        'Vin Vpp (V)',
        'Vout Vpp (V)',
        'Vin Vrms (V)',
        'Vout Vrms (V)',
        'Vpp/Vrms',
        'Valid',
        'Note',
      ];
    }
    return [
      '#',
      'Frequency',
      'Vin Rms (V)',
      'Vout Rms (V)',
      'Gain (dB)',
      if (config.measurePhase) 'Phase (deg)',
      'Valid',
      'Note',
    ];
  }

  /// Builds one row per measurement point, including invalid points and
  /// their diagnostic note.
  static List<List<dynamic>> _buildPointRows(
    BodeConfig config,
    List<BodePoint> points,
  ) {
    final rows = <List<dynamic>>[];
    for (var index = 0; index < points.length; index++) {
      final point = points[index];
      final valid = point.valid;
      if (config.mode == BodeMode.amplitudeSweep) {
        rows.add([
          '${index + 1}',
          _PointCell(
            _fmtNumber(point.amplitudeVpp ?? double.nan),
            point.amplitudeVpp,
            valid: valid,
          ),
          _PointCell(
            _fmtNumber(point.gainDb ?? double.nan),
            point.gainDb,
            valid: valid,
          ),
          _PointCell(
            _fmtNumber(point.vinVpp ?? double.nan),
            point.vinVpp,
            valid: valid,
          ),
          _PointCell(
            _fmtNumber(point.voutVpp ?? double.nan),
            point.voutVpp,
            valid: valid,
          ),
          _PointCell(
            _fmtNumber(point.vinRms ?? double.nan),
            point.vinRms,
            valid: valid,
          ),
          _PointCell(
            _fmtNumber(point.voutRms ?? double.nan),
            point.voutRms,
            valid: valid,
          ),
          _PointCell(
            _fmtNumber(point.voutVppRmsRatio ?? double.nan),
            point.voutVppRmsRatio,
            valid: valid,
          ),
          valid ? 'yes' : 'no',
          point.note ?? '',
        ]);
      } else {
        rows.add([
          '${index + 1}',
          _PointCell(
            _fmtFrequency(point.frequencyHz),
            point.frequencyHz,
            valid: valid,
          ),
          _PointCell(
            _fmtNumber(point.vinRms ?? double.nan),
            point.vinRms,
            valid: valid,
          ),
          _PointCell(
            _fmtNumber(point.voutRms ?? double.nan),
            point.voutRms,
            valid: valid,
          ),
          _PointCell(
            _fmtNumber(point.gainDb ?? double.nan),
            point.gainDb,
            valid: valid,
          ),
          if (config.measurePhase)
            _PointCell(
              _fmtNumber(point.phaseDeg ?? double.nan),
              point.phaseDeg,
              valid: valid,
            ),
          valid ? 'yes' : 'no',
          point.note ?? '',
        ]);
      }
    }
    return rows;
  }

  /// Minimum and maximum of every numeric point column, considering valid
  /// points only. Invalid points stay in the table but do not define the
  /// highlighted extrema.
  static Map<int, (double, double)> _columnExtrema(
    BodeConfig config,
    List<BodePoint> points,
  ) {
    final values = <int, List<double>>{};
    void add(int column, double? value) {
      if (value == null || !value.isFinite) return;
      values.putIfAbsent(column, () => <double>[]).add(value);
    }

    for (final point in points) {
      if (!point.valid) continue;
      if (config.mode == BodeMode.amplitudeSweep) {
        add(1, point.amplitudeVpp);
        add(2, point.gainDb);
        add(3, point.vinVpp);
        add(4, point.voutVpp);
        add(5, point.vinRms);
        add(6, point.voutRms);
        add(7, point.voutVppRmsRatio);
      } else {
        add(1, point.frequencyHz);
        add(2, point.vinRms);
        add(3, point.voutRms);
        add(4, point.gainDb);
        if (config.measurePhase) add(5, point.phaseDeg);
      }
    }

    return {
      for (final entry in values.entries)
        entry.key: (entry.value.reduce(math.min), entry.value.reduce(math.max)),
    };
  }

  /// Green for a column maximum, red for a column minimum. Cells of invalid
  /// points and columns with a single distinct value stay uncoloured.
  static pw.TextStyle? _pointCellStyle(
    int column,
    dynamic data,
    Map<int, (double, double)> extrema,
  ) {
    if (data is! _PointCell || !data.valid || data.value == null) return null;
    final range = extrema[column];
    if (range == null) return null;
    final min = range.$1;
    final max = range.$2;
    if (max - min <= 1e-9) return null;

    final value = data.value!;
    if ((value - max).abs() <= 1e-9) {
      return const pw.TextStyle(fontSize: 7, color: PdfColors.green800);
    }
    if ((value - min).abs() <= 1e-9) {
      return const pw.TextStyle(fontSize: 7, color: PdfColors.red800);
    }
    return null;
  }

  /// Builds the table rows describing the sweep configuration.
  static List<List<String>> _buildConfigRows(
    BodeConfig config,
    String? deviceName,
    String? generatorIdentity,
    SiggenFamily? generatorFamily,
  ) {
    final amplitudeSweep = config.mode == BodeMode.amplitudeSweep;
    final rows = <List<String>>[
      ['Sweep Type', amplitudeSweep ? 'Amplitude Sweep' : 'Frequency Sweep'],
    ];
    if (amplitudeSweep) {
      rows.addAll([
        ['Frequency', _fmtFrequency(config.sweepFrequencyHz)],
        ['Start Amplitude', '${_fmtNumber(config.startAmplitudeVpp)} Vpp'],
        ['Stop Amplitude', '${_fmtNumber(config.stopAmplitudeVpp)} Vpp'],
        ['Points', '${config.pointCount}'],
        [
          'Spacing',
          config.amplitudeSpacing == BodeSpacing.logarithmic
              ? 'Logarithmic'
              : 'Linear',
        ],
        ['Offset', '${_fmtNumber(config.offsetV)} V'],
        [
          'Waveform',
          config.waveform.displayNameFor(
            generatorFamily ?? SiggenFamily.jds6600,
          ),
        ],
        ['Settling Time', '${config.settling.inMilliseconds} ms'],
        ['Vin Channel', 'CH${config.vinChannel}'],
        ['Vout Channel', 'CH${config.voutChannel}'],
        ['Generator Channel', 'CH${config.generatorChannel}'],
      ]);
    } else {
      rows.addAll([
        ['Start Frequency', _fmtFrequency(config.startFrequencyHz)],
        ['Stop Frequency', _fmtFrequency(config.stopFrequencyHz)],
        ['Points', '${config.pointCount}'],
        [
          'Spacing',
          config.spacing == BodeSpacing.logarithmic ? 'Logarithmic' : 'Linear',
        ],
        ['Amplitude', '${_fmtNumber(config.amplitudeVpp)} Vpp'],
        ['Offset', '${_fmtNumber(config.offsetV)} V'],
        [
          'Waveform',
          config.waveform.displayNameFor(
            generatorFamily ?? SiggenFamily.jds6600,
          ),
        ],
        ['Settling Time', '${config.settling.inMilliseconds} ms'],
        ['Phase Measurement', config.measurePhase ? 'Enabled' : 'Disabled'],
        ['Vin Channel', 'CH${config.vinChannel}'],
        ['Vout Channel', 'CH${config.voutChannel}'],
        ['Generator Channel', 'CH${config.generatorChannel}'],
      ]);
    }
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

    if (config.mode == BodeMode.amplitudeSweep) {
      final voutVpp = valid
          .map((point) => point.voutVpp)
          .whereType<double>()
          .where((value) => value.isFinite)
          .toList();
      if (voutVpp.isNotEmpty) {
        rows.add([
          'Vout Vpp Range',
          '${_fmtValue(voutVpp.reduce(math.min), 'Vpp')} to '
              '${_fmtValue(voutVpp.reduce(math.max), 'Vpp')}',
        ]);
      }
      final voutRms = valid
          .map((point) => point.voutRms)
          .whereType<double>()
          .where((value) => value.isFinite)
          .toList();
      if (voutRms.isNotEmpty) {
        rows.add([
          'Vout Vrms Range',
          '${_fmtValue(voutRms.reduce(math.min), 'V')} to '
              '${_fmtValue(voutRms.reduce(math.max), 'V')}',
        ]);
      }
      final ratios = valid
          .map((point) => point.voutVppRmsRatio)
          .whereType<double>()
          .where((value) => value.isFinite)
          .toList();
      if (ratios.isNotEmpty) {
        rows.add([
          'Vpp/Vrms Range',
          '${_fmtNumber(ratios.reduce(math.min))} to '
              '${_fmtNumber(ratios.reduce(math.max))}',
        ]);
      }
      return rows;
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
          '${_fmtValue(phases.reduce(math.min), 'deg')} to '
              '${_fmtValue(phases.reduce(math.max), 'deg')}',
        ]);
      }
    }

    return rows;
  }

  /// Builds the table rows of the automatic gain analysis.
  static List<List<String>> _buildAnalysisRows(BodeAnalysisSummary analysis) {
    final rows = <List<String>>[];
    if (analysis.peakGainDb != null && analysis.peakFrequencyHz != null) {
      rows.add([
        'Peak Gain',
        '${_fmtValue(analysis.peakGainDb!, 'dB')} at '
            '${_fmtFrequency(analysis.peakFrequencyHz!)}',
      ]);
    }
    if (analysis.minus3DbFrequencyHz != null) {
      rows.add([
        '-3 dB Frequency',
        _fmtFrequency(analysis.minus3DbFrequencyHz!),
      ]);
    }
    if (analysis.lowerMinus3DbFrequencyHz != null) {
      rows.add([
        'Lower -3 dB Frequency',
        _fmtFrequency(analysis.lowerMinus3DbFrequencyHz!),
      ]);
    }
    if (analysis.bandwidthHz != null) {
      rows.add(['Bandwidth', _fmtFrequency(analysis.bandwidthHz!)]);
    }
    if (analysis.qFactor != null) {
      rows.add(['Q Factor', _fmtNumber(analysis.qFactor!)]);
    }
    if (analysis.unityCrossoverHz != null) {
      rows.add(['0 dB Crossover', _fmtFrequency(analysis.unityCrossoverHz!)]);
    }
    if (analysis.notes.isNotEmpty) {
      rows.add(['Notes', analysis.notes.join('; ')]);
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
