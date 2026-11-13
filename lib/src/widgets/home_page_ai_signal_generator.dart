part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeAiSignalGenerator on _OsciHomePageState {
  /// Reports the live signal-generator status to the Waveform Agent.
  Future<Map<String, dynamic>> _readSignalGeneratorStatusForAi() async {
    final device = _signalGenerator;
    final supported = device == 'jds6600' || device == 'fy6900';
    final service = _sigGenService;
    final store = await _deviceProfiles();
    final profileId = DeviceProfileIds.normalize(device);
    final profile = profileId == null ? null : store?.getProfile(profileId);
    final profileError = store != null && profileId != null && profile == null
        ? store.errorFor(profileId)?.toJson() ??
              {
                'error_code': DeviceErrorCode.profileNotLoaded.code,
                'error': 'The device profile "$profileId" is not loaded.',
              }
        : null;
    final profileStatus = profile == null
        ? null
        : buildDeviceProfileStatus(
            profile,
            identity: store!.resolveIdentity(
              service?.deviceInfo?.scpiIdentity,
              configuredDevice: device,
            ),
          );
    if (!supported || service == null) {
      return {
        'configured_device': device,
        'supported': supported,
        'connected': false,
        'error':
            'No signal generator is configured. Select JDS6600 or FY6900 in '
            'Settings -> Signal Generator.',
        'device_profile': ?profileStatus,
        'device_profile_error': ?profileError,
      };
    }
    if (!service.isConnected) {
      return {
        'configured_device': device,
        'supported': true,
        'detected': _sigGenDetected,
        'connected': false,
        'port': _sigGenPort,
        'error':
            'The signal generator is not connected. Check the USB connection '
            'and the device selection.',
        'device_profile': ?profileStatus,
        'device_profile_error': ?profileError,
      };
    }
    try {
      await service.refreshAll();
    } catch (_) {
      // Keep the cached values; the status below reports the last error.
    }
    final status = readMacroSiggenStatus(
      configuredDevice: device,
      detected: _sigGenDetected,
      service: service,
      rememberedPort: _sigGenPort,
    );
    final info = service.deviceInfo;
    if (profileStatus != null) {
      status['device_profile'] = profileStatus;
    }
    if (profileError != null) {
      status['device_profile_error'] = profileError;
    }
    if (info != null) {
      status['limits'] = {
        'min_frequency_hz': info.limits.minFrequencyHz,
        'max_frequency_hz_by_waveform': {
          for (final waveform in Jds6600Waveform.selectableFor(info.family))
            waveform.scpiMnemonic: info.maxFrequencyHz(waveform),
        },
        'min_offset_v': info.limits.minOffsetV,
        'max_offset_v': info.limits.maxOffsetV,
        'min_duty_percent': info.limits.minDutyPercent,
        'max_duty_percent': info.limits.maxDutyPercent,
        'min_phase_deg': info.limits.minPhaseDegrees,
        'max_phase_deg': info.limits.maxPhaseDegrees,
        'amplitude_vpp_by_frequency_band': _signalGeneratorAmplitudeBands(info),
      };
    }
    return status;
  }

  /// Amplitude limits of the generator by frequency band, for the planner.
  ///
  /// The last band omits `max_frequency_hz`, meaning unlimited. The values are
  /// JSON-safe (no infinity) and mirror `Jds6600DeviceInfo.maxAmplitudeVpp`.
  List<Map<String, Object?>> _signalGeneratorAmplitudeBands(
    Jds6600DeviceInfo info,
  ) {
    if (info.family == SiggenFamily.fy6900) {
      return const <Map<String, Object?>>[
        {'max_frequency_hz': 5e6, 'max_amplitude_vpp': 24.0},
        {'max_frequency_hz': 10e6, 'max_amplitude_vpp': 20.0},
        {'max_frequency_hz': 20e6, 'max_amplitude_vpp': 10.0},
        {'max_amplitude_vpp': 5.0},
      ];
    }
    return const <Map<String, Object?>>[
      {'max_frequency_hz': 10e6, 'max_amplitude_vpp': 20.0},
      {'max_amplitude_vpp': 10.0},
    ];
  }

  /// Applies a Waveform Agent signal-generator change request.
  ///
  /// The request is validated against the active device profile before the
  /// first command is sent. Unsupported waveforms, channels, units and unknown
  /// values return a structured error; they are never mapped silently.
  Future<Map<String, dynamic>> _applySignalGeneratorForAi(
    SignalGeneratorSettings settings,
  ) async {
    final service = _sigGenService;
    if (service == null || !service.isConnected) {
      return {'error': 'The signal generator is not connected.'};
    }

    final store = await _deviceProfiles();
    if (store == null) {
      return {
        'error_code': DeviceErrorCode.profileNotLoaded.code,
        'error': 'The device profiles are not available.',
      };
    }
    final profileId = DeviceProfileIds.normalize(_signalGenerator);
    if (profileId == null) {
      return {
        'error_code': DeviceErrorCode.profileUnknown.code,
        'error': 'No signal generator profile is configured.',
        'configured_device': _signalGenerator,
      };
    }
    DeviceProfile profile;
    try {
      profile = await store.loadProfile(profileId);
    } on DeviceCommandException catch (error) {
      return error.toJson();
    }

    final allowedChannels = profile.syntax.sourceChannelAllowedValues;
    if (allowedChannels.isNotEmpty &&
        !allowedChannels.contains(settings.channel)) {
      return DeviceCommandException(
        DeviceErrorCode.unsupportedChannel,
        'Channel ${settings.channel} is not supported by profile '
        '"$profileId".',
        profile: profileId,
        requestedValue: settings.channel,
        supportedValues: allowedChannels
            .map((value) => value.toString())
            .toList(growable: false),
      ).toJson();
    }

    final validatedCommands = <String, String>{};
    DeviceWaveformResolution? waveformResolution;
    Jds6600Waveform? resolvedWaveform;
    try {
      final channel = settings.channel;
      final frequency = settings.frequencyHz;
      if (frequency != null) {
        validatedCommands['freq'] = profile.registry.resolveCommand('freq', {
          'n': channel,
          'value': frequency,
          'unit': 'HZ',
        }).scpi;
      }
      final amplitude = settings.amplitudeVpp;
      if (amplitude != null) {
        validatedCommands['volt'] = profile.registry.resolveCommand('volt', {
          'n': channel,
          'value': amplitude,
          'unit': 'V',
        }).scpi;
      }
      final offset = settings.offsetV;
      if (offset != null) {
        validatedCommands['volt_offs'] = profile.registry.resolveCommand(
          'volt_offs',
          {'n': channel, 'value': offset, 'unit': 'V'},
        ).scpi;
      }
      final duty = settings.dutyPercent;
      if (duty != null) {
        validatedCommands['puls_dcyc'] = profile.registry.resolveCommand(
          'puls_dcyc',
          {'n': channel, 'value': duty, 'unit': '%'},
        ).scpi;
      }
      final phase = settings.phaseDeg;
      if (phase != null) {
        validatedCommands['phas'] = profile.registry.resolveCommand('phas', {
          'n': channel,
          'value': phase,
          'unit': 'DEG',
        }).scpi;
      }
      final output = settings.output;
      if (output != null) {
        validatedCommands['output_state'] = profile.registry.resolveCommand(
          'output_state',
          {'n': channel, 'state': output ? 'ON' : 'OFF'},
        ).scpi;
      }
      final requestedWaveform =
          settings.requestedWaveform ?? settings.waveform?.scpiMnemonic;
      if (requestedWaveform != null) {
        final resolved = profile.registry.resolveCommand('func', {
          'n': channel,
          'shape': requestedWaveform,
        });
        validatedCommands['func'] = resolved.scpi;
        waveformResolution = resolved.waveformResolution;
        resolvedWaveform = Jds6600Waveform.fromScpi(
          resolved.parameters['shape']!.toString(),
        );
        if (resolvedWaveform == null) {
          return DeviceCommandException(
            DeviceErrorCode.profileInconsistent,
            'The profile resolved the waveform to '
            '"${resolved.parameters['shape']}", which the driver does not '
            'know.',
            profile: profileId,
            parameter: 'shape',
            requestedValue: requestedWaveform,
          ).toJson();
        }
      }
    } on DeviceCommandException catch (error) {
      return error.toJson();
    }

    final applied = <String, dynamic>{};
    final logger = AppLogger(agentName: 'SigGen', toolName: 'applyForAi');
    logger.debug('Validated signal-generator commands: $validatedCommands');
    try {
      // Order matters: the device limits depend on the waveform and the
      // frequency, so set the waveform first and the frequency before the
      // amplitude.
      if (resolvedWaveform != null) {
        await service.setWaveform(settings.channel, resolvedWaveform);
        applied['waveform'] = resolvedWaveform.scpiMnemonic;
        final mapping = waveformResolution;
        if (mapping != null && mapping.mapped) {
          applied['waveform_mapping'] = mapping.toJson();
          logger.warning(
            'Signal generator waveform mapping: requested '
            '"${mapping.requested}", resolved "${mapping.resolved}", '
            'channel ${mapping.channel}.',
          );
        }
      }
      if (settings.frequencyHz != null) {
        await service.setFrequency(settings.channel, settings.frequencyHz!);
        applied['frequency_hz'] = settings.frequencyHz;
      }
      if (settings.amplitudeVpp != null) {
        await service.setAmplitude(settings.channel, settings.amplitudeVpp!);
        applied['amplitude_vpp'] = settings.amplitudeVpp;
      }
      if (settings.offsetV != null) {
        await service.setOffset(settings.channel, settings.offsetV!);
        applied['offset_v'] = settings.offsetV;
      }
      if (settings.dutyPercent != null) {
        await service.setDuty(settings.channel, settings.dutyPercent!);
        applied['duty_percent'] = settings.dutyPercent;
      }
      if (settings.phaseDeg != null) {
        await service.setPhase(settings.channel, settings.phaseDeg!);
        applied['phase_deg'] = settings.phaseDeg;
      }
      if (settings.output != null) {
        await service.setOutput(settings.channel, settings.output!);
        applied['output'] = settings.output;
      }
      // Read the real state back so a duty-driven waveform change (square to
      // RECT on the FY6900) is visible to the agent.
      try {
        await service.refreshAll();
      } catch (_) {
        // The cached values remain; the status below reports them.
      }
      final actualWaveform = service.channel(settings.channel).waveform;
      if (settings.dutyPercent != null &&
          applied['waveform'] != null &&
          actualWaveform.scpiMnemonic != applied['waveform']) {
        applied['waveform_after_apply'] = actualWaveform.scpiMnemonic;
        applied['note'] =
            'The FY6900 switches a square shape to RECT so the duty cycle '
            'takes effect. The channel is now ${actualWaveform.scpiMnemonic}.';
      }
      final identity = store.resolveIdentity(
        service.deviceInfo?.scpiIdentity,
        configuredDevice: _signalGenerator,
      );
      return {
        'success': true,
        'channel': settings.channel,
        'applied': applied,
        'device_profile': buildDeviceProfileStatus(profile, identity: identity),
        'status': readMacroSiggenStatus(
          configuredDevice: _signalGenerator,
          detected: _sigGenDetected,
          service: service,
          rememberedPort: _sigGenPort,
        ),
      };
    } on Jds6600Exception catch (error) {
      return {
        'error_code': DeviceErrorCode.deviceCommunicationFailed.code,
        'error': error.message,
        'profile': profileId,
        'channel': settings.channel,
        'applied': applied,
      };
    } catch (error) {
      return {
        'error_code': DeviceErrorCode.deviceCommunicationFailed.code,
        'error': 'Signal generator command failed: $error',
        'profile': profileId,
        'channel': settings.channel,
        'applied': applied,
      };
    }
  }

  /// Runs a reset or stop action on the connected signal generator.
  Future<Map<String, dynamic>> _controlSignalGeneratorForAi(
    String operation,
  ) async {
    final service = _sigGenService;
    if (service == null || !service.isConnected) {
      return {'error': 'The signal generator is not connected.'};
    }
    try {
      switch (operation) {
        case 'reset_safe_state':
          await service.resetSafeState();
        case 'stop_action':
          await service.stopActions();
        default:
          return {'error': 'Unknown signal generator operation "$operation".'};
      }
      return {
        'success': true,
        'operation': operation,
        'status': readMacroSiggenStatus(
          configuredDevice: _signalGenerator,
          detected: _sigGenDetected,
          service: service,
          rememberedPort: _sigGenPort,
        ),
      };
    } on Jds6600Exception catch (error) {
      return {'error': error.message};
    } catch (error) {
      return {'error': 'Signal generator command failed: $error'};
    }
  }
}
