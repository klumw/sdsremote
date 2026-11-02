import '../tools/control_panel_tool.dart';

/// The panel context passed to the voice app agent with every command.
///
/// [buttons] is empty for panels that do not have a button catalog yet. The
/// Control Panel context is built with [AppPanelContext.controlPanel], which
/// filters model-dependent buttons (CH3/CH4, Search, Digital, navigation) to
/// the connected instrument.
class AppPanelContext {
  const AppPanelContext({
    required this.id,
    required this.title,
    this.buttons = const [],
  });

  /// Stable panel identifier, for example `control_panel` or `profiles`.
  final String id;

  /// Human-readable panel name shown to the agent.
  final String title;

  /// Buttons available in this panel.
  final List<ControlPanelButton> buttons;

  bool get isControlPanel => id == 'control_panel';

  /// Builds the Control Panel context for an instrument with [channelCount]
  /// analog channels.
  factory AppPanelContext.controlPanel({required int channelCount}) {
    final buttons = controlPanelButtons
        .where((button) {
          if (button.channelNumber != null &&
              button.channelNumber! > channelCount) {
            return false;
          }
          if (button.fourChannelOnly && channelCount < 4) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    return AppPanelContext(
      id: 'control_panel',
      title: 'Control Panel ($channelCount-channel)',
      buttons: buttons,
    );
  }
}
