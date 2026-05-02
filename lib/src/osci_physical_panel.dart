import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'osci_knob_widgets.dart';

/// A widget that renders a physical oscilloscope control panel overlay
/// on top of a screen dump image.
class PhysicalControlPanel extends StatelessWidget {
  final bool isOnline;
  final Uint8List screenDump;
  final bool ch1Enabled;
  final bool ch2Enabled;
  final ValueChanged<String> onChannelToggle;
  final ValueChanged<int>? onSoftKeyPressed;
  final VoidCallback? onMenuPressed;
  final ValueChanged<double>? onIntensityAdjustChanged;
  final VoidCallback? onIntensityAdjustTapped;
  final ValueChanged<double>? onCh1VoltageKnobChanged;
  final VoidCallback? onCh1VoltageKnobTapped;
  final ValueChanged<double>? onCh1PositionKnobChanged;
  final ValueChanged<double>? onCh2VoltageKnobChanged;
  final VoidCallback? onCh2VoltageKnobTapped;
  final ValueChanged<double>? onCh2PositionKnobChanged;
  final VoidCallback? onCh1PositionKnobTapped;
  final VoidCallback? onCh2PositionKnobTapped;
  final ValueChanged<double>? onHorizontalTimeKnobChanged;
  final VoidCallback? onHorizontalTimeKnobTapped;
  final VoidCallback? onHorizontalPositionKnobTapped;
  final ValueChanged<double>? onTriggerLevelKnobChanged;
  final VoidCallback? onTriggerLevelKnobTapped;
  final ValueChanged<String>? onMenuButtonPressed;
  final ValueChanged<String>? onVerticalButtonPressed;
  final ValueChanged<String>? onHorizontalButtonPressed;
  final ValueChanged<String>? onTriggerButtonPressed;

