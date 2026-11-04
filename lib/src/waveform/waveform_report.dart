/// PDF measurement report for an acquired waveform.
///
/// Contains the chart image, the automatic measurements per channel, the
/// spectrum analysis (window, metrics, peak markers), the device settings,
/// the reference comparison and the mask-test result. The class mirrors
/// `DataLoggerReport` and `BodeReport`; it is pure computation and returns the
/// PDF bytes without touching the file system.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../spectrum/spectrum_models.dart';
import '../spectrum/windows.dart';
import 'waveform_compare.dart';
import 'waveform_mask.dart';
import 'waveform_measurements.dart';
import 'waveform_models.dart';

/// Generates a PDF report for the currently displayed waveform.
class WaveformReport {
  WaveformReport._();

  /// Builds the PDF bytes.
  ///
  /// [measurements] is keyed by channel (`'ch1'` … `'ch4'`); missing channels
  /// are omitted. [comparison] and [maskResult] are optional and only shown
  /// when they contain data. [timestamp] defaults to the current time.
  static Future<Uint8List> generatePdf({
    required Uint8List chartImageBytes,
    required DeviceParams params,
    required Map<String, WaveformMeasurements> measurements,
    ComparisonMetrics? comparison,
    MaskResult? maskResult,
    SpectrumResult? spectrum,
    String? agentAnalysis,
    String? reportName,
    String deviceName = '',
    DateTime? timestamp,
  }) async {
    final pdf = pw.Document();
    final chartImage = pw.MemoryImage(chartImageBytes);
    final createdAt = timestamp ?? DateTime.now();
    final ordered = _orderedMeasurements(measurements);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              'Waveform Measurement Report',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
          ),
          if (reportName != null && reportName.trim().isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text(
              'Report Name: ${reportName.trim()}',
              style: const pw.TextStyle(fontSize: 12),
            ),
          ],
          pw.SizedBox(height: 8),
          pw.Text(
            'Date: ${_fmtTimestamp(createdAt)}',
            style: const pw.TextStyle(fontSize: 12),
          ),
          if (deviceName.isNotEmpty)
            pw.Text(
              'Device: $deviceName',
              style: const pw.TextStyle(fontSize: 12),
            ),
          pw.SizedBox(height: 20),

          // ---- Chart image ----
          pw.Center(
            child: pw.Container(
              width: double.infinity,
              constraints: const pw.BoxConstraints(maxHeight: 400),
              child: pw.Image(chartImage, fit: pw.BoxFit.contain),
            ),
          ),
          pw.SizedBox(height: 24),

          // ---- Measurements ----
          pw.Header(
            text: 'Measurements',
            level: 1,
            textStyle: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          if (ordered.isEmpty)
            pw.Text('No measurements available.')
          else ...[
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerAlignment: pw.Alignment.centerLeft,
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FlexColumnWidth(0.8),
                1: const pw.FlexColumnWidth(1.1),
                2: const pw.FlexColumnWidth(1.1),
                3: const pw.FlexColumnWidth(1.2),
                4: const pw.FlexColumnWidth(0.9),
                5: const pw.FlexColumnWidth(1.1),
                6: const pw.FlexColumnWidth(1.1),
                7: const pw.FlexColumnWidth(1.0),
              },
              headers: [
                'CH',
                'Vpp',
                'RMS',
                'Frequency',
                'Duty',
                'Rise',
                'Fall',
                'Overshoot',
              ],
              data: [
                for (final entry in ordered)
                  [
                    entry.key.toUpperCase(),
                    _fmtVoltage(entry.value.vPp),
                    _fmtVoltage(entry.value.vRms),
                    _fmtFrequency(entry.value.frequencyHz),
                    _fmtPercent(entry.value.dutyPercent),
                    _fmtTime(entry.value.riseTimeSeconds),
                    _fmtTime(entry.value.fallTimeSeconds),
                    _fmtPercent(entry.value.overshootPercent),
                  ],
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Header(
              text: 'Levels and Timing',
              level: 2,
              textStyle: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerAlignment: pw.Alignment.centerLeft,
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FlexColumnWidth(0.8),
                1: const pw.FlexColumnWidth(1.1),
                2: const pw.FlexColumnWidth(1.1),
                3: const pw.FlexColumnWidth(1.1),
                4: const pw.FlexColumnWidth(1.1),
                5: const pw.FlexColumnWidth(1.1),
                6: const pw.FlexColumnWidth(1.1),
                7: const pw.FlexColumnWidth(0.9),
                8: const pw.FlexColumnWidth(0.9),
                9: const pw.FlexColumnWidth(1.1),
              },
              headers: [
                'CH',
                'Vmax',
                'Vmin',
                'Vmean',
                'Top',
                'Base',
                'Pulse',
                'Periods',
                'Samples',
                'Delta t',
              ],
              data: [
                for (final entry in ordered)
                  [
                    entry.key.toUpperCase(),
                    _fmtVoltage(entry.value.vMax),
                    _fmtVoltage(entry.value.vMin),
                    _fmtVoltage(entry.value.vMean),
                    _fmtVoltage(entry.value.vTop),
                    _fmtVoltage(entry.value.vBase),
                    _fmtTime(entry.value.pulseWidthSeconds),
                    '${entry.value.periodCount}',
                    '${entry.value.sampleCount}',
                    _fmtTime(entry.value.sampleIntervalSeconds),
                  ],
              ],
            ),
          ],
          pw.SizedBox(height: 24),

