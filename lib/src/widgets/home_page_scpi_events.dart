part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeScpiEvents on _OsciHomePageState {
  /// Sends a SCPI command, waits for the instrument to process it,
  /// refreshes the screen dump, and enforces a cooldown.
  ///
  /// Returns `true` if the command was sent and screen refreshed successfully.
  Future<bool> _processScpiEvent(
    String command, {
    String? errorContext,
    Duration extraProcessingDelay = Duration.zero,
  }) async {
    if (_isProcessingEvent || !_isOnline) return false;

    _isProcessingEvent = true;
    if (mounted) _setState(() {});

    try {
      if (await _sendCommand(command)) {
        // Wait for oscilloscope to process the command. Auto Setup passes a
        // longer delay because a full acquisition setup takes extra time.
        await Future.delayed(
          Duration(
            milliseconds:
                _OsciHomePageState._refreshDelayMs +
                extraProcessingDelay.inMilliseconds,
          ),
        );
        // Fetch the screen dump synchronously — except while the live screen
        // is active: the VNC stream already reflects the new display state.
        if (!_vncLive) {
          await _acquireScreenDump(keepPanels: true);
        }
        // Final cooldown before next event is allowed
        await Future.delayed(const Duration(milliseconds: 500));
        return true;
      }
    } catch (e) {
      final ctx = errorContext ?? command;
      AppLogger().error('$ctx handler error: $e');
      if (mounted) {
        _showErrorSnackBar('Error processing $ctx: $e');
      }
    } finally {
      _isProcessingEvent = false;
      if (mounted) _setState(() {});
    }
    return false;
  }

  /// Handles soft key button press (M1-M6).
  /// Sends $$SY_FP X,1 command where X is button number, then refreshes screen.
  Future<bool> _handleSoftKeyPress(int buttonNumber) => _processScpiEvent(
    '\$\$SY_FP $buttonNumber,1',
    errorContext: 'M$buttonNumber',
  );

  /// Handles MENU button press.
  /// Sends $$SY_FP 0,1 command (VXI special SPCI command for MENU button),
  /// then immediately requests a screen dump image.
  Future<bool> _handleMenuPress() =>
      _processScpiEvent('\$\$SY_FP 0,1', errorContext: 'MENU');

  /// Generic handler for knob rotation (value changes).
  /// Sends `$$SY_FP <cmd>,1` when turned right or `$$SY_FP <cmd>,-1` when left.
  Future<void> _handleKnobChanged(KnobId knob, double newValue) async {
    final prev = _knobPreviousValues[knob]!;
    if (newValue == prev || !_isOnline || _isProcessingEvent) return;
    final dir = newValue > prev ? 1 : -1;
    await _processScpiEvent(
      '\$\$SY_FP ${knob.scpiCommandNumber},$dir',
      errorContext: '${knob.name} knob',
    );
    _knobPreviousValues[knob] = newValue;
  }

  /// Generic handler for knob tap/click.
  /// Sends `$$SY_FP <cmd>,0`.
  Future<void> _handleKnobTapped(KnobId knob) => _processScpiEvent(
    '\$\$SY_FP ${knob.scpiCommandNumber},0',
    errorContext: '${knob.name} knob tap',
  );

  /// Channel buttons select the channel the shared vertical knobs act on and
  /// then send the front-panel toggle command for it.
  Future<bool> _handleChannelButtonPress(String channel) async {
    final number = int.tryParse(channel.replaceFirst('CH', ''));
    if (number != null && number >= 1 && number <= _numChannels) {
      _setState(() => _selectedChannel = number);
    }
    return _handleButtonPress(channel);
  }

  /// Generic handler for any button press (menu, vertical, horizontal, trigger, channel).
  /// Looks up the SCPI command from [buttonCommands] and sends it.
  Future<bool> _handleButtonPress(String buttonLabel) async {
    final command = buttonCommands[buttonLabel];
    if (command == null) {
      AppLogger().log('Button "$buttonLabel" not implemented yet');
      if (mounted) {
        _showInfoSnackBar('Button "$buttonLabel" not implemented yet');
      }
      return false;
    }
    return _processScpiEvent(
      command,
      errorContext: buttonLabel,
      // Auto Setup needs the instrument's full acquisition setup to finish
      // before the display reflects the result.
      extraProcessingDelay: buttonLabel == autoSetupButtonLabel
          ? _OsciHomePageState._autoSetupExtraDelay
          : Duration.zero,
    );
  }
}
