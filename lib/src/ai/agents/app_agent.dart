import 'package:dartantic_ai/dartantic_ai.dart';

import '../tools/app_menu_tool.dart';
import '../tools/control_panel_tool.dart';
import 'app_panel_context.dart';
import 'systemprompts.dart';

/// Result of one voice command processed by the app agent.
class AppAgentResult {
  const AppAgentResult({required this.text, required this.executedActions});

  /// Reply produced by the model.
  final String text;

  /// Actions whose tool call reported success, including `panel:<id>` entries
  /// for Control Panel button presses.
  final List<String> executedActions;

  /// Whether at least one action was executed.
  bool get executed => executedActions.isNotEmpty;
}

/// Agent that maps a whisper transcript to an SDS-Remote menu button or
/// Control Panel button.
///
/// The agent always has the top-bar menu tool. When the active panel is the
/// Control Panel, it additionally receives the complete front-panel button
/// catalog with German/English aliases and the `press_control_panel_button`
/// tool. It never sends SCPI commands or asks for confirmation.
class AppAgent {
  factory AppAgent({
    required String model,
    required AppPanelContext panelContext,
    required AppMenuActionHandler onMenuAction,
    ControlPanelButtonHandler? onPanelButton,
  }) {
    final executedActions = <String>[];
    final hasPanelTool = panelContext.isControlPanel && onPanelButton != null;
    final tools = <Tool>[
      createAppMenuTool(
        onAction: (action) async {
          final result = await onMenuAction(action);
          if (result['success'] == true) {
            executedActions.add(action);
          }
          return result;
        },
        agentName: 'AppAgent',
      ),
      if (hasPanelTool)
        createControlPanelButtonTool(
          buttons: panelContext.buttons,
          onButton: (button) async {
            final result = await onPanelButton(button);
            if (result['success'] == true) {
              executedActions.add('panel:${button.id}');
            }
            return result;
          },
          agentName: 'AppAgent',
        ),
    ];
    final agent = Agent(model, displayName: 'AppAgent', tools: tools);
    return AppAgent._(agent, executedActions, panelContext, hasPanelTool);
  }

  AppAgent._(
    this._agent,
    this._executedActions,
    this._panelContext,
    this._hasPanelTool,
  );

  final Agent _agent;
  final List<String> _executedActions;
  final AppPanelContext _panelContext;
  final bool _hasPanelTool;

  String _buildSystemPrompt() {
    final buffer = StringBuffer(appAgentSystemPrompt);
    buffer.writeln();
    buffer.writeln(
      'CURRENT PANEL: ${_panelContext.title} (${_panelContext.id}).',
    );
    if (_hasPanelTool) {
      buffer.writeln(
        'The Control Panel is active. Press its front-panel buttons with '
        'press_control_panel_button. Button catalog with spoken aliases:',
      );
      buffer.write(describeControlPanelButtons(_panelContext.buttons));
    } else if (_panelContext.isControlPanel) {
      buffer.writeln(
        'The Control Panel is active, but no button handler is available.',
      );
    } else {
      buffer.writeln(
        'No panel-specific buttons are available in this context. Use only '
        'activate_app_menu_button.',
      );
    }
    return buffer.toString();
  }

  /// Processes one voice command and returns the model reply plus the actions
  /// that were actually executed.
  Future<AppAgentResult> send(String command) async {
    _executedActions.clear();
    final result = await _agent.send(
      command,
      history: [ChatMessage.system(_buildSystemPrompt())],
    );
    return AppAgentResult(
      text: result.output.trim(),
      executedActions: List.unmodifiable(_executedActions),
    );
  }
}
