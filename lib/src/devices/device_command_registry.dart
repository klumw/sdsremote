/// Indexed, validated access to one command package.
///
/// The registry is the only place that turns semantic parameters into SCPI
/// text. It never executes code and never interpolates unchecked user input:
/// every placeholder is resolved from a validated parameter, and every value is
/// checked against the package's type, enum, channel and unit rules.
library;

import 'device_profile_models.dart';

/// Optional device-specific waveform capability resolver.
///
/// Returning null means the registry applies the package's generic
/// `supported`/`accepted_aliases` rules. A resolver is used for the
/// signal-generator profiles, whose cross-model mapping is device-specific.
typedef DeviceWaveformCapabilityResolver =
    DeviceWaveformResolution? Function({
      required String requested,
      int? channel,
    });

/// Indexed command registry for one validated package.
class DeviceCommandRegistry {
  DeviceCommandRegistry({
    required this.profileId,
    required this.metadata,
    required List<DeviceCommandDefinition> commands,
    required this.waveforms,
    required this.syntax,
    DeviceWaveformCapabilityResolver? waveformResolver,
  }) : _commands = List.unmodifiable(commands),
       _waveformResolver = waveformResolver {
    for (final command in _commands) {
      _byId[command.commandId] = command;
      _byNormalizedName.putIfAbsent(_normalize(command.name), () => command);
      final alias = command.aliasOrDescription;
      if (alias != null) {
        _byNormalizedName.putIfAbsent(_normalize(alias), () => command);
      }
      for (final pattern in _allPatterns(command)) {
        _rawPatterns.add((
          command: command,
          regex: _compileRawPattern(_replaceAlternatives(pattern, command)),
          query: _isQueryPattern(command, pattern),
        ));
      }
    }
  }

  final String profileId;
  final DevicePackageMetadata metadata;
  final DeviceWaveforms waveforms;
  final DeviceSyntax syntax;

  final List<DeviceCommandDefinition> _commands;
  final DeviceWaveformCapabilityResolver? _waveformResolver;
  final Map<String, DeviceCommandDefinition> _byId = {};
  final Map<String, DeviceCommandDefinition> _byNormalizedName = {};
  final List<({DeviceCommandDefinition command, RegExp regex, bool query})>
  _rawPatterns = [];

  /// All commands in package order.
  List<DeviceCommandDefinition> get commands => _commands;

  /// Commands that can be built from semantic parameters without guessing.
  List<DeviceCommandDefinition> get semanticallyResolvableCommands =>
      _commands.where((command) => command.isSemanticallyResolvable).toList();

  /// Looks up a command by its stable `command_id`.
  DeviceCommandDefinition? getCommand(String commandId) => _byId[commandId];

