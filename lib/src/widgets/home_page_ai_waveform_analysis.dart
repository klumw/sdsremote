part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeAiWaveformAnalysis on _OsciHomePageState {
  /// First acquired channel, used when an analysis tool omits the channel.
  String? _defaultAnalysisChannel() {
    if (_waveformCh1?.points.isNotEmpty ?? false) return 'ch1';
    if (_waveformCh2?.points.isNotEmpty ?? false) return 'ch2';
    if (_waveformCh3?.points.isNotEmpty ?? false) return 'ch3';
    if (_waveformCh4?.points.isNotEmpty ?? false) return 'ch4';
    return null;
  }

  /// Trace of an acquired channel for the analysis engine.
  WaveformTrace? _analysisTraceForChannel(String? channel) {
    final requested = channel?.trim().toLowerCase();
    final selected = requested == null || requested.isEmpty
        ? _defaultAnalysisChannel()
        : requested;
    if (selected == null) return null;
    final data = switch (selected) {
      'ch1' => _waveformCh1,
      'ch2' => _waveformCh2,
      'ch3' => _waveformCh3,
      'ch4' => _waveformCh4,
      _ => null,
    };
    if (data == null || data.points.isEmpty) return null;
    return WaveformTrace.fromPoints(data.points, channel: selected);
  }

  ({List<WaveformSignalType>? types, String? error}) _parseReferenceTypes(
    List<String>? ids,
  ) {
    if (ids == null || ids.isEmpty) {
      return (types: null, error: null);
    }
    final types = <WaveformSignalType>[];
    final invalid = <String>[];
    for (final id in ids) {
      final type = WaveformSignalType.parse(id);
      if (type == null) {
        invalid.add(id);
      } else if (!types.contains(type)) {
        types.add(type);
      }
    }
    if (invalid.isNotEmpty) {
      return (
        types: null,
        error:
            'Unknown reference type(s): ${invalid.join(', ')}. Valid types: '
            '${WaveformSignalType.values.map((type) => type.id).join(', ')}.',
      );
    }
    return (types: types.isEmpty ? null : types, error: null);
  }

  /// `classify_waveform` provider for the Waveform AI.
  Future<Map<String, dynamic>> _classifyWaveformForAi({
    String? channel,
    List<String>? referenceTypes,
  }) async {
    if (!_waveformAcquired) {
      return <String, dynamic>{
        'error': 'No waveform is displayed. Acquire a waveform first.',
      };
    }
    final parsed = _parseReferenceTypes(referenceTypes);
    if (parsed.error != null) return <String, dynamic>{'error': parsed.error};
    final trace = _analysisTraceForChannel(channel);
    if (trace == null) {
      return <String, dynamic>{
        'error':
            'No acquired waveform data is available for '
            '${channel ?? 'the first channel'}. Acquire the channel first.',
      };
    }
    final result = await _waveformAnalysisService.classifyAsync(
      trace,
      options: WaveformAnalysisOptions(referenceTypes: parsed.types),
      channel: trace.channel,
    );
    return result.toMap();
  }

  /// `compare_waveform_to_references` provider for the Waveform AI.
  Future<Map<String, dynamic>> _compareWaveformToReferencesForAi({
    String? channel,
    List<String>? referenceTypes,
  }) async {
    final map = await _classifyWaveformForAi(
      channel: channel,
      referenceTypes: referenceTypes,
    );
    if (map.containsKey('error')) return map;
    final ranking = map['allCandidates'];
    final individualScores = <String, dynamic>{};
    if (ranking is List) {
      for (final candidate in ranking) {
        if (candidate is Map) {
          individualScores[candidate['referenceLabel']?.toString() ??
                  candidate['referenceType']?.toString() ??
                  'unknown'] =
              candidate['similarityPercent'];
        }
      }
    }
    return <String, dynamic>{
      ...map,
      'ranking': ranking,
      'bestMatch': ranking is List && ranking.isNotEmpty ? ranking.first : null,
      'individualSimilarityScores': individualScores,
    };
  }

  /// `get_waveform_features` provider for the Waveform AI.
  Future<Map<String, dynamic>> _waveformFeaturesForAi({String? channel}) async {
    if (!_waveformAcquired) {
      return <String, dynamic>{
        'error': 'No waveform is displayed. Acquire a waveform first.',
      };
    }
    final trace = _analysisTraceForChannel(channel);
    if (trace == null) {
      return <String, dynamic>{
        'error':
            'No acquired waveform data is available for '
            '${channel ?? 'the first channel'}. Acquire the channel first.',
      };
    }
    final features = await _waveformAnalysisService.featuresAsync(trace);
    return <String, dynamic>{'channel': trace.channel, ...features.toMap()};
  }

  /// `compare_waveforms` provider for the Waveform AI.
  Future<Map<String, dynamic>> _compareWaveformsForAi({
    required String channelA,
    required String channelB,
  }) async {
    if (!_waveformAcquired) {
      return <String, dynamic>{
        'error': 'No waveform is displayed. Acquire a waveform first.',
      };
    }
    if (channelA == channelB) {
      return <String, dynamic>{
        'error': 'Choose two different channels for the comparison.',
      };
    }
    final traceA = _analysisTraceForChannel(channelA);
    if (traceA == null) {
      return <String, dynamic>{
        'error': 'No acquired waveform data is available for $channelA.',
      };
    }
    final traceB = _analysisTraceForChannel(channelB);
    if (traceB == null) {
      return <String, dynamic>{
        'error': 'No acquired waveform data is available for $channelB.',
      };
    }
    final result = await _waveformAnalysisService.compareWaveformsAsync(
      traceA,
      traceB,
      channelA: channelA,
      channelB: channelB,
    );
    return result.toMap();
  }

  /// `generate_reference_waveform` provider for the Waveform AI.
  Future<Map<String, dynamic>> _generateWaveformReferenceForAi({
    required String referenceType,
    Map<String, dynamic>? parameters,
  }) async {
    final type = WaveformSignalType.parse(referenceType);
    if (type == null) {
      return <String, dynamic>{
        'error':
            'Unknown reference type "$referenceType". Valid types: '
            '${WaveformSignalType.values.map((type) => type.id).join(', ')}.',
      };
    }
    final parsed = parameters == null || parameters.isEmpty
        ? const ReferenceParameters()
        : ReferenceParameters.fromMap(parameters);
    final reference = _waveformAnalysisService.generateReference(type, parsed);
    return _waveformAnalysisService.referencePreview(reference);
  }
}
