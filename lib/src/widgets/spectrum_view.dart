import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../spectrum/spectrum_models.dart';
import '../spectrum/spectrum_viewport.dart';
import '../spectrum/windows.dart';
import '../waveform/waveform_models.dart' show waveformChannelColor;
import 'spectrum_painter.dart';

const String _allChannelsValue = 'all';

/// Interactive spectrum tab: analysis controls, overlaid traces, metric
/// cards and the automatic peak table of the selected channel.
class SpectrumView extends StatefulWidget {
  const SpectrumView({
    super.key,
    required this.result,
    required this.settings,
    required this.selectedChannel,
    required this.showAllChannels,
    required this.logFrequency,
    required this.loading,
    required this.onChannelSelectionChanged,
    required this.onSettingsChanged,
    required this.onLogFrequencyChanged,
    required this.onExportCsv,
    this.plotKey,
  });

  final SpectrumResult? result;
  final SpectrumSettings settings;

  /// Channel whose metric cards, peak markers and peak table are shown.
  final String selectedChannel;

  /// Overlays every acquired channel; when false only [selectedChannel] is
  /// drawn.
  final bool showAllChannels;

  final bool logFrequency;
  final bool loading;

  /// Reports the channel selected for display, or `null` for the overlay of
  /// all acquired channels.
  final ValueChanged<String?> onChannelSelectionChanged;
  final ValueChanged<SpectrumSettings> onSettingsChanged;
  final ValueChanged<bool> onLogFrequencyChanged;

  /// Exports the current spectrum as a CSV file.
  final VoidCallback onExportCsv;

  final GlobalKey? plotKey;

  @override
  State<SpectrumView> createState() => _SpectrumViewState();
}

class _SpectrumViewState extends State<SpectrumView> {
  SpectrumViewport _viewport = const SpectrumViewport();
  bool _dragging = false;

  SpectrumResult? get result => widget.result;
  SpectrumSettings get settings => widget.settings;
  String get selectedChannel => widget.selectedChannel;
  bool get showAllChannels => widget.showAllChannels;
  bool get logFrequency => widget.logFrequency;
  bool get loading => widget.loading;
  GlobalKey? get plotKey => widget.plotKey;
  ValueChanged<String?> get onChannelSelectionChanged =>
      widget.onChannelSelectionChanged;
  ValueChanged<SpectrumSettings> get onSettingsChanged =>
      widget.onSettingsChanged;
  ValueChanged<bool> get onLogFrequencyChanged => widget.onLogFrequencyChanged;
  VoidCallback get onExportCsv => widget.onExportCsv;

