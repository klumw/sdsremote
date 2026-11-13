part of 'home_page.dart';

// Stage A extraction from home_page.dart. Do not add imports here.

extension _HomeProfiles on _OsciHomePageState {
  List<ProfileInfo> get _profileFiles => _profileController.profileFiles;

  bool get _isProfileLoading => _profileController.isProfileLoading;

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

  void _loadProfileFiles() => _profileController.loadFiles();

  Future<void> _saveProfile(String name) => _profileController.save(name);

  /// Uploads [fileName] to the instrument and marks the panel as busy.
  Future<void> _loadProfile(String fileName) =>
      _profileController.load(fileName);

  Future<void> _deleteProfile(String fileName) =>
      _profileController.delete(fileName);
}
