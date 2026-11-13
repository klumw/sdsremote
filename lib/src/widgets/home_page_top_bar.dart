import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_config.dart';
import '../app/app_theme.dart';
import '../voice/voice_activity_indicator.dart';
import '../voice/voice_input_service.dart';
import 'animated_sync_icon.dart';
import 'osci_toolbar_button.dart';

/// Top bar of the home page with the main toolbar and window actions.
///
/// Purely presentational: all state and callbacks are supplied by the home
/// page.
class HomePageTopBar extends StatelessWidget {
  const HomePageTopBar({
    super.key,
    required this.voiceStatus,
    required this.activePanel,
    required this.hasScreenDump,
    required this.waveformAcquired,
    required this.isOnline,
    required this.isAcquiring,
    required this.isAcquiringWaveform,
    required this.isMacroPlaying,
    required this.isMacroRecording,
    required this.isAiEnabled,
    required this.signalGenerator,
    required this.signalGeneratorDetected,
    required this.hasUnreadUpdate,
    required this.canSave,
    required this.canExportWaveform,
    required this.loggerIcon,
    required this.onAcquireScreenDump,
    required this.onAcquireWaveform,
    required this.onTogglePanel,
    required this.onShowNews,
    required this.onOpenSettings,
    required this.onSave,
    required this.onShowExport,
  });

