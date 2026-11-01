import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../instrument/measurement.dart' show formatMeasurementValue;
import '../waveform/analysis/waveform_analysis_models.dart';
import '../waveform/analysis/waveform_analysis_service.dart';
import '../waveform/analysis/waveform_math.dart';
import '../waveform/waveform_models.dart';

/// Analysis view of the Acquire Waveform page.
///
/// Runs the classification engine against the captured channels, shows the
/// ranked reference matches, the extracted features and the detected
/// anomalies, and overlays the captured waveform with the best matching
/// reference and the difference trace.
class WaveformAnalysisView extends StatefulWidget {
  const WaveformAnalysisView({
    super.key,
    required this.channels,
    required this.service,
    required this.captureGeneration,
  });

  /// Acquired waveform channels keyed by `'ch1'` … `'ch4'`.
  final Map<String, WaveformData> channels;

  /// Shared analysis engine; also used by the Waveform AI tools.
  final WaveformAnalysisService service;

  /// Increments on every new acquisition; the view resets when it changes.
  final int captureGeneration;

  @override
  State<WaveformAnalysisView> createState() => _WaveformAnalysisViewState();
}

class _WaveformAnalysisViewState extends State<WaveformAnalysisView> {
  final Set<WaveformSignalType> _enabledTypes = {...WaveformSignalType.values};
  final ScrollController _scrollController = ScrollController();

