import 'package:flutter/material.dart';

/// A reusable toolbar button with the standard SDS-Remote dark theme styling.
/// Used in the top bar for Control Panel, Acquire Waveform, AI, Profiles, and Help buttons.
class OsciToolbarButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final bool alwaysEnabled;

  /// Whether this button belongs to the currently open panel. An active
  /// button gets a cyan border and a subtle glow.
  final bool active;

  const OsciToolbarButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.alwaysEnabled = false,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = !alwaysEnabled && onPressed == null;
    final isActive = active && !isDisabled;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(
              0xFF172A45,
            ).withValues(alpha: isDisabled ? 0.3 : 1.0),
            borderRadius: BorderRadius.circular(8),
            boxShadow: isDisabled
                ? []
                : [
                    if (isActive)
                      BoxShadow(
                        color: Colors.cyanAccent.withValues(alpha: 0.35),
                        blurRadius: 8,
                      ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      offset: const Offset(1, 1),
                      blurRadius: 2,
                    ),
                  ],
            border: Border.all(
              color: isActive
                  ? Colors.cyanAccent
                  : const Color(
                      0xFF475569,
                    ).withValues(alpha: isDisabled ? 0.3 : 1.0),
              width: isActive ? 2.0 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDisabled)
                ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.white.withValues(alpha: 0.3),
                    BlendMode.srcIn,
                  ),
                  child: icon,
                )
              else
                icon,
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: isDisabled ? 0.3 : 1.0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
