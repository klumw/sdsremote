import 'package:flutter/material.dart';

import '../ai/component_name_prompt.dart';

/// Text prompt shown above the chat while the SpecAnalyst asks for the
/// component or family name used for the IC reference file.
///
/// The widget is presentation-only; [controller] owns the pending request and
/// the text/conflict state. The prompt cannot be dismissed by clicking outside
/// because a pending save must end with either a name or an explicit cancel.
class ComponentNamePrompt extends StatefulWidget {
  const ComponentNamePrompt({super.key, required this.controller});

  final ComponentNamePromptController controller;

  @override
  State<ComponentNamePrompt> createState() => _ComponentNamePromptState();
}

class _ComponentNamePromptState extends State<ComponentNamePrompt> {
  late final TextEditingController _text;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: widget.controller.text);
    _focus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant ComponentNamePrompt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller ||
        widget.controller.text != _text.text) {
      _text.text = widget.controller.text;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final request = controller.request;
    if (request == null) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('component-name-prompt'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF10263D),
        border: Border.all(
          color: Colors.lightBlueAccent.withValues(alpha: 0.55),
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
                Icons.save_outlined,
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
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('component-name-field'),
            controller: _text,
            focusNode: _focus,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Component or family name, for example BME280',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              filled: true,
              fillColor: const Color(0xFF0A192F),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
            onChanged: controller.updateText,
            onSubmitted: (_) => controller.submit(),
          ),
          const SizedBox(height: 6),
          Text(
            controller.normalizedId.isEmpty
                ? 'The file name is derived from the name.'
                : 'File: ${controller.normalizedId}.json',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          if (controller.isChecking) ...[
            const SizedBox(height: 6),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (controller.fileExists) ...[
            const SizedBox(height: 4),
            CheckboxListTile(
              key: const ValueKey('component-name-overwrite'),
              value: controller.overwriteConfirmed,
              onChanged: (value) =>
                  controller.setOverwriteConfirmed(value ?? false),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: Colors.lightBlueAccent,
              title: const Text(
                'A file with this name already exists. Overwrite it.',
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),
          ],
          if (controller.error != null) ...[
            const SizedBox(height: 4),
            Text(
              controller.error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                key: const ValueKey('component-name-cancel'),
                onPressed: controller.cancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const ValueKey('component-name-save'),
                onPressed: controller.canSubmit ? controller.submit : null,
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
