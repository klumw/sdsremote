/// Device-profile catalog, atomic loading and identity resolution.
///
/// A profile becomes available only after the command package and the
/// knowledge document have both been loaded and validated for the same profile
/// id. A failure at any step removes the profile from the cache, so a partially
/// loaded profile can never be used for command execution.
library;

import 'device_asset_source.dart';
import 'device_command_package.dart';
import 'device_command_registry.dart';
import 'device_knowledge.dart';
import 'device_profile_models.dart';
import 'siggen_waveform_capabilities.dart';

/// Describes one device profile and its two assets.
class DeviceProfileDescriptor {
  const DeviceProfileDescriptor({
    required this.profileId,
    required this.displayName,
    required this.commandAsset,
    required this.knowledgeAsset,
    required this.identityPatterns,
    this.specialCommandPatterns = const [],
  });

  /// Canonical profile id, for example `sds1000xe`.
  final String profileId;

  final String displayName;

  /// Bundle-relative path of the command package.
  final String commandAsset;

  /// Bundle-relative path of the Markdown knowledge document.
  final String knowledgeAsset;

  /// Anchored regular expressions matched against the normalized model field
  /// of `*IDN?`. Matching is deliberately exact: no substring fallback.
  final List<String> identityPatterns;

  /// Documented commands that are not part of the SCPI command package, for
  /// example the SDS front-panel simulation commands.
  final List<String> specialCommandPatterns;

  /// Whether [model] belongs to this profile.
  bool matchesModel(String model) {
    final normalized = model.trim().toUpperCase().replaceAll(
      RegExp(r'\s+'),
      '',
    );
    for (final pattern in identityPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(normalized)) {
        return true;
      }
    }
    return false;
  }
}

/// Explicit, deterministic profile catalog.
///
/// The filenames are data, not scattered through execution code. Adding a
/// profile means adding a descriptor and its two files.
const List<DeviceProfileDescriptor> defaultDeviceProfileCatalog = [
  DeviceProfileDescriptor(
    profileId: DeviceProfileIds.sds1000xe,
    displayName: 'Siglent SDS1000X-E series',
    commandAsset:
        'assets/devices/commands/siglent_sds1000xe_scpi_commands.json',
    knowledgeAsset: 'assets/devices/knowledge/sds1000xe.md',
    identityPatterns: [r'^SDS(?:1102|1202|1104|1204)X-E$'],
    specialCommandPatterns: [r'^\$\$SY_FP -?\d+,-?\d+$'],
  ),
  DeviceProfileDescriptor(
    profileId: DeviceProfileIds.fy6900,
    displayName: 'FeelElec FY6900 series',
    commandAsset: 'assets/devices/commands/fy6900_scpi_commands.json',
    knowledgeAsset: 'assets/devices/knowledge/fy6900.md',
    identityPatterns: [r'^FY6900(?:-\d+M)?$'],
  ),
  DeviceProfileDescriptor(
    profileId: DeviceProfileIds.jds6600,
    displayName: 'JOY-IT/Juntek JDS6600 series',
    commandAsset: 'assets/devices/commands/jds6600_scpi_commands.json',
    knowledgeAsset: 'assets/devices/knowledge/jds6600.md',
    identityPatterns: [r'^JDS6600(?:-LITE)?$'],
  ),
];

/// A fully loaded and cross-checked device profile.
class DeviceProfile {
  const DeviceProfile({
    required this.descriptor,
    required this.package,
    required this.registry,
    required this.knowledge,
  });

  final DeviceProfileDescriptor descriptor;
  final DeviceCommandPackage package;
  final DeviceCommandRegistry registry;
  final DeviceKnowledgeDocument knowledge;

  String get profileId => descriptor.profileId;

  String get displayName => descriptor.displayName;

  DevicePackageMetadata get metadata => package.metadata;

  DeviceWaveforms get waveforms => package.waveforms;

  DeviceSyntax get syntax => package.syntax;

  List<DeviceCommandDefinition> get commands => registry.commands;