  @override
  void didUpdateWidget(SpectrumView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.result, widget.result) ||
        oldWidget.logFrequency != widget.logFrequency) {
      _viewport = const SpectrumViewport();
      _dragging = false;
    }
  }

  void _zoomBy(double factor) {
    final next = _viewport.zoomBy(factor);
    if (next == _viewport) return;
    setState(() => _viewport = next);
  }

  void _resetZoom() {
    if (!_viewport.isZoomed) return;
    setState(() => _viewport = _viewport.reset());
  }

  void _panBy(double visibleFraction) {
    final next = _viewport.panBy(visibleFraction);
    if (next == _viewport) return;
    setState(() => _viewport = next);
  }

  void _handlePointerSignal(
    PointerSignalEvent event,
    double plotWidth,
    SpectrumAxisRange axis,
  ) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy == 0 ||
        !axis.isValid ||
        plotWidth <= 1) {
      return;
    }
    final localX = event.localPosition.dx;
    final fraction = ((localX - spectrumPlotLeftPadding) / plotWidth)
        .clamp(0.0, 1.0)
        .toDouble();
    final factor = math
        .exp((-event.scrollDelta.dy).clamp(-200.0, 200.0) * 0.002)
        .clamp(0.5, 2.0)
        .toDouble();
    final next = _viewport.zoomAt(
      newZoom: _viewport.zoom * factor,
      fraction: fraction,
      fullMin: axis.min,
      fullMax: axis.max,
      log: axis.log,
    );
    if (next == _viewport) return;
    setState(() => _viewport = next);
  }

  @override
  Widget build(BuildContext context) {
    final traces = result?.traces ?? const <SpectrumTrace>[];
    final detail =
        result?.traceFor(selectedChannel) ??
        (traces.isNotEmpty ? traces.first : null);
    final detailLabel = detail == null
        ? ''
        : showAllChannels
        ? 'All channels (details ${detail.channel.toUpperCase()})'
        : detail.channel.toUpperCase();
    final chartTraces = showAllChannels ? traces : <SpectrumTrace>[?detail];
    final axis = spectrumAxisRange(chartTraces, logFrequency);
    final (visibleMin, visibleMax) = _viewport.visibleRange(
      fullMin: axis.min,
      fullMax: axis.max,
      log: axis.log,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildControls(traces, detail, axis),
        if (settings.window == SpectrumWindow.rectangular) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.warning_amber,
                size: 13,
                color: Colors.amberAccent,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Rectangular window: only use for coherently sampled '
                  'signals. Leakage can hide small peaks.',
                  style: TextStyle(
                    color: Colors.amberAccent.withValues(alpha: 0.85),
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Expanded(child: _buildChart(detail, axis)),
        if (axis.isValid) ...[
          const SizedBox(height: 4),
          _buildViewportStatus(axis, visibleMin, visibleMax),
        ],
        if (detail != null) ...[
          const SizedBox(height: 8),
          Text(
            '$detailLabel  |  FFT ${detail.fftSize}  |  '
            'fs ${formatSpectrumFrequency(detail.sampleRate)}  |  '
            'df ${formatSpectrumFrequency(detail.resolutionHz)}  |  '
            'Full scale ${detail.fullScaleVolts.toStringAsFixed(3)} V  |  '
            'Window ${_windowLabel(settings.window)}',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildMetrics(detail)),
              const SizedBox(width: 8),
              Expanded(child: _buildPeaks(detail)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildControls(
    List<SpectrumTrace> traces,
    SpectrumTrace? detail,
    SpectrumAxisRange axis,
  ) {
    final channels = [for (final trace in traces) trace.channel];
    final selected = detail?.channel;
    final fftOptions = _fftOptions();

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        if (selected != null)
          _control(
            'Channel',
            _dropdown<String>(
              value: showAllChannels ? _allChannelsValue : selected,
              items: [_allChannelsValue, ...channels],
              label: _channelLabel,
              onChanged: (value) {
                if (value == null) return;
                onChannelSelectionChanged(
                  value == _allChannelsValue ? null : value,
                );
              },
            ),
          ),
        _control(
          'Window',
          _dropdown<SpectrumWindow>(
            value: settings.window,
            items: SpectrumWindow.values,
            label: _windowLabel,
            onChanged: (value) {
              if (value != null) {
                onSettingsChanged(settings.copyWith(window: value));
              }
            },
          ),
        ),
        _control(
          'FFT size',
          _dropdown<int>(
            value: fftOptions.contains(settings.fftSize) ? settings.fftSize : 0,
            items: fftOptions,
            label: _fftLabel,
            onChanged: (value) {
              if (value != null) {
                onSettingsChanged(settings.copyWith(fftSize: value));
              }
            },
          ),
        ),
        _control(
          'Unit',
          _dropdown<SpectrumUnit>(
            value: settings.unit,
            items: SpectrumUnit.values,
            label: spectrumUnitLabel,
            onChanged: (value) {
              if (value != null) {
                onSettingsChanged(settings.copyWith(unit: value));
              }
            },
          ),
        ),
        _control(
          'Peak markers',
          _dropdown<int>(
            value: settings.peakCount,
            items: const [3, 5, 10],
            label: (value) => '$value',
            onChanged: (value) {
              if (value != null) {
                onSettingsChanged(settings.copyWith(peakCount: value));
              }
            },
          ),
        ),
        _control(
          'Log frequency',
          SizedBox(
            height: 30,
            child: Switch(
              value: logFrequency,
              onChanged: onLogFrequencyChanged,
            ),
          ),
        ),
        _control('Zoom', _buildZoomControl(axis)),
        _control(
          'Export',
          SizedBox(
            height: 30,
            child: OutlinedButton.icon(
              onPressed: traces.isEmpty ? null : onExportCsv,
              icon: const Icon(Icons.file_download_outlined, size: 15),
              label: const Text('CSV', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _control(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) label,
    required ValueChanged<T?> onChanged,
  }) {
    final values = items.contains(value) ? items : [value, ...items];
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF172A45),
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          dropdownColor: const Color(0xFF172A45),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          iconEnabledColor: Colors.white54,
          items: [
            for (final item in values)
              DropdownMenuItem<T>(value: item, child: Text(label(item))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildZoomControl(SpectrumAxisRange axis) {
    final canZoom = axis.isValid;
    return SizedBox(
      height: 30,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _zoomButton(
            icon: Icons.remove,
            tooltip: 'Zoom out',
            onPressed: canZoom && _viewport.isZoomed
                ? () => _zoomBy(0.5)
                : null,
          ),
          SizedBox(
            width: 46,
            child: Text(
              _viewport.zoomLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _zoomButton(
            icon: Icons.add,
            tooltip: 'Zoom in',
            onPressed: canZoom && _viewport.zoom < SpectrumViewport.maxZoom
                ? () => _zoomBy(2)
                : null,
          ),
          _zoomButton(
            icon: Icons.restart_alt,
            tooltip: 'Reset zoom',
            onPressed: _viewport.isZoomed ? _resetZoom : null,
          ),
        ],
      ),
    );
  }

  Widget _zoomButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 26, height: 30),
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 16),
      color: Colors.white70,
      disabledColor: Colors.white24,
    );
  }

  Widget _buildViewportStatus(
    SpectrumAxisRange axis,
    double visibleMin,
    double visibleMax,
  ) {
    final span = visibleMax - visibleMin;
    final range =
        'View ${formatSpectrumFrequencyForSpan(visibleMin, span)}'
        ' – ${formatSpectrumFrequencyForSpan(visibleMax, span)}';
    final hint = _viewport.isZoomed
        ? '${_viewport.zoomLabel} · mouse wheel zooms · drag pans'
        : 'Mouse wheel zooms horizontally';
    return Row(
      children: [
        const Icon(Icons.zoom_in_map, size: 12, color: Colors.white38),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            range,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            hint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ),
      ],
    );
  }

  Widget _buildChart(SpectrumTrace? detail, SpectrumAxisRange axis) {
    final traces = result?.traces ?? const <SpectrumTrace>[];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panelBackground,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final plotWidth = math.max(
            1.0,
            constraints.maxWidth -
                spectrumPlotLeftPadding -
                spectrumPlotRightPadding,
          );
          return MouseRegion(
            cursor: _viewport.isZoomed
                ? (_dragging
                      ? SystemMouseCursors.grabbing
                      : SystemMouseCursors.grab)
                : SystemMouseCursors.basic,
            child: Listener(
              onPointerSignal: (event) =>
                  _handlePointerSignal(event, plotWidth, axis),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _viewport.isZoomed
                    ? (_) => setState(() => _dragging = true)
                    : null,
                onHorizontalDragUpdate: _viewport.isZoomed
                    ? (details) => _panBy(-details.delta.dx / plotWidth)
                    : null,
                onHorizontalDragEnd: _viewport.isZoomed
                    ? (_) => setState(() => _dragging = false)
                    : null,
                onHorizontalDragCancel: _viewport.isZoomed
                    ? () => setState(() => _dragging = false)
                    : null,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        key: plotKey,
                        child: CustomPaint(
                          painter: SpectrumPainter(
                            result: result,
                            detailChannel: detail?.channel ?? selectedChannel,
                            showAllChannels: showAllChannels,
                            logFrequency: logFrequency,
                            viewport: _viewport,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    if (loading)
                      const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    if (!loading && traces.isEmpty)
                      const Center(
                        child: Text(
                          'Acquire a waveform to see the spectrum.',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetrics(SpectrumTrace trace) {
    final metrics = trace.metrics;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _metricCard(
          'Fundamental',
          '${formatSpectrumFrequency(metrics.fundamentalHz)}\n'
              '${_db(metrics.fundamentalDbfs)} dBFS',
          trace.channel,
        ),
        _metricCard(
          'THD',
          '${_percent(metrics.thdPercent)}\n${_db(metrics.thdDb)} dB',
          trace.channel,
        ),
        _metricCard('THD+N', '${_db(metrics.thdPlusNDb)} dB', trace.channel),
        _metricCard('SNR', '${_db(metrics.snrDb)} dB', trace.channel),
        _metricCard('SINAD', '${_db(metrics.sinadDb)} dB', trace.channel),
        _metricCard(
          'ENOB',
          metrics.enobBits.isFinite
              ? '${metrics.enobBits.toStringAsFixed(2)} bit'
              : '-',
          trace.channel,
        ),
        _metricCard('SFDR', '${_db(metrics.sfdrDb)} dBc', trace.channel),
        _metricCard(
          'Noise floor',
          '${_db(metrics.noiseFloorDbfs)} dBFS',
          trace.channel,
        ),
      ],
    );
  }

  Widget _metricCard(String label, String value, String channel) {
    final color = waveformChannelColor(channel);
    return Container(
      width: 118,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF172A45).withValues(alpha: 0.35),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 9),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildPeaks(SpectrumTrace trace) {
    final color = waveformChannelColor(trace.channel);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF172A45).withValues(alpha: 0.35),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Peak markers - ${trace.channel.toUpperCase()}',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          if (trace.peaks.isEmpty)
            const Text(
              'No peaks above the noise threshold.',
              style: TextStyle(color: Colors.white54, fontSize: 10),
            )
          else
            Table(
              columnWidths: const {
                0: FixedColumnWidth(22),
                1: FlexColumnWidth(1.25),
                2: FlexColumnWidth(1.1),
                3: FlexColumnWidth(0.9),
                4: FlexColumnWidth(0.9),
              },
              children: [
                _tableRow(const [
                  '#',
                  'Frequency',
                  'Amplitude',
                  'dBFS',
                  'dBc',
                ], header: true),
                for (final peak in trace.peaks)
                  _tableRow([
                    '${peak.marker}',
                    formatSpectrumFrequency(peak.frequencyHz),
                    '${peak.amplitudeVpk.toStringAsFixed(4)} V',
                    _db(peak.dbfs),
                    _db(peak.relativeToFundamentalDb),
                  ]),
              ],
            ),
        ],
      ),
    );
  }

  TableRow _tableRow(List<String> cells, {bool header = false}) {
    return TableRow(
      children: [
        for (final cell in cells)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 3),
            child: Text(
              cell,
              style: TextStyle(
                color: header ? Colors.white70 : Colors.white,
                fontSize: header ? 9 : 10,
                fontWeight: header ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  List<int> _fftOptions() {
    final options = <int>{
      0,
      settings.fftSize,
      4096,
      8192,
      16384,
      65536,
      262144,
      1048576,
    };
    return options
        .where(
          (value) =>
              value == 0 ||
              value == settings.fftSize ||
              value <= settings.maxFftSize,
        )
        .toList()
      ..sort();
  }

  String _fftLabel(int value) =>
      value == 0 ? 'Auto' : '${(value / 1024).round()}k';

  String _channelLabel(String value) =>
      value == _allChannelsValue ? 'All channels' : value.toUpperCase();

  String _windowLabel(SpectrumWindow window) => switch (window) {
    SpectrumWindow.rectangular => 'Rectangular',
    SpectrumWindow.hann => 'Hann',
    SpectrumWindow.hamming => 'Hamming',
    SpectrumWindow.blackmanHarris => 'Blackman-Harris',
    SpectrumWindow.flatTop => 'Flat-top',
  };

  String _db(double value) => value.isFinite ? value.toStringAsFixed(1) : '-';

  String _percent(double value) =>
      value.isFinite ? '${value.toStringAsFixed(3)} %' : '-';
}
