/// Core models for the device-profile layer.
///
/// The models in this file are deliberately free of Flutter, dart:io and
/// transport dependencies so that command resolution and schema validation can
/// be unit-tested without an application window or a connected instrument.
library;

/// Canonical device-profile identifiers used by the registry.
///
/// The application has historically used `jds6600` for the JOY-IT/Juntek
/// generator, while the command package declares `jd6600`. Both spellings are
/// accepted and normalized to [jds6600]. The configured identity is kept
/// separate from the identity detected through `*IDN?` in [DeviceIdentity].
abstract final class DeviceProfileIds {
  static const String fy6900 = 'fy6900';
  static const String jds6600 = 'jds6600';
  static const String sds1000xe = 'sds1000xe';
  static const String none = 'none';

  /// Explicit aliases only. Unknown values are returned unchanged so the
  /// caller can report a controlled [DeviceErrorCode.profileUnknown] error.
  static const Map<String, String> _aliases = {
    'fy6900': fy6900,
    'jd6600': jds6600,
    'jds6600': jds6600,
    'sds1000x-e': sds1000xe,
    'sds1000xe': sds1000xe,
  };

  /// Normalizes a configured device value.
  ///
  /// Returns null for null, empty or [none]. Unknown values are returned in
  /// lower case, not remapped.
  static String? normalize(String? value) {
    final trimmed = value?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty || trimmed == none) return null;
    return _aliases[trimmed] ?? trimmed;
  }
}

/// Structured error codes returned by the device-profile layer.
///
/// The codes are part of the agent-facing contract. Device-specific SCPI error
/// numbers (for example `-222`) are carried separately in
/// [DeviceCommandException.details] and are never invented here.
enum DeviceErrorCode {
  profileUnknown('PROFILE_UNKNOWN'),
  profileNotLoaded('PROFILE_NOT_LOADED'),
  commandFileMissing('COMMAND_FILE_MISSING'),
  knowledgeFileMissing('KNOWLEDGE_FILE_MISSING'),
  jsonSyntaxInvalid('JSON_SYNTAX_INVALID'),
  schemaInvalid('SCHEMA_INVALID'),
  schemaVersionUnsupported('SCHEMA_VERSION_UNSUPPORTED'),
  duplicateCommandId('DUPLICATE_COMMAND_ID'),
  unknownCommand('UNKNOWN_COMMAND'),
  unknownParameter('UNKNOWN_PARAMETER'),
  missingParameter('MISSING_PARAMETER'),
  invalidParameterValue('INVALID_PARAMETER_VALUE'),
  invalidUnit('INVALID_UNIT'),
  unsupportedWaveform('UNSUPPORTED_WAVEFORM'),
  unsupportedChannel('UNSUPPORTED_CHANNEL'),
  unknownDeviceIdentity('UNKNOWN_DEVICE_IDENTITY'),
  ambiguousDeviceIdentity('AMBIGUOUS_DEVICE_IDENTITY'),
  profileInconsistent('PROFILE_INCONSISTENT'),
  knowledgeProfileMismatch('KNOWLEDGE_PROFILE_MISMATCH'),
  knowledgeFileInvalid('KNOWLEDGE_FILE_INVALID'),
  commandNotResolvable('COMMAND_NOT_RESOLVABLE'),
  queryNotSupported('QUERY_NOT_SUPPORTED'),
  setNotSupported('SET_NOT_SUPPORTED'),
  deviceCommunicationFailed('DEVICE_COMMUNICATION_FAILED'),
  scpiError('SCPI_ERROR');

  const DeviceErrorCode(this.code);

  /// Stable machine-readable code used in tool results and logs.
  final String code;
}

/// A structured, agent-interpretable error from the device-profile layer.
class DeviceCommandException implements Exception {
  const DeviceCommandException(
    this.code,
    this.message, {
    this.profile,
    this.commandId,
    this.parameter,
    this.requestedValue,
    this.supportedValues = const [],
    this.details = const {},
  });

  final DeviceErrorCode code;
  final String message;
  final String? profile;
  final String? commandId;
  final String? parameter;
  final Object? requestedValue;
  final List<String> supportedValues;
  final Map<String, dynamic> details;

