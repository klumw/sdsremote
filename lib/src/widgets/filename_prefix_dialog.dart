import 'package:flutter/material.dart';

/// A dialog that prompts for a filename prefix with validation.
///
/// Only allows [a-zA-Z0-9_-], max 30 characters.
/// Returns the entered prefix on confirm, or null on cancel.
class FilenamePrefixDialog extends StatefulWidget {
  const FilenamePrefixDialog({super.key});

  @override
  State<FilenamePrefixDialog> createState() => _FilenamePrefixDialogState();
}

class _FilenamePrefixDialogState extends State<FilenamePrefixDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  static final _validChars = RegExp(r'^[a-zA-Z0-9_-]*$');

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSubmit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _errorText = 'Prefix cannot be empty');
      return;
    }
    if (text.length > 30) {
      setState(() => _errorText = 'Max 30 characters allowed');
      return;
    }
    if (!_validChars.hasMatch(text)) {
      setState(
        () => _errorText = 'Only a-z, A-Z, 0-9, underscore and hyphen allowed',
      );
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filename Prefix'),
      content: TextField(
        controller: _controller,
        decoration: InputDecoration(
          hintText: 'e.g. lab_measurement_1',
          errorText: _errorText,
        ),
        autofocus: true,
        onSubmitted: (_) => _onSubmit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _onSubmit, child: const Text('Save')),
      ],
    );
  }
}
