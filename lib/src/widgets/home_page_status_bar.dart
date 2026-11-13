import 'package:flutter/material.dart';

import '../app/app_theme.dart';

/// Bottom status bar of the home page.
///
/// Purely presentational; all values are supplied by the home page.
class HomePageStatusBar extends StatelessWidget {
  const HomePageStatusBar({
    super.key,
    required this.isUsb,
    required this.ipAddress,
    required this.isOnline,
    required this.signalGeneratorDetected,
    required this.signalGeneratorModel,
  });

  /// Whether the oscilloscope is connected over USB.
  final bool isUsb;

  /// Device IP address shown in network mode.
  final String ipAddress;

  /// Whether the oscilloscope is currently online.
  final bool isOnline;

  /// Whether a signal generator was detected.
  final bool signalGeneratorDetected;

  /// Model name of the detected signal generator.
  final String signalGeneratorModel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.statusBar,
        border: Border(top: BorderSide(color: Colors.white12, width: 2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (!isUsb) ...[
                const Icon(Icons.lan, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                const Text(
                  "Device IP:",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  ipAddress,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ] else ...[
                const Icon(Icons.usb, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                const Text(
                  "Device Mode: USB",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              if (signalGeneratorDetected) ...[
                const SizedBox(width: 24),
                const Icon(Icons.waves, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                const Text(
                  "Signal Generator:",
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  signalGeneratorModel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ],
          ),
          Row(
            children: [
              Text(
                isOnline ? "ONLINE" : "OFFLINE",
                style: TextStyle(
                  color: isOnline ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.circle,
                color: isOnline ? Colors.greenAccent : Colors.redAccent,
                size: 14,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