  /// Returns a copy with the profile context filled in. Used by the registry
  /// when a low-level validation error is attributed to a command.
  DeviceCommandException withContext({
    String? profile,
    String? commandId,
    String? parameter,
    Object? requestedValue,
  }) {
    return DeviceCommandException(
      code,
      message,
      profile: profile ?? this.profile,
      commandId: commandId ?? this.commandId,
      parameter: parameter ?? this.parameter,
      requestedValue: requestedValue ?? this.requestedValue,
      supportedValues: supportedValues,
      details: details,
    );
  }

  /// JSON shape returned by AI tools. It keeps the existing `error` key so
  /// callers that only render a message keep working.
  Map<String, dynamic> toJson() => {
    'error_code': code.code,
    'error': message,
    'message': message,
    if (profile != null) 'profile': profile,
    if (commandId != null) 'command_id': commandId,
    if (parameter != null) 'parameter': parameter,
    if (requestedValue != null) 'requested_value': requestedValue,
    if (supportedValues.isNotEmpty) 'supported_values': supportedValues,
    if (details.isNotEmpty) ...details,
  };

  @override
  String toString() => '${code.code}: $message';
}

/// The operation kind declared by a command definition.
enum DeviceOperationKind {
  query('query'),
  action('action'),
  setterQuery('setter_query'),
  unspecified('unspecified');

  const DeviceOperationKind(this.wireName);

  final String wireName;

  static DeviceOperationKind? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    for (final kind in values) {
      if (kind.wireName == normalized) return kind;
    }
    return null;
  }
}

/// The query-support classification declared by a command definition.
enum DeviceQuerySupport {
  queryOnly('query_only'),
  none('none'),
  documented('documented'),
  notSpecified('not_specified');

  const DeviceQuerySupport(this.wireName);

  final String wireName;

  static DeviceQuerySupport? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    for (final support in values) {
      if (support.wireName == normalized) return support;
    }
    return null;
  }
}

/// Parameter data types supported by the schema.
enum DeviceParameterType {
  integer('integer'),
  number('number'),
  enumValue('enum'),
  string('string');

  const DeviceParameterType(this.wireName);

  final String wireName;

  static DeviceParameterType? tryParse(String? value) {
    final normalized = value?.trim().toLowerCase();
    for (final type in values) {
      if (type.wireName == normalized) return type;
    }
    return null;
  }
}

/// Physical dimension of a unit rule.
///
/// The dimension keeps amplitude and DC offset distinct even where both accept
/// the same unit spellings: a peak-to-peak amplitude is not a DC offset.
enum DeviceUnitDimension { frequency, voltage, percent, phase, unknown }

/// One normalized unit conversion result.
class DeviceUnitNormalization {
  const DeviceUnitNormalization({
    required this.value,
    required this.unit,
    required this.requestedUnit,
    required this.converted,
  });

  /// Value expressed in the canonical base unit (Hz, V, %, degrees).
  final double value;

  /// Canonical unit token written into the command, for example `HZ`, `V`,
  /// `%` or `DEG`.
  final String unit;

  /// Unit supplied by the caller, or null when the default was used.
  final String? requestedUnit;

  /// Whether the value or the unit token changed during normalization.
  final bool converted;
}

/// Unit rules attached to a parameter definition.
class DeviceUnitRule {
  const DeviceUnitRule({
    required this.accepted,
    required this.defaultUnit,
    this.dimension = DeviceUnitDimension.unknown,
  });

  /// Accepted unit spellings, in the spelling used by the package.
  final List<String> accepted;

  /// Default unit used when the command omits the unit.
  final String defaultUnit;

  final DeviceUnitDimension dimension;

  /// Converts [value] with [unit] to the canonical base unit.
  ///
  /// Throws a [DeviceCommandException] with
  /// [DeviceErrorCode.invalidUnit] when the unit is not documented. No
  /// dimension is inferred for unknown unit spellings: they are accepted only
  /// when the package lists them, and are converted with factor 1.
  DeviceUnitNormalization normalize(double value, String? unit) {
    final requested = (unit ?? '').trim();
    final candidate = requested.isEmpty ? defaultUnit : requested;
    final upper = candidate.toUpperCase().replaceAll(' ', '');

    String? matched;
    for (final acceptedUnit in accepted) {
      if (acceptedUnit.toUpperCase().replaceAll(' ', '') == upper) {
        matched = acceptedUnit;
        break;
      }
    }
    if (matched == null) {
      throw DeviceCommandException(
        DeviceErrorCode.invalidUnit,
        'Unsupported unit "$candidate"; accepted units: '
        '${accepted.join(', ')}.',
        requestedValue: candidate,
        supportedValues: accepted,
        details: {'accepted_units': accepted},
      );
    }

    final factor = _unitFactor(upper);
    final canonical = _canonicalUnit(matched) ?? matched.toUpperCase();
    return DeviceUnitNormalization(
      value: value * factor,
      unit: canonical,
      requestedUnit: requested.isEmpty ? null : requested,
      converted: factor != 1.0 || canonical != upper,
    );
  }

