/// Persistent store for user-supplied waveform fault-analysis specifications.
///
/// The store is a JSON file in the application data directory. It is organized
/// per channel and contains only the values the user supplied for the fault
/// tests (reference values, tolerances and limits). Measured values and
/// analysis results are never written.
library;

import 'dart:convert';
import 'dart:io';

import '../../app/app_paths.dart';

/// Reads and writes the long-term fault-analysis profile.
///
/// The file layout is:
///
/// ```json
/// {
///   "schemaVersion": 1,
///   "updatedAt": "2026-11-02T12:00:00.000Z",
///   "channels": {
///     "ch1": {
///       "updatedAt": "2026-11-02T12:00:00.000Z",
///       "specification": {
///         "amplitude": {"expectedVppVolts": 5.0, "tolerancePercent": 2.0}
///       }
///     }
///   },
///   "global": {
///     "measurement_artifacts": {"probeAttenuation": 10.0, "adcBits": 8}
///   }
/// }
/// ```
class WaveformFaultProfileStore {
  const WaveformFaultProfileStore({this.file});

  /// Optional override for tests; production uses
  /// [AppPaths.faultAnalysisProfileFile].
  final File? file;

  static const int schemaVersion = 1;
  static const List<String> supportedChannels = ['ch1', 'ch2', 'ch3', 'ch4'];

  File get _file => file ?? AppPaths.faultAnalysisProfileFile;

  /// Reads the stored profile.
  ///
  /// With [channel], the result additionally contains the merged
  /// `specification` for that channel (channel values plus global values).
  Future<Map<String, dynamic>> read({String? channel}) async {
    final target = _file;
    if (!await target.exists()) {
      return <String, dynamic>{
        'exists': false,
        'hasData': false,
        'filePath': target.path,
      };
    }
    try {
      final decoded = jsonDecode(await target.readAsString());
      if (decoded is! Map) {
        return <String, dynamic>{
          'exists': true,
          'hasData': false,
          'filePath': target.path,
          'error': 'The stored profile is not a JSON object.',
        };
      }
      final root = Map<String, dynamic>.from(decoded);
      final version = root['schemaVersion'];
      if (version is num && version.toInt() > schemaVersion) {
        return <String, dynamic>{
          'exists': true,
          'hasData': false,
          'filePath': target.path,
          'schemaVersion': version.toInt(),
          'error':
              'The stored profile uses unsupported schema version $version '
              '(supported: $schemaVersion).',
        };
      }
      final channels = _readChannels(root);
      final global = _readGlobal(root);
      final hasData =
          channels.values.any(
            (entry) =>
                entry is Map &&
                entry['specification'] is Map &&
                (entry['specification'] as Map).isNotEmpty,
          ) ||
          global.values.any((value) => value is Map && value.isNotEmpty);
      final result = <String, dynamic>{
        'exists': true,
        'hasData': hasData,
        'schemaVersion': version is num ? version.toInt() : schemaVersion,
        if (root['updatedAt'] != null) 'updatedAt': root['updatedAt'],
        'filePath': target.path,
        'channels': channels,
        'global': global,
      };
      final requested = _normalizeChannel(channel);
      if (requested != null) {
        if (!supportedChannels.contains(requested)) {
          return <String, dynamic>{
            ...result,
            'error':
                'Unknown channel "$requested". Valid channels: '
                '${supportedChannels.join(', ')}.',
          };
        }
        final entry = channels[requested];
        final channelSpecification =
            entry is Map && entry['specification'] is Map
            ? Map<String, dynamic>.from(entry['specification'] as Map)
            : <String, dynamic>{};
        result['channel'] = requested;
        result['specification'] = _mergeSpecifications(
          channelSpecification,
          global,
        );
        result['channelUpdatedAt'] = entry is Map ? entry['updatedAt'] : null;
      }
      return result;
    } on Object catch (error) {
      return <String, dynamic>{
        'exists': true,
        'hasData': false,
        'filePath': target.path,
        'error': 'Could not read the stored profile: $error',
      };
    }
  }

