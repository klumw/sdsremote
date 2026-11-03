/// Runtime context that binds one loaded profile to an agent.
///
/// The context builds the device-specific part of the instrument-agent system
/// prompt and exposes the same registry as a command gate for the transport
/// tool. Keeping both on one object guarantees that the command definitions the
/// model sees and the definitions used for validation are identical.
library;

import 'device_profile_models.dart';
import 'device_profile_store.dart';

/// Builds the prompt section for one active profile.
class DeviceAgentContext {
  DeviceAgentContext({
    required this.profile,
    required this.identity,
    this.instrumentModel,
  });

  final DeviceProfile profile;
  final DeviceIdentity identity;

  /// Model designation from `*IDN?`, when known.
  final String? instrumentModel;

  String? _cachedPromptSection;

  String get profileId => profile.profileId;

  /// Returns a copy with a new detected instrument model.
  DeviceAgentContext withInstrumentModel(String? model) {
    final normalized = model?.trim();
    final effective = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    if (effective == instrumentModel) return this;

    final configured = profile.profileId;
    DeviceIdentity nextIdentity;
    if (effective == null) {
      nextIdentity = DeviceIdentity(
        configuredProfile: configured,
        status: DeviceIdentityStatus.configuredOnly,
        message: 'No instrument identity is currently detected.',
      );
    } else {
      final matches = profile.descriptor.matchesModel(effective);
      nextIdentity = DeviceIdentity(
        configuredProfile: configured,
        detectedProfile: matches ? configured : null,
        rawIdentity: identity.rawIdentity,
        model: effective,
        manufacturer: identity.manufacturer,
        serialNumber: identity.serialNumber,
        firmware: identity.firmware,
        status: matches
            ? DeviceIdentityStatus.confirmed
            : DeviceIdentityStatus.mismatch,
        message: matches
            ? 'The detected model "$effective" matches the configured '
                  'profile "$configured".'
            : 'The detected model "$effective" does not match the configured '
                  'profile "$configured".',
      );
    }
    return DeviceAgentContext(
      profile: profile,
      identity: nextIdentity,
      instrumentModel: effective,
    );
  }

  /// Device-specific prompt section, generated once and cached.
  String buildPromptSection() {
    final cached = _cachedPromptSection;
    if (cached != null) return cached;

    final metadata = profile.metadata;
    final knowledge = profile.knowledge;
    final lines = <String>[
      '## ACTIVE DEVICE PROFILE',
      '- Configured profile: `${profile.profileId}` '
          '(${profile.displayName})',
      '- Configured device value: `${metadata.configuredDevice}`',
      '- Detected identity: ${_identitySummary()}',
      '- Identity status: `${identity.status.name}`',
      '- Firmware: `${metadata.deviceScope['firmware'] ?? 'not_specified'}`',
      '- Command package: `${metadata.packageId}` '
          '(schema ${metadata.schemaVersion}, ${profile.commands.length} '
          'commands)',
      '- Protocol: ${metadata.protocol}',
      '- Knowledge document: `${knowledge.sourcePath}` '
          '(version ${knowledge.metadata.version})',
      if (!profile.waveforms.isEmpty)
        '- Supported waveforms: ${profile.waveforms.supported.join(', ')}',
      '',
      'The active device profile is the authoritative source for this device. '
          'Use only the commands listed below. Do not invent commands, '
          'parameters, units, query forms, value ranges or device '
          'capabilities. If the profile does not define a value range, the '
          'driver performs the device-specific range check. If information is '
          'missing or contradictory, ask the user or decline the unsafe '
          'action.',
      '',
      '## AUTHORIZED COMMAND DEFINITIONS',
      '',
      _formatCommandReference(),
      '',
      '## DEVICE KNOWLEDGE',
      '',
      knowledge.bodyMarkdown,
    ];
    final section = lines.join('\n');
    _cachedPromptSection = section;
    return section;
  }

  String _identitySummary() {
    final detected = identity.detectedProfile;
    final model = identity.model ?? instrumentModel;
    final parts = <String>[
      if (detected != null) 'profile `$detected`',
      if (model != null) 'model `$model`',
      if (identity.rawIdentity != null) 'raw `${identity.rawIdentity}`',
    ];
    if (parts.isEmpty) return 'not detected';
    return '${parts.join(', ')} '
        '(${identity.message ?? identity.status.name})';
  }