  const PhysicalControlPanel({
    super.key,
    required this.isOnline,
    required this.screenDump,
    required this.ch1Enabled,
    required this.ch2Enabled,
    required this.onChannelToggle,
    this.onSoftKeyPressed,
    this.onMenuPressed,
    this.onIntensityAdjustChanged,
    this.onIntensityAdjustTapped,
    this.onCh1VoltageKnobChanged,
    this.onCh1VoltageKnobTapped,
    this.onCh1PositionKnobChanged,
    this.onCh2VoltageKnobChanged,
    this.onCh2VoltageKnobTapped,
    this.onCh2PositionKnobChanged,
    this.onCh1PositionKnobTapped,
    this.onCh2PositionKnobTapped,
    this.onHorizontalTimeKnobChanged,
    this.onHorizontalTimeKnobTapped,
    this.onHorizontalPositionKnobTapped,
    this.onTriggerLevelKnobChanged,
    this.onTriggerLevelKnobTapped,
    this.onMenuButtonPressed,
    this.onVerticalButtonPressed,
    this.onHorizontalButtonPressed,
    this.onTriggerButtonPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left Side: Display Area (now contains the actual screen dump)
        Expanded(
          flex: 6,
          child: Container(
            color: const Color(0xFF0A192F),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFF475569),
                            width: 2.0,
                          ),
                        ),
                        child: Image.memory(
                          screenDump,
                          fit: BoxFit.fitWidth,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ],
                ),
                // Bottom Bar (Soft keys)
                Container(
                  height: 50, // Reduced height for tighter fit
                  color: const Color(0xFF2C3E50),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 2, // Reduced to half of original width
                              child: Container(
                                color: const Color(
                                  0xFF0A192F,
                                ), // Same as panel background
                              ),
                            ), // Half the previous width - blended with background
                            _buildSoftKey('M1', flex: 18),
                            _buildSoftKey('M2', flex: 18),
                            _buildSoftKey('M3', flex: 18),
                            _buildSoftKey('M4', flex: 18),
                            _buildSoftKey('M5', flex: 18),
                            _buildSoftKey('M6', flex: 18),
                            Expanded(
                              flex: 14,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 1.0,
                                ),
                                child: _buildRoundMenuButton(),
                              ),
                            ), // 70% of M6 width (20 flex)
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Right Side: Control Panel
        Expanded(
          flex: 4,
          child: Stack(
            children: [
              Container(
                margin: const EdgeInsets.all(4),
                child: _buildBorderedSectionWithoutTitle(
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF172A45), Color(0xFF0A192F)],
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          // Top Section: Intensity and Main Buttons
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildKnobSection(
                                'Intensity\nAdjust',
                                60,
                                onChanged: onIntensityAdjustChanged,
                                showCounter: false,
                                onTap: onIntensityAdjustTapped,
                              ),
                              const SizedBox(width: 10),
                              Expanded(flex: 4, child: _buildMenuGrid()),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 1,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 100,
                                  ),
                                  child: _buildVerticalButtonGroup([
                                    'History',
                                    'Decode',
                                    'Run/Stop',
                                    'Auto\nSetup',
                                  ]),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Control Sections Row
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Vertical Section
                                Expanded(
                                  flex: 2,
                                  child: _buildSectionWrapper(
                                    'Vertical',
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        _buildChannelColumn('CH1'),
                                        const SizedBox(width: 20),
                                        _buildChannelColumn('CH2'),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Horizontal Section
                                Expanded(
                                  flex: 1,
                                  child: _buildSectionWrapper(
                                    'Horizontal',
                                    Column(
                                      children: [
                                        const Text(
                                          's <-> ns',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        const SizedBox(height: 8),
                                        _buildKnob(
                                          70,
                                          onChanged:
                                              onHorizontalTimeKnobChanged,
                                          showCounter: false,
                                          onTap: onHorizontalTimeKnobTapped,
                                        ),
                                        const SizedBox(height: 25),
                                        _buildOscButton(
                                          'Roll',
                                          onTap:
                                              onHorizontalButtonPressed != null
                                                  ? () =>
                                                      onHorizontalButtonPressed!(
                                                        'Roll',
                                                      )
                                                  : null,
                                        ),
                                        const Spacer(),
                                        const Text(
                                          'Position',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        const SizedBox(height: 8),
                                        _buildKnob(
                                          50,
                                          showCounter: false,
                                          onTap: onHorizontalPositionKnobTapped,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Trigger Section
                                Expanded(
                                  flex: 1,
                                  child: _buildSectionWrapper(
                                    'Trigger',
                                    Column(
                                      children: [
                                        _buildOscButton(
                                          'Setup',
                                          onTap:
                                              onTriggerButtonPressed != null
                                                  ? () =>
                                                      onTriggerButtonPressed!(
                                                        'Setup',
                                                      )
                                                  : null,
                                        ),
                                        const SizedBox(height: 10),
                                        _buildOscButton(
                                          'Auto',
                                          onTap:
                                              onTriggerButtonPressed != null
                                                  ? () =>
                                                      onTriggerButtonPressed!(
                                                        'Auto',
                                                      )
                                                  : null,
                                        ),
                                        const SizedBox(height: 10),
                                        _buildOscButton(
                                          'Normal',
                                          onTap:
                                              onTriggerButtonPressed != null
                                                  ? () =>
                                                      onTriggerButtonPressed!(
                                                        'Normal',
                                                      )
                                                  : null,
                                        ),
                                        const SizedBox(height: 10),
                                        _buildOscButton(
                                          'Single',
                                          onTap:
                                              onTriggerButtonPressed != null
                                                  ? () =>
                                                      onTriggerButtonPressed!(
                                                        'Single',
                                                      )
                                                  : null,
                                        ),
                                        const Spacer(),
                                        const Text(
                                          'Level',
                                          style: TextStyle(fontSize: 10),
                                        ),
                                        const SizedBox(height: 8),
                                        _buildKnob(
                                          50,
                                          onChanged: onTriggerLevelKnobChanged,
                                          showCounter: false,
                                          onTap: onTriggerLevelKnobTapped,
                                        ),
                                      ],
                                    ),
                                  ),
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
              if (!isOnline)
                Positioned.fill(
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border.all(color: Colors.redAccent, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'OFFLINE',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRoundMenuButton() {
    final bool canPress = isOnline && onMenuPressed != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canPress ? onMenuPressed : null,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          width: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isOnline
                  ? [const Color(0xFF475569), const Color(0xFF1E293B)]
                  : [const Color(0xFF2D3748), const Color(0xFF1A202C)],
            ),
            border: Border.all(
              color: isOnline ? Colors.white : Colors.white24,
            ),
            boxShadow: isOnline
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      offset: const Offset(1, 1),
                      blurRadius: 2,
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              'Menu',
              style: TextStyle(
                color: isOnline ? Colors.white : Colors.white24,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSoftKey(String label, {int flex = 20}) {
    // Extract button number from label (M1 -> 1, M2 -> 2, etc.)
    final buttonNumber = int.tryParse(label.substring(1));
    final bool canPress =
        isOnline && buttonNumber != null && onSoftKeyPressed != null;

    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3.2),
        child: _buildOscButton(
          label,
          height: double.infinity,
          onTap: canPress ? () => onSoftKeyPressed!(buttonNumber) : null,
          borderColor: isOnline ? Colors.white : Colors.white10,
          lowContrast: !isOnline,
        ),
      ),
    );
  }

  Widget _buildKnobSection(String label, double size, {ValueChanged<double>? onChanged, bool showCounter = true, VoidCallback? onTap}) {
    return _buildBorderedSectionWithoutTitle(
      Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          _buildKnob(size, onChanged: onChanged, showCounter: showCounter, onTap: onTap),
        ],
      ),
    );
  }

  Widget _buildKnob(double size, {bool enabled = true, ValueChanged<double>? onChanged, bool showCounter = true, VoidCallback? onTap}) {
    return KnobWithDisplay(size: size, enabled: enabled, onChanged: onChanged, showCounter: showCounter, onTap: onTap);
  }

  Widget _buildMenuGrid() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF475569)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: 3,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio:
                3.0, 
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _buildOscButton('Cursors', onTap: onMenuButtonPressed != null ? () => onMenuButtonPressed!('Cursors') : null),
              _buildOscButton('Acquire', onTap: onMenuButtonPressed != null ? () => onMenuButtonPressed!('Acquire') : null),
              _buildOscButton('Save/\nRecall', onTap: onMenuButtonPressed != null ? () => onMenuButtonPressed!('Save/Recall') : null),
              _buildOscButton('Measure', onTap: onMenuButtonPressed != null ? () => onMenuButtonPressed!('Measure') : null),
              _buildOscButton('Clear\nSweeps', onTap: onMenuButtonPressed != null ? () => onMenuButtonPressed!('Clear Sweeps') : null),
              _buildOscButton('Utility', onTap: onMenuButtonPressed != null ? () => onMenuButtonPressed!('Utility') : null),
              _buildOscButton('Default', color: Colors.cyan[700], onTap: onMenuButtonPressed != null ? () => onMenuButtonPressed!('Default') : null),
              _buildOscButton('Display/\nPersist', onTap: onMenuButtonPressed != null ? () => onMenuButtonPressed!('Display/Persist') : null),
              _buildOscButton(
                'Print',
                color: Colors.lightBlue[300],
                onTap: onMenuButtonPressed != null ? () => onMenuButtonPressed!('Print') : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalButtonGroup(List<String> labels) {
    return _buildBorderedSectionWithoutTitle(
      Column(
        children: [
          for (int i = 0; i < labels.length; i++)
            Padding(
              padding: EdgeInsets.only(
                bottom: i < labels.length - 1 ? 4.0 : 0.0,
              ),
              child: _buildOscButton(
                labels[i],
                height: 45,
                color: labels[i] == 'Auto\nSetup' ? Colors.blue[900] : null,
                onTap: onVerticalButtonPressed != null ? () => onVerticalButtonPressed!(labels[i]) : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChannelColumn(String ch) {
    // Channels are always enabled
    return Column(
      children: [
        // Top Knob Section (Always enabled)
        Column(
          children: [
            const Text('V <-> mV', style: TextStyle(fontSize: 10)),
            const SizedBox(height: 8),
            _buildKnob(70, enabled: true, showCounter: false, onChanged: ch == 'CH1' ? onCh1VoltageKnobChanged : (ch == 'CH2' ? onCh2VoltageKnobChanged : null), onTap: ch == 'CH1' ? onCh1VoltageKnobTapped : (ch == 'CH2' ? onCh2VoltageKnobTapped : null)),
          ],
        ),
        const SizedBox(height: 15),

        // Math/Ref Button (Forced High Contrast)
        _buildOscButton(
          ch == 'CH1' ? 'Math' : 'Ref',
          width: 50,
          color: Colors.blue[900],
          onTap: onVerticalButtonPressed != null ? () => onVerticalButtonPressed!(ch == 'CH1' ? 'Math' : 'Ref') : null,
        ),
        const SizedBox(height: 10),

        // Channel Button (Always active)
        _buildOscButton(
          ch,
          width: 50,
          color: ch == 'CH1' ? Colors.yellow[700] : Colors.purple[300],
          onTap: () => onChannelToggle(ch),
        ),
        const SizedBox(height: 15),

        const Spacer(),

        // Bottom Knob Section (Always enabled)
        Column(
          children: [
            const Text('Position', style: TextStyle(fontSize: 10)),
            const SizedBox(height: 8),
            _buildKnob(50, enabled: true, showCounter: false, onChanged: ch == 'CH1' ? onCh1PositionKnobChanged : (ch == 'CH2' ? onCh2PositionKnobChanged : null), onTap: ch == 'CH1' ? onCh1PositionKnobTapped : (ch == 'CH2' ? onCh2PositionKnobTapped : null)),
          ],
        ),
      ],
    );
  }

  Widget _buildOscButton(
    String label, {
    double? width,
    double? height,
    Color? color,
    VoidCallback? onTap,
    bool highContrast = false,
    bool lowContrast = false,
    Color? borderColor,
  }) {
    bool useBlackText =
        highContrast ||
        color == Colors.cyanAccent ||
        color == Colors.lightBlue[300];

    // Determine border color: use provided borderColor, or highContrast white, or default
    final Color actualBorderColor =
        borderColor ?? (highContrast ? Colors.white : const Color(0xFF475569));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () {},
        borderRadius: BorderRadius.circular(4),
        child: Ink(
          width: width ?? double.infinity,
          height: height ?? 30,
          decoration: BoxDecoration(
            color: highContrast
                ? Colors.white
                : (color ?? const Color(0xFF334155)),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                offset: const Offset(1, 1),
                blurRadius: 2,
              ),
            ],
            border: Border.all(color: actualBorderColor, width: 0.5),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: lowContrast
                    ? Colors.white38
                    : (useBlackText ? Colors.black : Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBorderedSectionWithoutTitle(Widget child) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF172A45).withValues(alpha: 0.3),
              border: Border.all(color: const Color(0xFF475569)),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        Padding(padding: const EdgeInsets.all(8.0), child: child),
      ],
    );
  }

  Widget _buildSectionWrapper(String title, Widget child) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF172A45).withValues(alpha: 0.3),
              border: Border.all(color: const Color(0xFF475569)),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        Padding(padding: const EdgeInsets.all(8.0), child: child),
        Positioned(
          top: -8,
          left: 10,
          child: Container(
            color: const Color(0xFF172A45),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