  /// Writes [specification] for [channel].
  ///
  /// [mode] is `replace` (default) to overwrite the channel block, or `merge`
  /// to update only the supplied tests and fields. `measurement_artifacts`
  /// values are stored once in the global block.
  Future<Map<String, dynamic>> save({
    required String channel,
    required Map<String, dynamic> specification,
    String mode = 'replace',
  }) async {
    final normalizedChannel = _normalizeChannel(channel);
    final normalizedMode = mode.trim().toLowerCase();
    if (normalizedChannel == null ||
        !supportedChannels.contains(normalizedChannel)) {
      return <String, dynamic>{
        'error':
            'Unknown channel "$channel". Valid channels: '
            '${supportedChannels.join(', ')}.',
      };
    }
    if (normalizedMode != 'replace' && normalizedMode != 'merge') {
      return <String, dynamic>{
        'error': 'Unknown save mode "$mode". Valid modes: replace, merge.',
      };
    }
    final target = _file;
    try {
      await target.parent.create(recursive: true);
      final root = await _loadRoot(target);
      final channels = _readChannels(root);
      final global = _readGlobal(root);
      final incoming = _deepCopyMap(specification);
      final incomingArtifacts = incoming.remove('measurement_artifacts');
      final existingEntry = channels[normalizedChannel];
      final existingSpecification =
          existingEntry is Map && existingEntry['specification'] is Map
          ? Map<String, dynamic>.from(existingEntry['specification'] as Map)
          : <String, dynamic>{};
      final mergedSpecification = normalizedMode == 'merge'
          ? _mergeSpecifications(existingSpecification, incoming)
          : incoming;
      final now = DateTime.now().toUtc().toIso8601String();
      if (mergedSpecification.isEmpty) {
        channels.remove(normalizedChannel);
      } else {
        channels[normalizedChannel] = {
          'updatedAt': now,
          'specification': mergedSpecification,
        };
      }
      if (incomingArtifacts is Map) {
        final artifactMap = Map<String, dynamic>.from(incomingArtifacts);
        final existingArtifacts = global['measurement_artifacts'];
        if (normalizedMode == 'merge' && existingArtifacts is Map) {
          global['measurement_artifacts'] = {
            ...Map<String, dynamic>.from(existingArtifacts),
            ...artifactMap,
          };
        } else {
          global['measurement_artifacts'] = artifactMap;
        }
      }
      root['schemaVersion'] = schemaVersion;
      root['updatedAt'] = now;
      root['channels'] = channels;
      root['global'] = global;
      await _writeAtomic(target, root);
      return <String, dynamic>{
        'saved': true,
        'filePath': target.path,
        'channel': normalizedChannel,
        'mode': normalizedMode,
        'updatedAt': now,
        'storedTests': mergedSpecification.keys.toList(),
        'globalTests': global.keys.toList(),
      };
    } on Object catch (error) {
      return <String, dynamic>{'error': 'Could not save the profile: $error'};
    }
  }

