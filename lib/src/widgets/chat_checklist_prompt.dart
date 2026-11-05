import 'package:flutter/material.dart';

import '../ai/chat_checklist.dart';

/// Multi-select checkbox prompt rendered inside an AI chat panel.
///
/// The widget is presentation-only: the owning chat controller holds the
/// pending [ChatChecklistRequest] and the selection through its
/// [ChatChecklistPromptController]. The Confirm button is enabled only after
/// at least one option is checked; Cancel is available unless the request
/// disallows cancellation.
class ChatChecklistPrompt extends StatelessWidget {
  const ChatChecklistPrompt({super.key, required this.controller});

  final ChatChecklistPromptController controller;

  @override
  Widget build(BuildContext context) {
    final request = controller.request;
    if (request == null) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('chat-checklist-prompt'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF10263D),
        border: Border.all(
          color: Colors.lightBlueAccent.withValues(alpha: 0.55),
          width: 1.2,
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
                Icons.checklist,
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final option in request.options)
                    CheckboxListTile(
                      key: ValueKey('chat-checklist-option-${option.value}'),
                      value: controller.isSelected(option.value),
                      onChanged: (_) => controller.toggle(option.value),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      controlAffinity: ListTileControlAffinity.leading,
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
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${controller.selectedCount} selected',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const Spacer(),
              if (request.allowCancel)
                TextButton(
                  key: const ValueKey('chat-checklist-cancel'),
                  onPressed: controller.cancel,
                  child: const Text('Cancel'),
                ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('chat-checklist-confirm'),
                onPressed: controller.canSubmit ? controller.submit : null,
                child: const Text('Confirm'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
