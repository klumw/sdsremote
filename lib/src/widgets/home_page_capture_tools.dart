part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeCaptureTools on _OsciHomePageState {
  /// Sets a timebase with about four visible periods on the trigger channel.
  Future<void> _optimizeTimeDomain() async {
    final period = _triggerSourcePeriod();
    if (period == null) return;
    final timebase = timebaseForPeriods(
      period,
      targetPeriods: timeDomainTargetPeriodsOnScreen,
    );
    await _setTimebaseAndRefresh(
      timebase,
      'Timebase optimized for time-domain analysis: '
      '${formatTimebase(timebase)}',
    );
  }

  /// Sets a timebase with at least 80 visible periods on the trigger channel.
  Future<void> _optimizeFrequencyAnalysis() async {
    final period = _triggerSourcePeriod();
    if (period == null) return;
    final timebase = timebaseForFftPeriods(period);
    await _setTimebaseAndRefresh(
      timebase,
      'Timebase optimized for frequency analysis: '
      '${formatTimebase(timebase)}',
    );
  }

  /// Sends [timebaseSeconds] to the instrument and refreshes the waveform.
  Future<void> _setTimebaseAndRefresh(
    double timebaseSeconds,
    String message,
  ) async {
    final value = timebaseSeconds.toStringAsExponential(2).toUpperCase();
    if (!await _sendCommand('TDIV $value')) return;
    if (!mounted) return;
    _showInfoSnackBar(message);
    // Let the instrument apply the new timebase and acquire a fresh trace
    // before refreshing the waveform view.
    await Future.delayed(
      const Duration(milliseconds: _OsciHomePageState._refreshDelayMs),
    );
    // A manual acquisition started during the settling delay already refreshes
    // the view with the new timebase, so do not start a second one.
    if (!mounted || _isAcquiringWaveform) return;
    await _acquireWaveform();
  }

  /// Opens the timelapse settings dialog and starts the run.
  Future<void> _showTimelapseDialog() async {
    if (!_isOnline) {
      _showErrorSnackBar('Device is offline');
      return;
    }
    final plan = await showDialog<TimelapsePlan>(
      context: context,
      builder: (_) =>
          TimelapseDialog(targetDirectory: AppPaths.timelapseDirectory.path),
    );
    if (plan == null || !mounted) return;
    await _runTimelapse(plan);
  }

  /// Aborts a running timelapse immediately, including the current interval
  /// wait.
  void _stopTimelapse() {
    _timelapseSession?.abort();
    final stop = _timelapseStop;
    if (stop != null && !stop.isCompleted) stop.complete();
  }

  /// Captures [plan] frames into a timestamped folder under
  /// [AppPaths.timelapseDirectory].
  ///
  /// Auto capture and the live screen are stopped first; both stay blocked
  /// while the run is active.
  Future<void> _runTimelapse(TimelapsePlan plan) async {
    if (_timelapseRunning) return;
    if (_isAcquiring || _isAcquiringWaveform || _bodeIsRunning) {
      _showInfoSnackBar('Another capture is running. Try again afterwards.');
      return;
    }
    _stopAutoCapture();
    _restoreLiveOnPanelReturn = false;
    _stopVncLive(fetchScreen: false, restoreAutoCapture: false);
    _clearVncAvailability();

    final Directory runDirectory;
    try {
      final base = await AppPaths.getOrCreateTimelapseDir();
      runDirectory = await Directory(
        '${base.path}${Platform.pathSeparator}'
        '${timelapseRunFolderName(DateTime.now())}',
      ).create(recursive: true);
    } catch (e) {
      AppLogger().error('Timelapse folder error: $e');
      _showErrorSnackBar('Timelapse folder error: $e');
      return;
    }

    if (!mounted) return;

    final session = TimelapseSession(plan: plan);
    final stop = Completer<void>();
    final progress = ValueNotifier<int>(0);
    _timelapseSession = session;
    _timelapseStop = stop;
    _setState(() => _timelapseRunning = true);

    _timelapseSnackBar = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(days: 1),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, value, _) =>
              Text('Timelapse: frame $value / ${plan.frameCount}'),
        ),
        action: SnackBarAction(label: 'Stop', onPressed: _stopTimelapse),
      ),
    );

    try {
      while (session.isActive) {
        final fileName = session.nextFileName;
        if (fileName == null) break;
        final instr = await _getInstrument();
        if (instr == null) throw Exception('Device is offline');
        final data = await instr.getScreenDump();
        final processed = await compute(processScreenDump, data);
        await File(
          '${runDirectory.path}${Platform.pathSeparator}$fileName',
        ).writeAsBytes(processed);
        session.recordCaptured();
        progress.value = session.captured;
        if (!session.isActive) break;
        final delay = Future<void>.delayed(plan.interval);
        await Future.any<void>([delay, stop.future]);
      }
    } catch (e) {
      AppLogger().error('Timelapse frame failed: $e');
      session.abort();
      if (mounted) _showErrorSnackBar('Timelapse stopped: $e');
    } finally {
      _timelapseSnackBar?.close();
      _timelapseSnackBar = null;
      _timelapseSession = null;
      _timelapseStop = null;
      // The snackbar animates out while it may still rebuild its content.
      unawaited(
        Future<void>.delayed(const Duration(seconds: 1), progress.dispose),
      );
      if (mounted) {
        _setState(() => _timelapseRunning = false);
        final frames = session.captured;
        if (session.isComplete) {
          _showInfoSnackBar(
            'Timelapse finished: $frames frames saved in ${runDirectory.path}',
            duration: const Duration(seconds: 8),
          );
        } else if (frames > 0) {
          _showInfoSnackBar('Timelapse stopped after $frames frames');
        }
      } else {
        _timelapseRunning = false;
      }
    }
  }

  /// Opens the ripple/noise dialog for the connected instrument.
  Future<void> _showRippleNoiseDialog() async {
    if (!_isOnline) {
      _showErrorSnackBar('Device is offline');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => RippleNoiseDialog(
        channels: _numChannels >= 4 ? const [1, 2, 3, 4] : const [1, 2],
        run: _runRippleNoiseMeasurement,
      ),
    );
  }

  /// Applies the ripple/noise preset, reads RMS and Vpp, then restores the
  /// previous channel settings.
  ///
  /// The previous coupling, bandwidth limit, V/div and offset are queried
  /// first; a failed query falls back to the documented defaults instead of
  /// aborting the measurement.
  Future<String> _runRippleNoiseMeasurement({
    required int channel,
    required double vdiv,
    required double offset,
    required bool bandwidthLimit,
    required bool restore,
  }) async {
    final instr = await _getInstrument();
    if (instr == null) throw Exception('Device is offline');

    Future<String?> queryOrNull(String command) async {
      try {
        return await instr.queryString(command);
      } catch (e) {
        AppLogger().warning('Ripple preset: $command failed: $e');
        return null;
      }
    }

    var previousCoupling = 'D1M';
    var previousBandwidthLimit = false;
    double? previousVdiv;
    double? previousOffset;
    if (restore) {
      previousCoupling =
          parseCouplingResponse(await queryOrNull('C$channel:CPL?') ?? '') ??
          previousCoupling;
      previousBandwidthLimit =
          parseBandwidthLimitResponse(
            await queryOrNull('BWL?') ?? '',
            channel,
          ) ??
          previousBandwidthLimit;
      previousVdiv = parseVoltageResponse(
        await queryOrNull('C$channel:VDIV?') ?? '',
      );
      previousOffset = parseVoltageResponse(
        await queryOrNull('C$channel:OFST?') ?? '',
      );
    }

    final plan = buildRippleNoisePlan(
      channel: channel,
      vdiv: vdiv,
      offset: offset,
      bandwidthLimit: bandwidthLimit,
      previousCoupling: previousCoupling,
      previousBandwidthLimit: previousBandwidthLimit,
      previousVdiv: previousVdiv,
      previousOffset: previousOffset,
    );

    final responses = <String>[];
    try {
      for (final command in plan.applyCommands) {
        await instr.writeString(command);
      }
      // Give the acquisition a moment to settle on the new scale.
      await Future.delayed(const Duration(milliseconds: 300));
      for (final command in plan.measureCommands) {
        responses.add(await instr.queryString(command));
      }
    } finally {
      if (restore) {
        for (final command in plan.restoreCommands) {
          try {
            await instr.writeString(command);
          } catch (e) {
            AppLogger().warning('Ripple restore failed: $e');
          }
        }
      }
    }

    return formatRippleNoiseResult(
      rms: responses.isEmpty ? null : parseVoltageResponse(responses[0]),
      vpp: responses.length < 2 ? null : parseVoltageResponse(responses[1]),
    );
  }
}