  /// Finds commands by id, name, alias, description or pattern.
  List<DeviceCommandDefinition> findCommands(String query) {
    final needle = _normalize(query);
    if (needle.isEmpty) return const [];
    final ranked = <({DeviceCommandDefinition command, int score})>[];
    for (final command in _commands) {
      var score = 0;
      if (_normalize(command.commandId) == needle) score = 100;
      if (_normalize(command.name) == needle) score = score < 90 ? 90 : score;
      if (_normalize(command.aliasOrDescription ?? '') == needle) {
        score = score < 80 ? 80 : score;
      }
      if (score == 0) {
        if (_normalize(command.commandId).contains(needle)) {
          score = 60;
        }
        if (_normalize(command.name).contains(needle)) {
          score = score < 50 ? 50 : score;
        }
        if (_normalize(command.aliasOrDescription ?? '').contains(needle)) {
          score = score < 40 ? 40 : score;
        }
        if (_normalize(command.description ?? '').contains(needle)) {
          score = score < 30 ? 30 : score;
        }
        if (_normalize(command.scpiPattern).contains(needle)) {
          score = score < 20 ? 20 : score;
        }
      }
      if (score > 0) ranked.add((command: command, score: score));
    }
    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.command.commandId.compareTo(b.command.commandId);
    });
    return ranked.map((entry) => entry.command).toList(growable: false);
  }

  /// Supported canonical waveform names from the package.
  List<String> getSupportedWaveforms() =>
      List.unmodifiable(waveforms.supported);

  /// Resolves a requested waveform name.
  ///
  /// The package's own names and aliases are accepted directly. A
  /// device-specific resolver may apply the documented cross-model mapping and
  /// must report it in [DeviceWaveformResolution]. Unknown names are rejected;
  /// they are never silently changed.
  DeviceWaveformResolution resolveWaveform({
    required String requested,
    int? channel,
  }) {
    final trimmed = requested.trim();
    final normalized = trimmed.toUpperCase();
    if (normalized.isEmpty) {
      throw DeviceCommandException(
        DeviceErrorCode.invalidParameterValue,
        'The waveform name must not be empty.',
        profile: profileId,
        parameter: 'shape',
        requestedValue: requested,
      );
    }

    final custom = _waveformResolver?.call(
      requested: trimmed,
      channel: channel,
    );
    if (custom != null) return custom;

    if (waveforms.supported
        .map((name) => name.toUpperCase())
        .contains(normalized)) {
      return DeviceWaveformResolution(
        requested: trimmed,
        resolved: normalized,
        channel: channel,
        mapped: normalized != trimmed,
      );
    }
    if (waveforms.acceptedAliases
        .map((name) => name.toUpperCase())
        .contains(normalized)) {
      final canonical = _canonicalWaveformAlias(normalized);
      final resolved =
          canonical != null &&
              waveforms.supported
                  .map((name) => name.toUpperCase())
                  .contains(canonical)
          ? canonical
          : normalized;
      return DeviceWaveformResolution(
        requested: trimmed,
        resolved: resolved,
        channel: channel,
        mapped: resolved != normalized,
        note: resolved != normalized
            ? 'Accepted alias "$normalized" normalized to "$resolved".'
            : null,
      );
    }

    throw DeviceCommandException(
      DeviceErrorCode.unsupportedWaveform,
      'The waveform "$trimmed" is not supported by profile "$profileId".',
      profile: profileId,
      parameter: 'shape',
      requestedValue: trimmed,
      supportedValues: [...waveforms.supported, ...waveforms.acceptedAliases],
      details: {
        'supported_waveforms': waveforms.supported,
        'accepted_aliases': waveforms.acceptedAliases,
        if (waveforms.unsupportedNote != null)
          'unsupported_note': waveforms.unsupportedNote,
      },
    );
  }

  /// Resolves [commandId] with semantic [parameters].
  ///
  /// Set [query] to true to use the documented query form. The returned SCPI
  /// string is deterministic and contains no unchecked interpolation.
  DeviceResolvedCommand resolveCommand(
    String commandId,
    Map<String, Object?> parameters, {
    bool query = false,
  }) {
    final command = _requireCommand(commandId);
    _ensureOperationSupported(command, query: query);

    final pattern = query ? command.queryPattern : command.scpiPattern;
    if (pattern == null) {
      throw DeviceCommandException(
        query
            ? DeviceErrorCode.queryNotSupported
            : DeviceErrorCode.setNotSupported,
        'Command "$commandId" has no ${query ? 'query' : 'write'} form.',
        profile: profileId,
        commandId: commandId,
      );
    }

    if (!command.isSemanticallyResolvable) {
      throw DeviceCommandException(
        DeviceErrorCode.commandNotResolvable,
        'Command "$commandId" has placeholders without parameter '
        'definitions (${command.unresolvedPlaceholders.map((name) => '<$name>').join(', ')}). '
        'Use the authorized raw command reference for this command.',
        profile: profileId,
        commandId: commandId,
        details: {'unresolved_placeholders': command.unresolvedPlaceholders},
      );
    }

    final normalization = _normalizeParameters(
      command,
      parameters,
      pattern: pattern,
    );

    final scpi = _renderPattern(
      pattern,
      command,
      normalization.values,
      units: normalization.units,
      query: query,
    );

    return DeviceResolvedCommand(
      command: command,
      scpi: scpi,
      query: query,
      parameters: normalization.values,
      waveformResolution: normalization.waveformResolution,
      notes: normalization.notes,
    );
  }

  /// Validates a semantic command without building the final string.
  DeviceCommandValidation validateCommand(
    String commandId,
    Map<String, Object?> parameters, {
    bool query = false,
  }) {
    try {
      resolveCommand(commandId, parameters, query: query);
      return DeviceCommandValidation(command: getCommand(commandId));
    } on DeviceCommandException catch (error) {
      return DeviceCommandValidation(
        command: getCommand(commandId),
        error: error,
      );
    }
  }

  /// Builds the deterministic SCPI string for a semantic command.
  String buildCommand(
    String commandId,
    Map<String, Object?> parameters, {
    bool query = false,
  }) => resolveCommand(commandId, parameters, query: query).scpi;

  /// Returns documentation for one command.
  DeviceCommandDocumentation getCommandDocumentation(String commandId) {
    final command = _requireCommand(commandId);
    return DeviceCommandDocumentation(command: command, profileId: profileId);
  }

  /// Normalizes whole header segments through the documented aliases.
  ///
  /// Only complete segments are replaced. `SQUARE` and `PULSE` are not in the
  /// alias table and therefore stay untouched.
  String normalizeHeaderAliases(String command) {
    final firstSpace = command.indexOf(RegExp(r'\s'));
    final header = firstSpace < 0 ? command : command.substring(0, firstSpace);
    final rest = firstSpace < 0 ? '' : command.substring(firstSpace);
    final segments = header.split(':').map((segment) {
      final match = RegExp(r'^([A-Za-z]+)(\d*)$').firstMatch(segment);
      if (match == null) return segment.toUpperCase();
      final base = match.group(1)!.toUpperCase();
      final suffix = match.group(2)!;
      final alias = syntax.headerAliases[base] ?? base;
      return '$alias$suffix';
    });
    return '${segments.join(':')}$rest';
  }

  /// Validates a raw SCPI command against the package.
  ///
  /// This is the guard for the transport tool. It checks the header, the
  /// operation kind, the channel and any parameter definition that exists. If
  /// the package has placeholders without definitions, the command is accepted
  /// with a warning instead of inventing a validation rule.
  DeviceCommandValidation validateRawCommand(
    String command, {
    required bool isQuery,
  }) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) {
      return DeviceCommandValidation(
        error: DeviceCommandException(
          DeviceErrorCode.invalidParameterValue,
          'The SCPI command must not be empty.',
          profile: profileId,
        ),
      );
    }
    if (trimmed.contains(';') ||
        trimmed.contains('\n') ||
        trimmed.contains('\r') ||
        trimmed.contains('\u0000')) {
      return DeviceCommandValidation(
        error: DeviceCommandException(
          DeviceErrorCode.invalidParameterValue,
          'The SCPI command must contain exactly one line and no command '
          'chaining.',
          profile: profileId,
          requestedValue: trimmed,
        ),
      );
    }
    // The question mark belongs to the header and may be followed by query
    // parameters (for example "C1:PAVA? PKPK"), so it is checked in the first
    // token rather than at the end of the line.
    final headerToken = trimmed.split(RegExp(r'\s')).first;
    final looksLikeQuery = headerToken.contains('?');
    if (isQuery != looksLikeQuery) {
      return DeviceCommandValidation(
        error: DeviceCommandException(
          isQuery
              ? DeviceErrorCode.invalidParameterValue
              : DeviceErrorCode.setNotSupported,
          isQuery
              ? 'A query operation requires a query header containing "?".'
              : 'A write operation must not use a query header.',
          profile: profileId,
          requestedValue: trimmed,
        ),
      );
    }

    final normalized = normalizeHeaderAliases(trimmed);

    for (final entry in _rawPatterns) {
      if (entry.query != isQuery) continue;
      final match = entry.regex.firstMatch(normalized);
      if (match == null) continue;
      return _validateRawMatch(entry.command, match, normalized, isQuery);
    }

    // A command that exists in the other operation class produces a clearer
    // error than an unknown header.
    for (final entry in _rawPatterns) {
      if (entry.query == isQuery) continue;
      if (entry.regex.hasMatch(normalized)) {
        return DeviceCommandValidation(
          command: entry.command,
          error: DeviceCommandException(
            isQuery
                ? DeviceErrorCode.queryNotSupported
                : DeviceErrorCode.setNotSupported,
            isQuery
                ? 'Command "${entry.command.commandId}" has no documented '
                      'query form.'
                : 'Command "${entry.command.commandId}" is a query and cannot '
                      'be sent as a write.',
            profile: profileId,
            commandId: entry.command.commandId,
            requestedValue: trimmed,
          ),
        );
      }
    }

    for (final pattern in _specialCommandPatterns) {
      if (pattern.hasMatch(normalized)) {
        return DeviceCommandValidation(
          warnings: [
            'Documented special command accepted outside the SCPI command '
                'package.',
          ],
        );
      }
    }

    final channel = _channelFromRawCommand(normalized);
    if (channel != null && !_channelAllowed(channel, null)) {
      return DeviceCommandValidation(
        error: DeviceCommandException(
          DeviceErrorCode.unsupportedChannel,
          'Channel $channel is not supported by profile "$profileId".',
          profile: profileId,
          requestedValue: channel,
          supportedValues: syntax.sourceChannelAllowedValues
              .map((value) => value.toString())
              .toList(growable: false),
        ),
      );
    }

    final header = normalized.split(RegExp(r'\s')).first;
    final suggestions = findCommands(
      header,
    ).take(3).map((c) => c.name).toList();
    return DeviceCommandValidation(
      error: DeviceCommandException(
        DeviceErrorCode.unknownCommand,
        'The command "$trimmed" is not defined by profile "$profileId".',
        profile: profileId,
        requestedValue: trimmed,
        supportedValues: suggestions,
        details: {if (suggestions.isNotEmpty) 'suggestions': suggestions},
      ),
    );
  }

  /// Additional raw-command patterns documented outside the SCPI package,
  /// for example the SDS front-panel simulation commands.
  List<RegExp> get _specialCommandPatterns => _specialPatterns;
  final List<RegExp> _specialPatterns = [];

  /// Registers special command patterns. Called by the profile store after
  /// construction so the descriptor remains the single source.
  void registerSpecialCommandPatterns(Iterable<String> patterns) {
    for (final pattern in patterns) {
      _specialPatterns.add(RegExp(pattern, caseSensitive: false));
    }
  }

  // ---------------------------------------------------------------------------
  // Resolution internals
  // ---------------------------------------------------------------------------

  DeviceCommandDefinition _requireCommand(String commandId) {
    final command = _byId[commandId];
    if (command == null) {
      throw DeviceCommandException(
        DeviceErrorCode.unknownCommand,
        'Command "$commandId" is not defined by profile "$profileId".',
        profile: profileId,
        commandId: commandId,
      );
    }
    return command;
  }

  void _ensureOperationSupported(
    DeviceCommandDefinition command, {
    required bool query,
  }) {
    if (query) {
      if (!command.allowsQuery) {
        throw DeviceCommandException(
          DeviceErrorCode.queryNotSupported,
          'Command "${command.commandId}" has no documented query form.',
          profile: profileId,
          commandId: command.commandId,
        );
      }
      return;
    }
    if (!command.allowsSet) {
      throw DeviceCommandException(
        DeviceErrorCode.setNotSupported,
        command.isQueryOnly
            ? 'Command "${command.commandId}" is a query and cannot be used '
                  'as a setter.'
            : 'Command "${command.commandId}" cannot be used as a setter.',
        profile: profileId,
        commandId: command.commandId,
      );
    }
  }

  _ParameterNormalization _normalizeParameters(
    DeviceCommandDefinition command,
    Map<String, Object?> input, {
    required String pattern,
  }) {
    final parameterNames = command.parameters
        .map((parameter) => parameter.name)
        .toSet();
    final allowsUnitKey = command.parameters.any(
      (parameter) => parameter.unitRule != null,
    );
    for (final key in input.keys) {
      if (!parameterNames.contains(key) && !(key == 'unit' && allowsUnitKey)) {
        throw DeviceCommandException(
          DeviceErrorCode.unknownParameter,
          'Command "${command.commandId}" has no parameter "$key".',
          profile: profileId,
          commandId: command.commandId,
          parameter: key,
          details: {'known_parameters': parameterNames.toList(growable: false)},
        );
      }
    }

    final values = <String, Object?>{};
    final units = <String, String>{};
    final notes = <String>[];
    DeviceWaveformResolution? waveformResolution;

    final unitInput = input['unit']?.toString();

    for (final parameter in command.parameters) {
      final provided = input.containsKey(parameter.name);
      final referenced = _patternReferencesParameter(pattern, parameter);
      if (!provided) {
        if (parameter.required && referenced) {
          throw DeviceCommandException(
            DeviceErrorCode.missingParameter,
            'Command "${command.commandId}" requires parameter '
            '"${parameter.name}".',
            profile: profileId,
            commandId: command.commandId,
            parameter: parameter.name,
          );
        }
        continue;
      }

      final rawValue = input[parameter.name];
      if (rawValue == null) {
        if (parameter.required && referenced) {
          throw DeviceCommandException(
            DeviceErrorCode.missingParameter,
            'Command "${command.commandId}" requires parameter '
            '"${parameter.name}".',
            profile: profileId,
            commandId: command.commandId,
            parameter: parameter.name,
          );
        }
        continue;
      }

      try {
        switch (parameter.type) {
          case DeviceParameterType.integer:
            final parsed = _parseInteger(rawValue);
            if (parsed == null) {
              throw DeviceCommandException(
                DeviceErrorCode.invalidParameterValue,
                'Parameter "${parameter.name}" must be an integer.',
                profile: profileId,
                commandId: command.commandId,
                parameter: parameter.name,
                requestedValue: rawValue,
              );
            }
            _validateNumberBounds(parameter, parsed.toDouble());
            if (parameter.name == 'n') {
              if (!_channelAllowed(parsed, command)) {
                throw DeviceCommandException(
                  DeviceErrorCode.unsupportedChannel,
                  'Channel $parsed is not supported by profile "$profileId".',
                  profile: profileId,
                  commandId: command.commandId,
                  parameter: parameter.name,
                  requestedValue: parsed,
                  supportedValues: _allowedChannels(
                    command,
                  ).map((value) => value.toString()).toList(growable: false),
                );
              }
            } else {
              _validateAllowedValues(parameter, parsed);
            }
            values[parameter.name] = parsed;

          case DeviceParameterType.number:
            final token = _parseNumericToken(rawValue);
            if (token == null) {
              throw DeviceCommandException(
                DeviceErrorCode.invalidParameterValue,
                'Parameter "${parameter.name}" must be a finite number.',
                profile: profileId,
                commandId: command.commandId,
                parameter: parameter.name,
                requestedValue: rawValue,
              );
            }
            final rule = parameter.unitRule;
            if (rule == null) {
              if (token.unit != null || unitInput != null) {
                throw DeviceCommandException(
                  DeviceErrorCode.invalidUnit,
                  'Parameter "${parameter.name}" does not accept a unit.',
                  profile: profileId,
                  commandId: command.commandId,
                  parameter: parameter.name,
                  requestedValue: token.unit ?? unitInput,
                );
              }
              _validateNumberBounds(parameter, token.value);
              values[parameter.name] = token.value;
            } else {
              final requestedUnit = unitInput ?? token.unit;
              final normalized = rule.normalize(token.value, requestedUnit);
              _validateNumberBounds(parameter, normalized.value);
              values[parameter.name] = normalized.value;
              units[parameter.name] = normalized.unit;
              if (normalized.converted) {
                notes.add(
                  'Parameter "${parameter.name}" normalized from '
                  '${_formatNumber(token.value)}${token.unit ?? ''} to '
                  '${_formatNumber(normalized.value)}${normalized.unit}.',
                );
              }
            }

          case DeviceParameterType.enumValue:
            final text = rawValue.toString().trim().toUpperCase();
            if (text.isEmpty) {
              throw DeviceCommandException(
                DeviceErrorCode.invalidParameterValue,
                'Parameter "${parameter.name}" must not be empty.',
                profile: profileId,
                commandId: command.commandId,
                parameter: parameter.name,
              );
            }
            if (parameter.isWaveformReference) {
              final resolution = resolveWaveform(
                requested: text,
                channel: _intFrom(values['n']),
              );
              values[parameter.name] = resolution.resolved;
              waveformResolution = resolution;
              if (resolution.mapped) {
                notes.add(
                  'Waveform "${resolution.requested}" mapped to '
                  '"${resolution.resolved}"'
                  '${resolution.note == null ? '.' : ': ${resolution.note}'}',
                );
              }
            } else {
              final allowed = parameter.matchAllowedValue(rawValue);
              if (allowed == null) {
                throw DeviceCommandException(
                  DeviceErrorCode.invalidParameterValue,
                  'Parameter "${parameter.name}" has unsupported value '
                  '"$rawValue".',
                  profile: profileId,
                  commandId: command.commandId,
                  parameter: parameter.name,
                  requestedValue: rawValue,
                  supportedValues: parameter.allowedValues
                      .map((value) => value.toString())
                      .toList(growable: false),
                );
              }
              values[parameter.name] = allowed;
            }

          case DeviceParameterType.string:
            final text = rawValue.toString().trim();
            if (text.isEmpty ||
                text.contains(';') ||
                text.contains('\n') ||
                text.contains('\r')) {
              throw DeviceCommandException(
                DeviceErrorCode.invalidParameterValue,
                'Parameter "${parameter.name}" contains invalid characters.',
                profile: profileId,
                commandId: command.commandId,
                parameter: parameter.name,
                requestedValue: rawValue,
              );
            }
            values[parameter.name] = text;
        }
      } on DeviceCommandException catch (error) {
        throw error.withContext(
          profile: profileId,
          commandId: command.commandId,
          parameter: parameter.name,
          requestedValue: rawValue,
        );
      }
    }

    return _ParameterNormalization(
      values: values,
      units: units,
      notes: notes,
      waveformResolution: waveformResolution,
    );
  }

  String _renderPattern(
    String pattern,
    DeviceCommandDefinition command,
    Map<String, Object?> values, {
    required Map<String, String> units,
    required bool query,
  }) {
    var rendered = pattern;
    rendered = _replaceAlternatives(rendered, command);

    if (rendered.contains('[unit]')) {
      final unitParameter = command.parameters
          .where((parameter) => parameter.unitRule != null)
          .firstOrNull;
      if (unitParameter == null) {
        throw DeviceCommandException(
          DeviceErrorCode.commandNotResolvable,
          'Command "${command.commandId}" uses an optional unit but has no '
          'unit rule.',
          profile: profileId,
          commandId: command.commandId,
        );
      }
      final unit = units[unitParameter.name];
      if (unit == null) {
        throw DeviceCommandException(
          DeviceErrorCode.missingParameter,
          'Command "${command.commandId}" requires a value for '
          '"${unitParameter.name}" before the unit can be rendered.',
          profile: profileId,
          commandId: command.commandId,
          parameter: unitParameter.name,
        );
      }
      rendered = rendered.replaceAll('[unit]', unit);
    }

    final buffer = StringBuffer();
    final ok = _renderOptionalAware(
      rendered,
      command,
      values,
      buffer,
      optional: false,
    );
    if (!ok) {
      throw DeviceCommandException(
        DeviceErrorCode.commandNotResolvable,
        'Command "${command.commandId}" could not be rendered from the '
        'supplied parameters.',
        profile: profileId,
        commandId: command.commandId,
      );
    }
    final text = buffer.toString();
    if (text.contains('<') || text.contains('>')) {
      throw DeviceCommandException(
        DeviceErrorCode.commandNotResolvable,
        'Command "${command.commandId}" still contains an unresolved '
        'placeholder.',
        profile: profileId,
        commandId: command.commandId,
        details: {'pattern': pattern},
      );
    }
    return text;
  }

  bool _renderOptionalAware(
    String pattern,
    DeviceCommandDefinition command,
    Map<String, Object?> values,
    StringBuffer output, {
    required bool optional,
  }) {
    var index = 0;
    while (index < pattern.length) {
      final char = pattern[index];
      if (char == '[') {
        final end = _matchingBracket(pattern, index);
        if (end < 0) {
          throw DeviceCommandException(
            DeviceErrorCode.schemaInvalid,
            'Unbalanced optional group in pattern "${command.scpiPattern}".',
            profile: profileId,
            commandId: command.commandId,
          );
        }
        final inner = pattern.substring(index + 1, end);
        final innerBuffer = StringBuffer();
        final rendered = _renderOptionalAware(
          inner,
          command,
          values,
          innerBuffer,
          optional: true,
        );
        if (rendered) {
          output.write(innerBuffer.toString());
        }
        index = end + 1;
        continue;
      }
      if (char == '<') {
        final end = pattern.indexOf('>', index);
        if (end < 0) {
          throw DeviceCommandException(
            DeviceErrorCode.schemaInvalid,
            'Unbalanced placeholder in pattern "${command.scpiPattern}".',
            profile: profileId,
            commandId: command.commandId,
          );
        }
        final name = pattern.substring(index + 1, end).trim();
        final value = values[name];
        if (value == null) {
          if (optional) return false;
          throw DeviceCommandException(
            DeviceErrorCode.missingParameter,
            'Command "${command.commandId}" requires parameter "$name".',
            profile: profileId,
            commandId: command.commandId,
            parameter: name,
          );
        }
        output.write(_formatParameterValue(value));
        index = end + 1;
        continue;
      }
      output.write(char);
      index++;
    }
    return true;
  }

  String _replaceAlternatives(String pattern, DeviceCommandDefinition command) {
    return pattern.replaceAllMapped(
      RegExp(r'(?<![<\w])([A-Z0-9]+(?:\|[A-Z0-9]+)+)(?![\w>])'),
      (match) {
        final alternatives = match.group(1)!;
        final alternativeSet = alternatives
            .split('|')
            .map((value) => value.toUpperCase())
            .toSet();
        for (final parameter in command.parameters) {
          if (parameter.allowedValues.isEmpty) continue;
          final allowedSet = parameter.allowedValues
              .map((value) => value.toString().toUpperCase())
              .toSet();
          if (allowedSet.containsAll(alternativeSet) &&
              alternativeSet.containsAll(allowedSet)) {
            return '<${parameter.name}>';
          }
        }
        return alternatives;
      },
    );
  }

  int _matchingBracket(String text, int openIndex) {
    var depth = 0;
    for (var index = openIndex; index < text.length; index++) {
      if (text[index] == '[') depth++;
      if (text[index] == ']') {
        depth--;
        if (depth == 0) return index;
      }
    }
    return -1;
  }

  DeviceCommandValidation _validateRawMatch(
    DeviceCommandDefinition command,
    RegExpMatch match,
    String normalized,
    bool isQuery,
  ) {
    final warnings = <String>[];
    final values = <String, Object?>{};

    final channelText = _named(match, 'n');
    if (channelText != null) {
      final channel = int.tryParse(channelText);
      if (channel == null || !_channelAllowed(channel, command)) {
        return DeviceCommandValidation(
          command: command,
          error: DeviceCommandException(
            DeviceErrorCode.unsupportedChannel,
            'Channel $channelText is not supported by profile "$profileId".',
            profile: profileId,
            commandId: command.commandId,
            requestedValue: channelText,
            supportedValues: _allowedChannels(
              command,
            ).map((value) => value.toString()).toList(growable: false),
          ),
        );
      }
      values['n'] = channel;
    }

    final traceText =
        _named(match, 'trace') ??
        _named(match, 'channel') ??
        _named(match, 'source');
    if (traceText != null) {
      final channelMatch = RegExp(
        r'(?:C|CH)(\d+)',
        caseSensitive: false,
      ).firstMatch(traceText);
      if (channelMatch != null) {
        final channel = int.tryParse(channelMatch.group(1)!);
        if (channel != null && !_channelAllowed(channel, command)) {
          return DeviceCommandValidation(
            command: command,
            error: DeviceCommandException(
              DeviceErrorCode.unsupportedChannel,
              'Channel $channel is not supported by profile "$profileId".',
              profile: profileId,
              commandId: command.commandId,
              requestedValue: traceText,
              supportedValues: _allowedChannels(
                command,
              ).map((value) => value.toString()).toList(growable: false),
            ),
          );
        }
      }
    }

    for (final parameter in command.parameters) {
      if (parameter.name == 'n') continue;
      final captured = _named(match, parameter.name);
      if (captured == null) {
        if (parameter.required &&
            _patternHasPlaceholder(
              isQuery ? command.queryPattern ?? '' : command.scpiPattern,
              parameter.name,
            )) {
          warnings.add(
            'Parameter "${parameter.name}" could not be extracted from the '
            'raw command; it was not validated.',
          );
        }
        continue;
      }

      try {
        if (parameter.isWaveformReference) {
          final resolution = resolveWaveform(
            requested: captured,
            channel: _intFrom(values['n']),
          );
          values[parameter.name] = resolution.resolved;
          if (resolution.mapped) {
            warnings.add(
              'Waveform "$captured" resolves to "${resolution.resolved}".',
            );
          }
          continue;
        }

        switch (parameter.type) {
          case DeviceParameterType.integer:
            final parsed = _parseInteger(captured);
            if (parsed == null || !_channelAllowed(parsed, command)) {
              return DeviceCommandValidation(
                command: command,
                error: DeviceCommandException(
                  DeviceErrorCode.unsupportedChannel,
                  'Channel "$captured" is not supported by profile '
                  '"$profileId".',
                  profile: profileId,
                  commandId: command.commandId,
                  requestedValue: captured,
                ),
              );
            }
            values[parameter.name] = parsed;

          case DeviceParameterType.number:
            final token = _parseNumericToken(captured);
            if (token == null) {
              return DeviceCommandValidation(
                command: command,
                error: DeviceCommandException(
                  DeviceErrorCode.invalidParameterValue,
                  'Parameter "${parameter.name}" must be a finite number.',
                  profile: profileId,
                  commandId: command.commandId,
                  parameter: parameter.name,
                  requestedValue: captured,
                ),
              );
            }
            final rule = parameter.unitRule;
            if (rule == null) {
              values[parameter.name] = token.value;
            } else {
              final unitCapture = _named(match, 'unit');
              final normalizedValue = rule.normalize(
                token.value,
                unitCapture ?? token.unit,
              );
              values[parameter.name] = normalizedValue.value;
              if (normalizedValue.converted) {
                warnings.add(
                  'Parameter "${parameter.name}" normalized to '
                  '${_formatNumber(normalizedValue.value)}'
                  '${normalizedValue.unit}.',
                );
              }
            }

          case DeviceParameterType.enumValue:
            final allowed = parameter.matchAllowedValue(captured);
            if (allowed == null) {
              return DeviceCommandValidation(
                command: command,
                error: DeviceCommandException(
                  DeviceErrorCode.invalidParameterValue,
                  'Parameter "${parameter.name}" has unsupported value '
                  '"$captured".',
                  profile: profileId,
                  commandId: command.commandId,
                  parameter: parameter.name,
                  requestedValue: captured,
                  supportedValues: parameter.allowedValues
                      .map((value) => value.toString())
                      .toList(growable: false),
                ),
              );
            }
            values[parameter.name] = allowed;

          case DeviceParameterType.string:
            values[parameter.name] = captured;
        }
      } on DeviceCommandException catch (error) {
        return DeviceCommandValidation(
          command: command,
          error: error.withContext(
            profile: profileId,
            commandId: command.commandId,
            parameter: parameter.name,
            requestedValue: captured,
          ),
        );
      }
    }

    if (command.unresolvedPlaceholders.isNotEmpty) {
      warnings.add(
        'Profile "$profileId" has no parameter definitions for '
        '${command.unresolvedPlaceholders.map((name) => '<$name>').join(', ')}; '
        'the value was checked syntactically but not against a range.',
      );
    }

    return DeviceCommandValidation(
      command: command,
      warnings: warnings,
      parameters: values,
    );
  }

  void _validateNumberBounds(
    DeviceParameterDefinition parameter,
    double value,
  ) {
    final minimum = parameter.minimum;
    final maximum = parameter.maximum;
    if (minimum != null && value < minimum) {
      throw DeviceCommandException(
        DeviceErrorCode.invalidParameterValue,
        'Parameter "${parameter.name}" must be at least $minimum.',
        parameter: parameter.name,
        requestedValue: value,
        supportedValues: ['$minimum..${maximum ?? '*'}'],
      );
    }
    if (maximum != null && value > maximum) {
      throw DeviceCommandException(
        DeviceErrorCode.invalidParameterValue,
        'Parameter "${parameter.name}" must be at most $maximum.',
        parameter: parameter.name,
        requestedValue: value,
        supportedValues: ['${minimum ?? '*'}..$maximum'],
      );
    }
  }

  void _validateAllowedValues(
    DeviceParameterDefinition parameter,
    Object value,
  ) {
    if (parameter.allowedValues.isEmpty) return;
    if (parameter.matchAllowedValue(value) == null) {
      throw DeviceCommandException(
        DeviceErrorCode.invalidParameterValue,
        'Parameter "${parameter.name}" has unsupported value "$value".',
        parameter: parameter.name,
        requestedValue: value,
        supportedValues: parameter.allowedValues
            .map((allowed) => allowed.toString())
            .toList(growable: false),
      );
    }
  }

  bool _channelAllowed(int channel, DeviceCommandDefinition? command) {
    final fromCommand = command
        ?.parameter('n')
        ?.allowedValues
        .whereType<num>()
        .map((value) => value.toInt())
        .toSet();
    if (fromCommand != null && fromCommand.isNotEmpty) {
      return fromCommand.contains(channel);
    }
    final fromSyntax = syntax.sourceChannelAllowedValues.toSet();
    if (fromSyntax.isNotEmpty) return fromSyntax.contains(channel);
    return true;
  }

  List<int> _allowedChannels(DeviceCommandDefinition? command) {
    final fromCommand = command
        ?.parameter('n')
        ?.allowedValues
        .whereType<num>()
        .map((value) => value.toInt())
        .toList(growable: false);
    if (fromCommand != null && fromCommand.isNotEmpty) return fromCommand;
    return syntax.sourceChannelAllowedValues;
  }

  int? _channelFromRawCommand(String command) {
    final match = RegExp(
      r'(?:^|:)(?:C|CH|SOUR|OUTP)(\d+)',
      caseSensitive: false,
    ).firstMatch(command);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  // ---------------------------------------------------------------------------
  // Raw pattern compilation
  // ---------------------------------------------------------------------------

  Iterable<String> _allPatterns(DeviceCommandDefinition command) sync* {
    yield command.scpiPattern;
    if (command.queryPattern != null) yield command.queryPattern!;
    yield* command.scpiPatternAliases;
    yield* command.queryPatternAliases;
  }

  bool _isQueryPattern(DeviceCommandDefinition command, String pattern) =>
      pattern == command.queryPattern ||
      command.queryPatternAliases.contains(pattern);

  RegExp _compileRawPattern(String pattern) {
    final buffer = StringBuffer('^');
    _appendRawPattern(buffer, pattern, <String>{});
    buffer.write(r'$');
    return RegExp(buffer.toString(), caseSensitive: false);
  }

  void _appendRawPattern(
    StringBuffer buffer,
    String pattern,
    Set<String> usedGroupNames,
  ) {
    var index = 0;
    while (index < pattern.length) {
      final char = pattern[index];
      if (char == '[') {
        final end = _matchingBracket(pattern, index);
        if (end > index) {
          final inner = pattern.substring(index + 1, end);
          // `[unit]` is the optional unit suffix of a numeric value, not a
          // literal word. Accept one unit token when it is present.
          if (inner.trim() == 'unit') {
            final capture = usedGroupNames.add('unit')
                ? r'(?<unit>[A-Za-z%]+)'
                : r'([A-Za-z%]+)';
            buffer.write(r'(?:\s*');
            buffer.write(capture);
            buffer.write(')?');
            index = end + 1;
            continue;
          }
          // The packages use a human ellipsis for repeated groups, for
          // example `[<parameter>,…]` or `[,<channel>,<mode>…]`. Expand it to
          // one-or-more comma-separated repetitions of the inner element.
          if (inner.contains('…')) {
            var body = inner.replaceAll('…', '').trim();
            body = body.replaceFirst(RegExp(r',$'), '').trim();
            buffer.write('(?:');
            _appendRawPattern(buffer, body, usedGroupNames);
            buffer.write('(?:,');
            _appendRawPattern(buffer, body, usedGroupNames);
            buffer.write(')*)?');
            index = end + 1;
            continue;
          }
          buffer.write('(?:');
          _appendRawPattern(buffer, inner, usedGroupNames);
          buffer.write(')?');
          index = end + 1;
          continue;
        }
      }
      if (char == '<') {
        final end = pattern.indexOf('>', index);
        if (end > index) {
          final name = pattern.substring(index + 1, end).trim();
          final rest = pattern.substring(end + 1);
          final isHeader = RegExp(r'^\s*:').hasMatch(rest);
          final validName = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$').hasMatch(name);
          // Dart's RegExp rejects duplicate named capture groups. Repeated
          // placeholders (for example `BWL <channel>,<mode>[,<channel>...]`)
          // keep the first named group and use a plain group afterwards.
          final groupName = validName && usedGroupNames.add(name) ? name : null;
          final String capture;
          if (name == 'n') {
            capture = r'\d+';
          } else if (isHeader) {
            capture = r'[A-Za-z0-9]+';
          } else {
            capture = r'[^,\s]+';
          }
          if (groupName == null) {
            buffer.write('($capture)');
          } else {
            buffer.write('(?<$groupName>$capture)');
          }
          index = end + 1;
          continue;
        }
      }
      if (char == '…') {
        buffer.write('.*');
        index++;
        continue;
      }
      if (RegExp(r'\s').hasMatch(char)) {
        buffer.write(r'\s+');
        while (index + 1 < pattern.length &&
            RegExp(r'\s').hasMatch(pattern[index + 1])) {
          index++;
        }
        index++;
        continue;
      }
      if (char == ',') {
        buffer.write(r'\s*,\s*');
        index++;
        continue;
      }
      if (RegExp(r'[A-Za-z0-9_|]').hasMatch(char)) {
        final start = index;
        while (index < pattern.length &&
            RegExp(r'[A-Za-z0-9_|]').hasMatch(pattern[index])) {
          index++;
        }
        final token = pattern.substring(start, index);
        if (token.contains('|')) {
          buffer.write('(?:${token.split('|').map(RegExp.escape).join('|')})');
        } else {
          buffer.write(RegExp.escape(token));
        }
        continue;
      }
      buffer.write(RegExp.escape(char));
      index++;
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

  static String? _canonicalWaveformAlias(String name) {
    switch (name) {
      case 'SINE':
        return 'SIN';
      case 'SQUARE':
        return 'SQU';
      case 'RECTANGLE':
        return 'RECT';
      case 'TRAPEZOID':
        return 'TRAP';
      case 'PULSE':
        return 'PULS';
      case 'TRIANGLE':
        return 'TRI';
      case 'NOISE':
        return 'NOIS';
      default:
        return null;
    }
  }

  static bool _patternHasPlaceholder(String pattern, String name) =>
      RegExp('<${RegExp.escape(name)}>').hasMatch(pattern);

  /// Whether [pattern] references [parameter], either as an explicit
  /// placeholder or through an alternatives group that exactly matches the
  /// parameter's allowed values (for example `ON|OFF|1|0` and `state`).
  static bool _patternReferencesParameter(
    String pattern,
    DeviceParameterDefinition parameter,
  ) {
    if (_patternHasPlaceholder(pattern, parameter.name)) return true;
    if (parameter.allowedValues.isEmpty) return false;
    final allowed = parameter.allowedValues
        .map((value) => value.toString().toUpperCase())
        .toSet();
    for (final match in RegExp(
      r'(?<![<\w])([A-Z0-9]+(?:\|[A-Z0-9]+)+)(?![\w>])',
    ).allMatches(pattern)) {
      final alternatives = match
          .group(1)!
          .split('|')
          .map((value) => value.toUpperCase())
          .toSet();
      if (alternatives.length == allowed.length &&
          alternatives.containsAll(allowed)) {
        return true;
      }
    }
    return false;
  }

  static int? _parseInteger(Object value) {
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    if (value is String) {
      final trimmed = value.trim();
      if (!RegExp(r'^[+-]?\d+$').hasMatch(trimmed)) return null;
      return int.tryParse(trimmed);
    }
    return null;
  }

  static ({double value, String? unit})? _parseNumericToken(Object? value) {
    if (value is num) {
      final doubleValue = value.toDouble();
      if (!doubleValue.isFinite) return null;
      return (value: doubleValue, unit: null);
    }
    if (value is! String) return null;
    final text = value.trim();
    if (text.isEmpty || text.contains(',')) return null;
    final match = RegExp(
      r'^([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)\s*([A-Za-z%]*)$',
    ).firstMatch(text);
    if (match == null) return null;
    final parsed = double.tryParse(match.group(1)!);
    if (parsed == null || !parsed.isFinite) return null;
    final unit = match.group(2)!.isEmpty ? null : match.group(2);
    return (value: parsed, unit: unit);
  }

  /// Reads a named group only when the compiled pattern actually contains it.
  ///
  /// `RegExpMatch.namedGroup` throws for unknown names instead of returning
  /// null, so the presence check is required.
  static String? _named(RegExpMatch match, String name) {
    if (!match.groupNames.contains(name)) return null;
    return match.namedGroup(name);
  }

  static int? _intFrom(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static String _formatNumber(num value) {
    final doubleValue = value.toDouble();
    if (doubleValue.isFinite && doubleValue == doubleValue.roundToDouble()) {
      return doubleValue.toInt().toString();
    }
    return doubleValue.toString();
  }

  static String _formatParameterValue(Object value) {
    if (value is num) return _formatNumber(value);
    if (value is bool) return value ? 'ON' : 'OFF';
    return value.toString().trim().toUpperCase();
  }
}

class _ParameterNormalization {
  const _ParameterNormalization({
    required this.values,
    required this.units,
    required this.notes,
    this.waveformResolution,
  });

  final Map<String, Object?> values;
  final Map<String, String> units;
  final List<String> notes;
  final DeviceWaveformResolution? waveformResolution;
}
