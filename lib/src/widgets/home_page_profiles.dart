part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeProfiles on _OsciHomePageState {
  Widget _buildProfilesWindow() {
    return ProfilesPanel(
      profileFiles: _profileFiles,
      isOnline: _isOnline,
      isLoading: _isProfileLoading,
      onSave: _saveProfile,
      onLoad: _loadProfile,
      onDelete: _deleteProfile,
      onClose: () => _togglePanel(ActivePanel.profiles),
    );
  }

  void _loadProfileFiles() {
    try {
      final dir = AppPaths.profilesDirectory;
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.lss'))
          .map(
            (f) => ProfileInfo(
              fileName: f.uri.pathSegments.last,
              lastModified: f.lastModifiedSync(),
            ),
          )
          .toList();
      _setState(() {
        _profileFiles = files;
      });
    } catch (e) {
      AppLogger().error('Error loading profile files: $e');
    }
  }

  Future<void> _saveProfile(String name) async {
    final sw = Stopwatch()..start();
    try {
      final instr = await _getInstrument();
      if (instr == null) throw Exception('Device not connected');

      // Send PNSU? to get XML settings.
      // The instrument returns data with an IEEE 488.2 definite-length block
      // header (e.g. "PNSU #9000047692<?xml..."). Decode with lenient UTF-8
      // handling to tolerate any non-UTF-8 bytes in the raw response.
      // The instrument needs ~14 s to build the setup block before it sends
      // the first byte; a 15 s timeout left no margin.
      final data = await instr.readRawResponse(
        'PNSU?',
        timeout: const Duration(seconds: 30),
      );
      final content = utf8.decode(data, allowMalformed: true);

      final dir = await AppPaths.getOrCreateProfilesDir();
      final file = File('${dir.path}/$name.lss');
      await file.writeAsString(content);

      _loadProfileFiles();
      AppLogger().log(
        'Profile "$name" saved successfully (${sw.elapsedMilliseconds} ms).',
      );
      _showInfoSnackBar('Profile "$name" saved.');
    } catch (e) {
      AppLogger().error('Save profile error: $e');
      AppLogger().error('Popup: Save profile failed: $e');
      _showErrorSnackBar('Save profile failed: $e');
    }
  }

  /// Uploads [fileName] to the instrument and marks the panel as busy.
  Future<void> _loadProfile(String fileName) async {
    if (_isProfileLoading) return;
    _setState(() => _isProfileLoading = true);
    try {
      await _loadProfileInner(fileName);
    } finally {
      if (mounted) {
        _setState(() => _isProfileLoading = false);
      }
    }
  }

  Future<void> _loadProfileInner(String fileName) async {
    // Capture profile load during macro recording
    if (_isMacroRecording) {
      final fullPath = '${AppPaths.profilesDirectory.path}/$fileName';
      _currentMacroContent += 'loadProfile("$fullPath")\n';
    }

    try {
      final dir = AppPaths.profilesDirectory;
      final file = File('${dir.path}/$fileName');
      if (!await file.exists()) throw Exception('File not found');

      final xml = await file.readAsString();
      AppLogger().log(
        'LoadProfile: reading "$fileName" (${xml.length} bytes / '
        '${(xml.length / 1024).toStringAsFixed(1)} KB)',
      );
      final instr = await _getInstrument();
      if (instr == null) throw Exception('Device not connected');

      // Send the XML string via writeProfileData. Over USB, Linux splits it
      // into 64-byte transfers while Windows uses a single bulk transfer
      // that WinUSB segments itself.  For VXI-11 mode this delegates to
      // writeString.
      AppLogger().log(
        'LoadProfile: sending ${xml.length} bytes via writeProfileData '
        '(timeout: 15s, isUsb: $_isUsb)',
      );
      await instr.writeProfileData(xml, timeout: const Duration(seconds: 15));
      // The scope stops answering while it applies the profile. Over VXI-11
      // *OPC? reports completion; over USB the instrument resets its USB
      // interface and is reconnected once it is back on the bus.
      await instr.awaitProfileApplied();

      AppLogger().log('Profile "$fileName" loaded successfully.');
      _showInfoSnackBar('Profile "$fileName" loaded.');
      // Refresh screen dump after loading profile
      _scheduleRefresh();
    } catch (e) {
      AppLogger().error('Load profile error: $e');
      AppLogger().error('Popup: Load profile failed: $e');
      _showErrorSnackBar('Load profile failed: $e');
    }
  }

  Future<void> _deleteProfile(String fileName) async {
    try {
      final dir = AppPaths.profilesDirectory;
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) {
        await file.delete();
      }
      _loadProfileFiles();
    } catch (e) {
      AppLogger().error('Delete profile error: $e');
    }
  }
}
