/// Short commands that ask an assistant to read fresh data from the
/// oscilloscope.
///
/// The Waveform AI assistant and the Control Panel AI assistant treat the
/// words "Aufnahme", "record", "update" and "snapshot" as direct capture
/// commands: the waveform assistant reads a new waveform, the control panel
/// assistant fetches a new screen dump. The check is deliberately
/// conservative — only short phrases built from a trigger word and a few
/// neutral filler words match — so questions such as "What is the record
/// length?" still go to the AI model.
library;

const Set<String> _triggers = {
  'aufnahme',
  'aufnehmen',
  'record',
  'update',
  'snapshot',
};

const Set<String> _fillers = {
  'a',
  'an',
  'bitte',
  'can',
  'capture',
  'could',
  'das',
  'do',
  'du',
  'ein',
  'eine',
  'einen',
  'ich',
  'jetzt',
  'kann',
  'kannst',
  'koennte',
  'koenntest',
  'mach',
  'machen',
  'mal',
  'mir',
  'moechte',
  'moechtest',
  'neu',
  'neue',
  'neuen',
  'neues',
  'new',
  'now',
  'oscilloscope',
  'oszi',
  'oszilloskop',
  'please',
  'scope',
  'screen',
  'screenshot',
  'signal',
  'the',
  'waveform',
  'you',
};

/// Maximum number of words in a command phrase. Longer sentences are treated
/// as normal conversation and reach the AI model.
const int _maxWords = 8;

String _normalize(String input) {
  var value = input.toLowerCase().trim();
  value = value
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss');
  value = value.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Whether [text] is a short capture command such as "Aufnahme", "record",
/// "update" or "snapshot".
bool isCaptureCommand(String text) {
  if (text.contains('?')) return false;
  final normalized = _normalize(text);
  if (normalized.isEmpty) return false;
  final words = normalized.split(' ');
  if (words.length > _maxWords) return false;

  var hasTrigger = false;
  for (final word in words) {
    if (_triggers.contains(word)) {
      hasTrigger = true;
    } else if (!_fillers.contains(word)) {
      return false;
    }
  }
  return hasTrigger;
}