          // ---- Spectrum analysis ----
          ..._spectrumSection(spectrum),
          pw.SizedBox(height: 24),

          // ---- Device parameters ----
          pw.Header(
            text: 'Device Parameters',
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
              1: const pw.FlexColumnWidth(1.4),
            },
            headers: ['Parameter', 'Value'],
            data: _deviceParameterRows(params),
          ),
          pw.SizedBox(height: 24),

          // ---- Reference and mask ----
          pw.Header(
            text: 'Reference and Mask',
            level: 1,
            textStyle: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          ..._referenceRows(comparison, maskResult),
          ..._agentAnalysisSection(agentAnalysis),
        ],
      ),
    );

    return pdf.save();
  }

  static List<MapEntry<String, WaveformMeasurements>> _orderedMeasurements(
    Map<String, WaveformMeasurements> measurements,
  ) => [
    for (final channel in const ['ch1', 'ch2', 'ch3', 'ch4'])
      if (measurements[channel] != null)
        MapEntry(channel, measurements[channel]!),
  ];

  static List<pw.Widget> _spectrumSection(SpectrumResult? spectrum) {
    final widgets = <pw.Widget>[
      pw.Header(
        text: 'Spectrum Analysis',
        level: 1,
        textStyle: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 12),
    ];
    if (spectrum == null || spectrum.traces.isEmpty) {
      widgets.add(pw.Text('No spectrum data available.'));
      return widgets;
    }

    for (var i = 0; i < spectrum.traces.length; i++) {
      final trace = spectrum.traces[i];
      final color = _spectrumColors[i % _spectrumColors.length];
      widgets.add(
        pw.Header(
          text: '${trace.channel.toUpperCase()} - Spectrum',
          level: 2,
          textStyle: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
      );
      widgets.add(
        pw.Text(
          'Window: ${_windowLabel(spectrum.settings.window)}  |  '
          'FFT size: ${trace.fftSize}  |  '
          'Sample rate: ${_fmtSi(trace.sampleRate, 'Sa/s')}  |  '
          'Resolution: ${_fmtFrequency(trace.resolutionHz)}  |  '
          'Full scale: ${_fmtVoltage(trace.fullScaleVolts)}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      );
      widgets.add(pw.SizedBox(height: 8));

      final chart = _spectrumChart(trace, color);
      if (chart != null) {
        widgets.add(pw.SizedBox(height: 160, child: chart));
        widgets.add(pw.SizedBox(height: 8));
      }

      widgets.add(
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerAlignment: pw.Alignment.centerLeft,
          cellAlignment: pw.Alignment.centerLeft,
          columnWidths: {
            0: const pw.FlexColumnWidth(1.4),
            1: const pw.FlexColumnWidth(2.0),
          },
          headers: ['Metric', 'Value'],
          data: _spectrumMetricRows(trace.metrics),
        ),
      );

      if (trace.peaks.isNotEmpty) {
        widgets.add(pw.SizedBox(height: 8));
        widgets.add(
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerAlignment: pw.Alignment.centerLeft,
            cellAlignment: pw.Alignment.centerLeft,
            columnWidths: {
              0: const pw.FlexColumnWidth(0.5),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.0),
              4: const pw.FlexColumnWidth(1.0),
            },
            headers: ['#', 'Frequency', 'Amplitude', 'dBFS', 'dBc'],
            data: [
              for (final peak in trace.peaks)
                [
                  '${peak.marker}',
                  _fmtFrequency(peak.frequencyHz),
                  _fmtVoltage(peak.amplitudeVpk),
                  _fmtDb(peak.dbfs),
                  _fmtDb(peak.relativeToFundamentalDb),
                ],
            ],
          ),
        );
      }
      widgets.add(pw.SizedBox(height: 16));
    }
    return widgets;
  }

  static pw.Widget? _spectrumChart(SpectrumTrace trace, PdfColor color) {
    final length = trace.dbfs.length;
    if (length < 2 || trace.sampleRate <= 0) return null;

    final nyquist = trace.sampleRate / 2;
    if (nyquist <= 0) return null;

    final points = <pw.PointChartValue>[];
    final step = (length / 600).ceil();
    for (var i = 0; i < length; i += step) {
      points.add(
        pw.PointChartValue(trace.frequenciesHz[i], _clampDb(trace.dbfs[i])),
      );
    }
    if (points.isEmpty || points.last.x < nyquist) {
      points.add(
        pw.PointChartValue(trace.frequenciesHz.last, _clampDb(trace.dbfs.last)),
      );
    }

    final xTicks = <double>[
      0,
      nyquist / 4,
      nyquist / 2,
      nyquist * 3 / 4,
      nyquist,
    ];
    const yTicks = <double>[-160, -120, -80, -40, 0];

    return pw.Chart(
      grid: pw.CartesianGrid(
        xAxis: pw.FixedAxis<double>(
          xTicks,
          format: (value) => _fmtFrequency(value.toDouble()),
          textStyle: const pw.TextStyle(fontSize: 7),
        ),
        yAxis: pw.FixedAxis<double>(
          yTicks,
          format: (value) => '${value.toInt()}',
          textStyle: const pw.TextStyle(fontSize: 7),
        ),
      ),
      datasets: [
        pw.LineDataSet<pw.PointChartValue>(
          data: points,
          color: color,
          lineWidth: 0.8,
          drawPoints: false,
        ),
      ],
    );
  }

  static List<List<String>> _spectrumMetricRows(SpectrumMetrics metrics) => [
    [
      'Fundamental',
      '${_fmtFrequency(metrics.fundamentalHz)} '
          '(${_fmtVoltage(metrics.fundamentalVpk)}, '
          '${_fmtDb(metrics.fundamentalDbfs)})',
    ],
    [
      'THD',
      '${_fmtPercentValue(metrics.thdPercent)} (${_fmtDb(metrics.thdDb)})',
    ],
    ['THD+N', _fmtDb(metrics.thdPlusNDb)],
    ['SNR', _fmtDb(metrics.snrDb)],
    ['SINAD', _fmtDb(metrics.sinadDb)],
    [
      'ENOB',
      metrics.enobBits.isFinite
          ? '${metrics.enobBits.toStringAsFixed(2)} bit'
          : 'N/A',
    ],
    ['SFDR', _fmtDb(metrics.sfdrDb)],
    ['Noise Floor', _fmtDb(metrics.noiseFloorDbfs)],
    ['Harmonics used', '${metrics.harmonicsUsed}'],
    ['Nyquist', _fmtFrequency(metrics.nyquistHz)],
    ['Resolution', _fmtFrequency(metrics.resolutionHz)],
  ];

  static double _clampDb(double value) {
    if (!value.isFinite) return -160;
    if (value < -160) return -160;
    if (value > 0) return 0;
    return value;
  }

  static String _fmtDb(double value) =>
      value.isFinite ? '${value.toStringAsFixed(1)} dB' : 'N/A';

  static String _fmtPercentValue(double value) =>
      value.isFinite ? '${value.toStringAsFixed(3)} %' : 'N/A';

  static String _windowLabel(SpectrumWindow window) => switch (window) {
    SpectrumWindow.rectangular => 'Rectangular',
    SpectrumWindow.hann => 'Hann',
    SpectrumWindow.hamming => 'Hamming',
    SpectrumWindow.blackmanHarris => 'Blackman-Harris',
    SpectrumWindow.flatTop => 'Flat-top',
  };

  static const List<PdfColor> _spectrumColors = [
    PdfColors.orange800,
    PdfColors.purple800,
    PdfColors.blue800,
    PdfColors.green800,
  ];

  static List<List<String>> _deviceParameterRows(DeviceParams params) {
    final rows = <List<String>>[
      ['Timebase', _fmtSi(params.timebase, 's/div')],
      ['Trigger Delay', _fmtSi(params.trdl, 's')],
      ['Sample Rate', _fmtSi(params.sampleRate, 'Sa/s')],
    ];
    for (var channel = 1; channel <= 4; channel++) {
      final name = 'ch$channel';
      final vdiv = params.vdivFor(name);
      final offset = params.voffsetFor(name);
      if (vdiv == null) continue;
      rows.add(['CH$channel V/div', _fmtSi(vdiv, 'V')]);
      rows.add(['CH$channel Offset', _fmtSi(offset ?? 0, 'V')]);
    }
    return rows;
  }

  static List<pw.Widget> _referenceRows(
    ComparisonMetrics? comparison,
    MaskResult? maskResult,
  ) {
    final widgets = <pw.Widget>[];
    if (comparison != null && comparison.hasData) {
      widgets.add(
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerAlignment: pw.Alignment.centerLeft,
          cellAlignment: pw.Alignment.centerLeft,
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(1.4),
          },
          headers: ['Comparison', 'Value'],
          data: [
            ['RMS Error', _fmtVoltage(comparison.rmsErrorVolts)],
            ['Max Deviation', _fmtVoltage(comparison.maxAbsDeviationVolts)],
            ['Mean Error', _fmtVoltage(comparison.meanErrorVolts)],
            [
              'Coverage',
              '${comparison.coveragePercent.toStringAsFixed(1)} % '
                  '(${comparison.comparedPoints}/${comparison.livePoints})',
            ],
          ],
        ),
      );
    }
    if (maskResult != null && maskResult.hasData) {
      if (widgets.isNotEmpty) widgets.add(pw.SizedBox(height: 12));
      widgets.add(
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerAlignment: pw.Alignment.centerLeft,
          cellAlignment: pw.Alignment.centerLeft,
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(1.4),
          },
          headers: ['Mask Test', 'Value'],
          data: [
            ['Result', maskResult.passed ? 'PASS' : 'FAIL'],
            ['Violations', '${maskResult.violations}'],
            ['Checked Points', '${maskResult.checkedPoints}'],
            if (!maskResult.passed) ...[
              ['First Violation', _fmtTime(maskResult.firstViolationTime)],
              ['Last Violation', _fmtTime(maskResult.lastViolationTime)],
              ['Max Violation', _fmtVoltage(maskResult.maxViolationVolts)],
            ],
          ],
        ),
      );
    }
    if (widgets.isEmpty) {
      widgets.add(pw.Text('No reference comparison or mask result available.'));
    }
    return widgets;
  }

  static List<pw.Widget> _agentAnalysisSection(String? analysis) {
    final text = analysis?.trim();
    if (text == null || text.isEmpty) return const <pw.Widget>[];
    final safeText = _truncateAnalysis(_asciiSafe(text));
    return [
      pw.SizedBox(height: 24),
      pw.Header(
        text: 'Agent Analysis',
        level: 1,
        textStyle: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 12),
      for (final paragraph in _analysisParagraphs(safeText)) ...[
        pw.Text(paragraph, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 6),
      ],
    ];
  }

  /// Splits the analysis into page-safe paragraphs without interpreting
  /// Markdown. The PDF's built-in font only supports ASCII.
  static List<String> _analysisParagraphs(String text) {
    final paragraphs = <String>[];
    for (final block in text.split(RegExp(r'\n\s*\n'))) {
      var remaining = block.trim();
      if (remaining.isEmpty) continue;
      while (remaining.length > 1200) {
        var cut = remaining.lastIndexOf('\n', 1200);
        if (cut <= 0) cut = remaining.lastIndexOf(' ', 1200);
        if (cut <= 0) cut = 1200;
        paragraphs.add(remaining.substring(0, cut).trim());
        remaining = remaining.substring(cut).trim();
      }
      if (remaining.isNotEmpty) paragraphs.add(remaining);
    }
    return paragraphs;
  }

  static String _truncateAnalysis(String text, {int maxCharacters = 6000}) {
    if (text.length <= maxCharacters) return text;
    return '${text.substring(0, maxCharacters).trimRight()}\n\n'
        '[Analysis truncated]';
  }

  static String _asciiSafe(String text) {
    const replacements = <String, String>{
      'µ': 'u',
      'μ': 'u',
      'Ω': 'Ohm',
      '°': 'deg',
      '±': '+/-',
      '×': 'x',
      '≤': '<=',
      '≥': '>=',
      '≈': '~',
      '→': '->',
      '←': '<-',
      '–': '-',
      '—': '-',
      '’': "'",
      '‘': "'",
      '“': '"',
      '”': '"',
      '…': '...',
      '·': '.',
      'Δ': 'Delta',
    };
    var result = text;
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result.replaceAll(RegExp(r'[^\x00-\x7F]'), '?');
  }

  static String _fmtTimestamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  static String _fmtVoltage(double? value) =>
      value == null ? 'N/A' : '${value.toStringAsFixed(4)} V';

  static String _fmtPercent(double? value) =>
      value == null ? 'N/A' : '${value.toStringAsFixed(1)} %';

  static String _fmtFrequency(double? value) {
    if (value == null || !value.isFinite) return 'N/A';
    final abs = value.abs();
    if (abs >= 1e6) return '${(value / 1e6).toStringAsFixed(3)} MHz';
    if (abs >= 1e3) return '${(value / 1e3).toStringAsFixed(3)} kHz';
    return '${value.toStringAsFixed(2)} Hz';
  }

  static String _fmtTime(double? value) {
    if (value == null || !value.isFinite) return 'N/A';
    final abs = value.abs();
    if (abs >= 1) return '${value.toStringAsFixed(4)} s';
    if (abs >= 1e-3) return '${(value * 1e3).toStringAsFixed(3)} ms';
    if (abs >= 1e-6) return '${(value * 1e6).toStringAsFixed(3)} us';
    if (abs >= 1e-9) return '${(value * 1e9).toStringAsFixed(3)} ns';
    return '${(value * 1e12).toStringAsFixed(0)} ps';
  }

  /// ASCII-safe SI formatting (the PDF's Helvetica has no Unicode support).
  static String _fmtSi(double value, String unit) {
    if (!value.isFinite) return 'N/A';
    if (value == 0) return '0 $unit';
    final abs = value.abs();
    final (factor, prefix) = switch (abs) {
      >= 1e9 => (1e9, 'G'),
      >= 1e6 => (1e6, 'M'),
      >= 1e3 => (1e3, 'k'),
      >= 1 => (1.0, ''),
      >= 1e-3 => (1e-3, 'm'),
      >= 1e-6 => (1e-6, 'u'),
      >= 1e-9 => (1e-9, 'n'),
      _ => (1e-12, 'p'),
    };
    final scaled = value / factor;
    var text = scaled.toStringAsFixed(3);
    if (text.contains('.')) {
      text = text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return '$text $prefix$unit';
  }
}
