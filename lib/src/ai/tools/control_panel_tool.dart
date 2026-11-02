import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// How a Control Panel button is handled.
enum ControlPanelButtonKind {
  /// A momentary front-panel button handled by `_handleButtonPress`.
  button,

  /// A channel on/off button; also selects the channel for the shared knobs.
  channel,

  /// A soft key below the display (M1-M6).
  softKey,

  /// The round MENU button.
  menu,

  /// The periodic screen capture toggle.
  autoCapture,

  /// The live screen (VNC) toggle.
  liveScreen,

  /// The Control Panel AI assistant overlay.
  aiAssistant,
}

/// One button on the SDS-Remote Control Panel, including its spoken aliases.
class ControlPanelButton {
  const ControlPanelButton({
    required this.id,
    required this.label,
    required this.kind,
    this.aliases = const [],
    this.description = '',
    this.channelNumber,
    this.softKeyNumber,
    this.fourChannelOnly = false,
  });

  /// Stable identifier used in the tool schema and execution handler.
  final String id;

  /// Button label shown in the Control Panel.
  final String label;

  /// What pressing the button does.
  final String description;

  /// German and English names a user may speak for this button.
  final List<String> aliases;

  final ControlPanelButtonKind kind;

  /// Channel number for [ControlPanelButtonKind.channel].
  final int? channelNumber;

  /// Soft-key number (1-6) for [ControlPanelButtonKind.softKey].
  final int? softKeyNumber;

  /// Whether the button exists only on four-channel instruments.
  final bool fourChannelOnly;
}

