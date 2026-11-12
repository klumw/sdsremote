import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/screen_settings.dart';

/// Fixed width of the floating display-adjustment panel.
const double displayAdjustPanelWidth = 340;

/// Approximate rendered height of the panel, used to keep it on screen.
const double displayAdjustPanelApproximateHeight = 260;

/// Floating panel for adjusting screenshot brightness and contrast.
///
/// Opened by right-clicking the Control Panel screenshot. Slider changes are
/// forwarded through [onChanged] for a live preview; [onSave] persists the
/// values and [onCancel] restores the settings that were active when the
/// panel was opened.
class DisplayAdjustPanel extends StatefulWidget {
  /// Position of the panel's top-left corner in the parent stack.
  final Offset offset;

  /// Values the sliders start from when the panel opens.
  final ScreenSettings settings;

  /// Called on every slider change for the live preview.
  final ValueChanged<ScreenSettings> onChanged;

  /// Called with the final values when Save is pressed.
  final ValueChanged<ScreenSettings> onSave;

  /// Called on Cancel, Escape or a click outside the panel.
  final VoidCallback onCancel;

  /// Called when the header is dragged.
  final ValueChanged<Offset> onDrag;

  const DisplayAdjustPanel({
    super.key,
    required this.offset,
    required this.settings,
    required this.onChanged,
    required this.onSave,
    required this.onCancel,
    required this.onDrag,
  });

  @override
  State<DisplayAdjustPanel> createState() => _DisplayAdjustPanelState();
}

class _DisplayAdjustPanelState extends State<DisplayAdjustPanel> {
  late double _brightness;
  late double _contrast;

  @override
  void initState() {
    super.initState();
    _brightness = widget.settings.brightness;
    _contrast = widget.settings.contrast;
  }

  ScreenSettings get _settings =>
      ScreenSettings(brightness: _brightness, contrast: _contrast);

  void _update({double? brightness, double? contrast}) {
    setState(() {
      _brightness = brightness ?? _brightness;
      _contrast = contrast ?? _contrast;
    });
    widget.onChanged(_settings);
  }

  void _reset() {
    setState(() {
      _brightness = ScreenSettings.defaults.brightness;
      _contrast = ScreenSettings.defaults.contrast;
    });
    widget.onChanged(_settings);
  }

  String _percent(double value) => '${(value * 100).round()} %';

  String _signedPercent(double value) {
    final percent = (value * 100).round();
    return percent > 0 ? '+$percent %' : '$percent %';
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.offset.dx,
      top: widget.offset.dy,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
        },
        child: Focus(
          autofocus: true,
          child: Material(
            elevation: 20,
            color: Colors.transparent,
            child: Container(
              key: const ValueKey('display-adjust-panel'),
              width: displayAdjustPanelWidth,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E).withValues(alpha: 0.97),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.cyanAccent, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header (also the drag handle)
                  GestureDetector(
                    onPanUpdate: (details) => widget.onDrag(details.delta),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: const BoxDecoration(
                        color: Color(0xFF252525),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'DISPLAY ADJUST',
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          IconButton(
                            onPressed: widget.onCancel,
                            tooltip: 'Cancel',
                            icon: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white54,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Applied to the displayed screenshot and live screen.',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                        const SizedBox(height: 12),
                        _buildSlider(
                          label: 'Brightness',
                          value: _brightness,
                          min: ScreenSettings.minBrightness,
                          max: ScreenSettings.maxBrightness,
                          valueLabel: _signedPercent(_brightness),
                          onChanged: (value) => _update(brightness: value),
                        ),
                        const SizedBox(height: 8),
                        _buildSlider(
                          label: 'Contrast',
                          value: _contrast,
                          min: ScreenSettings.minContrast,
                          max: ScreenSettings.maxContrast,
                          valueLabel: _percent(_contrast),
                          onChanged: (value) => _update(contrast: value),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: const Size(0, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _reset,
                              child: const Text(
                                'Reset',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: const Size(0, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: widget.onCancel,
                              child: const Text(
                                'Cancel',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.cyan[800],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                minimumSize: const Size(0, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () => widget.onSave(_settings),
                              child: const Text(
                                'Save',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String valueLabel,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Text(
              valueLabel,
              style: const TextStyle(
                color: Colors.cyanAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.cyanAccent,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.cyanAccent,
            overlayColor: Colors.cyanAccent.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