  DeviceWaveformResolution resolveWaveform({
    required String requested,
    int? channel,
  }) => registry.resolveWaveform(requested: requested, channel: channel);

  List<DeviceKnowledgeSearchResult> searchKnowledge(
    String query, {
    int limit = 5,
  }) => knowledge.search(query, limit: limit);

  DeviceKnowledgeSection? getKnowledgeSection(String section) =>
      knowledge.getSection(section);

  DeviceCommandDocumentation getCommandDocumentation(String commandId) {
    final documentation = registry.getCommandDocumentation(commandId);
    final references = <String>{
      ...knowledge.referencesFor(commandId),
      ...knowledge.referencesFor(documentation.command.name),
    }.toList(growable: false);
    return DeviceCommandDocumentation(
      command: documentation.command,
      profileId: documentation.profileId,
      knowledgeReferences: references,
    );
  }
}

/// Result of loading all profiles at application start.
class DeviceProfileLoadReport {
  const DeviceProfileLoadReport({required this.loaded, required this.errors});

  final Map<String, DeviceProfile> loaded;
  final Map<String, DeviceCommandException> errors;

  bool get hasFailures => errors.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'loaded': loaded.keys.toList(growable: false),
    'errors': {
      for (final entry in errors.entries) entry.key: entry.value.toJson(),
    },
  };
}

/// Loads profiles from a [DeviceAssetSource] and caches successful results.
class DeviceProfileStore {
  DeviceProfileStore({
    required this.assetSource,
    List<DeviceProfileDescriptor> catalog = defaultDeviceProfileCatalog,
  }) : _catalog = {
         for (final descriptor in catalog) descriptor.profileId: descriptor,
       };

  final DeviceAssetSource assetSource;
  final Map<String, DeviceProfileDescriptor> _catalog;
  final Map<String, DeviceProfile> _loaded = {};
  final Map<String, DeviceCommandException> _errors = {};

  /// Descriptors known to this store, in catalog order.
  List<DeviceProfileDescriptor> get descriptors =>
      List.unmodifiable(_catalog.values);

  /// Profile ids that loaded successfully.
  List<String> get loadedProfileIds =>
      List.unmodifiable(_loaded.keys.toList(growable: false));

  /// Loads and validates one profile.
  ///
  /// A previously cached profile is returned without touching the assets.
  /// Throws [DeviceCommandException] on any failure. Nothing is cached unless
  /// both assets validated for the same profile.
  Future<DeviceProfile> loadProfile(String profileId) async {
    final normalized = DeviceProfileIds.normalize(profileId);
    if (normalized == null) {
      throw const DeviceCommandException(
        DeviceErrorCode.profileUnknown,
        'No device profile was selected.',
      );
    }
    final cached = _loaded[normalized];
    if (cached != null) return cached;

    final descriptor = _catalog[normalized];
    if (descriptor == null) {
      throw DeviceCommandException(
        DeviceErrorCode.profileUnknown,
        'Unknown device profile "$profileId". Known profiles: '
        '${_catalog.keys.join(', ')}.',
        profile: normalized,
        requestedValue: profileId,
        supportedValues: _catalog.keys.toList(growable: false),
      );
    }

    try {
      final commandText = await _loadAsset(
        descriptor.commandAsset,
        missingCode: DeviceErrorCode.commandFileMissing,
        profileId: normalized,
      );
      final package = DeviceCommandPackageParser.parse(
        expectedProfileId: normalized,
        jsonText: commandText,
        sourcePath: descriptor.commandAsset,
      );

      final knowledgeText = await _loadAsset(
        descriptor.knowledgeAsset,
        missingCode: DeviceErrorCode.knowledgeFileMissing,
        profileId: normalized,
      );
      final knowledge = DeviceKnowledgeParser.parse(
        expectedProfileId: normalized,
        markdown: knowledgeText,
        sourcePath: descriptor.knowledgeAsset,
      );

      final registry = DeviceCommandRegistry(
        profileId: normalized,
        metadata: package.metadata,
        commands: package.commands,
        waveforms: package.waveforms,
        syntax: package.syntax,
        waveformResolver: createSiggenWaveformResolver(
          profileId: normalized,
          waveforms: package.waveforms,
        ),
      )..registerSpecialCommandPatterns(descriptor.specialCommandPatterns);

      final profile = DeviceProfile(
        descriptor: descriptor,
        package: package,
        registry: registry,
        knowledge: knowledge,
      );
      _loaded[normalized] = profile;
      _errors.remove(normalized);
      return profile;
    } on DeviceCommandException catch (error) {
      // Atomic activation: remove any previous entry and record the failure.
      _loaded.remove(normalized);
      _errors[normalized] = error;
      rethrow;
    } catch (error) {
      final wrapped = DeviceCommandException(
        DeviceErrorCode.schemaInvalid,
        'Failed to load device profile "$normalized": $error',
        profile: normalized,
        details: {'source': descriptor.commandAsset},
      );
      _loaded.remove(normalized);
      _errors[normalized] = wrapped;
      throw wrapped;
    }
  }

