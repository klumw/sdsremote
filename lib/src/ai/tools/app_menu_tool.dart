import 'package:dartantic_ai/dartantic_ai.dart';

import '../../core/logger.dart';

/// Executes one app menu action and reports whether it could be performed.
typedef AppMenuActionHandler =
    Future<Map<String, dynamic>> Function(String action);

/// One action the voice app agent can trigger.
class AppMenuAction {
  const AppMenuAction(this.id, this.label, this.description);

  /// Stable identifier used in the tool schema and the action handler.
  final String id;

  /// Button label shown in the SDS-Remote main window.
  final String label;

  /// What activating the button does.
  final String description;
}

/// All menu buttons the app agent may activate.
const List<AppMenuAction> appMenuActions = [
  AppMenuAction(
    'control_panel',
    'Control Panel',
    'Open the Control Panel by capturing the oscilloscope screen.',
  ),
  AppMenuAction(
    'acquire_waveform',
    'Acquire Waveform',
    'Start a waveform acquisition from the oscilloscope.',
  ),
  AppMenuAction(
    'ai_chat',
    'AI',
    'Show or hide the main-window AI chat panel. In the Control Panel '
        'context, "AI" or "AI assistant" means the Control Panel AI '
        'assistant (control_panel_ai) instead; use this action only for '
        '"AI Chat", "AI panel" or "main AI".',
  ),
  AppMenuAction(
    'profiles',
    'Profiles',
    'Show or hide the device profiles panel.',
  ),
  AppMenuAction(
    'data_logger',
    'Data Logger',
    'Show or hide the Data Logger panel.',
  ),
  AppMenuAction('bode', 'Bode', 'Show or hide the Bode plot panel.'),
  AppMenuAction(
    'macro_recorder',
    'Macro Recorder',
    'Show or hide the Macro Recorder panel.',
  ),
  AppMenuAction('help', 'Help', 'Open or close the SDS-Remote help window.'),
  AppMenuAction(
    'timelapse',
    'Timelapse',
    'Open the timelapse dialog, or stop a running timelapse.',
  ),
  AppMenuAction('news', 'News', 'Open the news dialog.'),
  AppMenuAction('settings', 'Settings', 'Open the settings dialog.'),
  AppMenuAction('save', 'Save', 'Save the current view, report, or CSV data.'),
  AppMenuAction(
    'export_data',
    'Export Data',
    'Open the waveform export dialog.',
  ),
];

/// Creates the tool that activates an SDS-Remote menu button.
///
/// The agent must call this tool immediately when the spoken command clearly
/// refers to a menu button; no confirmation step is involved.
Tool<Map<String, dynamic>> createAppMenuTool({
  required AppMenuActionHandler onAction,
  String agentName = 'AppAgent',
}) {
  final actionDescriptions = appMenuActions
      .map(
        (action) => '- ${action.id}: ${action.label} — ${action.description}',
      )
      .join('\n');

  return Tool<Map<String, dynamic>>(
    name: 'activate_app_menu_button',
    description:
        'Activate exactly one menu button in the SDS-Remote main window. '
        'Call this tool immediately when the user command refers to a menu '
        'button; never ask for confirmation. Available actions:\n'
        '$actionDescriptions\n'
        'If the command does not clearly refer to one of these actions, do '
        'not call the tool and reply briefly that the command is unsupported.',
    inputSchema: Schema.fromMap({
      'type': 'object',
      'properties': <String, Object?>{
        'action': <String, Object?>{
          'type': 'string',
          'enum': appMenuActions.map((action) => action.id).toList(),
          'description': 'Exact ID of the menu button to activate.',
        },
      },
      'required': <String>['action'],
    }),
    onCall: (args) async {
      final action = (args['action'] as String?)?.trim() ?? '';
      final logger = AppLogger(agentName: agentName, toolName: 'menu');
      if (action.isEmpty) {
        const result = <String, dynamic>{
          'success': false,
          'action': '',
          'message': 'No menu action was given.',
        };
        await logger.logToolCall(input: args, output: result);
        return result;
      }

      final result = await onAction(action);
      await logger.logToolCall(input: args, output: result);
      return result;
    },
  );
}
