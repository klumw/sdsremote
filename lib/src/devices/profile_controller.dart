import 'dart:convert';
import 'dart:io';

import '../app/app_paths.dart';
import '../core/logger.dart';
import '../instrument/dart_vxi11.dart';
import 'profile_info.dart';

/// Owns the saved device setup profile files and their upload state.
///
/// The panel stays a thin view; this controller lists, saves, uploads, and
/// deletes `.lss` profile files and reports busy/refresh state through
/// callbacks.
class ProfileController {
  ProfileController({
    required this.getInstrument,
    required this.isUsb,
    required this.isMacroRecording,
    required this.appendMacroLine,
    required this.onScheduleRefresh,
    required this.showInfo,
    required this.showError,
    required this.onChanged,
  });

  final Future<Vxi11Instrument?> Function() getInstrument;
  final bool Function() isUsb;
  final bool Function() isMacroRecording;
  final void Function(String line) appendMacroLine;
  final void Function() onScheduleRefresh;
  final void Function(String message) showInfo;
  final void Function(String message) showError;
  final void Function() onChanged;

  List<ProfileInfo> profileFiles = [];
  bool isProfileLoading = false;

  /// Reloads the profile file list from disk.
  void loadFiles() {
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
      profileFiles = files;
      onChanged();
    } catch (e) {
      AppLogger().error('Error loading profile files: $e');
    }
  }

  Future<void> save(String name) async {
    final sw = Stopwatch()..start();
    try {
      final instr = await getInstrument();
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

      loadFiles();
      AppLogger().log(
        'Profile "$name" saved successfully (${sw.elapsedMilliseconds} ms).',
      );
      showInfo('Profile "$name" saved.');
    } catch (e) {
      AppLogger().error('Save profile error: $e');
      AppLogger().error('Popup: Save profile failed: $e');
      showError('Save profile failed: $e');
    }
  }

  /// Uploads [fileName] to the instrument and marks the panel as busy.
  Future<void> load(String fileName) async {
    if (isProfileLoading) return;
    isProfileLoading = true;
    onChanged();
    try {
      await _loadInner(fileName);
    } finally {
      isProfileLoading = false;
      onChanged();
    }
  }

  Future<void> _loadInner(String fileName) async {
    // Capture profile load during macro recording
    if (isMacroRecording()) {
      final fullPath = '${AppPaths.profilesDirectory.path}/$fileName';
      appendMacroLine('loadProfile("$fullPath")\n');
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
      final instr = await getInstrument();
      if (instr == null) throw Exception('Device not connected');

      // Send the XML string via writeProfileData. Over USB, Linux splits it
      // into 64-byte transfers while Windows uses a single bulk transfer
      // that WinUSB segments itself.  For VXI-11 mode this delegates to
      // writeString.
      AppLogger().log(
        'LoadProfile: sending ${xml.length} bytes via writeProfileData '
        '(timeout: 15s, isUsb: ${isUsb()})',
      );
      await instr.writeProfileData(xml, timeout: const Duration(seconds: 15));
      // The scope stops answering while it applies the profile. Over VXI-11
      // *OPC? reports completion; over USB the instrument resets its USB
      // interface and is reconnected once it is back on the bus.
      await instr.awaitProfileApplied();

      AppLogger().log('Profile "$fileName" loaded successfully.');
      showInfo('Profile "$fileName" loaded.');
      // Refresh screen dump after loading profile
      onScheduleRefresh();
    } catch (e) {
      AppLogger().error('Load profile error: $e');
      AppLogger().error('Popup: Load profile failed: $e');
      showError('Load profile failed: $e');
    }
  }

  Future<void> delete(String fileName) async {
    try {
      final dir = AppPaths.profilesDirectory;
      final file = File('${dir.path}/$fileName');
      if (await file.exists()) {
        await file.delete();
      }
      loadFiles();
    } catch (e) {
      AppLogger().error('Delete profile error: $e');
    }
  }
}