  static double _unitFactor(String unit) {
    switch (unit) {
      case 'KHZ':
        return 1e3;
      case 'MHZ':
        return 1e6;
      case 'MV':
        return 1e-3;
      default:
        return 1.0;
    }
  }

  static String? _canonicalUnit(String unit) {
    switch (unit.toUpperCase()) {
      case 'HZ':
      case 'KHZ':
      case 'MHZ':
        return 'HZ';
      case 'V':
      case 'VPP':
      case 'MV':
        return 'V';
      case '%':
      case 'PCT':
        return '%';
      case 'DEG':
      case 'DEGREE':
      case 'DEGREES':
        return 'DEG';
      default:
        return null;
    }
  }

  /// Builds a rule from the optional `unit` object of a parameter.
  static DeviceUnitRule fromJson(Map<String, dynamic> json) {
    final accepted = (json['accepted'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false);
    final defaultUnit =
        (json['default'] ?? (accepted.isEmpty ? '' : accepted.first))
            .toString();
    return DeviceUnitRule(
      accepted: accepted,
      defaultUnit: defaultUnit,
      dimension: _dimensionFor(accepted),
    );
  }

  static DeviceUnitDimension _dimensionFor(List<String> accepted) {
    final upper = accepted.map((unit) => unit.toUpperCase()).toSet();
    if (upper.intersection(const {'HZ', 'KHZ', 'MHZ'}).isNotEmpty) {
      return DeviceUnitDimension.frequency;
    }
    if (upper.intersection(const {'V', 'VPP', 'MV'}).isNotEmpty) {
      return DeviceUnitDimension.voltage;
    }
    if (upper.intersection(const {'%', 'PCT'}).isNotEmpty) {
      return DeviceUnitDimension.percent;
    }
    if (upper.intersection(const {'DEG', 'DEGREE', 'DEGREES'}).isNotEmpty) {
      return DeviceUnitDimension.phase;
    }
    return DeviceUnitDimension.unknown;
  }
}

/// One parameter of a command definition.
class DeviceParameterDefinition {
  const DeviceParameterDefinition({
    required this.name,
    required this.type,
    required this.required,
    this.allowedValues = const [],
    this.valuesRef,
    this.unitRule,
    this.minimum,
    this.maximum,
    this.rangeKnown = false,
    this.extensions = const {},
  });

  /// Placeholder name without angle brackets, for example `n`, `value`,
  /// `shape`.
  final String name;

  final DeviceParameterType type;

  /// Whether the parameter must be supplied to build the command.
  final bool required;

  /// Explicit enum or integer choices. Values keep their JSON type so the
  /// caller can distinguish 1 from "1" where that matters.
  final List<Object?> allowedValues;

  /// Reference to profile data such as `waveforms.supported_and_aliases`.
  final String? valuesRef;

  /// Unit rule for numeric parameters. Null when the parameter is unitless.
  final DeviceUnitRule? unitRule;

  /// Documented bounds, when the package provides them. A null bound with
  /// [rangeKnown] false means the range is unknown; no bound is invented.
  final num? minimum;
  final num? maximum;
  final bool rangeKnown;

  /// Unknown optional fields, preserved for forward compatibility.
  final Map<String, dynamic> extensions;

  /// Whether this parameter is resolved from the profile's waveform list.
  bool get isWaveformReference =>
      valuesRef == 'waveforms.supported_and_aliases';

  /// Returns the canonical spelling of [value] when it is allowed, else null.
  String? matchAllowedValue(Object value) {
    final text = value.toString().trim().toUpperCase();
    for (final allowed in allowedValues) {
      if (allowed.toString().trim().toUpperCase() == text) {
        return allowed.toString().trim().toUpperCase();
      }
    }
    return null;
  }
}

/// One command definition parsed from a command package.
class DeviceCommandDefinition {
  const DeviceCommandDefinition({
    required this.commandId,
    required this.name,
    required this.scpiPattern,
    required this.operationKind,
    required this.querySupport,
    this.aliasOrDescription,
    this.description,
    this.queryPattern,
    this.parameters = const [],
    this.scpiPatternAliases = const [],
    this.queryPatternAliases = const [],
    this.unresolvedPlaceholders = const [],
    this.deviceScope = const {},
    this.provenance = const {},
    this.extensions = const {},
  });

