/// Root widget of the separate signal-generator OS window.
///
/// The window is created by the main application with `desktop_multi_window`;
/// `main.dart` selects this widget for the child engine.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app/app_theme.dart';
import '../core/logger.dart';
import '../signal_generator/siggen_window_client.dart';
import '../signal_generator/siggen_window_controller.dart';
import 'signal_generator_panel.dart';

class SignalGeneratorWindowApp extends StatefulWidget {
  const SignalGeneratorWindowApp({
    super.key,
    required this.client,
    this.onReady,
  });

  final SigGenWindowClient client;

  /// Called after the first complete frame (with the initial snapshot) has
  /// been painted. The OS window is shown only then.
  final VoidCallback? onReady;

  @override
  State<SignalGeneratorWindowApp> createState() =>
      _SignalGeneratorWindowAppState();
}

class _SignalGeneratorWindowAppState extends State<SignalGeneratorWindowApp>
    with WindowListener {
  late final SignalGeneratorPanelController _controller;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // Hide instead of destroying the window. Destroying a child engine's
    // view currently trips a Flutter implicit-view teardown bug that can
    // terminate the whole application process.
    unawaited(
      windowManager.setPreventClose(true).catchError((Object _) {
        // Not available in widget tests or without the plugin.
      }),
    );
    _controller = SignalGeneratorPanelController(client: widget.client);
    unawaited(_initialize());
  }

  @override
  void onWindowClose() async {
    try {
      await windowManager.hide();
    } catch (error) {
      AppLogger(
        agentName: 'SigGen',
        toolName: 'window',
      ).error('Could not hide signal generator window: $error');
    }
  }

  Future<void> _initialize() async {
    final log = AppLogger(agentName: 'SigGen', toolName: 'window');
    log.log('Signal generator panel: initializing');
    try {
      await _controller.init().timeout(const Duration(seconds: 2));
      log.log('Signal generator panel: init complete');
    } catch (error) {
      // Show the window anyway; the periodic pull retries the snapshot.
      log.error('Signal generator panel: init failed: $error');
    }
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      log.log('Signal generator panel: first frame painted');
      if (mounted) widget.onReady?.call();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _controller.dispose();
    unawaited(widget.client.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Signal Generator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.scaffoldBackground,
      ),
      home: SignalGeneratorPanel(controller: _controller),
    );
  }
}
