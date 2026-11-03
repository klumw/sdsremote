/// Parsing and validation for device command packages (`assets/devices/commands`).
///
/// The parser accepts schema version 1.0 and the two layouts that exist in the
/// repository:
/// - the signal-generator layout with top-level `configured_device`,
///   `waveforms` and `syntax`;
/// - the SDS1000X-E layout with a `knowledge_package` block and per-command
///   `device_scope`/`provenance`.
///
/// Unknown optional fields are preserved in `extensions` maps instead of being
/// silently discarded. Unknown schema versions fail with
/// [DeviceErrorCode.schemaVersionUnsupported].
library;

import 'dart:convert';

import 'device_profile_models.dart';

/// Parses and validates one command package.
abstract final class DeviceCommandPackageParser {
  /// Schema versions this implementation understands.
  static const Set<String> supportedSchemaVersions = {'1.0'};

  /// Parses [jsonText] and verifies that it belongs to [expectedProfileId].
  ///
  /// Throws a [DeviceCommandException] on any structural problem. The caller
  /// must not activate a profile when this method throws.
  static DeviceCommandPackage parse({
    required String expectedProfileId,
    required String jsonText,
    required String sourcePath,
  }) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException catch (error) {
      throw DeviceCommandException(
        DeviceErrorCode.jsonSyntaxInvalid,
        'The command package "$sourcePath" is not valid JSON: '
        '${error.message}.',
        profile: expectedProfileId,
        details: {'source': sourcePath},
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw DeviceCommandException(
        DeviceErrorCode.schemaInvalid,
        'The command package "$sourcePath" must contain a JSON object.',
        profile: expectedProfileId,
        details: {'source': sourcePath},
      );
    }

    final root = decoded;
    final schemaVersion = _requiredString(
      root,
      'schema_version',
      expectedProfileId,
      sourcePath,
    );
    if (!supportedSchemaVersions.contains(schemaVersion)) {
      throw DeviceCommandException(
        DeviceErrorCode.schemaVersionUnsupported,
        'Schema version "$schemaVersion" is not supported. Supported '
        'versions: ${supportedSchemaVersions.join(', ')}.',
        profile: expectedProfileId,
        requestedValue: schemaVersion,
        supportedValues: supportedSchemaVersions.toList(growable: false),
        details: {'source': sourcePath},
      );
    }

    final knowledgePackage = _optionalMap(root['knowledge_package']);
    final packageId =
        _optionalString(root['package_id']) ??
        _optionalString(knowledgePackage?['package_id']);
    if (packageId == null || packageId.isEmpty) {
      throw DeviceCommandException(
        DeviceErrorCode.schemaInvalid,
        'The command package "$sourcePath" has no package_id.',
        profile: expectedProfileId,
        details: {'source': sourcePath},
      );
    }

    final configuredDeviceRaw =
        _optionalString(root['configured_device']) ?? expectedProfileId;
    final configuredProfile = DeviceProfileIds.normalize(configuredDeviceRaw);
    if (configuredProfile != expectedProfileId) {
      throw DeviceCommandException(
        DeviceErrorCode.profileInconsistent,
        'The command package "$sourcePath" declares configured_device '
        '"$configuredDeviceRaw" but profile "$expectedProfileId" was '
        'requested.',
        profile: expectedProfileId,
        requestedValue: configuredDeviceRaw,
        details: {'source': sourcePath},
      );
    }

    final manufacturer =
        _optionalString(root['manufacturer']) ??
        _optionalString(knowledgePackage?['manufacturer']) ??
        'unknown';
    final deviceScope =
        _optionalMap(root['device_scope']) ??
        {
          'model':
              _optionalString(knowledgePackage?['series']) ?? 'not_specified',
          'firmware': 'not_specified',
        };
    final protocol = _optionalString(root['protocol']) ?? 'SCPI';
    final provenance =
        _optionalMap(root['provenance']) ?? knowledgePackage ?? const {};

    final knownTopLevel = {
      'schema_version',
      'package_id',
      'manufacturer',
      'configured_device',
      'device_scope',
      'protocol',
      'waveforms',
      'syntax',
      'commands',
      'provenance',
      'knowledge_package',
    };

    final commandsRaw = root['commands'];
    if (commandsRaw is! List<dynamic> || commandsRaw.isEmpty) {
      throw DeviceCommandException(
        DeviceErrorCode.schemaInvalid,
        'The command package "$sourcePath" must contain a non-empty '
        '"commands" list.',
        profile: expectedProfileId,
        details: {'source': sourcePath},
      );
    }

    final waveforms = DeviceWaveforms.fromJson(_optionalMap(root['waveforms']));
    final syntax = DeviceSyntax.fromJson(_optionalMap(root['syntax']));

    final commands = <DeviceCommandDefinition>[];
    final seenIds = <String>{};
    for (var index = 0; index < commandsRaw.length; index++) {
      final raw = commandsRaw[index];
      if (raw is! Map<String, dynamic>) {
        throw DeviceCommandException(
          DeviceErrorCode.schemaInvalid,
          'Command entry $index in "$sourcePath" is not a JSON object.',
          profile: expectedProfileId,
          details: {'source': sourcePath, 'index': index},
        );
      }
      final command = _parseCommand(
        raw,
        profileId: expectedProfileId,
        sourcePath: sourcePath,
        index: index,
        syntax: syntax,
        waveforms: waveforms,
      );
      if (!seenIds.add(command.commandId)) {
        throw DeviceCommandException(
          DeviceErrorCode.duplicateCommandId,
          'Duplicate command_id "${command.commandId}" in "$sourcePath".',
          profile: expectedProfileId,
          commandId: command.commandId,
          details: {'source': sourcePath},
        );
      }
      commands.add(command);
    }

    _validateWaveformReferences(
      commands,
      waveforms: waveforms,
      profileId: expectedProfileId,
      sourcePath: sourcePath,
    );

    return DeviceCommandPackage(
      metadata: DevicePackageMetadata(
        schemaVersion: schemaVersion,
        packageId: packageId,
        manufacturer: manufacturer,
        configuredDevice: configuredDeviceRaw,
        profileId: expectedProfileId,
        deviceScope: deviceScope,
        protocol: protocol,
        provenance: provenance,
        extensions: {
          for (final entry in root.entries)
            if (!knownTopLevel.contains(entry.key)) entry.key: entry.value,
        },
      ),
      commands: List.unmodifiable(commands),
      waveforms: waveforms,
      syntax: syntax,
      knowledgePackage: knowledgePackage ?? const {},
      extensions: {
        for (final entry in root.entries)
          if (!knownTopLevel.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  static DeviceCommandDefinition _parseCommand(
    Map<String, dynamic> raw, {
    required String profileId,
    required String sourcePath,
    required int index,
    required DeviceSyntax syntax,
    required DeviceWaveforms waveforms,
  }) {
    final commandId = _requiredString(
      raw,
      'command_id',
      profileId,
      sourcePath,
      commandIndex: index,
    );
    final name = _requiredString(
      raw,
      'name',
      profileId,
      sourcePath,
      commandIndex: index,
    );
    final scpiPattern = _requiredString(
      raw,
      'scpi_pattern',
      profileId,
      sourcePath,
      commandIndex: index,
    );

    final operationKindRaw = _requiredString(
      raw,
      'operation_kind',
      profileId,
      sourcePath,
      commandIndex: index,
    );
    var operationKind = DeviceOperationKind.tryParse(operationKindRaw);
    if (operationKind == null) {
      throw DeviceCommandException(
        DeviceErrorCode.schemaInvalid,
        'Command "$commandId" uses unknown operation_kind '
        '"$operationKindRaw".',
        profile: profileId,
        commandId: commandId,
        details: {'source': sourcePath},
      );
    }

    final querySupportRaw = _requiredString(
      raw,
      'query_support',
      profileId,
      sourcePath,
      commandIndex: index,
    );
    var querySupport = DeviceQuerySupport.tryParse(querySupportRaw);
    if (querySupport == null) {
      throw DeviceCommandException(
        DeviceErrorCode.schemaInvalid,
        'Command "$commandId" uses unknown query_support '
        '"$querySupportRaw".',
        profile: profileId,
        commandId: commandId,
        details: {'source': sourcePath},
      );
    }

    var queryPattern = _optionalString(raw['query_pattern']);
    final migrationNotes = <String>[];

    // Documented migration rule for packages that mark a command as
    // unspecified: the trailing question mark is the only evidence available.
    // A query pattern is never invented for a setter.
    if (operationKind == DeviceOperationKind.unspecified) {
      if (querySupport != DeviceQuerySupport.notSpecified) {
        throw DeviceCommandException(
          DeviceErrorCode.schemaInvalid,
          'Command "$commandId" declares operation_kind "unspecified" with '
          'query_support "$querySupportRaw". Expected "not_specified".',
          profile: profileId,
          commandId: commandId,
          details: {'source': sourcePath},
        );
      }
      if (scpiPattern.trim().endsWith('?')) {
        operationKind = DeviceOperationKind.query;
        querySupport = DeviceQuerySupport.queryOnly;
        queryPattern = scpiPattern;
        migrationNotes.add(
          'operation_kind unspecified classified as query_only because the '
          'scpi_pattern ends with "?".',
        );
      } else {
        operationKind = DeviceOperationKind.action;
        querySupport = DeviceQuerySupport.none;
        queryPattern = null;
        migrationNotes.add(
          'operation_kind unspecified classified as action without query.',
        );
      }
    }

    // A query command whose query_pattern is missing but whose scpi_pattern
    // already ends with "?" uses that pattern. This is the same string, not an
    // invented query form.
    if (operationKind == DeviceOperationKind.query &&
        queryPattern == null &&
        scpiPattern.trim().endsWith('?')) {
      queryPattern = scpiPattern;
      migrationNotes.add(
        'query_pattern copied from scpi_pattern because it is already a '
        'query form.',
      );
    }

    _validateOperationConsistency(
      commandId: commandId,
      operationKind: operationKind,
      querySupport: querySupport,
      queryPattern: queryPattern,
      profileId: profileId,
      sourcePath: sourcePath,
    );

    final parameters = _parseParameters(
      raw['parameters'],
      commandId: commandId,
      profileId: profileId,
      sourcePath: sourcePath,
    );

    final placeholders = <String>{
      ..._extractPlaceholders(scpiPattern),
      if (queryPattern != null) ..._extractPlaceholders(queryPattern),
    };
    final parameterNames = parameters.map((param) => param.name).toSet();
    // `[unit]` is an optional unit suffix, not an unresolved placeholder.
    // A required `<unit>` placeholder (for example in the SDS FFTU command)
    // has no definition and must mark the command as pattern-only.
    final hasOptionalUnit =
        RegExp(r'\[unit\]').hasMatch(scpiPattern) ||
        (queryPattern != null && RegExp(r'\[unit\]').hasMatch(queryPattern));
    final unresolved = placeholders
        .where(
          (name) =>
              !(name == 'unit' && hasOptionalUnit) &&
              !parameterNames.contains(name),
        )
        .toList(growable: false);

    final scpiPatternAliases = _optionalStringList(
      raw['scpi_pattern_aliases'],
      commandId: commandId,
      field: 'scpi_pattern_aliases',
      profileId: profileId,
      sourcePath: sourcePath,
    );
    final queryPatternAliases = _optionalStringList(
      raw['query_pattern_aliases'],
      commandId: commandId,
      field: 'query_pattern_aliases',
      profileId: profileId,
      sourcePath: sourcePath,
    );

    final knownFields = {
      'command_id',
      'name',
      'alias_or_description',
      'description',
      'scpi_pattern',
      'query_pattern',
      'operation_kind',
      'query_support',
      'parameters',
      'scpi_pattern_aliases',
      'query_pattern_aliases',
      'device_scope',
      'provenance',
    };
    final extensions = <String, dynamic>{
      for (final entry in raw.entries)
        if (!knownFields.contains(entry.key)) entry.key: entry.value,
    };
    if (migrationNotes.isNotEmpty) {
      extensions['migration'] = migrationNotes;
    }

    final channelValues = syntax.sourceChannelAllowedValues;
    final channelParameter = parameters.where((p) => p.name == 'n');
    if (channelValues.isNotEmpty && channelParameter.isNotEmpty) {
      final declared = channelParameter.first.allowedValues
          .whereType<num>()
          .map((value) => value.toInt())
          .toSet();
      if (declared.isNotEmpty && !declared.containsAll(channelValues)) {
        throw DeviceCommandException(
          DeviceErrorCode.schemaInvalid,
          'Command "$commandId" restricts channel values to '
          '${declared.join(', ')}, but syntax.source_channel allows '
          '${channelValues.join(', ')}.',
          profile: profileId,
          commandId: commandId,
          details: {'source': sourcePath},
        );
      }
    }

    if (unresolved.isNotEmpty && parameters.isEmpty) {
      extensions['pattern_only'] = true;
    }

    return DeviceCommandDefinition(
      commandId: commandId,
      name: name,
      aliasOrDescription: _optionalString(raw['alias_or_description']),
      description: _optionalString(raw['description']),
      scpiPattern: scpiPattern,
      queryPattern: queryPattern,
      operationKind: operationKind,
      querySupport: querySupport,
      parameters: List.unmodifiable(parameters),
      scpiPatternAliases: scpiPatternAliases,
      queryPatternAliases: queryPatternAliases,
      unresolvedPlaceholders: unresolved,
      deviceScope: _optionalMap(raw['device_scope']) ?? const {},
      provenance: _optionalMap(raw['provenance']) ?? const {},
      extensions: extensions,
    );
  }

  static void _validateOperationConsistency({
    required String commandId,
    required DeviceOperationKind operationKind,
    required DeviceQuerySupport querySupport,
    required String? queryPattern,
    required String profileId,
    required String sourcePath,
  }) {
    String? problem;
    switch (operationKind) {
      case DeviceOperationKind.query:
        if (querySupport != DeviceQuerySupport.queryOnly &&
            querySupport != DeviceQuerySupport.documented) {
          problem =
              'operation_kind "query" requires query_support "query_only" '
              'or "documented", got "${querySupport.wireName}".';
        }
      case DeviceOperationKind.action:
        if (querySupport != DeviceQuerySupport.none) {
          problem =
              'operation_kind "action" requires query_support "none", got '
              '"${querySupport.wireName}".';
        }
      case DeviceOperationKind.setterQuery:
        if (querySupport != DeviceQuerySupport.documented) {
          problem =
              'operation_kind "setter_query" requires query_support '
              '"documented", got "${querySupport.wireName}".';
        }
      case DeviceOperationKind.unspecified:
        problem = 'operation_kind "unspecified" was not resolved.';
    }

    if (problem == null) {
      final needsQuery =
          querySupport == DeviceQuerySupport.queryOnly ||
          querySupport == DeviceQuerySupport.documented;
      if (needsQuery && queryPattern == null) {
        problem =
            'query_support "${querySupport.wireName}" requires a '
            'query_pattern.';
      }
      if (querySupport == DeviceQuerySupport.none && queryPattern != null) {
        problem = 'query_support "none" must not declare a query_pattern.';
      }
      if (querySupport == DeviceQuerySupport.notSpecified &&
          queryPattern != null) {
        problem =
            'query_support "not_specified" must not declare a query_pattern.';
      }
    }

    if (problem != null) {
      throw DeviceCommandException(
        DeviceErrorCode.schemaInvalid,
        'Command "$commandId": $problem',
        profile: profileId,
        commandId: commandId,
        details: {'source': sourcePath},
      );
    }
  }

  static List<DeviceParameterDefinition> _parseParameters(
    Object? raw, {
    required String commandId,
    required String profileId,
    required String sourcePath,
  }) {
    if (raw == null) return const [];
    if (raw is! List<dynamic>) {
      throw DeviceCommandException(
        DeviceErrorCode.schemaInvalid,
        'Command "$commandId" has a non-list "parameters" field.',
        profile: profileId,
        commandId: commandId,
        details: {'source': sourcePath},
      );
    }

    final parameters = <DeviceParameterDefinition>[];
    final names = <String>{};
    for (var index = 0; index < raw.length; index++) {
      final entry = raw[index];
      if (entry is! Map<String, dynamic>) {
        throw DeviceCommandException(
          DeviceErrorCode.schemaInvalid,
          'Parameter $index of command "$commandId" is not a JSON object.',
          profile: profileId,
          commandId: commandId,
          details: {'source': sourcePath, 'index': index},
        );
      }
      final name = _requiredString(
        entry,
        'name',
        profileId,
        sourcePath,
        commandId: commandId,
      );
      if (!names.add(name)) {
        throw DeviceCommandException(
          DeviceErrorCode.schemaInvalid,
          'Command "$commandId" declares parameter "$name" more than once.',
          profile: profileId,
          commandId: commandId,
          parameter: name,
          details: {'source': sourcePath},
        );
      }
      final typeRaw = _requiredString(
        entry,
        'type',
        profileId,
        sourcePath,
        commandId: commandId,
      );
      final type = DeviceParameterType.tryParse(typeRaw);
      if (type == null) {
        throw DeviceCommandException(
          DeviceErrorCode.schemaInvalid,
          'Parameter "$name" of command "$commandId" uses unknown type '
          '"$typeRaw".',
          profile: profileId,
          commandId: commandId,
          parameter: name,
          details: {'source': sourcePath},
        );
      }

      final allowedValuesRaw = entry['allowed_values'];
      final allowedValues = allowedValuesRaw is List<dynamic>
          ? List<Object?>.unmodifiable(allowedValuesRaw)
          : const <Object?>[];

      final valuesRef = _optionalString(entry['values_ref']);
      if (valuesRef != null && valuesRef != 'waveforms.supported_and_aliases') {
        throw DeviceCommandException(
          DeviceErrorCode.schemaInvalid,
          'Parameter "$name" of command "$commandId" references unknown '
          'profile data "$valuesRef".',
          profile: profileId,
          commandId: commandId,
          parameter: name,
          details: {'source': sourcePath},
        );
      }

      final unitJson = _optionalMap(entry['unit']);
      final unitRule = unitJson == null
          ? null
          : DeviceUnitRule.fromJson(unitJson);
      if (unitJson != null &&
          (unitJson['accepted'] is! List<dynamic> ||
              (unitJson['accepted'] as List<dynamic>).isEmpty)) {
        throw DeviceCommandException(
          DeviceErrorCode.schemaInvalid,
          'Parameter "$name" of command "$commandId" has a unit rule without '
          'accepted units.',
          profile: profileId,
          commandId: commandId,
          parameter: name,
          details: {'source': sourcePath},
        );
      }

      final rawMinimum = entry['minimum'];
      final rawMaximum = entry['maximum'];
      final minimum = rawMinimum is num ? rawMinimum : null;
      final maximum = rawMaximum is num ? rawMaximum : null;
      if (rawMinimum != null && minimum == null ||
          rawMaximum != null && maximum == null) {
        throw DeviceCommandException(
          DeviceErrorCode.schemaInvalid,
          'Parameter "$name" of command "$commandId" has a non-numeric '
          'minimum or maximum.',
          profile: profileId,
          commandId: commandId,
          parameter: name,
          details: {'source': sourcePath},
        );
      }
      if (minimum != null && maximum != null && minimum > maximum) {
        throw DeviceCommandException(
          DeviceErrorCode.schemaInvalid,
          'Parameter "$name" of command "$commandId" has minimum > maximum.',
          profile: profileId,
          commandId: commandId,
          parameter: name,
          details: {'source': sourcePath},
        );
      }

      final knownFields = {
        'name',
        'type',
        'required',
        'allowed_values',
        'values_ref',
        'unit',
        'minimum',
        'maximum',
      };

      parameters.add(
        DeviceParameterDefinition(
          name: name,
          type: type,
          required: entry['required'] as bool? ?? true,
          allowedValues: allowedValues,
          valuesRef: valuesRef,
          unitRule: unitRule,
          minimum: minimum,
          maximum: maximum,
          rangeKnown: minimum != null || maximum != null,
          extensions: {
            for (final field in entry.entries)
              if (!knownFields.contains(field.key)) field.key: field.value,
          },
        ),
      );
    }
    return parameters;
  }

  static void _validateWaveformReferences(
    List<DeviceCommandDefinition> commands, {
    required DeviceWaveforms waveforms,
    required String profileId,
    required String sourcePath,
  }) {
    for (final command in commands) {
      for (final parameter in command.parameters) {
        if (!parameter.isWaveformReference) continue;
        if (waveforms.isEmpty) {
          throw DeviceCommandException(
            DeviceErrorCode.schemaInvalid,
            'Command "${command.commandId}" references the waveform list, '
            'but the package has no supported waveforms.',
            profile: profileId,
            commandId: command.commandId,
            parameter: parameter.name,
            details: {'source': sourcePath},
          );
        }
      }
    }
  }

  static List<String> _extractPlaceholders(String pattern) {
    final names = <String>[];
    for (final match in RegExp(r'<([^>]+)>').allMatches(pattern)) {
      final name = match.group(1)!.trim();
      if (name.isNotEmpty && !names.contains(name)) names.add(name);
    }
    return names;
  }

  static List<String> _optionalStringList(
    Object? value, {
    required String commandId,
    required String field,
    required String profileId,
    required String sourcePath,
  }) {
    if (value == null) return const [];
    if (value is! List<dynamic>) {
      throw DeviceCommandException(
        DeviceErrorCode.schemaInvalid,
        'Command "$commandId" has a non-list "$field" field.',
        profile: profileId,
        commandId: commandId,
        details: {'source': sourcePath},
      );
    }
    return List<String>.unmodifiable(value.map((entry) => entry.toString()));
  }

  static Map<String, dynamic>? _optionalMap(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    return Map<String, dynamic>.unmodifiable(value);
  }

  static String? _optionalString(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static String _requiredString(
    Map<String, dynamic> map,
    String key,
    String profileId,
    String sourcePath, {
    int? commandIndex,
    String? commandId,
  }) {
    final value = _optionalString(map[key]);
    if (value == null) {
      throw DeviceCommandException(
        DeviceErrorCode.schemaInvalid,
        'Missing required field "$key" in "$sourcePath"'
        '${commandId == null ? '' : ' for command "$commandId"'}'
        '${commandIndex == null ? '' : ' (entry $commandIndex)'}.',
        profile: profileId,
        commandId: commandId,
        details: {'source': sourcePath, 'field': key},
      );
    }
    return value;
  }
}
