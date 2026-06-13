import 'package:flutter/material.dart';

import '../app_config.dart';

/// A dialog shown when the user tries to close the app while a macro has
/// unsaved changes, prompting them to save, discard, or cancel.
class UnsavedChangesDialog extends StatelessWidget {
  const UnsavedChangesDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unsaved Macro Changes'),
      content: const Text(
        'The current macro has unsaved changes.\n'
        'Do you want to save before closing?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, UnsavedMacroAction.discard),
          child: const Text('Discard'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, UnsavedMacroAction.save),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
