import 'package:dartantic_ai/dartantic_ai.dart';

import '../core/logger.dart';
import 'agents/app_agent.dart';
import 'agents/app_panel_context.dart';
import 'ai_settings.dart';
import 'tools/app_menu_tool.dart';
import 'tools/control_panel_tool.dart';

/// Thrown when the voice app agent cannot be started.
class AppAgentException implements Exception {
  const AppAgentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Runs the voice app agent with the AI settings from the settings panel.
///
/// One agent is created per command, so no conversation state leaks between
/// unrelated spoken commands.
class AppAgentService {
  Future<AppAgentResult> run({
    required AiSettings settings,
    required String transcript,
    required AppPanelContext panelContext,
    required AppMenuActionHandler onMenuAction,
    ControlPanelButtonHandler? onPanelButton,
  }) async {
    if (!settings.isConfigured) {
      throw const AppAgentException(
        'AI is not configured. Set the provider, API token and model in '
        'Settings.',
      );
    }

    // dartantic reads API keys from this static map, which takes priority over
    // the process environment.
    Agent.environment[settings.apiKeyName] = settings.apiToken;

    final logger = AppLogger(agentName: 'AppAgentService', toolName: 'run');
    await logger.log(
      'Voice command: "$transcript" (panel: ${panelContext.title})',
    );

    final agent = AppAgent(
      model: settings.model,
      panelContext: panelContext,
      onMenuAction: onMenuAction,
      onPanelButton: onPanelButton,
    );
    final result = await agent.send(transcript);

    await logger.log(
      'Voice command result: executed=${result.executedActions}, '
      'reply="${result.text}"',
    );
    return result;
  }
}
