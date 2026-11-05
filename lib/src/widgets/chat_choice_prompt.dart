import 'package:flutter/material.dart';

import '../ai/chat_choice.dart';

/// Reusable radio-button question rendered inside an AI chat panel.
///
/// The widget is presentation-only: the owning chat controller holds the
/// pending [ChatChoiceRequest] through its [ChatChoicePromptController], so
/// any assistant can reuse the same UI. Selecting a radio button confirms the
/// answer immediately; there is no separate confirm or cancel action.
class ChatChoicePrompt extends StatelessWidget {
  const ChatChoicePrompt({
    super.key,
    required this.request,
    required this.onSelect,
  });

  /// Pending question and its options.
  final ChatChoiceRequest request;

  /// Called when the user selects an option.
  ///
  /// Selection is the confirmation; the owning controller submits the value
  /// and closes the prompt.
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('chat-choice-prompt'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF10263D),
        border: Border.all(
          color: Colors.lightBlueAccent.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
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
                  request.question,
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
            onChanged: (value) {
              if (value != null) onSelect(value);
            },
            child: Column(
              children: [
                for (final option in request.options)
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
        ],
      ),
    );
  }
}
