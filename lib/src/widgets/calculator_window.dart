/// Root widget of the separate engineering-calculator OS window.
///
/// The window is created with `desktop_multi_window`; `main.dart` selects
/// this widget for the child engine. It follows the same show-after-first-
/// frame and hide-on-close pattern as the signal generator window.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app/app_theme.dart';
import '../calculator/calculator_controller.dart';
import '../core/logger.dart';
import 'calculator_panel.dart';

class CalculatorWindowApp extends StatefulWidget {
  const CalculatorWindowApp({
    super.key,
    required this.controller,
    this.onReady,
  });

  final CalculatorController controller;

  /// Called after the first complete frame has been painted.
  final VoidCallback? onReady;

  @override
  State<CalculatorWindowApp> createState() => _CalculatorWindowAppState();
}

class _CalculatorWindowAppState extends State<CalculatorWindowApp>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(
      windowManager.setPreventClose(true).catchError((Object _) {
        // Not available in widget tests or without the plugin.
      }),
    );
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final log = AppLogger(agentName: 'Calculator', toolName: 'window');
    log.log('Calculator window: initializing');
    try {
      await widget.controller.initialize();
      log.log('Calculator window: workspace loaded');
    } catch (error) {
      log.error('Calculator window: initialization failed: $error');
    }
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onReady?.call();
    });
  }

  @override
  void onWindowClose() async {
    try {
      await widget.controller.save();
      await windowManager.hide();
    } catch (error) {
      AppLogger(
        agentName: 'Calculator',
        toolName: 'window',
      ).error('Could not hide calculator window: $error');
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Engineering Calculator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.scaffoldBackground,
        colorScheme: ThemeData.dark().colorScheme.copyWith(
          primary: Colors.cyanAccent,
        ),
      ),
      home: CalculatorPanel(controller: widget.controller),
    );
  }
}
