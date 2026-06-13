import 'dart:io';

import 'package:flutter/material.dart';

/// A simple dialog that lists CSV waveform files and lets the user pick one.
class ReferenceFilePickerDialog extends StatelessWidget {
  final List<File> files;
  const ReferenceFilePickerDialog({super.key, required this.files});

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Select Waveform CSV'),
      children: files.map((file) {
        final name = file.uri.pathSegments.last;
        return SimpleDialogOption(
          onPressed: () => Navigator.pop(context, file.path),
          child: Text(name, style: const TextStyle(fontSize: 13)),
        );
      }).toList(),
    );
  }
}
