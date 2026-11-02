/// Routing rules for spoken commands while the Control Panel AI assistant is
/// open.
///
/// Most commands belong to the assistant, but app-control commands (close the
/// assistant, switch a top-bar menu panel) must bypass it and go to the
/// App-Agent.
library;

/// Verbs that indicate an app/menu action rather than a question or a scope
/// command.
const List<String> _switchVerbs = [
  'open',
  'show',
  'switch',
  'switching',
  'go',
  'goto',
  'activate',
  'display',
  'bring',
  'close',
  'hide',
  'toggle',
  'select',
  'change',
  'oeffne',
  'oeffnen',
  'zeige',
  'zeig',
  'zeigen',
  'wechsle',
  'wechseln',
  'wechsel',
  'gehe',
  'aktiviere',
  'schalte',
  'umschalten',
  'umschalte',
  'schliesse',
  'schliessen',
  'schliesst',
  'ausblenden',
  'verstecken',
];

/// Names of the top-bar menu actions and the Control Panel AI assistant.
/// The App-Agent resolves the exact action; this list only decides whether the
/// command must bypass the assistant.
const List<String> _menuNames = [
  'control panel',
  'kontrollpanel',
  'steuerpanel',
  'acquire waveform',
  'waveform aufnehmen',
  'messung starten',
  'ai',
  'ai chat',
  'ai panel',
  'ai assistant',
  'assistant',
  'assistent',
  'assistenten',
  'assistentin',
  'ki',
  'main ai',
  'haupt ai',
  'profiles',
  'profile',
  'data logger',
  'datenlogger',
  'logger',
  'bode',
  'bode plot',
  'frequenzgang',
  'macro recorder',
  'makro recorder',
  'makro',
  'help',
  'hilfe',
  'timelapse',
  'zeitraffer',
  'news',
  'neuigkeiten',
  'nachrichten',
  'settings',
  'einstellungen',
  'konfiguration',
  'export data',
  'daten exportieren',
  'save view',
  'save the view',
  'speichern ansicht',
];

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

bool _containsPhrase(String text, String phrase) {
  final normalized = _normalize(phrase);
  if (normalized.isEmpty) return false;
  return RegExp('(^| )${RegExp.escape(normalized)}( |\$)').hasMatch(text);
}

/// Whether [transcript] is an app-control command that must go to the
/// App-Agent even while the Control Panel AI assistant is open.
///
/// The rule is intentionally conservative: a command needs both an action verb
/// ("open", "switch", "close", "öffne", "schließe", …) and a top-bar menu name
/// ("Profiles", "Settings", "AI", …). A plain question such as "What is the
/// trigger mode?" stays with the assistant.
bool shouldBypassControlPanelAssistant(String transcript) {
  final text = _normalize(transcript);
  if (text.isEmpty) return false;
  final hasVerb = _switchVerbs.any((verb) => _containsPhrase(text, verb));
  if (!hasVerb) return false;
  return _menuNames.any((name) => _containsPhrase(text, name));
}
