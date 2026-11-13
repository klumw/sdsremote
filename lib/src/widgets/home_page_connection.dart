part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeConnection on _OsciHomePageState {
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pingDevice(),
    );
    _pingDevice();
  }

  /// Called by [Vxi11Instrument] when a fatal USB transfer error invalidated
  /// the shared connection (IO_ERROR, PIPE, NO_DEVICE).
  ///
  /// Drops the cached instrument synchronously, so the next operation opens a
  /// fresh device, and marks the UI offline. Once the device is reachable
  /// again, the ping timer reopens it — replugging is enough, no app restart.
  void _onUsbConnectionLost() {
    if (!_isUsb) {
      // A USB operation from a previous connection mode is still unwinding;
      // do not disturb the current (network) instrument.
      return;
    }
    AppLogger().warning('USB connection lost; dropping cached instrument');
    // _closeInstrument() clears _instrument before its first await, so no
    // follow-up operation can reuse the dead instrument.
    unawaited(_closeInstrument());
    _markUsbDeviceOffline();
  }

  /// Marks the device offline and clears the cached identity after a USB
  /// disconnect or a fatal transfer error.
  void _markUsbDeviceOffline() {
    if (!mounted) return;
    _setState(() {
      _isOnline = false;
      _deviceName = null;
      _deviceModel = null;
      _numChannels = 2;
    });
    _setFallbackWindowTitle();
    _restoreLiveOnPanelReturn = false;
    _stopVncLive(fetchScreen: false, restoreAutoCapture: false);
    _clearVncAvailability();
  }

  Future<void> _pingDevice() async {
    if (_isPinging || _isAcquiring || _isAcquiringWaveform || _bodeIsRunning) {
      return;
    }
    _isPinging = true;

    try {
      if (_isUsb) {
        final address = await Vxi11Instrument.detectLiveVisaAddress();
        if (address == null) {
          // The oscilloscope disappeared from the bus. Invalidate the shared
          // handle and drop the cached instrument so a replug opens a fresh
          // connection instead of retrying a dead one.
          if (_instrument != null || Vxi11Instrument.hasSharedUsbConnection) {
            await Vxi11Instrument.invalidateUsbConnection();
          }
          _markUsbDeviceOffline();
          return;
        }

        if (mounted) {
          _setState(() => _isOnline = true);
          if (_deviceName == null) {
            // Awaited so _isPinging stays set until the IDN query finishes;
            // otherwise the next tick starts a second device query while
            // this one is still in flight.
            await _updateWindowTitle();
          } else {
            windowManager.setTitle(_deviceName!);
            // Re-assert the name: a transient ping failure clears it (see
            // _setFallbackWindowTitle) and _updateWindowTitle() is only
            // called while _deviceName is still unknown, so the agent would
            // otherwise never learn it again.
            _aiChatService.updateInstrumentModel(_deviceModel);
          }
        }
      } else {
        final socket = await Socket.connect(
          _ipAddress,
          111,
          timeout: const Duration(seconds: 3),
        );
        socket.destroy();
        if (mounted) {
          _setState(() => _isOnline = true);
          if (_deviceName == null) {
            await _updateWindowTitle();
          } else {
            windowManager.setTitle(_deviceName!);
            // Re-assert the name; see the note in the USB branch above.
            _aiChatService.updateInstrumentModel(_deviceModel);
          }
          unawaited(_refreshVncAvailability());
        }
      }
    } catch (e) {
      if (_isUsb) {
        // Clear the cached identity so the next successful ping re-queries
        // *IDN? after the device becomes reachable again.
        _markUsbDeviceOffline();
      } else if (mounted) {
        _setState(() => _isOnline = false);
        _setFallbackWindowTitle();
        _restoreLiveOnPanelReturn = false;
        _stopVncLive(fetchScreen: false, restoreAutoCapture: false);
        _clearVncAvailability();
      }
    } finally {
      _isPinging = false;
    }
  }

  /// Sets the window title to the fallback value when the device name
  /// cannot be determined (offline, connection error, etc.).
  void _setFallbackWindowTitle() {
    if (_isUsb) {
      windowManager.setTitle('SDS-Remote — USB');
    } else {
      windowManager.setTitle('SDS-Remote — $_ipAddress');
    }
    // No instrument is reachable, so the AI must stop naming a specific model.
    // It answers knowledge and software questions either way.
    _sdsDeviceContext = _sdsDeviceContext?.withInstrumentModel(null);
    _aiChatService.updateInstrumentModel(null);
  }

  Future<void> _updateWindowTitle() async {
    try {
      // Use the cached instrument to avoid creating a separate USB connection
      // that would fight with the kernel driver detach/attach cycle.
      final instr = _instrument ?? await _getInstrument();
      if (instr == null) {
        _setFallbackWindowTitle();
        return;
      }
      final idn = (await instr.queryString('*IDN?')).trim();
      final parts = idn.split(',');
      final name = parts.length >= 2
          ? '${parts[0].trim()} ${parts[1].trim()}'
          : idn;
      // The model designation alone ("SDS1202X-E") is what identifies the
      // instrument in the knowledge base. The vendor prefix of the display
      // name is not part of the model and does not appear in the knowledge
      // base text, so it must not be used for searching.
      final model = parts.length >= 2 ? parts[1].trim() : idn;
      // The instrument reports its available channels directly; fall back to
      // the model number when the query is unavailable.
      int? chsChannels;
      try {
        chsChannels = channelCountFromChs(await instr.queryString('CHS?'));
      } catch (e) {
        AppLogger().warning('CHS? query failed, using model number: $e');
      }
      if (mounted) {
        _setState(() {
          _deviceName = name;
          _deviceModel = model;
          _sdsDeviceContext = _sdsDeviceContext?.withInstrumentModel(model);
          _numChannels = chsChannels ?? channelCountForModel(model);
          if (_selectedChannel > _numChannels) _selectedChannel = 1;
        });
        windowManager.setTitle(name);
        // Tell the AI which oscilloscope it is answering for. The agent is
        // configured before the first device response, so it learns the model
        // here rather than at construction time.
        _aiChatService.updateInstrumentModel(model);
        if (_numChannels < 4) {
          // A two-channel model has no live screen; drop a stale session and
          // never try to restore one.
          _restoreLiveOnPanelReturn = false;
          if (_vncLive) {
            _stopVncLive(fetchScreen: false, restoreAutoCapture: false);
          }
        }
        unawaited(_refreshVncAvailability(force: true));
      }
    } catch (_) {
      if (mounted) {
        _setFallbackWindowTitle();
      }
    }
  }

  Future<Vxi11Instrument?> _getInstrument() async {
    if (_instrument != null) return _instrument;
    // Join an open that is already running instead of starting a second one.
    final inFlight = _instrumentOpenInFlight;
    if (inFlight != null) return inFlight;

    final future = _openInstrument();
    _instrumentOpenInFlight = future;
    try {
      return await future;
    } finally {
      _instrumentOpenInFlight = null;
    }
  }

  Future<Vxi11Instrument?> _openInstrument() async {
    try {
      final instr = Vxi11Instrument(_ipAddress, sourceLabel: 'getInstrument');
      await instr.open(timeoutSeconds: 5.0);
      _instrument = instr;
      return _instrument;
    } catch (e) {
      // open() drives either transport; naming the wrong one here sends the
      // reader hunting in the wrong layer (a USB claim failure used to be
      // reported as a VXI-11 failure).
      final transport = Vxi11Instrument.isUsbMode ? 'USB (USBTMC)' : 'VXI-11';
      AppLogger().error('Failed to open $transport connection: $e');
      _setState(() => _isOnline = false);
      return null;
    }
  }

  Future<void> _closeInstrument() async {
    if (_instrument != null) {
      final instr = _instrument!;
      _instrument = null;
      try {
        // Use a tight timeout: instr.close() sends a DESTROY_LINK RPC
        // and closes the TCP socket.  If the instrument is unresponsive
        // this must not block application shutdown for more than 1 s.
        await instr.close().timeout(const Duration(seconds: 1));
      } catch (e) {
        AppLogger().error('Error closing instrument: $e');
      }
    }
  }

  /// NOTE: In USB mode the connection is deliberately NOT released after each
  /// SCPI transaction any more.
  ///
  /// Releasing it made the kernel driver re-attach (and re-probe the device)
  /// after every transaction, then detach again on the next claim. That
  /// detach/attach churn — 40 open cycles in a single session — de-stabilised
  /// the USB link: the instrument re-enumerated underneath the app and opens
  /// started failing with "Failed to claim interface 0: error code -6 (BUSY)".
  /// The interface is now claimed once and held for the lifetime of the app,
  /// and released in [dispose].

  void _scheduleRefresh({
    Duration extraDelay = Duration.zero,
    bool reschedule = false,
  }) {
    // While the live screen streams the current display there is no point in
    // fetching SCPI screen dumps; the VNC stream already shows every change.
    if (_vncLive) return;
    if (_refreshPending && !reschedule) return;
    _refreshPending = true;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(
      Duration(milliseconds: _OsciHomePageState._refreshDelayMs) + extraDelay,
      () {
        _refreshPending = false;
        if (mounted && _isOnline && !_isAcquiringWaveform && !_bodeIsRunning) {
          _acquireScreenDump(keepPanels: true);
        }
      },
    );
  }

  /// Starts or stops the periodic screen capture requested by the toggle at
  /// the bottom right of the Control Panel. While enabled, a fresh screen
  /// dump is fetched every [_autoCaptureInterval].
  void _setAutoCaptureEnabled(bool enabled) {
    // The periodic capture and the live screen are mutually exclusive; the
    // toggle is disabled in the UI while live, this guards programmatic calls.
    if (enabled && _vncLive) return;
    if (enabled && _timelapseRunning) return;
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _setState(() => _autoCaptureEnabled = enabled);
    if (!enabled) return;

    _autoCaptureTimer = Timer.periodic(
      _OsciHomePageState._autoCaptureInterval,
      (_) {
        if (!mounted ||
            !_isOnline ||
            _isAcquiring ||
            _isAcquiringWaveform ||
            _bodeIsRunning ||
            _timelapseRunning ||
            _screenDump == null ||
            _activePanel != ActivePanel.none) {
          return;
        }
        _acquireScreenDump(keepPanels: true);
      },
    );
  }

  /// Stops the periodic screen capture and resets the toggle to "off".
  void _stopAutoCapture() {
    if (_autoCaptureTimer == null && !_autoCaptureEnabled) return;
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    if (mounted) {
      _setState(() => _autoCaptureEnabled = false);
    } else {
      _autoCaptureEnabled = false;
    }
  }

  /// Sends a SCPI command to the instrument and returns true if successful.
  /// Shows error message on failure.
  /// If a macro recording is in progress the command is captured into
  /// [_currentMacroContent].
  Future<bool> _sendCommand(String command) async {
    // Capture SCPI commands during macro recording
    if (_isMacroRecording) {
      _currentMacroContent += 'cmd("$command")\n';
    }

    if (!_isOnline) {
      AppLogger().error('Popup: Device is offline');
      _showErrorSnackBar('Device is offline');
      return false;
    }

    try {
      final instr = await _getInstrument();
      if (instr == null) return false;

      await instr.writeString(command);
      return true;
    } catch (e) {
      AppLogger().error('Send command error: $e');
      _closeInstrument(); // Connection might be bad
      AppLogger().error('Popup: Failed to send command: $e');
      _showErrorSnackBar('Failed to send command: $e');
      return false;
    }
  }
}