  String _formatCommandReference() {
    final buffer = StringBuffer();
    for (final command in profile.registry.commands) {
      buffer.writeln(
        '**${command.name}**'
        '${command.aliasOrDescription == null ? '' : ' (${command.aliasOrDescription})'}',
      );
      if (command.description != null && command.description!.isNotEmpty) {
        buffer.writeln(command.description);
      }
      switch (command.operationKind) {
        case DeviceOperationKind.query:
          buffer.writeln('Query: `${command.scpiPattern}`');
        case DeviceOperationKind.action:
          buffer.writeln('Action: `${command.scpiPattern}`');
          buffer.writeln('No query.');
        case DeviceOperationKind.setterQuery:
          buffer.writeln('Write: `${command.scpiPattern}`');
          buffer.writeln('Query: `${command.queryPattern}`');
        case DeviceOperationKind.unspecified:
          buffer.writeln('Pattern: `${command.scpiPattern}`');
          buffer.writeln('Query support: not specified.');
      }
      if (command.scpiPatternAliases.isNotEmpty) {
        buffer.writeln(
          'Write aliases: '
          '${command.scpiPatternAliases.map((p) => '`$p`').join(', ')}',
        );
      }
      if (command.queryPatternAliases.isNotEmpty) {
        buffer.writeln(
          'Query aliases: '
          '${command.queryPatternAliases.map((p) => '`$p`').join(', ')}',
        );
      }
      if (command.parameters.isNotEmpty) {
        buffer.writeln(
          'Parameters: ${command.parameters.map(_formatParameter).join('; ')}',
        );
      }
      if (command.unresolvedPlaceholders.isNotEmpty) {
        buffer.writeln(
          'Pattern-only placeholders (no range validation): '
          '${command.unresolvedPlaceholders.map((name) => '<$name>').join(', ')}',
        );
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  String _formatParameter(DeviceParameterDefinition parameter) {
    final parts = <String>[parameter.name, parameter.type.wireName];
    if (parameter.allowedValues.isNotEmpty) {
      parts.add(
        'allowed: ${parameter.allowedValues.map((value) => value.toString()).join(', ')}',
      );
    }
    if (parameter.valuesRef != null) {
      parts.add(
        'values from profile: ${profile.waveforms.supported.join(', ')}',
      );
    }
    final unitRule = parameter.unitRule;
    if (unitRule != null) {
      parts.add(
        'units: ${unitRule.accepted.join('/')}, default '
        '${unitRule.defaultUnit}',
      );
    }
    if (parameter.minimum != null || parameter.maximum != null) {
      parts.add(
        'range: ${parameter.minimum ?? '*'}..${parameter.maximum ?? '*'}',
      );
    } else {
      parts.add('range: not specified');
    }
    if (!parameter.required) parts.add('optional');
    return '${parts.first} (${parts.skip(1).join(', ')})';
  }

  /// Validates a raw command against this profile.
  DeviceCommandValidation validateRawCommand(
    String command, {
    required bool isQuery,
  }) => profile.registry.validateRawCommand(command, isQuery: isQuery);

  /// Returns the profile metadata exposed to agents and tools.
  Map<String, dynamic> statusJson() =>
      buildDeviceProfileStatus(profile, identity: identity);
}

/// Shared JSON shape for profile status returned by signal-generator tools.
Map<String, dynamic> buildDeviceProfileStatus(
  DeviceProfile profile, {
  DeviceIdentity? identity,
}) {
  return {
    'profile_id': profile.profileId,
    'display_name': profile.displayName,
    'package_id': profile.metadata.packageId,
    'schema_version': profile.metadata.schemaVersion,
    'manufacturer': profile.metadata.manufacturer,
    'device_scope': profile.metadata.deviceScope,
    'protocol': profile.metadata.protocol,
    'knowledge_version': profile.knowledge.metadata.version,
    'knowledge_source': profile.knowledge.sourcePath,
    'command_count': profile.commands.length,
    'supported_waveforms': profile.waveforms.supported,
    if (identity != null) 'identity': identity.toJson(),
  };
}

/// Loads a profile and builds its agent context in one step.
Future<DeviceAgentContext> buildDeviceContext({
  required DeviceProfileStore store,
  required String profileId,
  String? configuredDevice,
  String? instrumentModel,
  String? rawIdentity,
}) async {
  final profile = await store.loadProfile(profileId);
  final configured = configuredDevice ?? profileId;
  final identity = rawIdentity != null
      ? store.resolveIdentity(rawIdentity, configuredDevice: configured)
      : store.resolveModel(instrumentModel, configuredDevice: configured);
  return DeviceAgentContext(
    profile: profile,
    identity: identity,
    instrumentModel: instrumentModel,
  );
}

/// Mutable validation hook shared with the VXI-11 transport tool.
///
/// The tool captures the gate, not a snapshot of the context, so updating the
/// context (for example when the instrument model is detected) also updates
/// the validation rules used by the already constructed tool.
class DeviceCommandGate {
  DeviceCommandGate([this._context, this.failClosed = false]);

  DeviceAgentContext? _context;

  /// Whether a missing context blocks every command.
  ///
  /// The instrument agent enables this so a profile that failed to load can
  /// never fall back to unchecked raw SCPI. Callers that only use the gate as
  /// an optional add-on keep the default, which allows the command.
  final bool failClosed;

  DeviceAgentContext? get context => _context;

  void update(DeviceAgentContext? context) {
    _context = context;
  }

  /// Returns null when no profile context is active and [failClosed] is false.
  DeviceCommandValidation? validate(String command, {required bool isQuery}) {
    final context = _context;
    if (context == null) {
      if (!failClosed) return null;
      return DeviceCommandValidation(
        error: DeviceCommandException(
          DeviceErrorCode.profileNotLoaded,
          'No active device profile is loaded; the command was not sent.',
          requestedValue: command,
        ),
      );
    }
    return context.validateRawCommand(command, isQuery: isQuery);
  }
}