  /// Removes [channel] from the profile, or deletes the complete file when
  /// [channel] is omitted.
  Future<Map<String, dynamic>> clear({String? channel}) async {
    final target = _file;
    if (!await target.exists()) {
      return <String, dynamic>{
        'cleared': true,
        'filePath': target.path,
        'message': 'No stored profile exists.',
      };
    }
    final normalizedChannel = _normalizeChannel(channel);
    if (normalizedChannel == null) {
      try {
        await target.delete();
        return <String, dynamic>{
          'cleared': true,
          'scope': 'all',
          'filePath': target.path,
        };
      } on Object catch (error) {
        return <String, dynamic>{
          'error': 'Could not delete the profile: $error',
        };
      }
    }
    if (!supportedChannels.contains(normalizedChannel)) {
      return <String, dynamic>{
        'error':
            'Unknown channel "$channel". Valid channels: '
            '${supportedChannels.join(', ')}.',
      };
    }
    try {
      final root = await _loadRoot(target);
      final channels = _readChannels(root);
      final global = _readGlobal(root);
      channels.remove(normalizedChannel);
      if (channels.isEmpty && global.isEmpty) {
        await target.delete();
        return <String, dynamic>{
          'cleared': true,
          'scope': normalizedChannel,
          'filePath': target.path,
          'message': 'The profile is now empty and the file was removed.',
        };
      }
      root['channels'] = channels;
      root['global'] = global;
      root['updatedAt'] = DateTime.now().toUtc().toIso8601String();
      await _writeAtomic(target, root);
      return <String, dynamic>{
        'cleared': true,
        'scope': normalizedChannel,
        'filePath': target.path,
      };
    } on Object catch (error) {
      return <String, dynamic>{'error': 'Could not clear the profile: $error'};
    }
  }
}

Future<Map<String, dynamic>> _loadRoot(File target) async {
  if (!await target.exists()) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(await target.readAsString());
    return decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
  } on Object {
    return <String, dynamic>{};
  }
}

Future<void> _writeAtomic(File target, Map<String, dynamic> root) async {
  final temporary = File('${target.path}.tmp');
  await temporary.writeAsString(
    const JsonEncoder.withIndent('  ').convert(root),
    flush: true,
  );
  try {
    await temporary.rename(target.path);
  } on FileSystemException {
    if (await target.exists()) await target.delete();
    await temporary.rename(target.path);
  }
}

Map<String, dynamic> _readChannels(Map<String, dynamic> root) {
  final raw = root['channels'];
  if (raw is! Map) return <String, dynamic>{};
  final result = <String, dynamic>{};
  for (final entry in raw.entries) {
    final channel = _normalizeChannel(entry.key.toString());
    if (channel == null ||
        !WaveformFaultProfileStore.supportedChannels.contains(channel)) {
      continue;
    }
    final value = entry.value;
    if (value is! Map) continue;
    final specification = value['specification'];
    result[channel] = <String, dynamic>{
      if (value['updatedAt'] != null) 'updatedAt': value['updatedAt'],
      'specification': specification is Map
          ? _deepCopyMap(specification)
          : <String, dynamic>{},
    };
  }
  return result;
}

Map<String, dynamic> _readGlobal(Map<String, dynamic> root) {
  final raw = root['global'];
  if (raw is! Map) return <String, dynamic>{};
  final result = <String, dynamic>{};
  for (final entry in raw.entries) {
    final value = entry.value;
    if (value is Map) {
      result[entry.key.toString()] = _deepCopyMap(value);
    }
  }
  return result;
}

Map<String, dynamic> _mergeSpecifications(
  Map<String, dynamic> existing,
  Map<String, dynamic> incoming,
) {
  final result = _deepCopyMap(existing);
  for (final entry in incoming.entries) {
    final key = entry.key.toString();
    final oldValue = result[key];
    final newValue = entry.value;
    if (oldValue is Map && newValue is Map) {
      result[key] = <String, dynamic>{
        ..._deepCopyMap(oldValue),
        ..._deepCopyMap(newValue),
      };
    } else {
      result[key] = _deepCopy(newValue);
    }
  }
  return result;
}

Map<String, dynamic> _deepCopyMap(Map<dynamic, dynamic> source) =>
    <String, dynamic>{
      for (final entry in source.entries)
        entry.key.toString(): _deepCopy(entry.value),
    };

Object? _deepCopy(Object? value) {
  if (value is Map) return _deepCopyMap(value);
  if (value is List) return [for (final item in value) _deepCopy(item)];
  return value;
}

String? _normalizeChannel(String? value) {
  final normalized = value?.trim().toLowerCase();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
