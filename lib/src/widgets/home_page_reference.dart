part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeReference on _OsciHomePageState {
  WaveformData? get _refWaveform => _referenceController.refWaveform;
  set _refWaveform(WaveformData? value) =>
      _referenceController.refWaveform = value;

  bool get _refVisible => _referenceController.refVisible;
  set _refVisible(bool value) => _referenceController.refVisible = value;

  String? get _refFileName => _referenceController.refFileName;
  set _refFileName(String? value) => _referenceController.refFileName = value;

  String? get _refChannelOrigin => _referenceController.refChannelOrigin;
  set _refChannelOrigin(String? value) =>
      _referenceController.refChannelOrigin = value;

  WaveformCsvMetadata? get _refMetadata => _referenceController.refMetadata;
  set _refMetadata(WaveformCsvMetadata? value) =>
      _referenceController.refMetadata = value;

  double? get _refVdivVolts => _referenceController.refVdivVolts;
  set _refVdivVolts(double? value) => _referenceController.refVdivVolts = value;

  double? get _refOffsetVolts => _referenceController.refOffsetVolts;
  set _refOffsetVolts(double? value) =>
      _referenceController.refOffsetVolts = value;

  ReferenceOffset get _refOffset => _referenceController.refOffset;
  set _refOffset(ReferenceOffset value) =>
      _referenceController.refOffset = value;

  bool get _refMoving => _referenceController.refMoving;
  set _refMoving(bool value) => _referenceController.refMoving = value;

  bool get _draggingRef => _referenceController.draggingRef;
  set _draggingRef(bool value) => _referenceController.draggingRef = value;

  ReferenceOffset get _refDragAnchor => _referenceController.refDragAnchor;
  set _refDragAnchor(ReferenceOffset value) =>
      _referenceController.refDragAnchor = value;

  Offset get _refDragOriginPx => _referenceController.refDragOriginPx;
  set _refDragOriginPx(Offset value) =>
      _referenceController.refDragOriginPx = value;

  String? get _dismissedReferenceTimingWarning =>
      _referenceController.dismissedReferenceTimingWarning;
  set _dismissedReferenceTimingWarning(String? value) =>
      _referenceController.dismissedReferenceTimingWarning = value;

  WaveformMeasurements? get _refMeasurements =>
      _referenceController.refMeasurements;

  bool get _diffVisible => _referenceController.diffVisible;
  set _diffVisible(bool value) => _referenceController.diffVisible = value;

  WaveformData? get _diffTrace => _referenceController.diffTrace;
  set _diffTrace(WaveformData? value) => _referenceController.diffTrace = value;

  ComparisonMetrics? get _comparison => _referenceController.comparison;
  set _comparison(ComparisonMetrics? value) =>
      _referenceController.comparison = value;

  MaskSettings get _maskSettings => _referenceController.maskSettings;
  set _maskSettings(MaskSettings value) =>
      _referenceController.maskSettings = value;

  MaskBand? get _maskBand => _referenceController.maskBand;
  set _maskBand(MaskBand? value) => _referenceController.maskBand = value;

  MaskResult? get _maskResult => _referenceController.maskResult;
  set _maskResult(MaskResult? value) => _referenceController.maskResult = value;

  double _referenceVpp() => _referenceController.referenceVpp;

  double _referenceDurationSeconds() =>
      _referenceController.referenceDurationSeconds;

  /// Timing settings in which the loaded reference differs from the current
  /// instrument settings. Empty when the reference has no timing metadata or
  /// all values match.
  List<ReferenceTimingMismatch> _referenceTimingMismatches() =>
      _referenceController.timingMismatches();

  /// Stable signature of one reference timing warning, used to keep a
  /// dismissed banner hidden until the warning content changes.
  String _referenceTimingWarningSignature(
    List<ReferenceTimingMismatch> mismatches,
  ) => _referenceController.timingWarningSignature(mismatches);

  /// Hint shown in the reference section when the loaded file carries no
  /// timing metadata, so a comparison is impossible.
  String? get _referenceTimingNote => _referenceController.timingNote;

  /// Recomputes the cached reference geometry and measurements after a
  /// reference change.
  void _cacheReferenceGeometry() => _referenceController.cacheGeometry();

  void _onDiffToggled(bool visible) {
    _setState(() => _diffVisible = visible);
    if (visible) _recomputeReferenceAnalysis();
  }

  void _onMaskSettingsChanged(MaskSettings settings) {
    _setState(() => _maskSettings = settings);
    _recomputeReferenceAnalysis();
  }

  /// Measurement of the trigger source channel, or null when unavailable.
  WaveformMeasurements? get _triggerSourceMeasurement =>
      _referenceController.triggerSourceMeasurement;

  /// Period of the trigger source signal, or null when it cannot be measured.
  double? _triggerSourcePeriod() => _referenceController.triggerSourcePeriod();

  /// Copies the current waveform of an enabled channel into the reference.
  Future<void> _useCurrentWaveformAsReference() async {
    final channels = _enabledLiveChannels();
    if (channels.isEmpty) {
      _showInfoSnackBar('No current waveform available.');
      return;
    }

    final channel = channels.length == 1
        ? channels.keys.first
        : await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Use which channel as reference?'),
              children: [
                for (final entry in channels.entries)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, entry.key),
                    child: Text(
                      entry.key.toUpperCase(),
                      style: TextStyle(color: waveformChannelColor(entry.key)),
                    ),
                  ),
              ],
            ),
          );
    if (channel == null || !mounted) return;

    final points = channels[channel]!.points;
    final params = _deviceParams;
    _setState(() {
      _refWaveform = WaveformData(points: points);
      _refVisible = true;
      _refFileName = '${channel.toUpperCase()} (current)';
      _refChannelOrigin = channel;
      _refOffset = const ReferenceOffset();
      // The copy carries the settings the current acquisition was made with,
      // so a warning only appears after the user changes one of them.
      _refMetadata = params == null
          ? null
          : WaveformCsvMetadata(
              timebaseSecondsPerDiv: params.timebase,
              triggerDelaySeconds: params.trdl,
              sampleRateHz: params.sampleRate,
            );
      _refVdivVolts = params?.vdivFor(channel);
      _refOffsetVolts = params?.voffsetFor(channel);
      _dismissedReferenceTimingWarning = null;
      _cacheReferenceGeometry();
    });
    _recomputeReferenceAnalysis();
  }

  /// Recomputes difference trace, deviation metrics and the mask test.
  ///
  /// Called after an acquisition, a reference change, a reference drag and a
  /// mask settings change. The result only covers the live points that the
  /// (shifted) reference actually spans.
  void _recomputeReferenceAnalysis() {
    if (!_referenceController.hasAnalysisInputs) {
      if (_referenceController.hasAnalysisResults) {
        _setState(() => _referenceController.clearAnalysis());
      }
      return;
    }
    _referenceController.computeAnalysis();
    _setState(() {});
  }

  void _onRefToggled(bool visible) {
    _setState(() {
      _refVisible = visible;
      // Aligning a hidden reference would move something the user cannot see.
      if (!visible) _refMoving = false;
    });
  }

  void _onRefMovingToggled(bool moving) {
    _setState(() {
      _refMoving = moving;
      _draggingRef = false;
      // The hover highlight belongs to the cursor drag, which is suspended
      // while the reference is being moved.
      _hoveredCursorType = null;
    });
  }

  void _onRefReset() {
    _setState(() => _refOffset = const ReferenceOffset());
    _recomputeReferenceAnalysis();
  }

  /// Lists CSV waveform files in the waveform/csv directory and shows a
  /// file-picker dialog. Returns the selected file path, or null if the
  /// user cancelled or no files are available.
  Future<String?> _pickReferenceCsvFile() async {
    final dir = AppPaths.waveformCsvDirectory;
    if (!await dir.exists()) {
      _showInfoSnackBar('No saved waveform CSV files found.');
      return null;
    }

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.csv'))
        .toList();

    if (files.isEmpty) {
      _showInfoSnackBar('No waveform CSV files found.');
      return null;
    }

    if (!mounted) return null;
    return showDialog<String>(
      context: context,
      builder: (ctx) => ReferenceFilePickerDialog(files: files),
    );
  }

  /// Aligns reference waveform points so their time axis matches the
  /// live waveform: the CSV always starts at t=0, but live data may use
  /// trigger-relative times starting at a negative value.
  static List<(double, double)> _alignReferencePoints(
    List<(double, double)> points,
    double? liveFirstTime,
  ) {
    final shift = (liveFirstTime ?? points.first.$1) - points.first.$1;
    if (shift == 0) return points;
    return points.map((p) => (p.$1 + shift, p.$2)).toList();
  }

  /// Opens a file selection dialog showing CSV waveform files in the
  /// application's waveform/csv subdirectory. When the file contains more
  /// than one channel the user is asked which channel to load.
  Future<void> _loadReferenceWaveform() async {
    final selected = await _pickReferenceCsvFile();
    if (selected == null || !mounted) return;

    try {
      final file = File(selected);
      final content = await file.readAsString();
      final csv = parseWaveformCsv(content);
      final channels = <String, List<(double, double)>>{
        if (csv.ch1 != null) 'ch1': csv.ch1!,
        if (csv.ch2 != null) 'ch2': csv.ch2!,
        if (csv.ch3 != null) 'ch3': csv.ch3!,
        if (csv.ch4 != null) 'ch4': csv.ch4!,
      };
      if (channels.isEmpty) {
        _showErrorSnackBar(
          'Invalid waveform CSV. Expected header: '
          'Time (s),CH1 (V),CH2 (V) or '
          'Time (s),CH1 (V),CH2 (V),CH3 (V),CH4 (V)',
        );
        return;
      }

      if (!mounted) return;

      final channel = channels.length == 1
          ? channels.keys.first
          : await showDialog<String>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: const Text('Select Channel'),
                children: [
                  for (final entry in channels.entries)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, entry.key),
                      child: Text(
                        entry.key.toUpperCase(),
                        style: TextStyle(
                          color: waveformChannelColor(entry.key),
                        ),
                      ),
                    ),
                ],
              ),
            );
      if (channel == null) return;

      final points = channels[channel]!;

      final (liveFirstTime, _) = _waveformTimeBounds();
      final alignedPoints = _alignReferencePoints(points, liveFirstTime);
      final channelSettings = csv.metadata?.channels[channel];

      _setState(() {
        _refWaveform = WaveformData(points: alignedPoints);
        _refVisible = true;
        _refFileName = file.uri.pathSegments.last;
        _refChannelOrigin = channel;
        _refMetadata = csv.metadata;
        _refVdivVolts = channelSettings?.vdivVolts;
        _refOffsetVolts = channelSettings?.offsetVolts;
        _dismissedReferenceTimingWarning = null;
        // The load aligns the reference itself, so an offset from a previous
        // reference would be meaningless for this one.
        _refOffset = const ReferenceOffset();
        _cacheReferenceGeometry();
      });
      _recomputeReferenceAnalysis();
    } catch (e) {
      _showErrorSnackBar('Error loading reference: $e');
    }
  }

  /// Overlay hint shown while the reference can be moved: what the gesture
  /// does and how far the reference currently sits from its loaded position.
  Widget _buildRefMoveHint() {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xCC0D1117),
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.open_with,
              size: 14,
              color: Colors.lightBlueAccent,
            ),
            const SizedBox(width: 8),
            Text(
              'Move reference  ·  ΔX ${formatOffsetDivisions(_refOffset.dxDiv)}'
              '  ·  ΔY ${formatOffsetDivisions(_refOffset.dyDiv)}'
              '  ·  Shift = snap',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  /// Pan dispatcher: with "Move Reference" armed the drag aligns the
  /// reference, otherwise it drags a cursor.
  void _onWaveformPanStart(DragStartDetails details) {
    if (_refMoving && _refVisible && _startRefDrag(details)) return;
    _onCursorDragStart(details);
  }

  void _onWaveformPanUpdate(DragUpdateDetails details) {
    if (_draggingRef) {
      _updateRefDrag(details);
      return;
    }
    _onCursorDragUpdate(details);
  }

  void _onWaveformPanEnd(DragEndDetails details) {
    if (_draggingRef) {
      _draggingRef = false;
      return;
    }
    _onCursorDragEnd(details);
  }

  /// Starts a reference drag. Returns false when the gesture belongs to the
  /// cursor info panel, which stays draggable in every mode.
  bool _startRefDrag(DragStartDetails details) {
    final size = _getWaveformSize();
    if (size == null || size.width == 0 || size.height == 0) return false;

    final panelRect = _getCursorInfoPanelRect(size);
    if (panelRect != null && panelRect.contains(details.localPosition)) {
      _draggingCursorInfo = true;
      return false;
    }

    // setState so the pointer switches to the "grabbing" cursor right away.
    _setState(() {
      _draggingRef = true;
      _refDragAnchor = _refOffset;
      _refDragOriginPx = details.localPosition;
    });
    return true;
  }

  /// Moves the reference by the pointer movement since the drag started,
  /// converted through the same mapping the painter draws the reference with
  /// — so the trace stays under the pointer at any zoom and pan position.
  void _updateRefDrag(DragUpdateDetails details) {
    final size = _getWaveformSize();
    final params = _deviceParams;
    if (size == null || size.width == 0 || size.height == 0 || params == null) {
      return;
    }

    final transform = WaveformViewTransform.forReference(
      params: params,
      zoom: _zoomState,
      size: size,
      origin: _refChannelOrigin,
    );

    final double dxPx = details.localPosition.dx - _refDragOriginPx.dx;
    final double dyPx = details.localPosition.dy - _refDragOriginPx.dy;

    var offset = ReferenceOffset(
      dxDiv: _refDragAnchor.dxDiv + dxPx * transform.dxDivPerPixel,
      // Screen y grows downwards, voltage upwards.
      dyDiv: _refDragAnchor.dyDiv - dyPx * transform.dyDivPerPixel,
    );

    if (HardwareKeyboard.instance.isShiftPressed) {
      offset = offset.snappedTo(
        _OsciHomePageState._refMinorDiv / _zoomState.zoomFactor,
      );
    }

    _setState(() {
      _refOffset = offset.clampedTo(
        maxDivX: _OsciHomePageState._refMaxDivX / _zoomState.zoomFactor,
        maxDivY: _OsciHomePageState._refMaxDivY / _zoomState.zoomFactor,
      );
    });
    // Only the difference trace and the mask depend on the offset; skip the
    // resampling work while both are hidden.
    if (_diffVisible || _maskSettings.enabled) {
      _recomputeReferenceAnalysis();
    }
  }
}
