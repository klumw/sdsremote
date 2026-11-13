import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import '../app/app_paths.dart';
import '../core/logger.dart';
import '../spectrum/spectrum_models.dart';
import 'waveform_compare.dart';
import 'waveform_export.dart';
import 'waveform_mask.dart';
import 'waveform_measurements.dart';
import 'waveform_models.dart';
import 'waveform_report.dart';

/// Performs the report and export file operations for the waveform views.
///
/// The home page gathers the current state and shows the dialogs; this
/// controller captures chart images, builds reports/exports, and writes the
/// files.
class ReportExportController {
  /// Captures the current chart and writes the waveform PDF report.
  Future<({String fileName, String path})> writeWaveformReportPdf({
    required GlobalKey chartKey,
    required DeviceParams params,
    required Map<String, WaveformMeasurements> measurements,
    required Future<SpectrumResult?> Function() readSpectrum,
    ComparisonMetrics? comparison,
    MaskResult? maskResult,
    String? agentAnalysis,
    String? reportName,
    required String deviceName,
  }) async {
    final boundary =
        chartKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw Exception('Waveform not rendered yet');

    final uiImage = await boundary.toImage(pixelRatio: 2.0);
    final byteData = await uiImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (byteData == null) {
      throw Exception('Failed to capture waveform image');
    }
    final image = img.Image.fromBytes(
      width: uiImage.width,
      height: uiImage.height,
      bytes: byteData.buffer,
      numChannels: 4,
    );

    SpectrumResult? spectrum;
    try {
      spectrum = await readSpectrum();
    } catch (e) {
      AppLogger().warning('Spectrum computation for the report failed: $e');
    }

    final pdfBytes = await WaveformReport.generatePdf(
      chartImageBytes: img.encodePng(image),
      params: params,
      measurements: measurements,
      comparison: comparison,
      maskResult: maskResult,
      spectrum: spectrum,
      agentAnalysis: agentAnalysis,
      reportName: reportName,
      deviceName: deviceName,
    );

    final reportDir = await AppPaths.getOrCreateWaveformReportsDir();
    final reportFile = await AppPaths.getUniqueFilePath(
      reportDir,
      reportBaseName(reportName),
      'pdf',
    );
    await reportFile.writeAsBytes(pdfBytes);
    return (fileName: reportFile.uri.pathSegments.last, path: reportFile.path);
  }

  /// Returns a safe file-name prefix for the waveform report.
  String reportBaseName(String? reportName) {
    final trimmed = reportName?.trim() ?? '';
    if (trimmed.isEmpty) return 'waveform_report';
    final safe = trimmed
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (safe.isEmpty) return 'waveform_report';
    return safe.length > 80 ? safe.substring(0, 80) : safe;
  }

  /// Exports the selected waveform channels in the requested format.
  ///
  /// Throws on write failures; the caller shows the error.
  Future<void> performWaveformExport({
    required WaveformExportRequest request,
    required Map<String, WaveformData> channels,
    required Map<String, WaveformMeasurements> measurements,
    required double defaultSampleRate,
    required void Function(String message) showInfo,
  }) async {
    if (request.format == WaveformExportFormat.clipboard) {
      await Clipboard.setData(
        ClipboardData(text: buildClipboardText(measurements)),
      );
      showInfo('Measurements copied to the clipboard.');
      return;
    }

    final String extension;
    Uint8List? bytes;
    String? text;
    switch (request.format) {
      case WaveformExportFormat.ltspicePwl:
        final points = channels[request.channel]?.points ?? const [];
        text = buildLtspicePwl(points, wrap: request.wrapPwl);
        extension = 'txt';
        break;
      case WaveformExportFormat.wav:
        final points = channels[request.channel]?.points ?? const [];
        bytes = buildWav(
          points,
          sampleRate: waveformPointRate(points, defaultSampleRate),
        );
        extension = 'wav';
        break;
      case WaveformExportFormat.vcd:
        text = buildVcd({
          for (final entry in channels.entries) entry.key: entry.value.points,
        }, thresholdVolts: request.thresholdVolts);
        extension = 'vcd';
        break;
      case WaveformExportFormat.clipboard:
        throw StateError('clipboard export is handled above');
    }

    final dir = await AppPaths.getOrCreateWaveformExportsDir();
    final base = request.fileName.trim().isEmpty
        ? 'waveform_export'
        : request.fileName.trim();
    final file = await AppPaths.getUniqueFilePath(dir, base, extension);
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    } else {
      await file.writeAsString(text ?? '');
    }
    showInfo('Saved ${file.uri.pathSegments.last}');
  }

  /// Effective sample rate of the displayed points (1 / first interval).
  double waveformPointRate(
    List<(double, double)> points,
    double defaultSampleRate,
  ) {
    if (points.length >= 2) {
      final dt = points[1].$1 - points[0].$1;
      if (dt.isFinite && dt > 0) return 1 / dt;
    }
    return defaultSampleRate;
  }
}
