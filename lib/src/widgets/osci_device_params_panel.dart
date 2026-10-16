import 'package:flutter/material.dart';

import '../waveform/waveform_models.dart';

/// A panel that displays oscilloscope device parameters (timebase, V/div, etc.).
class DeviceParametersPanel extends StatefulWidget {
  final DeviceParams params;
  final bool ch1Enabled;
  final bool ch2Enabled;
  final bool isOnline;
  final bool cursorsXEnabled;
  final bool cursorsYEnabled;
  final double zoomFactor;
  final ValueChanged<String>? onChannelToggle;
  final ValueChanged<bool>? onCursorXToggled;
  final ValueChanged<bool>? onCursorYToggled;
  final ValueChanged<double>? onZoomFactorChanged;
  final bool refVisible;
  final String? refLabel; // "REF" when a reference is loaded
  final VoidCallback? onLoadReference;
  final ValueChanged<bool>? onRefToggled;
  final bool refMoving; // "Move Reference" mode armed
  final ValueChanged<bool>? onRefMovingToggled;
  final ReferenceOffset refOffset; // manual alignment offset of the reference
  final VoidCallback? onRefReset;

  const DeviceParametersPanel({
    super.key,
    required this.params,
    required this.ch1Enabled,
    required this.ch2Enabled,
    required this.isOnline,
    this.cursorsXEnabled = false,
    this.cursorsYEnabled = false,
    this.zoomFactor = 1.0,
    this.onChannelToggle,
    this.onCursorXToggled,
    this.onCursorYToggled,
    this.onZoomFactorChanged,
    this.refVisible = false,
    this.refLabel,
    this.onLoadReference,
    this.onRefToggled,
    this.refMoving = false,
    this.onRefMovingToggled,
    this.refOffset = const ReferenceOffset(),
    this.onRefReset,
  });

  @override
  State<DeviceParametersPanel> createState() => _DeviceParametersPanelState();
}

class _DeviceParametersPanelState extends State<DeviceParametersPanel> {
  /// Tracks the slider position during dragging for smooth visual feedback
  /// without triggering waveform repaint on every tick.
  late double _sliderZoomFactor;

  @override
  void initState() {
    super.initState();
    _sliderZoomFactor = widget.zoomFactor;
  }

