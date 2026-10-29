import 'package:flutter/material.dart';

import '../ai/ai_settings.dart';
import '../ai/control_panel_chat_controller.dart';
import 'osci_chat_window.dart';

/// Overlay that hosts the Control Panel's AI chat on top of the controls.
///
/// The widget is always present in the control panel's stack so it can
/// configure the shared [controller] when the panel is mounted. It renders
/// nothing while the chat is collapsed and a full-size chat window while it is
/// open. The header's close button collapses the chat again.
class ControlPanelChatOverlay extends StatefulWidget {
  const ControlPanelChatOverlay({
    super.key,
    required this.controller,
    this.aiSettings,
    this.vxi11Host,
  });

  /// Owns the transcript and the agent for the Control Panel chat.
  final ControlPanelChatController controller;

  /// AI provider/token/model settings; null disables the assistant.
  final AiSettings? aiSettings;

  /// Instrument address used by the agent's instrument sub-agent.
  final String? vxi11Host;

  @override
  State<ControlPanelChatOverlay> createState() =>
      _ControlPanelChatOverlayState();
}

class _ControlPanelChatOverlayState extends State<ControlPanelChatOverlay>
    with SingleTickerProviderStateMixin {
  /// Duration of the slide-in animation. Long enough to be perceived as a
  /// deliberate movement rather than a jump.
  static const Duration _showDuration = Duration(milliseconds: 2000);

  /// Duration of the slide-out animation.
  static const Duration _hideDuration = Duration(milliseconds: 1600);

  late final AnimationController _animationController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: _showDuration,
      reverseDuration: _hideDuration,
    );
    final curved = CurvedAnimation(
      parent: _animationController,
      // S-curve: slow start, fast middle, gentle settle — and the same
      // motion in reverse when the overlay slides out again.
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(curved);
    _fadeAnimation = curved;

    widget.controller.addListener(_onChatControllerChanged);
    _syncAnimation();
    _scheduleConfigure();
  }

  @override
  void didUpdateWidget(covariant ControlPanelChatOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChatControllerChanged);
      widget.controller.addListener(_onChatControllerChanged);
      _syncAnimation();
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.aiSettings != widget.aiSettings ||
        oldWidget.vxi11Host != widget.vxi11Host) {
      _scheduleConfigure();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChatControllerChanged);
    _animationController.dispose();
    super.dispose();
  }

  /// Starts the slide-in or slide-out animation for the current chat state.
  void _onChatControllerChanged() => _syncAnimation();

  void _syncAnimation() {
    if (widget.controller.isOpen && widget.controller.isAvailable) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  /// Configures the controller after the current frame.
  ///
  /// `configure` notifies its listeners; doing that from `initState` or
  /// `didUpdateWidget` would mark the AI button's [ListenableBuilder] dirty
  /// while the widget tree is still building.
  void _scheduleConfigure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _configure();
    });
  }

  void _configure() {
    widget.controller.configure(widget.aiSettings, vxi11Host: widget.vxi11Host);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, _) {
        return ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final visible =
                widget.controller.isAvailable &&
                (widget.controller.isOpen || _animationController.value > 0);
            if (!visible) return const SizedBox.shrink();

            return IgnorePointer(
              ignoring: !widget.controller.isOpen,
              child: SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: _buildChatCard(),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildChatCard() {
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0A192F),
        border: Border.all(color: const Color(0xFF475569)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(-6, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 2),
            child: Row(
              children: [
                const Icon(
                  Icons.auto_awesome,
                  size: 16,
                  color: Colors.cyanAccent,
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 18,
                  ),
                  tooltip: 'Collapse AI Control Assistant',
                  onPressed: widget.controller.toggleOpen,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: ChatWindow(
                chatMessages: widget.controller.messages,
                isChatting: widget.controller.isChatting,
                isInitialized: widget.controller.isInitialized,
                onSendMessage: widget.controller.send,
                onCancel: widget.controller.cancel,
                hintText: 'Ask the control panel assistant...',
                emptyStateText:
                    'Ask me to configure the oscilloscope.\n'
                    'Examples: "Set CH1 to 200 mV/div with 0.2 V offset, '
                    'then autoset"',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