  String? _channel;
  WaveformClassification? _result;
  WaveformTrace? _captureTrace;
  ReferenceWaveform? _reference;
  WaveformSignalType? _selectedReference;
  bool _loading = false;
  bool _showAllCandidates = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _channel = _defaultChannel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.channels.isNotEmpty) {
        _runClassification(types: _enabledTypes.toList());
      }
    });
  }

  @override
  void didUpdateWidget(WaveformAnalysisView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final channelStillAvailable =
        _channel != null && widget.channels.containsKey(_channel);
    if (oldWidget.captureGeneration != widget.captureGeneration ||
        !channelStillAvailable) {
      _requestId++;
      _result = null;
      _captureTrace = null;
      _reference = null;
      _error = null;
      _loading = false;
      _channel = _defaultChannel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.channels.isNotEmpty) {
          _runClassification(types: _enabledTypes.toList());
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String? _defaultChannel() {
    for (final key in const ['ch1', 'ch2', 'ch3', 'ch4']) {
      final data = widget.channels[key];
      if (data != null && data.points.isNotEmpty) return key;
    }
    return null;
  }

  String _channelLabel(String channel) => channel.toUpperCase();

  Future<void> _runClassification({List<WaveformSignalType>? types}) async {
    final channel = _channel;
    final data = channel == null ? null : widget.channels[channel];
    if (channel == null || data == null || data.points.isEmpty) {
      setState(() {
        _error = 'No acquired waveform data is available for this channel.';
        _loading = false;
      });
      return;
    }
    if (!mounted) return;
    final request = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trace = WaveformTrace.fromPoints(data.points, channel: channel);
      final result = await widget.service.classifyAsync(
        trace,
        options: WaveformAnalysisOptions(
          referenceTypes: types ?? _enabledTypes.toList(),
        ),
        channel: channel,
      );
      if (!mounted || request != _requestId) return;
      ReferenceWaveform? reference;
      final bestCandidate = result.topCandidates.isEmpty
          ? null
          : result.topCandidates.first;
      final bestType = result.primaryType ?? bestCandidate?.type;
      final parameters =
          result.referenceParameters ?? bestCandidate?.referenceParameters;
      if (bestType != null && parameters != null) {
        reference = widget.service.generateReference(bestType, parameters);
      }
      setState(() {
        _captureTrace = trace;
        _result = result;
        _reference = reference;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _loading = false;
        _error = 'Waveform classification failed: $error';
      });
    }
  }

  Future<void> _runSelectedReference() async {
    final type = _selectedReference;
    if (type == null) return;
    await _runClassification(types: [type]);
  }

  Future<void> _editReferences() async {
    final selected = await showDialog<Set<WaveformSignalType>>(
      context: context,
      builder: (context) {
        final working = <WaveformSignalType>{..._enabledTypes};
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.panelBackground,
              title: const Text(
                'Reference signals',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final type in WaveformSignalType.values)
                        CheckboxListTile(
                          value: working.contains(type),
                          onChanged: (value) {
                            setDialogState(() {
                              if (value == true) {
                                working.add(type);
                              } else {
                                working.remove(type);
                              }
                            });
                          },
                          dense: true,
                          activeColor: Colors.lightBlueAccent,
                          checkColor: Colors.black,
                          title: Text(
                            type.label,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: working.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(working),
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    setState(() {
      _enabledTypes
        ..clear()
        ..addAll(selected);
    });
    await _runClassification(types: _enabledTypes.toList());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.channels.isEmpty) {
      return const Center(
        child: Text(
          'Acquire a waveform to run the waveform analysis.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildControls(),
        if (_loading)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_result != null) ...[
                  _buildSummaryCard(_result!),
                  const SizedBox(height: 8),
                  _buildPlotCard(_result!),
                  const SizedBox(height: 8),
                  _buildCandidatesCard(_result!),
                  const SizedBox(height: 8),
                  _buildAnomaliesCard(_result!),
                  const SizedBox(height: 8),
                  _buildExplanationCard(_result!),
                  const SizedBox(height: 8),
                  _buildFeaturesCard(_result!),
                  if (_result!.warnings.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildWarningsCard(_result!),
                  ],
                ] else if (!_loading)
                  _buildEmptyCard(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControls() {
    final channel = _channel;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF172A45),
            border: Border.all(color: AppColors.border, width: 0.8),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: channel,
              dropdownColor: const Color(0xFF172A45),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              items: [
                for (final entry in widget.channels.entries)
                  if (entry.value.points.isNotEmpty)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(_channelLabel(entry.key)),
                    ),
              ],
              onChanged: _loading
                  ? null
                  : (value) {
                      if (value == null || value == _channel) return;
                      setState(() {
                        _channel = value;
                        _result = null;
                        _reference = null;
                        _error = null;
                      });
                      _runClassification(types: _enabledTypes.toList());
                    },
            ),
          ),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
          ),
          onPressed: _loading || channel == null
              ? null
              : () => _runClassification(types: _enabledTypes.toList()),
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: const Text('Classify'),
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : _editReferences,
          icon: const Icon(Icons.tune, size: 16),
          label: Text('References (${_enabledTypes.length})'),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF172A45),
            border: Border.all(color: AppColors.border, width: 0.8),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<WaveformSignalType>(
              value: _selectedReference,
              hint: const Text(
                'Specific reference',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              dropdownColor: const Color(0xFF172A45),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              items: [
                for (final type in WaveformSignalType.values)
                  DropdownMenuItem(value: type, child: Text(type.label)),
              ],
              onChanged: _loading
                  ? null
                  : (value) => setState(() => _selectedReference = value),
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _loading || _selectedReference == null
              ? null
              : _runSelectedReference,
          icon: const Icon(Icons.compare_arrows, size: 16),
          label: const Text('Compare selected'),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(WaveformClassification result) {
    final color = _scoreColor(result.score);
    final uncertain = result.uncertain;
    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${result.score.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: color,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'similarity',
                    style: TextStyle(color: Colors.white54, fontSize: 9),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        result.primaryLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _tag(
                      result.confidence.label,
                      uncertain ? Colors.orangeAccent : color,
                    ),
                    if (result.ambiguous) ...[
                      const SizedBox(width: 6),
                      _tag('Mixed result', Colors.amberAccent),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Channel ${_channelLabel(result.channel ?? _channel ?? '')} · '
                  '${result.sampleCount} samples · '
                  '${_formatSeconds(result.durationSeconds)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                if (result.secondaryCharacteristics.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final characteristic
                          in result.secondaryCharacteristics)
                        _tag(characteristic, Colors.lightBlueAccent),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                const Text(
                  'Similarity describes the match with the mathematical '
                  'reference; it is not a calibrated probability.',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlotCard(WaveformClassification result) {
    final trace = _captureTrace;
    final reference = _reference;
    if (trace == null || trace.isEmpty) {
      return _card(
        child: const SizedBox(
          height: 60,
          child: Center(
            child: Text(
              'No captured waveform available.',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ),
      );
    }
    return _card(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Captured waveform and reference',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const Spacer(),
              _legendDot(
                waveformChannelColor(_channel ?? 'ch1'),
                _channelLabel(_channel ?? 'ch1'),
              ),
              const SizedBox(width: 10),
              _legendDot(
                Colors.orangeAccent,
                reference?.type.label ?? 'Reference',
              ),
              const SizedBox(width: 10),
              _legendDot(Colors.greenAccent, 'Difference'),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 300,
            child: CustomPaint(
              painter: _WaveformAnalysisPlotPainter(
                capture: trace,
                reference: reference?.trace,
                lagSeconds: result.topCandidates.isEmpty
                    ? null
                    : result.topCandidates.first.breakdown.lagSeconds,
                captureColor: waveformChannelColor(_channel ?? 'ch1'),
                referenceLabel: reference?.type.label ?? 'Reference',
                channelLabel: _channelLabel(_channel ?? 'ch1'),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCandidatesCard(WaveformClassification result) {
    final candidates = _showAllCandidates
        ? result.allCandidates
        : result.topCandidates;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Reference matches',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    setState(() => _showAllCandidates = !_showAllCandidates),
                child: Text(
                  _showAllCandidates
                      ? 'Show top 3'
                      : 'Show all (${result.allCandidates.length})',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          if (candidates.isEmpty)
            const Text(
              'No reference candidates were evaluated.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          for (var index = 0; index < candidates.length; index++)
            _buildCandidateRow(index, candidates[index]),
        ],
      ),
    );
  }

  Widget _buildCandidateRow(int index, ClassificationCandidate candidate) {
    final color = _scoreColor(candidate.score);
    final breakdown = candidate.breakdown;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                child: Text(
                  '${index + 1}.',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
              Expanded(
                child: Text(
                  candidate.type.label,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              Text(
                '${candidate.score.toStringAsFixed(1)} %',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              _tag(candidate.confidence.label, color),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: candidate.score / 100,
              minHeight: 4,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'shape ${breakdown.shapeSimilarity.toStringAsFixed(0)} % · '
            'features ${breakdown.featureSimilarity.toStringAsFixed(0)} % · '
            'frequency ${breakdown.frequencySimilarity.toStringAsFixed(0)} % · '
            'DTW ${breakdown.dtwSimilarity.toStringAsFixed(0)} % · '
            'rules ${breakdown.ruleSimilarity.toStringAsFixed(0)} %',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildAnomaliesCard(WaveformClassification result) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                'Detected anomalies',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const Spacer(),
              Text(
                '${result.anomalies.length}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (result.anomalies.isEmpty)
            const Text(
              'No significant deviations from the reference were detected.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          for (final anomaly in result.anomalies)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _severityDot(anomaly.severity),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              anomaly.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 6),
                            _tag(
                              anomaly.severity.label,
                              _severityColor(anomaly.severity),
                            ),
                            if (anomaly.startSeconds != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                _anomalyInterval(anomaly),
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (anomaly.measuredValue != null)
                          Text(
                            anomaly.measuredValue!,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                            ),
                          ),
                        Text(
                          anomaly.description,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExplanationCard(WaveformClassification result) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Analysis explanation',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 4),
          SelectableText(
            result.explanation,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesCard(WaveformClassification result) {
    final features = result.features;
    final entries = <(String, String)>[
      ('Fundamental', _formatHz(features.frequencyHz)),
      ('Vpp', _formatVolts(features.vPp)),
      ('RMS', _formatVolts(features.vRms)),
      ('Mean', _formatVolts(features.vMean)),
      ('Duty cycle', _formatPercent(features.dutyPercent)),
      ('Rise time', _formatSeconds(features.riseTimeSeconds)),
      ('Fall time', _formatSeconds(features.fallTimeSeconds)),
      ('Crest factor', _formatNumber(features.crestFactor, 2)),
      ('THD', _formatPercent(features.thdPercent)),
      ('SNR', _formatDb(features.snrDb)),
      ('Sine correlation', _formatFraction(features.sineCorrelation)),
      ('Sine phase', _formatRadians(features.sinePhaseRadians)),
      ('Square correlation', _formatFraction(features.squareCorrelation)),
      ('Triangle correlation', _formatFraction(features.triangleCorrelation)),
      ('Sawtooth correlation', _formatFraction(features.sawtoothCorrelation)),
      ('Two-level ratio', _formatFraction(features.twoLevelRatio)),
      ('Plateau stability', _formatFraction(features.plateauStability)),
      ('Ramp linearity', _formatFraction(features.rampLinearity)),
      ('Exponential R²', _formatNumber(features.exponentialFitR2, 3)),
      ('Exponential tau', _formatSeconds(features.exponentialTauSeconds)),
      ('Envelope decay', _formatRate(features.envelopeDecayRate)),
      ('Envelope R²', _formatNumber(features.envelopeDecayR2, 3)),
      ('Log decrement', _formatNumber(features.logarithmicDecrement, 3)),
      (
        'Clipping',
        _formatPercent(
          features.clippingRatio == null ? null : features.clippingRatio! * 100,
        ),
      ),
      (
        'Duty variation',
        _formatPercent(
          features.dutyCycleVariation == null
              ? null
              : features.dutyCycleVariation! * 100,
        ),
      ),
      (
        'Period variation',
        _formatPercent(
          features.periodVariation == null
              ? null
              : features.periodVariation! * 100,
        ),
      ),
      ('Periods', '${features.periodCount}'),
      ('Samples', '${features.sampleCount}'),
      ('Duration', _formatSeconds(features.durationSeconds)),
    ];
    return _card(
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          title: const Text(
            'Extracted features',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          iconColor: Colors.white54,
          collapsedIconColor: Colors.white54,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in entries)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF112240),
                      border: Border.all(color: Colors.white12, width: 0.6),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.$1,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                          ),
                        ),
                        Text(
                          entry.$2,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningsCard(WaveformClassification result) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Warnings',
            style: TextStyle(color: Colors.amberAccent, fontSize: 12),
          ),
          const SizedBox(height: 4),
          for (final warning in result.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $warning',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard() {
    return _card(
      child: const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'Run the classification to compare the captured waveform with the '
            'ten reference signal types.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panelBackground,
        border: Border.all(color: AppColors.border, width: 0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 9)),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
      ],
    );
  }

  Widget _severityDot(AnomalySeverity severity) {
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: _severityColor(severity),
        shape: BoxShape.circle,
      ),
    );
  }

  Color _severityColor(AnomalySeverity severity) => switch (severity) {
    AnomalySeverity.info => Colors.lightBlueAccent,
    AnomalySeverity.minor => Colors.amberAccent,
    AnomalySeverity.moderate => Colors.orangeAccent,
    AnomalySeverity.severe => Colors.redAccent,
  };

  Color _scoreColor(double score) {
    if (score >= 90) return Colors.greenAccent;
    if (score >= 75) return Colors.lightGreenAccent;
    if (score >= 60) return Colors.amberAccent;
    if (score >= 40) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  String _anomalyInterval(WaveformAnomaly anomaly) {
    final start = anomaly.startSeconds;
    if (start == null) return '';
    final end = anomaly.endSeconds;
    if (end == null) return _formatSeconds(start);
    return '${_formatSeconds(start)} – ${_formatSeconds(end)}';
  }
}

class _WaveformAnalysisPlotPainter extends CustomPainter {
  _WaveformAnalysisPlotPainter({
    required this.capture,
    required this.reference,
    required this.lagSeconds,
    required this.captureColor,
    required this.referenceLabel,
    required this.channelLabel,
  });

  final WaveformTrace capture;
  final WaveformTrace? reference;
  final double? lagSeconds;
  final Color captureColor;
  final String referenceLabel;
  final String channelLabel;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = const Color(0xFF0D1B2E);
    canvas.drawRect(Offset.zero & size, background);

    const leftPadding = 54.0;
    const rightPadding = 8.0;
    const topPadding = 8.0;
    const bottomPadding = 18.0;
    const gap = 16.0;
    final plotWidth = math.max(10.0, size.width - leftPadding - rightPadding);
    final availableHeight = math.max(
      20.0,
      size.height - topPadding - bottomPadding - gap,
    );
    final upperHeight = availableHeight * 0.64;
    final lowerHeight = availableHeight - upperHeight;
    final upperRect = Rect.fromLTWH(
      leftPadding,
      topPadding,
      plotWidth,
      upperHeight,
    );
    final lowerRect = Rect.fromLTWH(
      leftPadding,
      topPadding + upperHeight + gap,
      plotWidth,
      lowerHeight,
    );

    final alignedReference = _alignedReferenceValues();
    final difference = <double?>[
      for (var i = 0; i < capture.length; i++)
        alignedReference[i] == null
            ? null
            : capture.volts[i] - alignedReference[i]!,
    ];

    final values = <double>[...capture.volts];
    if (alignedReference.any((value) => value != null)) {
      values.addAll(alignedReference.whereType<double>());
    }
    var minValue = values.reduce(math.min);
    var maxValue = values.reduce(math.max);
    if (maxValue - minValue < 1e-12) {
      minValue -= 1;
      maxValue += 1;
    }
    final valuePadding = (maxValue - minValue) * 0.08;
    minValue -= valuePadding;
    maxValue += valuePadding;

    final differenceValues = difference.whereType<double>().toList();
    var differenceLimit = 1e-12;
    for (final value in differenceValues) {
      if (value.abs() > differenceLimit) differenceLimit = value.abs();
    }
    differenceLimit *= 1.15;

    _drawGrid(canvas, upperRect, lowerRect);
    _drawUpperAxes(canvas, upperRect, minValue, maxValue);
    _drawLowerAxes(canvas, lowerRect, differenceLimit);

    final capturePath = _buildPath(
      upperRect,
      (i) => capture.volts[i],
      minValue,
      maxValue,
    );
    canvas.drawPath(
      capturePath,
      Paint()
        ..color = captureColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..isAntiAlias = true,
    );

    if (alignedReference.any((value) => value != null)) {
      final referencePath = _buildNullablePath(
        upperRect,
        alignedReference,
        minValue,
        maxValue,
      );
      canvas.drawPath(
        referencePath,
        Paint()
          ..color = Colors.orangeAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..isAntiAlias = true,
      );
      final differencePath = _buildNullablePath(
        lowerRect,
        difference,
        -differenceLimit,
        differenceLimit,
      );
      canvas.drawPath(
        differencePath,
        Paint()
          ..color = Colors.greenAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..isAntiAlias = true,
      );
    }

    _drawText(
      canvas,
      '$channelLabel vs $referenceLabel',
      Offset(leftPadding + 4, topPadding + 2),
      color: Colors.white54,
      fontSize: 10,
    );
    _drawText(
      canvas,
      'difference (V)',
      Offset(leftPadding + 4, lowerRect.top + 2),
      color: Colors.white38,
      fontSize: 9,
    );
    final timeStart = capture.times.first;
    final timeEnd = capture.times.last;
    _drawText(
      canvas,
      _formatTimeAxis(timeStart),
      Offset(leftPadding, size.height - 14),
      color: Colors.white38,
      fontSize: 9,
    );
    final endText = _formatTimeAxis(timeEnd);
    final textPainter = _textPainter(endText, Colors.white38, 9);
    textPainter.paint(
      canvas,
      Offset(size.width - rightPadding - textPainter.width, size.height - 14),
    );
  }

  List<double?> _alignedReferenceValues() {
    final result = List<double?>.filled(capture.length, null);
    final source = reference;
    if (source == null || source.isEmpty) return result;
    final trace = source.length == capture.length
        ? source
        : resampleTrace(source, capture.length);
    final duration = capture.durationSeconds;
    final lagSamples = duration > 0 && lagSeconds != null
        ? (lagSeconds! / duration * capture.length).round()
        : 0;
    for (var i = 0; i < capture.length; i++) {
      final index = i + lagSamples;
      if (index >= 0 && index < trace.length) {
        final value = trace.volts[index];
        if (value.isFinite) result[i] = value;
      }
    }
    return result;
  }

  Path _buildPath(
    Rect rect,
    double Function(int) valueAt,
    double minValue,
    double maxValue,
  ) {
    final path = Path();
    for (var i = 0; i < capture.length; i++) {
      final x = rect.left + i / math.max(1, capture.length - 1) * rect.width;
      final y = _mapY(valueAt(i), minValue, maxValue, rect);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  Path _buildNullablePath(
    Rect rect,
    List<double?> values,
    double minValue,
    double maxValue,
  ) {
    final path = Path();
    var started = false;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null) {
        started = false;
        continue;
      }
      final x = rect.left + i / math.max(1, values.length - 1) * rect.width;
      final y = _mapY(value, minValue, maxValue, rect);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  double _mapY(double value, double minValue, double maxValue, Rect rect) {
    final span = maxValue - minValue;
    if (span.abs() < 1e-15) return rect.center.dy;
    final fraction = (value - minValue) / span;
    return rect.bottom - fraction * rect.height;
  }

  void _drawGrid(Canvas canvas, Rect upper, Rect lower) {
    final paint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 0.6;
    for (var i = 0; i <= 4; i++) {
      final x = upper.left + upper.width * i / 4;
      canvas.drawLine(Offset(x, upper.top), Offset(x, lower.bottom), paint);
    }
    for (var i = 0; i <= 4; i++) {
      final y = upper.top + upper.height * i / 4;
      canvas.drawLine(Offset(upper.left, y), Offset(upper.right, y), paint);
    }
    for (var i = 0; i <= 2; i++) {
      final y = lower.top + lower.height * i / 2;
      canvas.drawLine(Offset(lower.left, y), Offset(lower.right, y), paint);
    }
    final border = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRect(upper, border);
    canvas.drawRect(lower, border);
  }

  void _drawUpperAxes(
    Canvas canvas,
    Rect rect,
    double minValue,
    double maxValue,
  ) {
    _drawText(
      canvas,
      _formatVoltsAxis(maxValue),
      Offset(2, rect.top - 1),
      color: Colors.white38,
      fontSize: 9,
    );
    _drawText(
      canvas,
      _formatVoltsAxis(minValue),
      Offset(2, rect.bottom - 11),
      color: Colors.white38,
      fontSize: 9,
    );
    _drawText(
      canvas,
      _formatVoltsAxis((minValue + maxValue) / 2),
      Offset(2, rect.center.dy - 5),
      color: Colors.white24,
      fontSize: 9,
    );
  }

  void _drawLowerAxes(Canvas canvas, Rect rect, double limit) {
    _drawText(
      canvas,
      _formatVoltsAxis(limit),
      Offset(2, rect.top - 1),
      color: Colors.white38,
      fontSize: 9,
    );
    _drawText(
      canvas,
      _formatVoltsAxis(-limit),
      Offset(2, rect.bottom - 11),
      color: Colors.white38,
      fontSize: 9,
    );
    final zero = Paint()
      ..color = Colors.white24
      ..strokeWidth = 0.8;
    canvas.drawLine(
      Offset(rect.left, rect.center.dy),
      Offset(rect.right, rect.center.dy),
      zero,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    required Color color,
    required double fontSize,
  }) {
    _textPainter(text, color, fontSize).paint(canvas, offset);
  }

  TextPainter _textPainter(String text, Color color, double fontSize) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
  }

  @override
  bool shouldRepaint(_WaveformAnalysisPlotPainter oldDelegate) {
    return oldDelegate.capture != capture ||
        oldDelegate.reference != reference ||
        oldDelegate.lagSeconds != lagSeconds ||
        oldDelegate.captureColor != captureColor;
  }
}

String _formatNumber(double? value, int digits) {
  if (value == null || !value.isFinite) return '—';
  return value.toStringAsFixed(digits);
}

String _formatFraction(double? value) {
  if (value == null || !value.isFinite) return '—';
  return value.toStringAsFixed(3);
}

String _formatRadians(double? value) {
  if (value == null || !value.isFinite) return '—';
  return '${value.toStringAsFixed(3)} rad';
}

String _formatPercent(double? value) {
  if (value == null || !value.isFinite) return '—';
  return '${value.toStringAsFixed(2)} %';
}

String _formatDb(double? value) {
  if (value == null || !value.isFinite) return '—';
  return '${value.toStringAsFixed(1)} dB';
}

String _formatRate(double? value) {
  if (value == null || !value.isFinite) return '—';
  return '${value.toStringAsFixed(1)} 1/s';
}

String _formatHz(double? value) {
  if (value == null || !value.isFinite) return '—';
  return formatMeasurementValue(value, 'Hz');
}

String _formatVolts(double? value) {
  if (value == null || !value.isFinite) return '—';
  return formatMeasurementValue(value, 'V');
}

String _formatSeconds(double? value) {
  if (value == null || !value.isFinite) return '—';
  return formatMeasurementValue(value, 's');
}

String _formatVoltsAxis(double value) {
  if (!value.isFinite) return '';
  final magnitude = value.abs();
  if (magnitude >= 1) return '${value.toStringAsFixed(2)}V';
  if (magnitude >= 1e-3) return '${(value * 1e3).toStringAsFixed(1)}mV';
  return '${(value * 1e6).toStringAsFixed(0)}uV';
}

String _formatTimeAxis(double value) {
  if (!value.isFinite) return '';
  final magnitude = value.abs();
  if (magnitude >= 1) return '${value.toStringAsFixed(2)}s';
  if (magnitude >= 1e-3) return '${(value * 1e3).toStringAsFixed(2)}ms';
  if (magnitude >= 1e-6) return '${(value * 1e6).toStringAsFixed(1)}us';
  return '${(value * 1e9).toStringAsFixed(1)}ns';
}
