/// PDF report for a Control Panel screen capture.
///
/// Contains the screenshot, the capture time, the identity of the instrument
/// and the channel settings read from the instrument. The class mirrors
/// `WaveformReport`, `DataLoggerReport` and `BodeReport`; it is pure
/// computation and returns the PDF bytes without touching the file system.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Channel settings of one analog channel at screenshot time.
class ScreenChannelSettings {
  final int channel;

  /// Whether the channel trace is displayed, or null when the state is
  /// unknown.
  final bool? enabled;

  /// Raw `C<n>:CPL?` token (`A1M`, `D1M`, `A50`, `D50`, `GND`), or null when
  /// the setting is unknown.
  final String? coupling;

  /// Whether the 20 MHz bandwidth limit is active, or null when unknown.
  final bool? bandwidthLimit;

  /// Probe attenuation factor, or null when unknown.
  final double? probeAttenuation;

  /// Vertical scale in volts per division, or null when unknown.
  final double? voltsPerDiv;

  /// Vertical offset in volts, or null when unknown.
  final double? offsetVolts;

  const ScreenChannelSettings({
    required this.channel,
    this.enabled,
    this.coupling,
    this.bandwidthLimit,
    this.probeAttenuation,
    this.voltsPerDiv,
    this.offsetVolts,
  });
}

/// Metadata recorded with a Control Panel screenshot.
class ScreenReportInfo {
  /// Time the screenshot was captured.
  final DateTime capturedAt;

  /// Display name of the instrument, e.g. `SIGLENT SDS1104X-E`.
  final String deviceName;

  /// Model designation reported by the instrument.
  final String? deviceModel;

  final String? serialNumber;
  final String? firmware;

  /// Connection description, e.g. `USB` or `192.168.178.91 (VXI-11)`.
  final String? connection;

  /// Whether the screenshot is a live VNC frame instead of a screen dump.
  final bool live;

  /// Horizontal scale in seconds per division, or null when unknown.
  final double? timebaseSeconds;

  /// Trigger delay in seconds, or null when unknown.
  final double? triggerDelaySeconds;

  /// Channel settings ordered by channel number.
  final List<ScreenChannelSettings> channels;

  const ScreenReportInfo({
    required this.capturedAt,
    this.deviceName = '',
    this.deviceModel,
    this.serialNumber,
    this.firmware,
    this.connection,
    this.live = false,
    this.timebaseSeconds,
    this.triggerDelaySeconds,
    this.channels = const [],
  });
}

/// Generates a PDF report for a Control Panel screenshot.
class ScreenReport {
  ScreenReport._();

  /// Builds the PDF bytes.
  ///
  /// [screenshotBytes] must be a PNG image of the captured screen.
  static Future<Uint8List> generatePdf({
    required Uint8List screenshotBytes,
    required ScreenReportInfo info,
  }) async {
    final pdf = pw.Document();
    final screenshot = pw.MemoryImage(screenshotBytes);
    final device = info.deviceName.trim().isNotEmpty
        ? info.deviceName.trim()
        : (info.deviceModel ?? 'Unknown');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              'Control Panel Screenshot Report',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Captured: ${_fmtTimestamp(info.capturedAt)}',
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.Text('Device: $device', style: const pw.TextStyle(fontSize: 12)),
          if (info.serialNumber != null && info.serialNumber!.isNotEmpty)
            pw.Text(
              'Serial Number: ${info.serialNumber}',
              style: const pw.TextStyle(fontSize: 12),
            ),
          if (info.firmware != null && info.firmware!.isNotEmpty)
            pw.Text(
              'Firmware: ${info.firmware}',
              style: const pw.TextStyle(fontSize: 12),
            ),
          if (info.connection != null && info.connection!.isNotEmpty)
            pw.Text(
              'Connection: ${info.connection}',
              style: const pw.TextStyle(fontSize: 12),
            ),
          pw.Text(
            'Capture Mode: '
            '${info.live ? 'Live screen (VNC)' : 'Screen dump (SCDP)'}',
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.SizedBox(height: 20),

          // ---- Screenshot ----
          pw.Center(
            child: pw.Container(
              width: double.infinity,
              constraints: const pw.BoxConstraints(maxHeight: 400),
              child: pw.Image(screenshot, fit: pw.BoxFit.contain),
            ),
          ),
          pw.SizedBox(height: 24),

          // ---- Acquisition ----
          pw.Header(
            text: 'Acquisition',
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
            data: [
              ['Timebase', _fmtSi(info.timebaseSeconds, 's/div')],
              ['Trigger Delay', _fmtSi(info.triggerDelaySeconds, 's')],
            ],
          ),
          pw.SizedBox(height: 24),

          // ---- Channel settings ----
          pw.Header(
            text: 'Channel Settings',
            level: 1,
            textStyle: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          if (info.channels.isEmpty)
            pw.Text('No channel settings available.')
          else
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerAlignment: pw.Alignment.centerLeft,
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: {
                0: const pw.FlexColumnWidth(0.5),
                1: const pw.FlexColumnWidth(0.7),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(0.9),
                4: const pw.FlexColumnWidth(0.8),
                5: const pw.FlexColumnWidth(1.0),
                6: const pw.FlexColumnWidth(1.0),
              },
              headers: [
                'CH',
                'State',
                'Coupling',
                'Bandwidth',
                'Probe',
                'V/div',
                'Offset',
              ],
              data: [
                for (final channel in info.channels)
                  [
                    'CH${channel.channel}',
                    _fmtState(channel.enabled),
                    _fmtCoupling(channel.coupling),
                    _fmtBandwidth(channel.bandwidthLimit),
                    _fmtProbe(channel.probeAttenuation),
                    _fmtSi(channel.voltsPerDiv, 'V'),
                    _fmtSi(channel.offsetVolts, 'V'),
                  ],
              ],
            ),
        ],
      ),
    );

    return pdf.save();
  }

  static String _fmtState(bool? enabled) => switch (enabled) {
    true => 'On',
    false => 'Off',
    null => 'N/A',
  };

  static String _fmtCoupling(String? token) {
    final label = switch (token?.toUpperCase()) {
      'A1M' => 'AC, 1 MOhm',
      'D1M' => 'DC, 1 MOhm',
      'A50' => 'AC, 50 Ohm',
      'D50' => 'DC, 50 Ohm',
      'GND' => 'GND',
      null => null,
      _ => token,
    };
    return label == null || label.isEmpty ? 'N/A' : label;
  }

  static String _fmtBandwidth(bool? limited) => switch (limited) {
    true => '20 MHz',
    false => 'Full',
    null => 'N/A',
  };

  static String _fmtProbe(double? attenuation) {
    if (attenuation == null || !attenuation.isFinite || attenuation <= 0) {
      return 'N/A';
    }
    return '${_trimZeros(attenuation.toStringAsFixed(3))}x';
  }

  static String _fmtTimestamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  /// ASCII-safe SI formatting (the PDF's Helvetica has no Unicode support).
  static String _fmtSi(double? value, String unit) {
    if (value == null || !value.isFinite) return 'N/A';
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
    return '${_trimZeros((value / factor).toStringAsFixed(3))} $prefix$unit';
  }

  static String _trimZeros(String text) {
    if (!text.contains('.')) return text;
    return text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}