  final ValueListenable<VoiceInputStatus> voiceStatus;
  final ActivePanel activePanel;
  final bool hasScreenDump;
  final bool waveformAcquired;
  final bool isOnline;
  final bool isAcquiring;
  final bool isAcquiringWaveform;
  final bool isMacroPlaying;
  final bool isMacroRecording;
  final bool isAiEnabled;
  final String signalGenerator;
  final bool signalGeneratorDetected;
  final bool hasUnreadUpdate;
  final bool canSave;
  final bool canExportWaveform;
  final Widget loggerIcon;
  final VoidCallback onAcquireScreenDump;
  final VoidCallback onAcquireWaveform;
  final ValueChanged<ActivePanel> onTogglePanel;
  final VoidCallback onShowNews;
  final VoidCallback onOpenSettings;
  final VoidCallback onSave;
  final VoidCallback onShowExport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: AppColors.panelBackground,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildToolbarButtons(),
            ),
          ),
          ValueListenableBuilder<VoiceInputStatus>(
            valueListenable: voiceStatus,
            builder: (context, status, _) {
              final color = status.isTranscribing || status.isResponding
                  ? Colors.greenAccent
                  : Colors.cyanAccent;
              return VoiceActivityIndicator(
                active: status.isActive,
                color: color,
              );
            },
          ),
          const SizedBox(width: 8),
          OsciToolbarButton(
            label: "Help",
            icon: const Icon(Icons.help_outline, size: 25),
            active: activePanel == ActivePanel.help,
            onPressed: isMacroPlaying
                ? null
                : () => onTogglePanel(ActivePanel.help),
            alwaysEnabled: !isMacroPlaying,
          ),
          const SizedBox(width: 16),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.campaign, size: 25),
                color: isMacroPlaying ? Colors.white24 : Colors.white70,
                tooltip: 'News',
                onPressed: isMacroPlaying ? null : onShowNews,
              ),
              if (hasUnreadUpdate)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings, size: 25),
            color: isMacroPlaying ? Colors.white24 : Colors.white70,
            tooltip: 'Settings',
            onPressed: isMacroPlaying ? null : onOpenSettings,
          ),
          IconButton(
            icon: const Icon(Icons.save_alt, size: 25),
            color: isMacroPlaying
                ? Colors.white24
                : canSave
                ? Colors.white70
                : Colors.white24,
            tooltip: 'Save',
            onPressed: (isMacroPlaying || !canSave) ? null : onSave,
          ),
          if (canExportWaveform)
            IconButton(
              icon: const Icon(Icons.ios_share, size: 25),
              color: isMacroPlaying ? Colors.white24 : Colors.white70,
              tooltip: 'Export Data',
              onPressed: isMacroPlaying ? null : onShowExport,
            ),
        ],
      ),
    );
  }

  Widget _buildToolbarButtons() {
    return Row(
      children: [
        // Control Panel
        OsciToolbarButton(
          label: isAcquiring ? "Acquiring..." : "Control",
          active:
              activePanel == ActivePanel.none &&
              !waveformAcquired &&
              hasScreenDump,
          icon: isAcquiring
              ? const AnimatedSyncIcon(size: 25, color: Colors.white)
              : const Icon(Icons.tune, size: 25),
          onPressed:
              (isAcquiring ||
                  isAcquiringWaveform ||
                  !isOnline ||
                  isMacroPlaying)
              ? null
              : onAcquireScreenDump,
        ),
        const SizedBox(width: 16),
        // Acquire Waveform
        OsciToolbarButton(
          label: isAcquiringWaveform ? "Acquiring..." : "Waveform",
          active: activePanel == ActivePanel.none && waveformAcquired,
          icon: isAcquiringWaveform
              ? const AnimatedSyncIcon(size: 25, color: Colors.white)
              : const Icon(Icons.show_chart, size: 25),
          onPressed: (isAcquiringWaveform || !isOnline || isMacroPlaying)
              ? null
              : onAcquireWaveform,
        ),
        const SizedBox(width: 16),
        // Profiles
        OsciToolbarButton(
          label: "Profiles",
          icon: const Icon(Icons.save, size: 25),
          active: activePanel == ActivePanel.profiles,
          onPressed: (isOnline && !isMacroPlaying)
              ? () => onTogglePanel(ActivePanel.profiles)
              : null,
        ),
        const SizedBox(width: 16),
        // Data Logger
        OsciToolbarButton(
          label: "Logger",
          icon: loggerIcon,
          active: activePanel == ActivePanel.dataLogger,
          onPressed: (isOnline && !isMacroPlaying)
              ? () => onTogglePanel(ActivePanel.dataLogger)
              : null,
        ),
        if (signalGenerator == 'jds6600' || signalGenerator == 'fy6900') ...[
          const SizedBox(width: 16),
          OsciToolbarButton(
            label: 'Bode',
            icon: const Icon(Icons.analytics_outlined, size: 25),
            active: activePanel == ActivePanel.bode,
            onPressed:
                (isOnline &&
                    signalGeneratorDetected &&
                    !isMacroPlaying &&
                    !isAcquiring &&
                    !isAcquiringWaveform)
                ? () => onTogglePanel(ActivePanel.bode)
                : null,
          ),
        ],
        const SizedBox(width: 16),
        // Macro Recorder
        OsciToolbarButton(
          label: isMacroPlaying
              ? "Playback"
              : (isMacroRecording ? "Recording..." : "Macro"),
          active: activePanel == ActivePanel.macroRecorder,
          icon: isMacroPlaying
              ? const Icon(
                  Icons.play_circle,
                  size: 25,
                  color: Colors.greenAccent,
                )
              : (isMacroRecording
                    ? const Icon(
                        Icons.fiber_manual_record,
                        size: 25,
                        color: Colors.red,
                      )
                    : const Icon(Icons.movie, size: 25)),
          // Always available so a macro can be reviewed and edited while the
          // oscilloscope is offline; the panel disables the device-dependent
          // actions itself.
          onPressed: () => onTogglePanel(ActivePanel.macroRecorder),
        ),
        const SizedBox(width: 16),
        // AI Chat — icon only; its label lives in the tooltip.
        OsciToolbarButton(
          tooltip: 'AI Chat',
          icon: const Icon(Icons.auto_awesome, size: 25),
          active: activePanel == ActivePanel.chat,
          onPressed: (isAiEnabled && !isMacroPlaying)
              ? () => onTogglePanel(ActivePanel.chat)
              : null,
        ),
      ],
    );
  }
}
