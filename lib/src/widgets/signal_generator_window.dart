/// Root widget of the separate signal-generator OS window.
///
/// The window is created by the main application with `desktop_multi_window`;
/// `main.dart` selects this widget for the child engine.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../signal_generator/siggen_window_client.dart';
import '../signal_generator/siggen_window_controller.dart';
import 'signal_generator_panel.dart';

class SignalGeneratorWindowApp extends StatefulWidget {
  const SignalGeneratorWindowApp({super.key, required this.client});

  final SigGenWindowClient client;

  @override
  State<SignalGeneratorWindowApp> createState() =>
      _SignalGeneratorWindowAppState();
}

class _SignalGeneratorWindowAppState extends State<SignalGeneratorWindowApp> {
  late final SignalGeneratorPanelController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SignalGeneratorPanelController(client: widget.client);
    unawaited(_controller.init());
  }

  @override
  void dispose() {
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