  @override
  void didUpdateWidget(DeviceParametersPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync local slider value when parent commits a new zoom factor
    // (e.g. after the user releases the slider or zoom is reset externally)
    if (widget.zoomFactor != oldWidget.zoomFactor) {
      _sliderZoomFactor = widget.zoomFactor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ch1Enabled = widget.ch1Enabled;
    final ch2Enabled = widget.ch2Enabled;
    final refLabel = widget.refLabel;
    final refVisible = widget.refVisible;
    final onRefToggled = widget.onRefToggled;
    final params = widget.params;
    final cursorsXEnabled = widget.cursorsXEnabled;
    final cursorsYEnabled = widget.cursorsYEnabled;
    final onCursorXToggled = widget.onCursorXToggled;
    final onCursorYToggled = widget.onCursorYToggled;
    return Container(
      width: 300,
      margin: const EdgeInsets.only(top: 24, bottom: 24, right: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0A192F),
        border: Border.all(color: const Color(0xFF475569)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF172A45),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: const Text(
              "Device Parameters",
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Channel Status Section (channels are always enabled)
                  _buildBorderedSection(
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildChannelStatus(
                          label: "CH1",
                          enabled: ch1Enabled,
                          activeColor: Colors.yellow,
                        ),
                        const SizedBox(width: 4),
                        _buildChannelStatus(
                          label: "CH2",
                          enabled: ch2Enabled,
                          activeColor: const Color(0xFFFF20FF),
                        ),
                        if (refLabel != null) ...[
                          const SizedBox(width: 4),
                          _buildChannelStatus(
                            label: refLabel,
                            enabled: refVisible,
                            activeColor: Colors.white54,
                            onTap: onRefToggled != null
                                ? () => onRefToggled(!refVisible)
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _paramRow("Timebase", _fmtSi(params.timebase, "s/div")),
                  _paramRow("Trig. Delay", _fmtSi(params.trdl, "s")),
                  _paramRow("Sample Rate", _fmtSi(params.sampleRate, "Sa/s")),
                  if (params.vdivCh1 != null) ...[
                    const Divider(color: Colors.yellow, height: 24),
                    const Text(
                      "CH1",
                      style: TextStyle(
                        color: Colors.yellow,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _paramRow("V/div", _fmtSi(params.vdivCh1!, "V")),
                    _paramRow("Offset", _fmtSi(params.voffsetCh1!, "V")),
                  ],
                  if (params.vdivCh2 != null) ...[
                    const Divider(color: Color(0xFFFF20FF), height: 24),
                    const Text(
                      "CH2",
                      style: TextStyle(
                        color: Color(0xFFFF20FF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _paramRow("V/div", _fmtSi(params.vdivCh2!, "V")),
                    _paramRow("Offset", _fmtSi(params.voffsetCh2!, "V")),
                  ],
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFF475569), height: 24),
                  const Text(
                    "Cursors",
                    style: TextStyle(
                      color: Colors.blueAccent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildToggleRow(
                    "Cursors X",
                    cursorsXEnabled,
                    Colors.cyanAccent,
                    onCursorXToggled,
                  ),
                  const SizedBox(height: 8),
                  _buildToggleRow(
                    "Cursors Y",
                    cursorsYEnabled,
                    Colors.orangeAccent,
                    onCursorYToggled,
                  ),
                  const SizedBox(height: 12),
                  _buildZoomSliderSection(),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFF475569), height: 24),
                  _buildReferenceSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A labelled switch row, used for the cursor and reference toggles.
  Widget _buildToggleRow(
    String label,
    bool value,
    Color activeColor,
    ValueChanged<bool>? onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF172A45).withValues(alpha: 0.3),
        border: Border.all(color: const Color(0xFF475569)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                value ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16,
                color: value ? activeColor : Colors.white38,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: value ? activeColor : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: activeColor,
            activeTrackColor: activeColor.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomSliderSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF172A45).withValues(alpha: 0.3),
        border: Border.all(color: const Color(0xFF475569)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Zoom",
                style: TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "${_sliderZoomFactor.toStringAsFixed(1)}x",
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: _sliderZoomFactor,
            min: 1.0,
            max: 4.0,
            divisions: 12,
            activeColor: Colors.greenAccent,
            inactiveColor: Colors.white24,
            onChanged: (v) {
              setState(() => _sliderZoomFactor = v);
            },
            onChangeEnd: (v) {
              widget.onZoomFactorChanged?.call(v);
            },
          ),
        ],
      ),
    );
  }

  /// The reference waveform section: loading a CSV, and — once one is loaded
  /// — manually aligning it against the live trace.
  ///
  /// The alignment offset is shown in divisions of the graticule, the unit
  /// the user counts on the screen.
  Widget _buildReferenceSection() {
    final refLoaded = widget.refLabel != null;
    final refVisible = widget.refVisible;
    final refOffset = widget.refOffset;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reference',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (refLoaded) ...[
          // Aligning only makes sense while the reference is displayed, so the
          // switch stays disabled while the REF chip is switched off.
          _buildToggleRow(
            'Move Reference',
            widget.refMoving,
            Colors.lightBlueAccent,
            refVisible ? widget.onRefMovingToggled : null,
          ),
          const SizedBox(height: 4),
          if (widget.refMoving) ...[
            const SizedBox(height: 4),
            const Text(
              'Drag the reference in the plot. Hold Shift to snap to the '
              'grid.',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          _buildActionRow(
            icon: Icons.restart_alt,
            label: 'Reset Offset',
            onTap: refOffset.isZero ? null : widget.onRefReset,
          ),
          const SizedBox(height: 8),
        ],
        _buildActionRow(
          icon: Icons.file_open,
          label: 'Load Reference',
          onTap: widget.onLoadReference,
        ),
      ],
    );
  }

  /// A full-width row that acts as a button, used for the panel's actions.
  /// A null [onTap] greys the row out instead of hiding it.
  Widget _buildActionRow({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF172A45).withValues(alpha: 0.3),
        border: Border.all(color: const Color(0xFF475569)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: Colors.white.withAlpha(enabled ? 180 : 60),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? Colors.white70 : Colors.white38,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBorderedSection(Widget child) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF172A45).withValues(alpha: 0.3),
        border: Border.all(color: const Color(0xFF475569)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  Widget _buildChannelStatus({
    required String label,
    required bool enabled,
    required Color activeColor,
    VoidCallback? onTap,
  }) {
    return _ChannelStatusButton(
      label: label,
      enabled: enabled,
      activeColor: activeColor,
      onTap:
          onTap ??
          (widget.onChannelToggle != null
              ? () => widget.onChannelToggle!(label)
              : null),
    );
  }

  Widget _paramRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Format a value with SI prefix
  String _fmtSi(double v, String unit) {
    final abs = v.abs();
    double scaled;
    String prefix;
    if (abs == 0) return '0 $unit';
    if (abs >= 1e9) {
      scaled = v / 1e9;
      prefix = 'G';
    } else if (abs >= 1e6) {
      scaled = v / 1e6;
      prefix = 'M';
    } else if (abs >= 1e3) {
      scaled = v / 1e3;
      prefix = 'k';
    } else if (abs >= 1) {
      scaled = v;
      prefix = '';
    } else if (abs >= 1e-3) {
      scaled = v * 1e3;
      prefix = 'm';
    } else if (abs >= 1e-6) {
      scaled = v * 1e6;
      prefix = 'µ';
    } else {
      scaled = v * 1e9;
      prefix = 'n';
    }

    // Remove trailing zeros: 100.000 → 100, 1.500 → 1.5
    String s = scaled.toStringAsFixed(3);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return '$s $prefix$unit';
  }
}

/// A stateful widget that provides hover effect for channel status buttons.
class _ChannelStatusButton extends StatefulWidget {
  final String label;
  final bool enabled;
  final Color activeColor;
  final VoidCallback? onTap;

  const _ChannelStatusButton({
    required this.label,
    required this.enabled,
    required this.activeColor,
    this.onTap,
  });

  @override
  State<_ChannelStatusButton> createState() => _ChannelStatusButtonState();
}

class _ChannelStatusButtonState extends State<_ChannelStatusButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          decoration: BoxDecoration(
            color: _isHovered && widget.onTap != null
                ? widget.activeColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          foregroundDecoration: _isHovered && widget.onTap != null
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget.activeColor.withValues(alpha: 0.4),
                  ),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                size: 18,
                color: widget.enabled ? widget.activeColor : Colors.transparent,
              ),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.activeColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