/// Complete Control Panel button catalog.
const List<ControlPanelButton> controlPanelButtons = [
  ControlPanelButton(
    id: 'menu',
    label: 'Menu',
    kind: ControlPanelButtonKind.menu,
    description: 'Open the oscilloscope main menu.',
    aliases: [
      'menu',
      'menü',
      'menue',
      'main menu',
      'hauptmenü',
      'hauptmenue',
      'menu button',
      'menütaste',
      'menue taste',
    ],
  ),
  ControlPanelButton(
    id: 'cursors',
    label: 'Cursors',
    kind: ControlPanelButtonKind.button,
    description: 'Open the cursors menu.',
    aliases: [
      'cursor',
      'cursors',
      'cursor menu',
      'cursors menu',
      'messcursor',
      'messzeiger',
    ],
  ),
  ControlPanelButton(
    id: 'acquire',
    label: 'Acquire',
    kind: ControlPanelButtonKind.button,
    description: 'Open the acquisition menu of the oscilloscope.',
    aliases: [
      'acquire',
      'erfassen',
      'aufnehmen',
      'akquirieren',
      'acquire menu',
      'erfassungsmenü',
      'erfassungsmenue',
    ],
  ),
  ControlPanelButton(
    id: 'save_recall',
    label: 'Save/Recall',
    kind: ControlPanelButtonKind.button,
    description: 'Open the Save/Recall menu of the oscilloscope.',
    aliases: [
      'save recall',
      'save/recall',
      'recall',
      'speichern laden',
      'speichern/laden',
      'speichern und laden',
      'rückruf',
      'rueckruf',
    ],
  ),
  ControlPanelButton(
    id: 'measure',
    label: 'Measure',
    kind: ControlPanelButtonKind.button,
    description: 'Open the measurement menu.',
    aliases: [
      'measure',
      'measurement',
      'messen',
      'messung',
      'messmenü',
      'messmenue',
    ],
  ),
  ControlPanelButton(
    id: 'clear_sweeps',
    label: 'Clear Sweeps',
    kind: ControlPanelButtonKind.button,
    description: 'Clear the acquired sweeps.',
    aliases: [
      'clear sweeps',
      'clear sweep',
      'sweeps löschen',
      'sweeps loeschen',
      'sweep löschen',
      'sweep loeschen',
      'löschen',
      'loeschen',
      'clear',
    ],
  ),
  ControlPanelButton(
    id: 'utility',
    label: 'Utility',
    kind: ControlPanelButtonKind.button,
    description: 'Open the utility menu.',
    aliases: [
      'utility',
      'utilities',
      'werkzeuge',
      'dienstprogramm',
      'utility menu',
    ],
  ),
  ControlPanelButton(
    id: 'default',
    label: 'Default',
    kind: ControlPanelButtonKind.button,
    description: 'Restore the oscilloscope default setup.',
    aliases: [
      'default',
      'reset',
      'standard',
      'zurücksetzen',
      'zuruecksetzen',
      'werkseinstellung',
      'default setup',
    ],
  ),
  ControlPanelButton(
    id: 'display_persist',
    label: 'Display/Persist',
    kind: ControlPanelButtonKind.button,
    description: 'Open the display and persistence menu.',
    aliases: [
      'display persist',
      'display/persist',
      'persistence',
      'persist',
      'anzeige',
      'persistenz',
      'display menu',
    ],
  ),
  ControlPanelButton(
    id: 'print',
    label: 'Print',
    kind: ControlPanelButtonKind.button,
    description: 'Print the current screen.',
    aliases: [
      'print',
      'drucken',
      'ausdrucken',
      'ausdruck',
      'screenshot drucken',
    ],
  ),
  ControlPanelButton(
    id: 'history',
    label: 'History',
    kind: ControlPanelButtonKind.button,
    description: 'Open the waveform history.',
    aliases: ['history', 'verlauf', 'historie', 'history menu'],
  ),
  ControlPanelButton(
    id: 'decode',
    label: 'Decode',
    kind: ControlPanelButtonKind.button,
    description: 'Open the protocol decode menu.',
    aliases: [
      'decode',
      'decoding',
      'dekodieren',
      'dekodierung',
      'decoder',
      'protokoll',
    ],
  ),
  ControlPanelButton(
    id: 'run_stop',
    label: 'Run/Stop',
    kind: ControlPanelButtonKind.button,
    description: 'Start or stop the acquisition.',
    aliases: [
      'run stop',
      'run/stop',
      'run',
      'stop',
      'start stop',
      'starten',
      'stoppen',
      'stopp',
      'laufen',
      'anhalten',
      'weiterlaufen',
      'run stop button',
    ],
  ),
  ControlPanelButton(
    id: 'auto_setup',
    label: 'Auto Setup',
    kind: ControlPanelButtonKind.button,
    description: 'Run the oscilloscope Auto Setup.',
    aliases: [
      'auto setup',
      'autosetup',
      'auto-setup',
      'aset',
      'a set',
      'automatik setup',
      'automatisches setup',
      'automatisches einrichten',
      'auto einrichten',
      'auto setup button',
      'autosetup taste',
    ],
  ),
  ControlPanelButton(
    id: 'math',
    label: 'Math',
    kind: ControlPanelButtonKind.button,
    description: 'Open the math menu.',
    aliases: [
      'math',
      'mathematik',
      'rechnen',
      'math menu',
      'math menü',
      'math menue',
    ],
  ),
  ControlPanelButton(
    id: 'ref',
    label: 'Ref',
    kind: ControlPanelButtonKind.button,
    description: 'Open the reference waveform menu.',
    aliases: ['ref', 'reference', 'referenz', 'referenzsignal', 'ref menu'],
  ),
  ControlPanelButton(
    id: 'ch1',
    label: 'CH1',
    kind: ControlPanelButtonKind.channel,
    channelNumber: 1,
    description: 'Toggle channel 1 and select it for the shared knobs.',
    aliases: [
      'ch1',
      'ch 1',
      'channel 1',
      'channel one',
      'kanal 1',
      'kanal eins',
    ],
  ),
  ControlPanelButton(
    id: 'ch2',
    label: 'CH2',
    kind: ControlPanelButtonKind.channel,
    channelNumber: 2,
    description: 'Toggle channel 2 and select it for the shared knobs.',
    aliases: [
      'ch2',
      'ch 2',
      'channel 2',
      'channel two',
      'kanal 2',
      'kanal zwei',
    ],
  ),
  ControlPanelButton(
    id: 'ch3',
    label: 'CH3',
    kind: ControlPanelButtonKind.channel,
    channelNumber: 3,
    fourChannelOnly: true,
    description: 'Toggle channel 3 and select it for the shared knobs.',
    aliases: [
      'ch3',
      'ch 3',
      'channel 3',
      'channel three',
      'kanal 3',
      'kanal drei',
    ],
  ),
  ControlPanelButton(
    id: 'ch4',
    label: 'CH4',
    kind: ControlPanelButtonKind.channel,
    channelNumber: 4,
    fourChannelOnly: true,
    description: 'Toggle channel 4 and select it for the shared knobs.',
    aliases: [
      'ch4',
      'ch 4',
      'channel 4',
      'channel four',
      'kanal 4',
      'kanal vier',
    ],
  ),
  ControlPanelButton(
    id: 'roll',
    label: 'Roll',
    kind: ControlPanelButtonKind.button,
    description: 'Switch to roll mode.',
    aliases: ['roll', 'rollen', 'rollmodus', 'roll mode'],
  ),
  ControlPanelButton(
    id: 'search',
    label: 'Search',
    kind: ControlPanelButtonKind.button,
    fourChannelOnly: true,
    description: 'Open the search function (four-channel models).',
    aliases: ['search', 'suche', 'suchen', 'search menu', 'search button'],
  ),
  ControlPanelButton(
    id: 'trigger_setup',
    label: 'Setup',
    kind: ControlPanelButtonKind.button,
    description: 'Open the trigger setup menu.',
    aliases: [
      'setup',
      'trigger setup',
      'trigger einstellen',
      'trigger menü',
      'trigger menue',
      'trigger setup button',
      'trigger setup taste',
    ],
  ),
  ControlPanelButton(
    id: 'trigger_auto',
    label: 'Auto',
    kind: ControlPanelButtonKind.button,
    description: 'Set the trigger mode to Auto.',
    aliases: [
      'auto',
      'trigger auto',
      'auto trigger',
      'automatik',
      'automatischer trigger',
      'automatischer auslöser',
      'automatischer ausloeser',
    ],
  ),
  ControlPanelButton(
    id: 'trigger_normal',
    label: 'Normal',
    kind: ControlPanelButtonKind.button,
    description: 'Set the trigger mode to Normal.',
    aliases: [
      'normal',
      'normal trigger',
      'trigger normal',
      'normalmodus',
      'normal mode',
    ],
  ),
  ControlPanelButton(
    id: 'trigger_single',
    label: 'Single',
    kind: ControlPanelButtonKind.button,
    description: 'Set the trigger mode to Single.',
    aliases: [
      'single',
      'single trigger',
      'einzelschuss',
      'einzelauslösung',
      'einzelausloesung',
      'single shot',
      'einzel',
    ],
  ),
  ControlPanelButton(
    id: 'digital',
    label: 'Digital',
    kind: ControlPanelButtonKind.button,
    fourChannelOnly: true,
    description: 'Open the digital channel menu (four-channel models).',
    aliases: [
      'digital',
      'digital channels',
      'digitalkanäle',
      'digitalkanaele',
      'digital menu',
    ],
  ),
  ControlPanelButton(
    id: 'navigate',
    label: 'Navigate',
    kind: ControlPanelButtonKind.button,
    fourChannelOnly: true,
    description: 'Open the navigation menu (four-channel models).',
    aliases: ['navigate', 'navigation', 'navigieren', 'navigate button'],
  ),
  ControlPanelButton(
    id: 'arrow_left',
    label: 'Arrow Left',
    kind: ControlPanelButtonKind.button,
    fourChannelOnly: true,
    description: 'Press the left arrow (four-channel models).',
    aliases: [
      'arrow left',
      'left',
      'links',
      'pfeil links',
      'left arrow',
      'pfeil nach links',
    ],
  ),
  ControlPanelButton(
    id: 'square',
    label: 'Square',
    kind: ControlPanelButtonKind.button,
    fourChannelOnly: true,
    description: 'Press the square button (four-channel models).',
    aliases: ['square', 'quadrat', 'viereck', 'rechteck', 'square button'],
  ),
  ControlPanelButton(
    id: 'arrow_right',
    label: 'Arrow Right',
    kind: ControlPanelButtonKind.button,
    fourChannelOnly: true,
    description: 'Press the right arrow (four-channel models).',
    aliases: [
      'arrow right',
      'right',
      'rechts',
      'pfeil rechts',
      'right arrow',
      'pfeil nach rechts',
    ],
  ),
  ControlPanelButton(
    id: 'softkey_1',
    label: 'M1',
    kind: ControlPanelButtonKind.softKey,
    softKeyNumber: 1,
    description: 'Press soft key M1 below the display.',
    aliases: [
      'm1',
      'm 1',
      'softkey 1',
      'soft key 1',
      'softkey1',
      'menu button 1',
      'funktionstaste 1',
      'menütaste 1',
      'menue taste 1',
    ],
  ),
  ControlPanelButton(
    id: 'softkey_2',
    label: 'M2',
    kind: ControlPanelButtonKind.softKey,
    softKeyNumber: 2,
    description: 'Press soft key M2 below the display.',
    aliases: [
      'm2',
      'm 2',
      'softkey 2',
      'soft key 2',
      'softkey2',
      'menu button 2',
      'funktionstaste 2',
      'menütaste 2',
      'menue taste 2',
    ],
  ),
  ControlPanelButton(
    id: 'softkey_3',
    label: 'M3',
    kind: ControlPanelButtonKind.softKey,
    softKeyNumber: 3,
    description: 'Press soft key M3 below the display.',
    aliases: [
      'm3',
      'm 3',
      'softkey 3',
      'soft key 3',
      'softkey3',
      'menu button 3',
      'funktionstaste 3',
      'menütaste 3',
      'menue taste 3',
    ],
  ),
  ControlPanelButton(
    id: 'softkey_4',
    label: 'M4',
    kind: ControlPanelButtonKind.softKey,
    softKeyNumber: 4,
    description: 'Press soft key M4 below the display.',
    aliases: [
      'm4',
      'm 4',
      'softkey 4',
      'soft key 4',
      'softkey4',
      'menu button 4',
      'funktionstaste 4',
      'menütaste 4',
      'menue taste 4',
    ],
  ),
  ControlPanelButton(
    id: 'softkey_5',
    label: 'M5',
    kind: ControlPanelButtonKind.softKey,
    softKeyNumber: 5,
    description: 'Press soft key M5 below the display.',
    aliases: [
      'm5',
      'm 5',
      'softkey 5',
      'soft key 5',
      'softkey5',
      'menu button 5',
      'funktionstaste 5',
      'menütaste 5',
      'menue taste 5',
    ],
  ),
  ControlPanelButton(
    id: 'softkey_6',
    label: 'M6',
    kind: ControlPanelButtonKind.softKey,
    softKeyNumber: 6,
    description: 'Press soft key M6 below the display.',
    aliases: [
      'm6',
      'm 6',
      'softkey 6',
      'soft key 6',
      'softkey6',
      'menu button 6',
      'funktionstaste 6',
      'menütaste 6',
      'menue taste 6',
    ],
  ),
  ControlPanelButton(
    id: 'auto_capture',
    label: 'Auto Capture',
    kind: ControlPanelButtonKind.autoCapture,
    description: 'Toggle the periodic screen capture.',
    aliases: [
      'auto capture',
      'autocapture',
      'automatische aufnahme',
      'automatischer screenshot',
      'auto screenshot',
      'automatische bildschirmaufnahme',
      'auto capture taste',
    ],
  ),
  ControlPanelButton(
    id: 'live_screen',
    label: 'Live Screen',
    kind: ControlPanelButtonKind.liveScreen,
    description: 'Toggle the live screen (VNC).',
    aliases: [
      'live',
      'live screen',
      'live bild',
      'livebild',
      'vnc',
      'live screen taste',
    ],
  ),
  ControlPanelButton(
    id: 'control_panel_ai',
    label: 'AI Assistant',
    kind: ControlPanelButtonKind.aiAssistant,
    description: 'Open the Control Panel AI assistant overlay.',
    aliases: [
      'ai',
      'ai assistant',
      'assistant',
      'control panel ai',
      'control panel assistant',
      'ki',
      'ki assistent',
      'ki-assistent',
      'assistent',
      'ai control assistant',
      'sparkle',
    ],
  ),
];

