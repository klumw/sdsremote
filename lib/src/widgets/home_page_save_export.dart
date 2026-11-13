part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeSaveExport on _OsciHomePageState {
  /// Whether the standard save (screen dump or waveform) is available.
  bool get _canSaveStandard =>
      _activePanel == ActivePanel.none &&
      (_screenDump != null || _waveformAcquired);

  /// Whether the current waveform can be exported in an external format.
  bool get _canExportWaveform =>
      _activePanel == ActivePanel.none &&
      _waveformAcquired &&
      (_waveformCh1 != null ||
          _waveformCh2 != null ||
          _waveformCh3 != null ||
          _waveformCh4 != null);

  /// Whether a Bode plot report can be saved.
  bool get _canSaveBodeReport =>
      _activePanel == ActivePanel.bode &&
      (_savedBodeStatus == BodeStatus.completed ||
          _savedBodeStatus == BodeStatus.cancelled) &&
      (_savedBodePoints?.any((point) => point.valid) ?? false);

  Future<void> _saveCurrentView() async {
    if (_canSaveBodeReport) {
      await _saveBodeReport();
    } else if (_canSaveDataLoggerReport) {
      await _saveDataLoggerReport();
    } else if (_screenDump != null) {
      await _saveScreenReport();
    } else if (_waveformCh1 != null ||
        _waveformCh2 != null ||
        _waveformCh3 != null ||
        _waveformCh4 != null) {
      await _saveWaveform();
    }
  }

  /// Captures the Bode plot as a PNG image, generates a PDF report, and
  /// saves it to the application's default save directory. When "Save csv
  /// data" is enabled, the sweep data is written as CSV as well.
  Future<void> _saveBodeReport() async {
    try {
      final prefix = await _askForFilenamePrefixIfNeeded();
      if (prefix == null) return; // user cancelled
      final pdfBaseName = prefix.isNotEmpty ? prefix : 'bode_plot_report';
      final csvBaseName = prefix.isNotEmpty ? prefix : 'bode_plot_data';

      final points = _savedBodePoints;
      final config = _savedBodeConfig;
      if (points == null || config == null || points.isEmpty) {
        throw Exception('No Bode plot data available');
      }

      // Capture the plot image from the RepaintBoundary
      final boundary =
          _bodePlotKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Bode plot not rendered yet');
      }

      // Capture at higher pixel ratio for better quality
      final uiImage = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await uiImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        throw Exception('Failed to capture Bode plot');
      }
      final rgba = byteData.buffer.asUint8List();

      // Brighten each pixel the same way the Data Logger report does, so the
      // dark plot background stays readable in the printed PDF.
      final image = img.Image.fromBytes(
        width: uiImage.width,
        height: uiImage.height,
        bytes: rgba.buffer,
        numChannels: 4,
      );
      for (final pixel in image) {
        pixel.r = (pixel.r * 2.5).clamp(0, 255).toInt();
        pixel.g = (pixel.g * 2.5).clamp(0, 255).toInt();
        pixel.b = (pixel.b * 2.5).clamp(0, 255).toInt();
      }
      final chartImageBytes = img.encodePng(image);

      final info = _sigGenService?.deviceInfo;
      final generatorIdentity = info?.scpiIdentity ?? 'Signal Generator';
      final deviceName = _deviceModel ?? _deviceName ?? _ipAddress;

      // Generate the PDF report
      final pdfBytes = await BodeReport.generatePdf(
        config: config,
        points: points,
        chartImageBytes: chartImageBytes,
        deviceName: deviceName,
        generatorIdentity: generatorIdentity,
        generatorFamily: info?.family,
      );

      // Write to the Bode reports subdirectory
      final dir = await AppPaths.getOrCreateBodeReportsDir();
      final file = await AppPaths.getUniqueFilePath(dir, pdfBaseName, 'pdf');
      await file.writeAsBytes(pdfBytes);
      final pdfName = file.uri.pathSegments.last;

      // If "Save csv data" is enabled, also write the sweep data as CSV
      String? csvName;
      if (_saveWithParams) {
        final csvDir = await AppPaths.getOrCreateBodeCsvDir();
        final csvFile = await AppPaths.getUniqueFilePath(
          csvDir,
          csvBaseName,
          'csv',
        );
        await csvFile.writeAsString(
          buildBodeCsv(
            config: config,
            points: points,
            deviceName: deviceName,
            generatorIdentity: generatorIdentity,
          ),
        );
        csvName = csvFile.uri.pathSegments.last;
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

  /// Shows the filename prefix dialog when [askForFilenamePrefix] is enabled.
  ///
  /// Returns the user-entered prefix, or null if the user cancelled.
  /// Returns an empty string when the flag is disabled (meaning "use default").
  Future<String?> _askForFilenamePrefixIfNeeded({String? initialValue}) async {
    if (!_askForFilenamePrefix) return '';
    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (_) => FilenamePrefixDialog(initialValue: initialValue),
    );
  }

  /// Saves the Control Panel screenshot as a PDF report.
  ///
  /// The report embeds the screenshot and records the capture time, the
  /// instrument identity and the channel settings read from the instrument.
  Future<void> _saveScreenReport() async {
    try {
      final prefix = await _askForFilenamePrefixIfNeeded();
      if (prefix == null) return; // user cancelled
      final baseName = prefix.isNotEmpty ? prefix : 'screen_dump_report';

      final liveImage = _vncLive ? _liveScreenImage : null;
      final Uint8List screenshotBytes;
      final DateTime capturedAt;
      if (liveImage != null) {
        // While live, the SCDP dump is stale — use the current frame.
        final data = await liveImage.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) {
          throw Exception('Failed to encode live screen');
        }
        screenshotBytes = data.buffer.asUint8List();
        capturedAt = _liveScreenCapturedAt ?? DateTime.now();
      } else {
        final dump = _screenDump;
        if (dump == null) {
          throw Exception('No screen dump available');
        }
        screenshotBytes = dump;
        capturedAt = _screenDumpCapturedAt ?? DateTime.now();
      }

      final info = await _collectScreenReportInfo(
        capturedAt: capturedAt,
        live: liveImage != null,
      );
      AppLogger().debug(
        'Screenshot report: device=${info.deviceName}, '
        'serial=${info.serialNumber}, firmware=${info.firmware}, '
        'captured=${info.capturedAt}, live=${info.live}, '
        'channels=${info.channels.length}',
      );

      final pdfBytes = await ScreenReport.generatePdf(
        screenshotBytes: screenshotBytes,
        info: info,
      );

      final dir = await AppPaths.getOrCreateScreenshotReportsDir();
      final file = await AppPaths.getUniqueFilePath(dir, baseName, 'pdf');
      await file.writeAsBytes(pdfBytes);
      final fileName = file.uri.pathSegments.last;
      _showInfoSnackBar('Saved $fileName');
    } catch (e) {
      _showErrorSnackBar('Save failed: $e');
    }
  }

  /// Collects the metadata for a Control Panel screenshot report.
  ///
  /// The channel settings are read from the instrument when it is reachable.
  /// A failed query leaves the affected value unknown instead of failing the
  /// save.
  Future<ScreenReportInfo> _collectScreenReportInfo({
    required DateTime capturedAt,
    required bool live,
  }) async {
    String? serialNumber;
    String? firmware;
    double? timebase;
    double? triggerDelay;
    String? bandwidthResponse;
    final channels = <ScreenChannelSettings>[];

    Vxi11Instrument? instrument = _instrument;
    if (instrument == null && _isOnline) {
      instrument = await _getInstrument();
    }

    if (instrument != null) {
      final connection = instrument;
      Future<String?> query(String command) async {
        try {
          return await connection.queryString(command);
        } catch (e) {
          AppLogger().warning('Screenshot report: $command failed: $e');
          return null;
        }
      }

      final idn = await query('*IDN?');
      if (idn != null) {
        final parts = idn.split(',');
        if (parts.length >= 4) {
          serialNumber = parts[2].trim();
          firmware = parts[3].trim();
        }
      }
      timebase = _parseScpiValue(await query('TDIV?'));
      triggerDelay = _parseScpiValue(await query('TRDL?'));
      bandwidthResponse = await query('BWL?');

      for (var channel = 1; channel <= _numChannels; channel++) {
        final trace = await query('C$channel:TRA?');
        final coupling = await query('C$channel:CPL?');
        final attenuation = await query('C$channel:ATTN?');
        final vdiv = await query('C$channel:VDIV?');
        final offset = await query('C$channel:OFST?');
        channels.add(
          ScreenChannelSettings(
            channel: channel,
            enabled: _parseTraceState(trace),
            coupling: coupling == null ? null : parseCouplingResponse(coupling),
            bandwidthLimit: bandwidthResponse == null
                ? null
                : parseBandwidthLimitResponse(bandwidthResponse, channel),
            probeAttenuation: _parseScpiValue(attenuation),
            voltsPerDiv: _parseScpiValue(vdiv),
            offsetVolts: _parseScpiValue(offset),
          ),
        );
      }
    } else {
      for (var channel = 1; channel <= _numChannels; channel++) {
        channels.add(ScreenChannelSettings(channel: channel));
      }
    }

    return ScreenReportInfo(
      capturedAt: capturedAt,
      deviceName:
          _deviceName ??
          _deviceModel ??
          (_isUsb ? 'USB instrument' : _ipAddress),
      deviceModel: _deviceModel,
      serialNumber: serialNumber,
      firmware: firmware,
      connection: _isUsb ? 'USB' : '$_ipAddress (VXI-11)',
      live: live,
      timebaseSeconds: timebase,
      triggerDelaySeconds: triggerDelay,
      channels: channels,
    );
  }

  /// Whether the trace is displayed, parsed from a `C<n>:TRA?` response.
  static bool? _parseTraceState(String? response) {
    if (response == null || response.trim().isEmpty) return null;
    return ScpiParser.parseStatus(response);
  }

  /// Numeric value from a SCPI response, or null when it cannot be parsed.
  static double? _parseScpiValue(String? response) {
    if (response == null) return null;
    try {
      return ScpiParser.parseValue(response);
    } on FormatException {
      return null;
    }
  }

  /// Saves the waveform measurement report (PDF) and the CSV data.
  ///
  /// The chart is captured only as the report image; no standalone image file
  /// is written.
  Future<void> _saveWaveform() async {
    try {
      final prefix = await _askForFilenamePrefixIfNeeded();
      if (prefix == null) return; // user cancelled
      final csvBaseName = prefix.isNotEmpty ? prefix : 'waveform_data';

      final report = await _writeWaveformReportPdf(
        reportName: prefix.isEmpty ? null : prefix,
      );
      final reportName = report.fileName;

      // Build waveform CSV using the extracted pure function.
      final csvContent = buildWaveformCsv(
        ch1: _waveformCh1,
        ch2: _waveformCh2,
        ch3: _waveformCh3,
        ch4: _waveformCh4,
        params: _deviceParams!,
        deviceName: _deviceName ?? _ipAddress,
        cursorState: _cursorState,
        channelCount: _numChannels,
      );

      final csvDir = await AppPaths.getOrCreateWaveformCsvDir();
      final csvFile = await AppPaths.getUniqueFilePath(
        csvDir,
        csvBaseName,
        'csv',
      );
      await csvFile.writeAsString(csvContent);
      final csvName = csvFile.uri.pathSegments.last;

      if (mounted) {
        _showInfoSnackBar('Saved $reportName + $csvName');
      }
    } catch (e) {
      _showErrorSnackBar('Save failed: $e');
    }
  }

  /// Creates the waveform PDF report for the Waveform Agent.
  ///
  /// When "Ask for filename on save" is enabled, the filename dialog is shown
  /// before the report is written. Returns `cancelled` when the user closes
  /// the dialog without a name.
  Future<Map<String, dynamic>> _createWaveformReportForAi({
    String? reportName,
    String? analysis,
  }) async {
    if (!_waveformAcquired || _deviceParams == null) {
      return {'error': 'No waveform is displayed. Acquire a waveform first.'};
    }

    final prefix = await _askForFilenamePrefixIfNeeded(
      initialValue: reportName,
    );
    if (prefix == null) {
      return {
        'cancelled': true,
        'error':
            'The user cancelled the report filename dialog. No report was '
            'saved.',
      };
    }
    final effectiveReportName = prefix.isNotEmpty ? prefix : reportName;

    try {
      final report = await _writeWaveformReportPdf(
        reportName: effectiveReportName,
        agentAnalysis: analysis,
      );
      return {'saved': true, 'fileName': report.fileName, 'path': report.path};
    } catch (e) {
      AppLogger().warning('Waveform report for AI failed: $e');
      return {'error': 'Report generation failed: $e'};
    }
  }

  /// Captures the current chart and writes the waveform PDF report.
  ///
  /// Reused by the manual save action and by the Waveform Agent's
  /// `create_waveform_report` tool.
  Future<({String fileName, String path})> _writeWaveformReportPdf({
    String? reportName,
    String? agentAnalysis,
  }) async {
    final params = _deviceParams;
    if (params == null) {
      throw Exception('No device parameters available');
    }

    final chartKey = _effectiveWaveformViewMode == _WaveformViewMode.spectrum
        ? _spectrumKey
        : _waveformKey;
    return _reportExportController.writeWaveformReportPdf(
      chartKey: chartKey,
      params: params,
      measurements: _acquiredMeasurements(),
      readSpectrum: _spectrumForReport,
      comparison: _comparison,
      maskResult: _maskSettings.enabled ? _maskResult : null,
      agentAnalysis: agentAnalysis,
      reportName: reportName,
      deviceName: _deviceName ?? _ipAddress,
    );
  }

  /// Acquired waveform channels with their display points.
  Map<String, WaveformData> _acquiredWaveformChannels() => {
    'ch1': ?_waveformCh1,
    'ch2': ?_waveformCh2,
    'ch3': ?_waveformCh3,
    'ch4': ?_waveformCh4,
  };

  Future<void> _showWaveformExportDialog() async {
    final channels = _acquiredWaveformChannels();
    if (channels.isEmpty) {
      _showInfoSnackBar('No waveform data available.');
      return;
    }
    final request = await showDialog<WaveformExportRequest>(
      context: context,
      builder: (_) => WaveformExportDialog(channels: channels.keys.toList()),
    );
    if (request == null || !mounted) return;
    await _performWaveformExport(request);
  }

  Future<void> _performWaveformExport(WaveformExportRequest request) async {
    try {
      await _reportExportController.performWaveformExport(
        request: request,
        channels: _acquiredWaveformChannels(),
        measurements: _acquiredMeasurements(),
        defaultSampleRate: _deviceParams?.sampleRate ?? 1000,
        showInfo: _showInfoSnackBar,
      );
    } catch (e) {
      _showErrorSnackBar('Export failed: $e');
    }
  }
}