  /// Stable technical key inside the package.
  final String commandId;

  /// Human-readable name.
  final String name;

  /// Readable long alias from the SDS package, for example `ACQUIRE_WAY`.
  final String? aliasOrDescription;

  final String? description;

  /// Write or action pattern. Treated as a declarative template, never as
  /// executable code.
  final String scpiPattern;

  /// Query pattern. Null means no query form is documented.
  final String? queryPattern;

  final DeviceOperationKind operationKind;
  final DeviceQuerySupport querySupport;
  final List<DeviceParameterDefinition> parameters;

  /// Additional documented patterns for the same command, for example the
  /// short `OUTP<n> <state>` form.
  final List<String> scpiPatternAliases;
  final List<String> queryPatternAliases;

  /// Placeholders that have no parameter definition in the package. Such
  /// commands can be validated syntactically but not built semantically.
  final List<String> unresolvedPlaceholders;

  final Map<String, dynamic> deviceScope;
  final Map<String, dynamic> provenance;

  /// Unknown optional fields, preserved for forward compatibility.
  final Map<String, dynamic> extensions;

  bool get hasDocumentedQuery =>
      queryPattern != null &&
      (querySupport == DeviceQuerySupport.documented ||
          querySupport == DeviceQuerySupport.queryOnly);

  bool get isQueryOnly =>
      operationKind == DeviceOperationKind.query ||
      querySupport == DeviceQuerySupport.queryOnly;

  bool get allowsSet =>
      operationKind == DeviceOperationKind.setterQuery ||
      operationKind == DeviceOperationKind.action;

  bool get allowsQuery => hasDocumentedQuery;

  /// Whether the command can be rendered from semantic parameters only.
  bool get isSemanticallyResolvable => unresolvedPlaceholders.isEmpty;

  DeviceParameterDefinition? parameter(String name) {
    for (final parameter in parameters) {
      if (parameter.name == name) return parameter;
    }
    return null;
  }
}

/// Device waveform capability data from a command package.
class DeviceWaveforms {
  const DeviceWaveforms({
    this.supported = const [],
    this.acceptedAliases = const [],
    this.unsupportedNote,
    this.crossModelMapping,
    this.extensions = const {},
  });

  final List<String> supported;
  final List<String> acceptedAliases;
  final String? unsupportedNote;
  final String? crossModelMapping;
  final Map<String, dynamic> extensions;

  bool get isEmpty => supported.isEmpty && acceptedAliases.isEmpty;

  /// All names accepted directly by the package, canonical spellings first.
  Set<String> get acceptedNames => {
    ...supported.map((name) => name.toUpperCase()),
    ...acceptedAliases.map((name) => name.toUpperCase()),
  };

