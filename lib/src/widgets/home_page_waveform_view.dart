part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeWaveformView on _OsciHomePageState {
  /// The view mode actually shown; the Analysis tab falls back to the time
  /// view while the debug flag is off.
  _WaveformViewMode get _effectiveWaveformViewMode =>
      _waveformViewMode == _WaveformViewMode.analysis &&
          !_isWaveformAnalysisAvailable
      ? _WaveformViewMode.time
      : _waveformViewMode;

  /// The Analysis tab is a debug-only feature enabled by the `--debug` start
  /// flag.
  bool get _isWaveformAnalysisAvailable => widget.debugMode;

  /// First and last timestamp across all acquired channels, used to place
  /// the cursor read-out along the visible time axis.
  (double?, double?) _waveformTimeBounds() {
    double? tMin;
    double? tMax;
    for (final data in [
      _waveformCh1,
      _waveformCh2,
      _waveformCh3,
      _waveformCh4,
    ]) {
      if (data == null || data.points.isEmpty) continue;
      final first = data.points.first.$1;
      final last = data.points.last.$1;
      if (tMin == null || first < tMin) tMin = first;
      if (tMax == null || last > tMax) tMax = last;
    }
    return (tMin, tMax);
  }

  Widget _buildWaveformAnalysisView() {
    final timingMismatches = _referenceTimingMismatches();
    final timingWarningSignature = timingMismatches.isEmpty
        ? null
        : _referenceTimingWarningSignature(timingMismatches);
    final showTimingWarning =
        timingWarningSignature != null &&
        timingWarningSignature != _dismissedReferenceTimingWarning;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _buildViewModeButton('Time domain', _WaveformViewMode.time),
              const SizedBox(width: 6),
              _buildViewModeButton(
                'Spectrum',
                _WaveformViewMode.spectrum,
                enabled: _hasEnoughSpectrumData,
              ),
              if (_isWaveformAnalysisAvailable) ...[
                const SizedBox(width: 6),
                _buildViewModeButton('Analysis', _WaveformViewMode.analysis),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _effectiveWaveformViewMode == _WaveformViewMode.time
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.only(
                              left:
                                  _OsciHomePageState._waveformMarkerGutterWidth,
                              right: _OsciHomePageState
                                  ._waveformZeroMarkerGutterWidth,
                            ),
                            // The timing warning floats over the bottom edge of
                            // the chart so showing or hiding it never changes
                            // the chart height.
                            child: Stack(
                              children: [
                                _buildWaveformView(),
                                if (showTimingWarning)
                                  Positioned(
                                    left: 8,
                                    right: 8,
                                    bottom: 8,
                                    child: ReferenceTimingBanner(
                                      mismatches: timingMismatches,
                                      onDismiss: () => _setState(
                                        () => _dismissedReferenceTimingWarning =
                                            timingWarningSignature,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      WaveformMeasurementPanel(
                        measurements: _currentMeasurements(),
                        referenceMeasurement: _refVisible
                            ? _refMeasurements
                            : null,
                        referenceVdivVolts: _refVdivVolts,
                        referenceOffsetVolts: _refOffsetVolts,
                        statistics: _measurementStatistics(),
                        deviceParams: _deviceParams,
                        historyCount: _measurementHistoryCount(),
                        // The mask is derived from the reference; without a
                        // visible reference there is nothing to compare and
                        // the mask bar at the bottom is hidden as well.
                        maskAvailable: _refVisible && _refWaveform != null,
                        referenceVppVolts: _referenceVpp(),
                        referenceDurationSeconds: _referenceDurationSeconds(),
                        maskSettings: _maskSettings,
                        maskResult: _maskResult,
                        onMaskSettingsChanged: _onMaskSettingsChanged,
                        onRippleNoise: _showRippleNoiseDialog,
                        triggerSourceChannel: _triggerSourceChannel,
                        onOptimizeTimeDomain: _triggerSourcePeriod() == null
                            ? null
                            : () => unawaited(_optimizeTimeDomain()),
                        onOptimizeFrequencyAnalysis:
                            _triggerSourcePeriod() == null
                            ? null
                            : () => unawaited(_optimizeFrequencyAnalysis()),
                      ),
                    ],
                  )
                : _effectiveWaveformViewMode == _WaveformViewMode.analysis
                ? WaveformAnalysisView(
                    channels: _acquiredWaveformChannels(),
                    service: _waveformAnalysisService,
                    captureGeneration: _acquisitionGeneration,
                  )
                : SpectrumView(
                    result: _spectrumResult,
                    settings: _spectrumSettings,
                    selectedChannel: _spectrumChannel,
                    showAllChannels: _spectrumShowAll,
                    logFrequency: _spectrumLogFrequency,
                    loading: _spectrumLoading,
                    channelNotices: _spectrumChannelNotices(),
                    onChannelSelectionChanged: (channel) => _setState(() {
                      _spectrumShowAll = channel == null;
                      if (channel != null) _spectrumChannel = channel;
                    }),
                    onSettingsChanged: _onSpectrumSettingsChanged,
                    onLogFrequencyChanged: (value) =>
                        _setState(() => _spectrumLogFrequency = value),
                    plotKey: _spectrumKey,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeButton(
    String label,
    _WaveformViewMode mode, {
    bool enabled = true,
  }) {
    final selected = _effectiveWaveformViewMode == mode;
    return TextButton(
      onPressed: enabled ? () => _setWaveformViewMode(mode) : null,
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.white : Colors.white54,
        backgroundColor: selected
            ? const Color(0xFF1E3A8A)
            : const Color(0xFF172A45),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(
            color: selected ? Colors.blueAccent : AppColors.border,
            width: 0.8,
          ),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _setWaveformViewMode(_WaveformViewMode mode) {
    if (mode == _WaveformViewMode.analysis && !_isWaveformAnalysisAvailable) {
      return;
    }
    if (mode == _WaveformViewMode.spectrum && !_hasEnoughSpectrumData) {
      return;
    }
    if (_effectiveWaveformViewMode == mode) return;
    _setState(() => _waveformViewMode = mode);
    if (mode == _WaveformViewMode.spectrum &&
        _spectrumResult == null &&
        !_spectrumLoading) {
      unawaited(_recomputeSpectrum());
    }
  }

  Widget _buildWaveformView() {
    final (dataTMin, dataTMax) = _waveformTimeBounds();
    final showZeroOriginMarker =
        (_ch1Enabled && (_waveformCh1?.points.isNotEmpty ?? false)) ||
        (_ch2Enabled && (_waveformCh2?.points.isNotEmpty ?? false)) ||
        (_numChannels >= 4 &&
            _ch3Enabled &&
            (_waveformCh3?.points.isNotEmpty ?? false)) ||
        (_numChannels >= 4 &&
            _ch4Enabled &&
            (_waveformCh4?.points.isNotEmpty ?? false)) ||
        (_refVisible && (_refWaveform?.points.isNotEmpty ?? false));
    return AspectRatio(
      aspectRatio: 14 / 8,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              key: _waveformKey,
              child: MouseRegion(
                cursor: _refMoving
                    ? (_draggingRef
                          ? SystemMouseCursors.grabbing
                          : SystemMouseCursors.move)
                    : _hoveredCursorType == 'x'
                    ? SystemMouseCursors.resizeColumn
                    : _hoveredCursorType == 'y'
                    ? SystemMouseCursors.resizeRow
                    : _hoveredCursorType == 'info'
                    ? SystemMouseCursors.move
                    : SystemMouseCursors.basic,
                onHover: _onCursorHover,
                child: GestureDetector(
                  // Both modes share the same pan gesture; the dispatcher
                  // decides between aligning the reference and dragging a
                  // cursor.
                  onPanStart: _onWaveformPanStart,
                  onPanUpdate: _onWaveformPanUpdate,
                  onPanEnd: _onWaveformPanEnd,
                  child: Stack(
                    children: [
                      RepaintBoundary(
                        child: CustomPaint(
                          painter: WaveformBasePainter(
                            ch1: _waveformCh1,
                            ch2: _waveformCh2,
                            ch3: _waveformCh3,
                            ch4: _waveformCh4,
                            ref: _refWaveform,
                            refVisible: _refVisible,
                            refChannelOrigin: _refChannelOrigin,
                            refOffset: _refOffset,
                            refHighlighted: _refMoving,
                            diffTrace: _diffTrace,
                            diffVisible: _diffVisible,
                            maskBand: _maskBand,
                            maskVisible: _maskSettings.enabled,
                            maskViolations:
                                _maskResult?.violationPoints ?? const [],
                            params: _deviceParams!,
                            ch1Enabled: _ch1Enabled,
                            ch2Enabled: _ch2Enabled,
                            ch3Enabled: _numChannels >= 4 && _ch3Enabled,
                            ch4Enabled: _numChannels >= 4 && _ch4Enabled,
                            zoom: _zoomState,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      CustomPaint(
                        painter: CursorPainter(
                          cursors: _cursorState,
                          params: _deviceParams!,
                          zoom: _zoomState,
                          dataTMin: dataTMin,
                          dataTMax: dataTMax,
                        ),
                        child: const SizedBox.expand(),
                      ),
                      if (_refMoving && _refVisible && _refWaveform != null)
                        Positioned(
                          left: 12,
                          top: 12,
                          child: _buildRefMoveHint(),
                        ),
                      if (_zoomState.zoomFactor > 1.0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 24,
                          child: _buildHorizontalPanSlider(),
                        ),
                      if (_zoomState.zoomFactor > 1.0)
                        Positioned(
                          top: 0,
                          bottom: 24,
                          right: 0,
                          width: 24,
                          child: _buildVerticalPanSlider(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: -_OsciHomePageState._waveformMarkerGutterWidth,
            top: 0,
            bottom: 0,
            width: _OsciHomePageState._waveformMarkerGutterWidth,
            child: IgnorePointer(
              child: CustomPaint(
                painter: WaveformOffsetMarkerPainter(
                  params: _deviceParams!,
                  zoom: _zoomState,
                  ch1Active:
                      _ch1Enabled && (_waveformCh1?.points.isNotEmpty ?? false),
                  ch2Active:
                      _ch2Enabled && (_waveformCh2?.points.isNotEmpty ?? false),
                  ch3Active:
                      _numChannels >= 4 &&
                      _ch3Enabled &&
                      (_waveformCh3?.points.isNotEmpty ?? false),
                  ch4Active:
                      _numChannels >= 4 &&
                      _ch4Enabled &&
                      (_waveformCh4?.points.isNotEmpty ?? false),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          if (showZeroOriginMarker)
            Positioned(
              right: -_OsciHomePageState._waveformZeroMarkerGutterWidth,
              top: 0,
              bottom: 0,
              width: _OsciHomePageState._waveformZeroMarkerGutterWidth,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: WaveformZeroOriginMarkerPainter(zoom: _zoomState),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhysicalPanel() {
    return PhysicalControlPanel(
      isOnline: _isOnline,
      isProcessingEvent: _isProcessingEvent,
      screenDump: _screenDump!,
      ch1Enabled: _ch1Enabled,
      ch2Enabled: _ch2Enabled,
      channelCount: _numChannels,
      selectedChannel: _selectedChannel,
      onChannelToggle: _handleChannelButtonPress,
      onSoftKeyPressed: _handleSoftKeyPress,
      onMenuPressed: _handleMenuPress,
      onKnobChanged: _handleKnobChanged,
      onKnobTapped: _handleKnobTapped,
      onMenuButtonPressed: _handleButtonPress,
      onVerticalButtonPressed: _handleButtonPress,
      onNavigationButtonPressed: _handleButtonPress,
      onHorizontalButtonPressed: _handleButtonPress,
      onTriggerButtonPressed: _handleButtonPress,
      autoCaptureEnabled: _autoCaptureEnabled,
      onAutoCaptureChanged: _setAutoCaptureEnabled,
      timelapseRunning: _timelapseRunning,
      onTimelapsePressed: _isMacroPlaying
          ? null
          : (_timelapseRunning
                ? _stopTimelapse
                : (_isOnline ? _showTimelapseDialog : null)),
      showLiveButton: _showLiveButton,
      liveEnabled: _vncLive,
      liveAvailable: _vncReachable,
      onLiveChanged: _setVncLiveEnabled,
      liveScreen: _liveScreenImage,
      screenSettings: _screenSettings,
      onDisplaySettingsRequested: _openDisplayAdjustPanel,
      aiSettings: _aiSettings,
      chatController: _controlPanelChatController,
      vxi11Host: _ipAddress,
      instrumentDeviceContext: _sdsDeviceContext,
      voiceInput: _voiceInputService,
    );
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.8,
            child: Image.asset(
              'assets/icons/sds-remote.png',
              width: 400,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "Version 0.4.0",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 16,
              fontWeight: FontWeight.w300,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