  /// Loads every profile in the catalog.
  ///
  /// Failures do not stop the remaining profiles; they are reported in
  /// [DeviceProfileLoadReport.errors].
  Future<DeviceProfileLoadReport> loadAll() async {
    final loaded = <String, DeviceProfile>{};
    final errors = <String, DeviceCommandException>{};
    for (final descriptor in _catalog.values) {
      try {
        loaded[descriptor.profileId] = await loadProfile(descriptor.profileId);
      } on DeviceCommandException catch (error) {
        errors[descriptor.profileId] = error;
      }
    }
    return DeviceProfileLoadReport(loaded: loaded, errors: errors);
  }

  /// Loads the profile and returns only its knowledge document.
  Future<DeviceKnowledgeDocument> loadKnowledge(String profileId) async =>
      (await loadProfile(profileId)).knowledge;

  /// Returns the knowledge document of a cached profile, or null.
  DeviceKnowledgeDocument? getKnowledge(String? profileId) =>
      getProfile(profileId)?.knowledge;

  /// Returns a cached profile, or null when it is not loaded.
  DeviceProfile? getProfile(String? profileId) {
    final normalized = DeviceProfileIds.normalize(profileId);
    if (normalized == null) return null;
    return _loaded[normalized];
  }

  /// Returns the cached profile selected by an application setting.
  DeviceProfile? profileForConfiguredDevice(String? configuredDevice) =>
      getProfile(configuredDevice);

  /// Last loading error for a profile, if any.
  DeviceCommandException? errorFor(String profileId) {
    final normalized = DeviceProfileIds.normalize(profileId);
    if (normalized == null) return null;
    return _errors[normalized];
  }

  /// Loads the profile selected by an application setting.
  Future<DeviceProfile> loadProfileForConfiguredDevice(
    String? configuredDevice,
  ) {
    final normalized = DeviceProfileIds.normalize(configuredDevice);
    if (normalized == null) {
      throw const DeviceCommandException(
        DeviceErrorCode.profileUnknown,
        'No device profile is configured.',
      );
    }
    return loadProfile(normalized);
  }

  /// Resolves a raw `*IDN?` response against the catalog.
  ///
  /// The configured profile and the detected profile stay separate. A detected
  /// identity that matches more than one profile is reported as ambiguous; the
  /// store never picks one silently.
  DeviceIdentity resolveIdentity(
    String? rawIdentity, {
    String? configuredDevice,
  }) {
    final configured = DeviceProfileIds.normalize(configuredDevice);
    final trimmed = rawIdentity?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return DeviceIdentity(
        configuredProfile: configured,
        status: configured == null
            ? DeviceIdentityStatus.unknown
            : DeviceIdentityStatus.configuredOnly,
        message: configured == null
            ? 'No device identity is known.'
            : 'Only the configured profile "$configured" is known.',
      );
    }

