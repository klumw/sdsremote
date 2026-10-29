import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ProfileInfo {
  final String fileName;
  final DateTime lastModified;

  ProfileInfo({required this.fileName, required this.lastModified});
}

class ProfilesPanel extends StatefulWidget {
  final List<ProfileInfo> profileFiles;
  final bool isOnline;

  /// True while a profile is uploaded to the instrument and applied there.
  final bool isLoading;
  final Function(String) onSave;
  final Function(String) onLoad;
  final Function(String) onDelete;
  final VoidCallback onClose;

  const ProfilesPanel({
    super.key,
    required this.profileFiles,
    required this.isOnline,
    required this.isLoading,
    required this.onSave,
    required this.onLoad,
    required this.onDelete,
    required this.onClose,
  });

  @override
  State<ProfilesPanel> createState() => _ProfilesPanelState();
}

enum ProfileSortType { name, date }

class _ProfilesPanelState extends State<ProfilesPanel> {
  final TextEditingController _nameController = TextEditingController();
  bool _isSaving = false;
  ProfileSortType _sortType = ProfileSortType.name;
  bool _isAscending = true;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// How long the busy indicator stays visible at minimum. Reading the setup
  /// from the instrument takes only a few frames over USB, which makes the
  /// spinner flash past unnoticed.
  static const Duration _minBusyDuration = Duration(milliseconds: 600);

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final started = DateTime.now();
    setState(() => _isSaving = true);
    // The instrument read blocks the UI isolate, so make sure the busy
    // indicator is painted before the transfer starts.
    await WidgetsBinding.instance.endOfFrame;
    try {
      await widget.onSave(name);
      _nameController.clear();
    } finally {
      final remaining = _minBusyDuration - DateTime.now().difference(started);
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  List<ProfileInfo> get _sortedFiles {
    final list = List<ProfileInfo>.from(widget.profileFiles);
    if (_sortType == ProfileSortType.name) {
      list.sort((a, b) {
        final cmp = a.fileName.toLowerCase().compareTo(
          b.fileName.toLowerCase(),
        );
        return _isAscending ? cmp : -cmp;
      });
    } else {
      list.sort((a, b) {
        final cmp = a.lastModified.compareTo(b.lastModified);
        return _isAscending ? cmp : -cmp;
      });
    }
    return list;
  }

  String _formatDate(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} "
        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final sortedList = _sortedFiles;

    return Container(
      width: 450,
      decoration: BoxDecoration(
        color: const Color(0xFF0A192F),
        border: Border.all(color: const Color(0xFF475569)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF172A45),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.save, color: Colors.cyanAccent, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      "Device Profiles",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (widget.isLoading || _isSaving) ...[
                      const SizedBox(width: 10),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.cyanAccent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white70,
                    size: 20,
                  ),
                  onPressed: widget.onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // Save New Profile Section
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.cyanAccent, width: 1.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Create New Profile",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2A4A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF475569)),
                          ),
                          child: TextField(
                            controller: _nameController,
                            maxLength: 30,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-Z0-9_-]'),
                              ),
                            ],
                            decoration: const InputDecoration(
                              hintText: 'Enter profile name...',
                              hintStyle: TextStyle(
                                color: Colors.white38,
                                fontSize: 13,
                              ),
                              border: InputBorder.none,
                              counterText: '',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: (_isSaving || !widget.isOnline)
                            ? null
                            : _handleSave,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text("Save"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.isOnline
                              ? Colors.cyan[800]
                              : Colors.grey[800],
                          foregroundColor: widget.isOnline
                              ? Colors.white
                              : Colors.white38,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const Divider(color: Colors.white12, height: 1),

          // Sort Controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text(
                  "Sort by:",
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(width: 8),
                _buildSortButton("Name", ProfileSortType.name),
                const SizedBox(width: 8),
                _buildSortButton("Date", ProfileSortType.date),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
                    color: Colors.cyanAccent,
                    size: 16,
                  ),
                  tooltip: _isAscending ? 'Ascending' : 'Descending',
                  onPressed: () => setState(() => _isAscending = !_isAscending),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // Profile List Section
          Expanded(
            child: widget.profileFiles.isEmpty
                ? const Center(
                    child: Text(
                      "No profiles found",
                      style: TextStyle(color: Colors.white38, fontSize: 14),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: sortedList.length,
                    itemBuilder: (context, index) {
                      final profile = sortedList[index];
                      final fileName = profile.fileName;
                      // Remove .lss extension for display
                      final displayName = fileName.endsWith('.lss')
                          ? fileName.substring(0, fileName.length - 4)
                          : fileName;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF172A45).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(
                              0xFF475569,
                            ).withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.description,
                              color: Colors.white38,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatDate(profile.lastModified),
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.file_upload,
                                color: widget.isOnline && !widget.isLoading
                                    ? Colors.greenAccent
                                    : Colors.white24,
                                size: 20,
                              ),
                              tooltip: widget.isLoading
                                  ? 'Loading Profile...'
                                  : widget.isOnline
                                  ? 'Load Profile'
                                  : 'Device Offline',
                              onPressed: widget.isOnline && !widget.isLoading
                                  ? () => widget.onLoad(fileName)
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              tooltip: 'Delete Profile',
                              onPressed: () => widget.onDelete(fileName),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortButton(String label, ProfileSortType type) {
    final isActive = _sortType == type;
    return InkWell(
      onTap: () => setState(() => _sortType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.cyan[800]?.withValues(alpha: 0.3)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive
                ? Colors.cyanAccent.withValues(alpha: 0.5)
                : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.cyanAccent : Colors.white70,
            fontSize: 11,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
