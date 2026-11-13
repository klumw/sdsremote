part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeAiService on _OsciHomePageState {
  bool get _isAiEnabled =>
      _aiProvider.isNotEmpty &&
      _aiApiToken.trim().length >= 8 &&
      _llmModel.trim().isNotEmpty;

  /// AI settings shared by the feature assistants (Macro Editor, Control
  /// Panel and help window), or null when the AI is not configured.
  ///
  /// The main chat is configured separately through [AiChatService]; the
  /// assistants use the same provider, token and model so every AI feature
  /// follows the values from the settings panel.
  AiSettings? get _aiSettings {
    if (!_isAiEnabled) return null;
    return AiSettings.fromProviderConfig(
      providerName: _aiProvider,
      apiToken: _aiApiToken,
      modelName: _llmModel,
    );
  }

  /// Refreshes the screen dump shown next to the Control Panel chat after the
  /// AI assistant changed a setting on the oscilloscope.
  ///
  /// Write commands are passed through the existing debounce with extra
  /// settling time, so the instrument has rendered the new setting before the
  /// capture is taken. Several commands in one agent turn restart the timer,
  /// resulting in a single capture after the last change.
  void _onControlPanelAiCommand(String command, String operation) {
    if (operation != 'write') return;
    _scheduleRefresh(
      extraDelay: _OsciHomePageState._controlPanelAiRefreshDelay,
      reschedule: true,
    );
  }

  /// Fetches a fresh Control Panel screen dump for a short capture command
  /// such as "snapshot" or "Aufnahme" in the Control Panel AI assistant.
  Future<Map<String, dynamic>> _refreshScreenDumpForAi() async {
    if (!mounted) {
      return {'error': 'The application window is not available.'};
    }
    if (!_isOnline) {
      return {'error': 'The oscilloscope is offline.'};
    }
    if (_isAcquiring || _isAcquiringWaveform || _timelapseRunning) {
      return {'error': 'The oscilloscope is busy.'};
    }
    await _acquireScreenDump(keepPanels: true);
    if (!mounted || !_isOnline || _screenDump == null) {
      return {
        'error':
            'The screen dump could not be read. Check the connection and the '
            'application log.',
      };
    }
    return {'success': true};
  }

  /// Configures the [AiChatService] with the current provider, API token,
  /// model, and device IP.
  ///
  /// Looks up the [providerConfigs] table to map the selected provider name
  /// to the correct API key environment variable name and model prefix.
  /// The full model string is constructed as `<prefix>:<model>` (e.g.
  /// `openai:gpt-4o`).
  // =========================================================================
  // Waveform AI assistant
  // =========================================================================

  void _toggleWaveformAi() => _waveformAiController.toggle();

  void _closeWaveformAi() => _waveformAiController.close();

  /// Configures the Waveform AI assistant from the current AI settings.
  void _configureWaveformAi() => _waveformAiController.configure();

  /// Returns authorized command definitions and knowledge for the Macro
  /// Editor's dynamic command-reference tool.
  Future<Map<String, dynamic>> _readDeviceCommandReferenceForAi({
    String? profileId,
    String? commandId,
    String? query,
  }) async {
    final store = await _deviceProfiles();
    if (store == null) {
      return {
        'error_code': DeviceErrorCode.profileNotLoaded.code,
        'error': 'The device profiles are not available.',
      };
    }

    if (profileId == null) {
      final details = <Map<String, dynamic>>[];
      for (final id in store.loadedProfileIds) {
        final profile = store.getProfile(id);
        if (profile == null) continue;
        details.add({
          'profile_id': profile.profileId,
          'display_name': profile.displayName,
          'package_id': profile.metadata.packageId,
          'command_count': profile.commands.length,
          'knowledge_version': profile.knowledge.metadata.version,
        });
      }
      return {
        'profiles': store.loadedProfileIds,
        'configured_signal_generator': _signalGenerator,
        'profiles_detail': details,
      };
    }

    DeviceProfile profile;
    try {
      profile = await store.loadProfile(profileId);
    } on DeviceCommandException catch (error) {
      return error.toJson();
    }

    if (commandId != null) {
      try {
        return profile.getCommandDocumentation(commandId).toJson();
      } on DeviceCommandException catch (error) {
        return error.toJson();
      }
    }

    if (query != null) {
      final commands = profile.registry
          .findCommands(query)
          .take(20)
          .map(
            (command) => {
              'command_id': command.commandId,
              'name': command.name,
              'description': command.description,
              'scpi_pattern': command.scpiPattern,
              'query_pattern': command.queryPattern,
              'operation_kind': command.operationKind.wireName,
              'query_support': command.querySupport.wireName,
            },
          )
          .toList(growable: false);
      final knowledge = profile
          .searchKnowledge(query)
          .map((result) => result.toJson())
          .toList(growable: false);
      return {
        'profile_id': profile.profileId,
        'query': query,
        'commands': commands,
        'knowledge': knowledge,
      };
    }

    return {
      'profile_id': profile.profileId,
      'display_name': profile.displayName,
      'package_id': profile.metadata.packageId,
      'schema_version': profile.metadata.schemaVersion,
      'device_scope': profile.metadata.deviceScope,
      'knowledge_version': profile.knowledge.metadata.version,
      'commands': [
        for (final command in profile.commands)
          {
            'command_id': command.commandId,
            'name': command.name,
            'description': command.description,
            'scpi_pattern': command.scpiPattern,
            'query_pattern': command.queryPattern,
            'operation_kind': command.operationKind.wireName,
            'query_support': command.querySupport.wireName,
          },
      ],
      'knowledge_sections': [
        for (final section in profile.knowledge.sections)
          {'id': section.id, 'title': section.title},
      ],
    };
  }

  void _configureAiService() {
    final logger = AppLogger(
      agentName: 'main',
      toolName: '_configureAiService',
    );
    logger.log('ENTER: _configureAiService()');

    if (_aiProvider.isEmpty || _aiApiToken.trim().length < 8) {
      logger.log(
        'EXIT: AI provider or token not valid, skipping configuration. '
        '_aiProvider="$_aiProvider", token length=${_aiApiToken.trim().length}',
      );
      return;
    }

    if (_llmModel.trim().isEmpty) {
      logger.log('EXIT: LLM model is empty, deactivating AI agent');
      _aiChatService.deactivate();
      if (mounted) {
        _setState(() {});
      }
      return;
    }

    // Look up the provider configuration from the table.
    final config = providerConfigs.firstWhere(
      (c) => c.providerName == _aiProvider,
      orElse: () => ProviderConfig(
        modelPrefix: _aiProvider.toLowerCase(),
        providerName: _aiProvider,
        apiKeyName: '${_aiProvider.toUpperCase()}_API_KEY',
      ),
    );

    final apiKeyName = config.apiKeyName;
    final modelPrefix = config.modelPrefix;
    final modelName = _llmModel.isNotEmpty ? _llmModel : 'gpt-4o';
    final fullModel = '$modelPrefix:$modelName';

    logger.log(
      'Configuring AI service: provider=$_aiProvider, '
      'apiKeyName=$apiKeyName, model=$fullModel, ip=$_ipAddress',
    );

    _aiChatService.configure(
      apiKey: apiKeyName,
      apiToken: _aiApiToken,
      model: fullModel,
      vxi11Host: _ipAddress,
      // Null until the device has answered its first *IDN? query; the ping
      // timer reports the name via updateInstrumentModel() once it is known.
      instrumentModel: _deviceModel,
      instrumentDeviceContext: _sdsDeviceContext,
      acquireWaveform: ({int delaySeconds = 0}) => _acquireWaveformForAi(),
      readSignalGeneratorStatus: _readSignalGeneratorStatusForAi,
      applySignalGenerator: _applySignalGeneratorForAi,
      controlSignalGenerator: _controlSignalGeneratorForAi,
    );

    logger.log(
      'After _aiChatService.configure(): isInitialized=${_aiChatService.isInitialized}',
    );

    if (mounted) {
      _setState(() {
        // Trigger rebuild after AI service is configured
      });
    }
  }
}
