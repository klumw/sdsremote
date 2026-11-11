import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Sort orders offered by [ReferenceFilePickerDialog].
enum ReferenceFileSortOrder {
  nameAscending('Name A–Z'),
  dateNewestFirst('Newest first'),
  dateOldestFirst('Oldest first');

  const ReferenceFileSortOrder(this.label);

  /// Label shown in the sort dropdown.
  final String label;
}

/// One picker row: the file plus the metadata needed for sorting/display.
class _ReferenceCsvFile {
  final File file;
  final String name;
  final DateTime modified;

  const _ReferenceCsvFile({
    required this.file,
    required this.name,
    required this.modified,
  });
}

/// Dialog that lists CSV waveform files with their modification time and lets
/// the user pick one. The list can be sorted by name or by date.
class ReferenceFilePickerDialog extends StatefulWidget {
  final List<File> files;

  const ReferenceFilePickerDialog({super.key, required this.files});

  @override
  State<ReferenceFilePickerDialog> createState() =>
      _ReferenceFilePickerDialogState();
}

class _ReferenceFilePickerDialogState extends State<ReferenceFilePickerDialog> {
  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  late final List<_ReferenceCsvFile> _entries;
  ReferenceFileSortOrder _sort = ReferenceFileSortOrder.nameAscending;

  @override
  void initState() {
    super.initState();
    _entries = [
      for (final file in widget.files)
        _ReferenceCsvFile(
          file: file,
          name: file.uri.pathSegments.last,
          modified: _modifiedOf(file),
        ),
    ];
  }

  /// Modification time, falling back to the epoch when the file vanished
  /// between listing the directory and opening the dialog.
  static DateTime _modifiedOf(File file) {
    try {
      return file.statSync().modified;
    } on FileSystemException {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  static int _byName(_ReferenceCsvFile a, _ReferenceCsvFile b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.modified.compareTo(b.modified);
  }

  static int _byDateDescending(_ReferenceCsvFile a, _ReferenceCsvFile b) {
    final byDate = b.modified.compareTo(a.modified);
    return byDate != 0 ? byDate : _byName(a, b);
  }

  static int _byDateAscending(_ReferenceCsvFile a, _ReferenceCsvFile b) {
    final byDate = a.modified.compareTo(b.modified);
    return byDate != 0 ? byDate : _byName(a, b);
  }

  List<_ReferenceCsvFile> get _sorted {
    final entries = List<_ReferenceCsvFile>.of(_entries);
    entries.sort(switch (_sort) {
      ReferenceFileSortOrder.nameAscending => _byName,
      ReferenceFileSortOrder.dateNewestFirst => _byDateDescending,
      ReferenceFileSortOrder.dateOldestFirst => _byDateAscending,
    });
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Select Waveform CSV')),
          DropdownButton<ReferenceFileSortOrder>(
            value: _sort,
            isDense: true,
            dropdownColor: const Color(0xFF172A45),
            style: const TextStyle(color: Colors.white, fontSize: 12),
            iconEnabledColor: Colors.white54,
            underline: const SizedBox.shrink(),
            items: [
              for (final order in ReferenceFileSortOrder.values)
                DropdownMenuItem(value: order, child: Text(order.label)),
            ],
            onChanged: (order) {
              if (order == null) return;
              setState(() => _sort = order);
            },
          ),
        ],
      ),
      children: [
        for (final entry in _sorted)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, entry.file.path),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  _dateFormat.format(entry.modified),
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
