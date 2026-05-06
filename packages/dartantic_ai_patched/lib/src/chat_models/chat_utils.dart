/// Safely appends a path to a base URL.
///
/// Unlike [Uri.resolve], this function preserves the existing path in the
/// base URL and appends the new path segment to it.
///
/// Examples:
/// - appendPath(Uri.parse('https://api.example.com/v1'), 'models')
///   → 'https://api.example.com/v1/models'
/// - appendPath(Uri.parse('https://api.example.com/v1/'), 'models')
///   → 'https://api.example.com/v1/models'
/// - appendPath(Uri.parse('http://localhost:11434/api'), 'tags')
///   → 'http://localhost:11434/api/tags'
Uri appendPath(Uri baseUrl, String path) {
  final baseStr = baseUrl.toString();
  final separator = baseStr.endsWith('/') ? '' : '/';
  return Uri.parse('$baseStr$separator$path');
}