/// Normalizes button names and aliases for matching.
///
/// Lower-cases the text, transliterates German umlauts, removes punctuation
/// and collapses whitespace. "Save/Recall" and "save recall" therefore match,
/// and "Menü" matches "menue".
String normalizeControlPanelButtonText(String input) {
  var value = input.toLowerCase().trim();
  value = value
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss');
  value = value.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Resolves a spoken button name, label, ID or alias to a catalog entry.
///
/// Exact matches win. Otherwise the longest alias contained in [input] is
/// used, so "press Auto Setup" resolves to Auto Setup rather than the shorter
/// "Setup" alias of the trigger button.
ControlPanelButton? findControlPanelButton(
  String input, {
  List<ControlPanelButton> buttons = controlPanelButtons,
}) {
  final normalized = normalizeControlPanelButtonText(input);
  if (normalized.isEmpty) return null;

  for (final button in buttons) {
    if (normalizeControlPanelButtonText(button.id) == normalized) {
      return button;
    }
  }
  for (final button in buttons) {
    for (final alias in [button.label, ...button.aliases]) {
      if (normalizeControlPanelButtonText(alias) == normalized) {
        return button;
      }
    }
  }

  ControlPanelButton? bestButton;
  var bestLength = 0;
  for (final button in buttons) {
    for (final alias in [button.label, ...button.aliases]) {
      final normalizedAlias = normalizeControlPanelButtonText(alias);
      if (normalizedAlias.isEmpty) continue;
      final pattern = RegExp('(^| )${RegExp.escape(normalizedAlias)}( |\$)');
      if (pattern.hasMatch(normalized) && normalizedAlias.length > bestLength) {
        bestButton = button;
        bestLength = normalizedAlias.length;
      }
    }
  }
  return bestButton;
}

/// Human-readable catalog for the agent prompt and tool description.
String describeControlPanelButtons(List<ControlPanelButton> buttons) {
  final buffer = StringBuffer();
  for (final button in buttons) {
    final aliases = button.aliases.isEmpty
        ? ''
        : ' | spoken aliases: ${button.aliases.join(', ')}';
    buffer.writeln('- ${button.id}: ${button.label}$aliases');
  }
  return buffer.toString();
}

/// Executes one Control Panel button and reports whether it could be pressed.
typedef ControlPanelButtonHandler =
    Future<Map<String, dynamic>> Function(ControlPanelButton button);

/// Creates the tool that presses a button on the active Control Panel.
Tool<Map<String, dynamic>> createControlPanelButtonTool({
  required List<ControlPanelButton> buttons,
  required ControlPanelButtonHandler onButton,
  String agentName = 'AppAgent',
}) {
  final catalog = describeControlPanelButtons(buttons);

  return Tool<Map<String, dynamic>>(
    name: 'press_control_panel_button',
    description:
        'Press a button on the currently active SDS-Remote Control Panel. '
        'Use this tool immediately when the user asks to press, toggle or '
        'activate a front-panel button. Accepts the button ID, its label, or '
        'any spoken alias (for example "auto_setup", "Auto Setup" or "ASET"). '
        'Only available while the Control Panel is the active panel. '
        'Do not use it for knob rotations.\n'
        'Available buttons:\n$catalog',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, Object?>{
        'button': <String, Object?>{
          'type': 'string',
          'description':
              'Button ID, label or alias, for example "auto_setup", '
              '"Auto Setup", "ASET", "ch1" or "Channel 1".',
        },
      },
      'required': <String>['button'],
    }),
    onCall: (args) async {
      final raw = (args['button'] as String?)?.trim() ?? '';
      final logger = AppLogger(
        agentName: agentName,
        toolName: 'control_panel_button',
      );
      final button = findControlPanelButton(raw, buttons: buttons);
      if (button == null) {
        final result = <String, dynamic>{
          'success': false,
          'button': raw,
          'message':
              'Unknown Control Panel button "$raw". Use a button ID or one '
              'of the spoken aliases from the Control Panel context.',
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      final result = await onButton(button);
      await logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}
