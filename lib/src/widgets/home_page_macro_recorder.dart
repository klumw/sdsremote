part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeMacroRecorder on _OsciHomePageState {
  Widget _buildMacroRecorderWindow() {
    if (_showMacroEditor) {
      return MacroEditorPanel(
        initialContent: _currentMacroContent,
        loadedFileName: _loadedMacroFileName,
        isModified: _isMacroModified,
        aiSettings: _aiSettings,
        chatController: _macroChatController,
        voiceInput: _voiceInputService,
        layout: _macroEditorLayout,
        isPlaying: _isMacroPlaying,
        hasDebugSession: _macroDebugSession != null,
        isDebugPaused: _macroDebugSession?.paused ?? false,
        isDebugRunning:
            _macroDebugSession != null &&
            !(_macroDebugSession?.paused ?? false),
        debugStatus: _macroDebugStatus,
        debugCurrentLine: _macroDebugCurrentLine,
        debugVariables: _macroDebugVariables,
        printController: _macroPrintController,
        breakpoints: _macroBreakpoints,
        inactiveBreakpoints: _macroInactiveBreakpoints,
        onBreakpointsChanged: (breakpoints) {
          _setState(() {
            final added = breakpoints.difference(_macroBreakpoints);
            _macroBreakpoints = breakpoints;
            // A newly created breakpoint is always active; removed lines no
            // longer belong to the inactive set.
            _macroInactiveBreakpoints.removeAll(added);
            _macroInactiveBreakpoints.removeWhere(
              (line) => !breakpoints.contains(line),
            );
          });
        },
        onDeleteBreakpoint: (line) {
          _setState(() {
            _macroBreakpoints.remove(line);
            _macroInactiveBreakpoints.remove(line);
          });
        },
        onSetBreakpointEnabled: (line, enabled) {
          _setState(() {
            if (enabled) {
              _macroInactiveBreakpoints.remove(line);
            } else {
              _macroInactiveBreakpoints.add(line);
            }
          });
        },
        onSetAllBreakpointsEnabled: (enabled) {
          _setState(() {
            if (enabled) {
              _macroInactiveBreakpoints.clear();
            } else {
              _macroInactiveBreakpoints = Set<int>.of(_macroBreakpoints);
            }
          });
        },
        onDeleteAllBreakpoints: () {
          _setState(() {
            _macroBreakpoints.clear();
            _macroInactiveBreakpoints.clear();
          });
        },
        onPlay: _onMacroEditorPlay,
        onStep: _onMacroEditorStep,
        onContinue: _onMacroEditorContinue,
        onStop: _onMacroStop,
        errorMessage: _macroHadPlaybackError ? _macroStatusMessage : null,
        onContentChanged: (content) {
          _currentMacroContent = content;
          // Editing invalidates a paused debug session because its AST no
          // longer matches the editor content.
          if (_macroDebugSession != null) {
            unawaited(_stopMacroDebugSession(status: 'Stopped (macro edited)'));
          }
          // Line numbers and variable values are stale after an edit.
          final hadDebugState =
              _macroDebugCurrentLine != null || _macroDebugVariables.isNotEmpty;
          _macroDebugCurrentLine = null;
          _macroDebugVariables = <String, String>{};
          if (hadDebugState) _setState(() {});
          // When a loaded file is edited, enable the Save button.
          if (_loadedMacroFileName != null && !_isMacroModified) {
            _setState(() => _isMacroModified = true);
          }
        },
        onSave: _currentMacroContent.trim().isNotEmpty ? _onMacroSave : null,
        onClose: () {
          unawaited(_stopMacroDebugSession());
          _setState(() {
            _showMacroEditor = false;
          });
        },
      );
    }

    return MacroRecorderPanel(
      macroFiles: _macroFiles,
      isRecording: _isMacroRecording,
      isPlaying: _isMacroPlaying,
      // Saving is a local file operation; content alone decides whether the
      // button is available, not the device connection.
      isSaveEnabled: _currentMacroContent.trim().isNotEmpty,
      hasContent: _currentMacroContent.trim().isNotEmpty,
      macroStatus: _macroStatus,
      macroStatusMessage: _macroStatusMessage,
      printController: _macroPrintController,
      loadedFileName: _loadedMacroFileName,
      isModified: _isMacroModified,
      onRecord: _onMacroStart,
      onNewFromTemplate: _showMacroTemplatePicker,
      onStop: _onMacroStop,
      onPlay: _onMacroPlay,
      onEdit: _onMacroEdit,
      onSave: _onMacroSave,
      onLoad: _onMacroLoad,
      onDelete: _onMacroDelete,
      onClose: () => _togglePanel(ActivePanel.macroRecorder),
    );
  }

  void _loadMacroFiles() {
    try {
      final dir = AppPaths.macrosDirectory;
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.m'))
          .map(
            (f) => MacroInfo(
              fileName: f.uri.pathSegments.last,
              lastModified: f.lastModifiedSync(),
            ),
          )
          .toList();
      _setState(() {
        _macroFiles = files;
      });
    } catch (e) {
      AppLogger().error('Error loading macro files: $e');
    }
  }

  void _onMacroStart() {
    unawaited(_stopMacroDebugSession());
    _macroDebugStatus = null;
    _macroBreakpoints = <int>{};
    _macroInactiveBreakpoints = <int>{};
    _macroDebugCurrentLine = null;
    _macroDebugVariables = <String, String>{};
    _macroPrintController.clear();
    _setState(() {
      _macroStatus = null;
      _macroStatusMessage = null;
      _isMacroRecording = true;
      _isMacroModified = true;
      _loadedMacroFileName = null;
      _currentMacroContent = _isUsb
          ? 'connect(usb)\n'
          : 'connect("$_ipAddress")\n';
    });

    onScpiCommandSent = (command, operation) {
      if (!_isMacroRecording) return;
      switch (operation) {
        case 'write':
          _currentMacroContent += 'cmd("$command")\n';
        case 'query':
          _currentMacroContent += 'query("$command")\n';
      }
    };

    AppLogger().log('Macro recording started');
  }

  void _onMacroStop() {
    _setState(() => _macroStatus = null);
    if (_isMacroPlaying) {
      _macroPlaybackCancelled = true;
    }
    unawaited(_stopMacroDebugSession());
    if (_isMacroRecording) {
      onScpiCommandSent = null;
      _setState(() {
        _isMacroRecording = false;
      });
      AppLogger().log('Macro recording stopped');
    }
  }

  /// Parses and executes the macro commands in [_currentMacroContent]
  /// using the petitparser-based Grammar → AST → Evaluator pipeline.
  ///
  /// See [MacroGrammarDefinition] and [MacroEvaluator] for the full
  /// list of supported commands.
  Future<void> _playMacro() async {
    _macroHadPlaybackError = false;
    // A new playback starts with an empty print panel.
    _macroPrintController.clear();
    final source = _currentMacroContent;

    if (source.trim().isEmpty) {
      _showMacroError('Macro is empty');
      return;
    }

    _playbackInstrument = null;

    final evaluator = MacroEvaluator(
      instrument: _playbackInstrument,
      onError: _showMacroError,
      isCancelled: () => _macroPlaybackCancelled,
      delay: (duration) => Future.delayed(duration),
      onPrint: _macroPrintController.add,
      siggenConnector: _connectMacroSignalGenerator,
    );

    final success = await evaluator.evaluateSource(source);

    // Set macro status for the header icon
    if (mounted) {
      _setState(() {
        if (!success && _macroPlaybackCancelled) {
          _macroStatus = 2; // cancelled
        } else if (!success) {
          _macroStatus = 0; // error
        } else {
          _macroStatus = 1; // success
        }
      });
    }

    // Clean up the dedicated macro playback connections (oscilloscope and
    // signal generator).
    await evaluator.close();
    _playbackInstrument = null;

    AppLogger().log(
      _macroPlaybackCancelled
          ? 'Macro playback: stopped by user'
          : 'Macro playback: finished',
    );

    if (mounted && !_macroHadPlaybackError) {
      if (_macroPlaybackCancelled) {
        _showInfoSnackBar(
          'Macro playback stopped',
          backgroundColor: Colors.orange,
        );
      } else if (success) {
        _showInfoSnackBar(
          'Macro playback completed',
          backgroundColor: Colors.green,
        );
      }
    }
  }

  /// Opens the signal generator configured in the settings for a macro's
  /// `connect(SIG, usb)` statement.
  ///
  /// The application's service is reused when available so macro playback and
  /// the signal generator window never open the same serial port twice.
  Future<MacroSiggenSession> _connectMacroSignalGenerator() =>
      AppMacroSiggenConnector(service: _sigGenService).connect();

  /// Reports the oscilloscope connection and detected model to the AI agents'
  /// `read_oscilloscope_status` tools.
  ///
  /// The values come from the same state used by the connection monitor and
  /// the window title, so no additional `*IDN?` query is sent.
  Future<Map<String, dynamic>> _readOscilloscopeStatus() async =>
      readMacroOscilloscopeStatus(
        connected: _isOnline,
        model: _deviceModel,
        name: _deviceName,
        channels: _numChannels,
        isUsb: _isUsb,
        ipAddress: _ipAddress,
      );

  /// Shows an error snackbar and logs the error.
  /// Also sets [_macroHadPlaybackError] if called during active playback.
  void _showMacroError(String message) {
    if (_isMacroPlaying || _macroDebugSession != null) {
      _macroHadPlaybackError = true;
      _macroStatus = 0; // show error icon immediately
    }
    _macroStatusMessage = message;
    if (_macroDebugSession != null) {
      _macroDebugStatus = 'Error';
    }
    AppLogger().error('Macro error: $message');
    if (mounted) {
      _setState(() {});
      _showErrorSnackBar(message);
    }
  }

  void _onMacroPlay() {
    AppLogger().log('Macro play requested');
    _macroDebugStatus = null;
    _macroDebugCurrentLine = null;
    _macroDebugVariables = <String, String>{};
    _setState(() => _macroStatus = null);
    _macroPlaybackCancelled = false;
    _setState(() => _isMacroPlaying = true);
    _playMacro().whenComplete(() {
      if (mounted) _setState(() => _isMacroPlaying = false);
    });
  }

  void _onMacroEdit() {
    _macroDebugStatus = null;
    _macroDebugCurrentLine = null;
    _macroDebugVariables = <String, String>{};
    _setState(() {
      _macroStatus = null;
      _macroStatusMessage = null;
      _macroHadPlaybackError = false;
      _showMacroEditor = true;
    });
  }

  /// Opens the template picker and loads the selected template into the editor.
  Future<void> _showMacroTemplatePicker() async {
    final template = await showDialog<MacroTemplate>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('New macro from template'),
        children: [
          for (final template in macroTemplates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, template),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(template.name),
                subtitle: Text(template.description),
              ),
            ),
        ],
      ),
    );
    if (template == null || !mounted) return;
    _setState(() {
      _currentMacroContent = template.content;
      _loadedMacroFileName = null;
      _isMacroModified = true;
      _showMacroEditor = true;
      _macroStatus = null;
      _macroStatusMessage = null;
      _macroHadPlaybackError = false;
    });
  }

  /// Core save logic — extracted so it can be awaited from [onWindowClose].
  Future<void> _saveMacro() async {
    _setState(() => _macroStatus = null);
    if (!mounted) return;

    // When a macro was loaded from file, save back under the same filename
    // without prompting.
    if (_loadedMacroFileName != null) {
      try {
        final dir = AppPaths.macrosDirectory;
        final file = File('${dir.path}/$_loadedMacroFileName');
        await file.writeAsString(_currentMacroContent);
        _loadMacroFiles();
        _setState(() {
          _isMacroModified = false;
        });
        _showInfoSnackBar('Macro "$_loadedMacroFileName" saved.');
      } catch (e) {
        AppLogger().error('Save macro error: $e');
        _showErrorSnackBar('Save macro failed: $e');
      }
      return;
    }

    // No loaded filename — ask for a name via the prefix dialog.
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const FilenamePrefixDialog(),
    );
    if (name == null || name.trim().isEmpty) return;

    try {
      final dir = await AppPaths.getOrCreateMacrosDir();
      final file = File('${dir.path}/${name.trim()}.m');
      await file.writeAsString(_currentMacroContent);
      _loadMacroFiles();
      _setState(() {
        _loadedMacroFileName = '${name.trim()}.m';
        _isMacroModified = false;
      });
      _showInfoSnackBar('Macro "$name" saved.');
    } catch (e) {
      AppLogger().error('Save macro error: $e');
      _showErrorSnackBar('Save macro failed: $e');
    }
  }

  void _onMacroSave() {
    // Fire-and-forget: the recorder-panel button expects a VoidCallback.
    _saveMacro();
  }

  Future<void> _onMacroLoad(String fileName) async {
    try {
      final dir = AppPaths.macrosDirectory;
      final file = File('${dir.path}/$fileName');
      if (!await file.exists()) throw Exception('Macro file not found');
      final content = await file.readAsString();
      unawaited(_stopMacroDebugSession());
      _macroDebugStatus = null;
      _macroBreakpoints = <int>{};
      _macroInactiveBreakpoints = <int>{};
      _macroDebugCurrentLine = null;
      _macroDebugVariables = <String, String>{};
      _macroPrintController.clear();
      _setState(() {
        _macroStatus = null;
        _currentMacroContent = content;
        _loadedMacroFileName = fileName;
        _isMacroModified = false;
        // Loading from the file list keeps the recorder view; the editor
        // opens only when the user presses Edit.
      });
    } catch (e) {
      AppLogger().error('Load macro error: $e');
      _showErrorSnackBar('Load macro failed: $e');
    }
  }

  Future<void> _onMacroDelete(String fileName) async {
    try {
      final dir = AppPaths.macrosDirectory;
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) {
        await file.delete();
      }
      _loadMacroFiles();
    } catch (e) {
      AppLogger().error('Delete macro error: $e');
    }
  }
}
