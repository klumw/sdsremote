part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeDataLogger on _OsciHomePageState {
  bool get _dlIsRunning => _dataLoggerSession.isRunning;

  List<DataLoggerPoint>? get _savedDlPoints => _dataLoggerSession.savedPoints;

  DataLoggerConfig? get _savedDlConfig => _dataLoggerSession.savedConfig;

  DataLoggerStatus? get _savedDlStatus => _dataLoggerSession.savedStatus;

  Set<String>? get _savedDlHiddenLines => _dataLoggerSession.savedHiddenLines;

  /// Builds the rotating arrows icon for the Data Logger toolbar button.
  Widget _buildDlButtonIcon() {
    return AnimatedSyncIcon(
      size: 25,
      color: _dlIsRunning ? Colors.greenAccent : Colors.white,
      animate: _dlIsRunning,
    );
  }

  Widget _buildDataLoggerWindow() {
    return DataLoggerPanel(
      plotKey: _dlPlotKey,
      getInstrument: _getInstrument,
      isOnline: _isOnline,
      channelCount: _numChannels,
      savedPoints: _savedDlPoints,
      savedConfig: _savedDlConfig,
      savedStatus: _savedDlStatus,
      savedHiddenLines: _savedDlHiddenLines,
      onServiceCreated: (service) {
        _dataLoggerSession.service = service;
      },
      onSaveState: _dataLoggerSession.saveState,
      onRecordingFinished: _dataLoggerSession.recordingFinished,
      onRunningChanged: _dataLoggerSession.setRunning,
      onClose: () {
        _dataLoggerSession.close();
        _togglePanel(ActivePanel.dataLogger);
      },
    );
  }

  /// Stops the Data Logger recording immediately, including the animation
  /// and the background SCPI service. Safe to call when logger is not running.
  void _stopDataLoggerIfRunning() {
    if (_activePanel == ActivePanel.dataLogger) {
      _dataLoggerSession.stop();
    }
  }

  /// Whether a data logger report can be saved.
  bool get _canSaveDataLoggerReport =>
      _activePanel == ActivePanel.dataLogger &&
      _savedDlStatus == DataLoggerStatus.stopped &&
      (_savedDlPoints?.length ?? 0) > 1;

  /// Captures the Data Logger chart as a PNG image, generates a PDF report,
  /// and saves it to the application's default save directory.
  Future<void> _saveDataLoggerReport() async {
    try {
      final prefix = await _askForFilenamePrefixIfNeeded();
      if (prefix == null) return; // user cancelled
      final pdfBaseName = prefix.isNotEmpty ? prefix : 'data_logging_report';
      final csvBaseName = prefix.isNotEmpty ? prefix : 'data_logger_data';

      final points = _savedDlPoints;
      final config = _savedDlConfig;
      if (points == null || config == null) {
        throw Exception('No data logger data available');
      }

      // Capture the chart image from the RepaintBoundary
      final boundary =
          _dlPlotKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Data logger chart not rendered yet');
      }

      // Capture at higher pixel ratio for better quality
      final uiImage = await boundary.toImage(pixelRatio: 2.0);
      // Use raw RGBA (same format as waveform capture) for reliable decoding
      final byteData = await uiImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        throw Exception('Failed to capture data logger chart');
      }
      final rgba = byteData.buffer.asUint8List();

      // Brighten each pixel: scale RGB values to lighten the dark background.
      // The background is 0xFF0A192F (R=10, G=25, B=47).
      final image = img.Image.fromBytes(
        width: uiImage.width,
        height: uiImage.height,
        bytes: rgba.buffer,
        numChannels: 4,
      );
      // First pass: multiply brightness (2.5x to lighten the very dark bg)
      for (final pixel in image) {
        pixel.r = (pixel.r * 2.5).clamp(0, 255).toInt();
        pixel.g = (pixel.g * 2.5).clamp(0, 255).toInt();
        pixel.b = (pixel.b * 2.5).clamp(0, 255).toInt();
      }
      final chartImageBytes = img.encodePng(image);

      // Generate the PDF report
      final pdfBytes = await DataLoggerReport.generatePdf(
        points: points,
        config: config,
        chartImageBytes: chartImageBytes,
      );

      // Write to the logger reports subdirectory
      final dir = await AppPaths.getOrCreateLoggerReportsDir();
      final file = await AppPaths.getUniqueFilePath(dir, pdfBaseName, 'pdf');
      await file.writeAsBytes(pdfBytes);
      final pdfName = file.uri.pathSegments.last;

      // If "Save csv data" is enabled, also write data logger data as CSV
      String? csvName;
      if (_saveWithParams) {
        csvName = await _saveDataLoggerCsv(
          await AppPaths.getOrCreateLoggerCsvDir(),
          config,
          points,
          csvBaseName,
        );
      }

      if (mounted) {
        final msg = _saveWithParams
            ? 'Saved $pdfName + $csvName'
            : 'Saved $pdfName';
        _showInfoSnackBar(msg);
      }
    } catch (e) {
      _showErrorSnackBar('Save failed: $e');
    }
  }

  /// Writes a CSV file with the data logger's recorded data points.
  ///
  /// Returns the saved filename.
  ///
  /// Only includes columns for measurements that are enabled in the config
  /// AND not hidden via the chip toggle buttons ([_savedDlHiddenLines]).
  Future<String> _saveDataLoggerCsv(
    Directory dir,
    DataLoggerConfig config,
    List<DataLoggerPoint> points, [
    String baseName = 'data_logger_data',
  ]) async {
    final csvContent = buildDataLoggerCsv(
      config: config,
      points: points,
      hiddenLines: _savedDlHiddenLines ?? <String>{},
      deviceName: _deviceName ?? _ipAddress,
    );

    final csvFile = await AppPaths.getUniqueFilePath(dir, baseName, 'csv');
    await csvFile.writeAsString(csvContent);
    return csvFile.uri.pathSegments.last;
  }
}
