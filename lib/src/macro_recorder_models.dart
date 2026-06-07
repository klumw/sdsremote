/// Metadata for a single macro file.
///
/// Mirrors the pattern established by [ProfileInfo] in `osci_profiles_panel.dart`.
class MacroInfo {
  /// The full filename including the `.m` extension, e.g. `"my_test.m"`.
  final String fileName;

  /// The last-modified timestamp of the file.
  final DateTime lastModified;

  const MacroInfo({
    required this.fileName,
    required this.lastModified,
  });
}