  static DeviceWaveforms fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DeviceWaveforms();
    final known = {
      'supported',
      'accepted_aliases',
      'unsupported_note',
      'cross_model_mapping',
    };
    return DeviceWaveforms(
      supported: (json['supported'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      acceptedAliases: (json['accepted_aliases'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
      unsupportedNote: json['unsupported_note']?.toString(),
      crossModelMapping: json['cross_model_mapping']?.toString(),
      extensions: {
        for (final entry in json.entries)
          if (!known.contains(entry.key)) entry.key: entry.value,
      },
    );
  }
}

/// Channel and unit rules from the package's `syntax` block.
class DeviceSyntax {
  const DeviceSyntax({
    this.sourceChannelPlaceholder = '<n>',
    this.sourceChannelAllowedValues = const [],
    this.unitsOptional = true,
    this.unitCaseInsensitive = true,
    this.unitRules = const {},
    this.headerAliases = const {},
    this.headerAliasNotes,
    this.extensions = const {},
  });

  final String sourceChannelPlaceholder;
  final List<int> sourceChannelAllowedValues;
  final bool unitsOptional;
  final bool unitCaseInsensitive;
  final Map<String, DeviceUnitRule> unitRules;

  /// Whole header segment aliases, for example `SOURCE` -> `SOUR`.
  final Map<String, String> headerAliases;
  final String? headerAliasNotes;
  final Map<String, dynamic> extensions;

  static DeviceSyntax fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DeviceSyntax();
    final known = {
      'source_channel',
      'units_optional',
      'unit_case_insensitive',
      'unit_rules',
      'header_aliases',
      'header_alias_notes',
    };
    final sourceChannel = json['source_channel'];
    final sourceChannelMap = sourceChannel is Map<String, dynamic>
        ? sourceChannel
        : const <String, dynamic>{};
    final unitRules = <String, DeviceUnitRule>{};
    final rawUnitRules = json['unit_rules'];
    if (rawUnitRules is Map<String, dynamic>) {
      for (final entry in rawUnitRules.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          unitRules[entry.key] = DeviceUnitRule.fromJson(value);
        }
      }
    }
    final headerAliases = <String, String>{};
    final rawAliases = json['header_aliases'];
    if (rawAliases is Map<String, dynamic>) {
      for (final entry in rawAliases.entries) {
        headerAliases[entry.key.toUpperCase()] = entry.value
            .toString()
            .toUpperCase();
      }
    }
    return DeviceSyntax(
      sourceChannelPlaceholder:
          sourceChannelMap['placeholder']?.toString() ?? '<n>',
      sourceChannelAllowedValues:
          (sourceChannelMap['allowed_values'] as List<dynamic>? ?? const [])
              .whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false),
      unitsOptional: json['units_optional'] as bool? ?? true,
      unitCaseInsensitive: json['unit_case_insensitive'] as bool? ?? true,
      unitRules: unitRules,
      headerAliases: headerAliases,
      headerAliasNotes: json['header_alias_notes']?.toString(),
      extensions: {
        for (final entry in json.entries)
          if (!known.contains(entry.key)) entry.key: entry.value,
      },
    );
  }
}

/// Package-level metadata validated by the command package parser.
class DevicePackageMetadata {
  const DevicePackageMetadata({
    required this.schemaVersion,
    required this.packageId,
    required this.manufacturer,
    required this.configuredDevice,
    required this.profileId,
    required this.deviceScope,
    required this.protocol,
    required this.provenance,
    this.extensions = const {},
  });

  final String schemaVersion;
  final String packageId;
  final String manufacturer;

  /// Raw `configured_device` value from the package, for example `jd6600`.
  final String configuredDevice;

  /// Canonical profile identifier, for example `jds6600`.
  final String profileId;

  /// Model and firmware scope.
  final Map<String, dynamic> deviceScope;

  final String protocol;
  final Map<String, dynamic> provenance;

  /// Unknown top-level fields, preserved for forward compatibility.
  final Map<String, dynamic> extensions;
}

/// Parsed, validated command package.
class DeviceCommandPackage {
  const DeviceCommandPackage({
    required this.metadata,
    required this.commands,
    required this.waveforms,
    required this.syntax,
    this.knowledgePackage = const {},
    this.extensions = const {},
  });

  final DevicePackageMetadata metadata;
  final List<DeviceCommandDefinition> commands;
  final DeviceWaveforms waveforms;
  final DeviceSyntax syntax;

  /// Raw `knowledge_package` block, used by packages that predate
  /// `configured_device` (the SDS1000X-E package uses this layout).
  final Map<String, dynamic> knowledgePackage;

  final Map<String, dynamic> extensions;
}

/// Result of resolving a requested waveform name against a device profile.
class DeviceWaveformResolution {
  const DeviceWaveformResolution({
    required this.requested,
    required this.resolved,
    required this.channel,
    required this.mapped,
    this.note,
    this.sourceProfile,
  });

  /// Name requested by the user or agent, exactly as supplied.
  final String requested;

  /// Name that is sent to the device.
  final String resolved;

  /// Channel the resolution applies to, when the capability is
  /// channel-dependent.
  final int? channel;

  /// Whether the resolved name differs from the requested one.
  final bool mapped;

  /// Human-readable explanation of a mapping.
  final String? note;

  /// Profile the mapping rule came from, when known.
  final String? sourceProfile;

  Map<String, dynamic> toJson() => {
    'requested': requested,
    'resolved': resolved,
    if (channel != null) 'channel': channel,
    'mapped': mapped,
    if (note != null) 'note': note,
    if (sourceProfile != null) 'source_profile': sourceProfile,
  };
}

/// A command rendered from semantic parameters.
class DeviceResolvedCommand {
  const DeviceResolvedCommand({
    required this.command,
    required this.scpi,
    required this.query,
    required this.parameters,
    this.waveformResolution,
    this.notes = const [],
  });

