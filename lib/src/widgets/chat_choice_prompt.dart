import 'package:flutter/material.dart';

import '../ai/chat_choice.dart';
import 'scroll_hint.dart';

/// Reusable radio-button question rendered inside an AI chat panel.
///
/// The widget is presentation-only: the owning chat controller holds the
/// pending [ChatChoiceRequest] through its [ChatChoicePromptController], so
/// any assistant can reuse the same UI. A radio button confirms the answer
/// immediately. When the request allows text, the widget also shows a
/// free-text field for corrections and a submit button; while a correction is
/// typed, a selection is only recorded until that button is pressed so the
/// typed text is not lost.
///
/// The prompt animates in from the bottom and pulses its accent border while
/// it waits, so the user notices that an input is required.
class ChatChoicePrompt extends StatefulWidget {
  const ChatChoicePrompt({
    super.key,
    required this.request,
    required this.onSelect,
    this.onTextChanged,
    this.onSubmit,
    this.canSubmit = false,
    this.selectedValue,
  });

  /// Pending question and its options.
  final ChatChoiceRequest request;

  /// Called when the user selects an option.
  ///
  /// Selection is the confirmation; the owning controller submits the value
  /// and closes the prompt. When the request allows text, the controller only
  /// records the selection until the user presses the submit button.
  final ValueChanged<String> onSelect;

  /// Called when the user edits the optional free-text field.
  final ValueChanged<String>? onTextChanged;

  /// Called when the user submits the free text or the selected option.
  final VoidCallback? onSubmit;

  /// Whether the submit button is enabled.
  final bool canSubmit;

  /// Currently selected option value, or null.
  ///
  /// The owning controller is the source of truth; feeding the value back into
  /// [RadioGroup.groupValue] keeps the radio button visibly selected while a
  /// free-text prompt stays open.
  final String? selectedValue;

  @override
  State<ChatChoicePrompt> createState() => _ChatChoicePromptState();
}

class _ChatChoicePromptState extends State<ChatChoicePrompt>
    with TickerProviderStateMixin {
  late final AnimationController _entry;
  late final AnimationController _pulse;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  final TextEditingController _textController = TextEditingController();

  @override
  void didUpdateWidget(covariant ChatChoicePrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request != widget.request) {
      _textController.clear();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _entry.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..forward();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fade = CurvedAnimation(parent: _entry, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic));
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final glow = 0.45 + 0.55 * _pulse.value;
            return Container(
              key: const ValueKey('chat-choice-prompt'),
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: const Color(0xFF10263D),
                border: Border.all(
                  color: Colors.lightBlueAccent.withValues(alpha: glow),
                  width: 1.2,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.lightBlueAccent.withValues(
                      alpha: 0.18 * _pulse.value,
                    ),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Material(
            type: MaterialType.transparency,
            child: ScrollHint(
              maxHeight: 420,
              background: const Color(0xFF10263D),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.help_outline,
                        size: 18,
                        color: Colors.lightBlueAccent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.request.question,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  RadioGroup<String>(
                    groupValue: widget.selectedValue,
                    onChanged: (value) {
                      if (value != null) widget.onSelect(value);
                    },
                    child: Column(
                      children: [
                        for (final option in widget.request.options)
                          RadioListTile<String>(
                            key: ValueKey('chat-choice-option-${option.value}'),
                            value: option.value,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            activeColor: Colors.lightBlueAccent,
                            title: Text(
                              option.label,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                height: 1.3,
                              ),
                            ),
                            subtitle: option.description == null
                                ? null
                                : Text(
                                    option.description!,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      height: 1.35,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.request.allowText) ...[
                    const SizedBox(height: 6),
                    TextField(
                      key: const ValueKey('chat-choice-text'),
                      controller: _textController,
                      onChanged: widget.onTextChanged,
                      minLines: 1,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        labelText:
                            widget.request.textLabel ?? 'Correction (optional)',
                        hintText: widget.request.textHint,
                        labelStyle: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                        hintStyle: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Colors.lightBlueAccent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        key: const ValueKey('chat-choice-submit'),
                        onPressed: widget.canSubmit ? widget.onSubmit : null,
                        child: Text(
                          widget.request.textSubmitLabel ?? 'Continue',
                          style: const TextStyle(
                            color: Colors.lightBlueAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