    final fields = trimmed.split(',').map((field) => field.trim()).toList();
    final hasIdnFields = fields.length >= 2;
    final manufacturer = hasIdnFields ? fields[0] : null;
    final model = hasIdnFields ? fields[1] : trimmed;
    final serialNumber = fields.length >= 3 ? fields[2] : null;
    final firmware = fields.length >= 4 ? fields[3] : null;

    return _resolveModel(
      model,
      configured: configured,
      rawIdentity: trimmed,
      manufacturer: manufacturer,
      serialNumber: serialNumber,
      firmware: firmware,
    );
  }

  /// Resolves only a model designation, for example `SDS1202X-E`.
  DeviceIdentity resolveModel(
    String? model, {
    String? configuredDevice,
    String? rawIdentity,
  }) {
    final configured = DeviceProfileIds.normalize(configuredDevice);
    final trimmed = model?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return resolveIdentity(rawIdentity, configuredDevice: configured);
    }
    return _resolveModel(
      trimmed,
      configured: configured,
      rawIdentity: rawIdentity,
    );
  }

  DeviceIdentity _resolveModel(
    String model, {
    required String? configured,
    required String? rawIdentity,
    String? manufacturer,
    String? serialNumber,
    String? firmware,
  }) {
    final matches = <String>[
      for (final descriptor in _catalog.values)
        if (descriptor.matchesModel(model)) descriptor.profileId,
    ];

    if (matches.length > 1) {
      return DeviceIdentity(
        configuredProfile: configured,
        rawIdentity: rawIdentity,
        manufacturer: manufacturer,
        model: model,
        serialNumber: serialNumber,
        firmware: firmware,
        status: DeviceIdentityStatus.ambiguous,
        message:
            'The identity model "$model" matches more than one profile '
            '(${matches.join(', ')}). Configure the device explicitly.',
      );
    }

    final detected = matches.isEmpty ? null : matches.single;
    if (detected == null) {
      return DeviceIdentity(
        configuredProfile: configured,
        rawIdentity: rawIdentity,
        manufacturer: manufacturer,
        model: model,
        serialNumber: serialNumber,
        firmware: firmware,
        status: DeviceIdentityStatus.unknown,
        message:
            'The identity model "$model" does not match any known profile.',
      );
    }

    if (configured == null) {
      return DeviceIdentity(
        configuredProfile: null,
        detectedProfile: detected,
        rawIdentity: rawIdentity,
        manufacturer: manufacturer,
        model: model,
        serialNumber: serialNumber,
        firmware: firmware,
        status: DeviceIdentityStatus.detectedOnly,
        message: 'Detected profile "$detected", but no profile is configured.',
      );
    }

    if (configured == detected) {
      return DeviceIdentity(
        configuredProfile: configured,
        detectedProfile: detected,
        rawIdentity: rawIdentity,
        manufacturer: manufacturer,
        model: model,
        serialNumber: serialNumber,
        firmware: firmware,
        status: DeviceIdentityStatus.confirmed,
        message:
            'Detected identity matches the configured profile '
            '"$detected".',
      );
    }

    return DeviceIdentity(
      configuredProfile: configured,
      detectedProfile: detected,
      rawIdentity: rawIdentity,
      manufacturer: manufacturer,
      model: model,
      serialNumber: serialNumber,
      firmware: firmware,
      status: DeviceIdentityStatus.mismatch,
      message:
          'The configured profile is "$configured", but the detected '
          'identity belongs to "$detected".',
    );
  }

  Future<String> _loadAsset(
    String path, {
    required DeviceErrorCode missingCode,
    required String profileId,
  }) async {
    try {
      return await assetSource.loadString(path);
    } on DeviceAssetNotFoundException catch (error) {
      throw DeviceCommandException(
        missingCode,
        'The device asset "$path" could not be loaded: $error',
        profile: profileId,
        details: {'asset': path},
      );
    } catch (error) {
      throw DeviceCommandException(
        missingCode,
        'The device asset "$path" could not be loaded: $error',
        profile: profileId,
        details: {'asset': path},
      );
    }
  }
}