  final DeviceCommandDefinition command;

  /// Deterministic, validated SCPI string.
  final String scpi;

  final bool query;

  /// Normalized parameter values, including canonical units.
  final Map<String, Object?> parameters;

  /// Waveform mapping applied while resolving a `shape` parameter.
  final DeviceWaveformResolution? waveformResolution;

  /// Normalization notes, for logging and agent feedback.
  final List<String> notes;
}

/// Result of validating a raw SCPI string against the registry.
class DeviceCommandValidation {
  const DeviceCommandValidation({
    this.command,
    this.error,
    this.warnings = const [],
    this.parameters = const {},
  });

  final DeviceCommandDefinition? command;
  final DeviceCommandException? error;
  final List<String> warnings;
  final Map<String, Object?> parameters;

  bool get isValid => error == null;

  Map<String, dynamic> toJson() => {
    if (command != null) 'command_id': command!.commandId,
    if (error != null) ...error!.toJson(),
    if (warnings.isNotEmpty) 'warnings': warnings,
    if (parameters.isNotEmpty) 'parameters': parameters,
  };
}

/// Documentation assembled for one command.
class DeviceCommandDocumentation {
  const DeviceCommandDocumentation({
    required this.command,
    required this.profileId,
    this.knowledgeReferences = const [],
  });

  final DeviceCommandDefinition command;
  final String profileId;

  /// Section titles in the knowledge file that mention this command.
  final List<String> knowledgeReferences;

  Map<String, dynamic> toJson() => {
    'profile': profileId,
    'command_id': command.commandId,
    'name': command.name,
    if (command.aliasOrDescription != null) 'alias': command.aliasOrDescription,
    'description': command.description,
    'scpi_pattern': command.scpiPattern,
    'query_pattern': command.queryPattern,
    'operation_kind': command.operationKind.wireName,
    'query_support': command.querySupport.wireName,
    'parameters': [
      for (final parameter in command.parameters)
        {
          'name': parameter.name,
          'type': parameter.type.wireName,
          'required': parameter.required,
          if (parameter.allowedValues.isNotEmpty)
            'allowed_values': parameter.allowedValues,
          if (parameter.valuesRef != null) 'values_ref': parameter.valuesRef,
          if (parameter.unitRule != null)
            'unit': {
              'accepted': parameter.unitRule!.accepted,
              'default': parameter.unitRule!.defaultUnit,
            },
        },
    ],
    if (command.unresolvedPlaceholders.isNotEmpty)
      'unresolved_placeholders': command.unresolvedPlaceholders,
    if (knowledgeReferences.isNotEmpty)
      'knowledge_references': knowledgeReferences,
  };
}

/// Identity status of the configured and detected device.
enum DeviceIdentityStatus {
  /// The detected identity matches the configured profile.
  confirmed,

  /// Only the configured profile is known; no identity has been detected.
  configuredOnly,

  /// An identity was detected, but no profile is configured.
  detectedOnly,

  /// The detected identity belongs to a different profile.
  mismatch,

  /// The identity string does not match any known profile.
  unknown,

  /// The identity string matches more than one profile.
  ambiguous,
}

/// Configured versus detected device identity.
class DeviceIdentity {
  const DeviceIdentity({
    required this.configuredProfile,
    required this.status,
    this.detectedProfile,
    this.rawIdentity,
    this.manufacturer,
    this.model,
    this.serialNumber,
    this.firmware,
    this.message,
  });

  /// Profile selected in the application settings, when one is selected.
  final String? configuredProfile;

  /// Profile matched from the `*IDN?` response, when one was detected.
  final String? detectedProfile;

  final DeviceIdentityStatus status;
  final String? rawIdentity;
  final String? manufacturer;
  final String? model;
  final String? serialNumber;
  final String? firmware;
  final String? message;

  bool get isConfirmed => status == DeviceIdentityStatus.confirmed;

  Map<String, dynamic> toJson() => {
    'configured_profile': configuredProfile,
    'detected_profile': detectedProfile,
    'status': status.name,
    if (rawIdentity != null) 'raw_identity': rawIdentity,
    if (manufacturer != null) 'manufacturer': manufacturer,
    if (model != null) 'model': model,
    if (serialNumber != null) 'serial_number': serialNumber,
    if (firmware != null) 'firmware': firmware,
    if (message != null) 'message': message,
  };
}
