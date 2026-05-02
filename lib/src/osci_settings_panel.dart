import 'package:flutter/material.dart';

/// Callbacks for the settings panel to communicate with the parent state.
class SettingsPanelCallbacks {
  final void Function(String ip, String key, String token, String model)
      onSave;
  final void Function() onClose;
  final void Function(Offset delta) onDrag;

  SettingsPanelCallbacks({
    required this.onSave,
    required this.onClose,
    required this.onDrag,
  });
}

/// A draggable settings panel for device configuration.
class SettingsPanel extends StatefulWidget {
  final Offset offset;
  final String ipAddress;
  final String aiApiKey;
  final String aiApiToken;
  final String llmModel;
  final bool saveWithParams;
  final bool isRunningDiagnostic;
  final List<String> diagnosticResults;
  final SettingsPanelCallbacks callbacks;
  final ValueChanged<bool> onSaveWithParamsChanged;
  final VoidCallback onRunDiagnostic;

  const SettingsPanel({
    super.key,
    required this.offset,
    required this.ipAddress,
    required this.aiApiKey,
    required this.aiApiToken,
    required this.llmModel,
    required this.saveWithParams,
    required this.isRunningDiagnostic,
    required this.diagnosticResults,
    required this.callbacks,
    required this.onSaveWithParamsChanged,
    required this.onRunDiagnostic,
  });

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late TextEditingController _ipController;
  late TextEditingController _aiApiKeyController;
  late TextEditingController _aiApiTokenController;
  late TextEditingController _llmModelController;

  @override
  void initState() {
    super.initState();
    _ipController = TextEditingController(text: widget.ipAddress);
    _aiApiKeyController = TextEditingController(text: widget.aiApiKey);
    _aiApiTokenController = TextEditingController(text: widget.aiApiToken);
    _llmModelController = TextEditingController(text: widget.llmModel);
  }

  @override
  void didUpdateWidget(SettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ipAddress != widget.ipAddress) {
      _ipController.text = widget.ipAddress;
    }
    if (oldWidget.aiApiKey != widget.aiApiKey) {
      _aiApiKeyController.text = widget.aiApiKey;
    }
    if (oldWidget.aiApiToken != widget.aiApiToken) {
      _aiApiTokenController.text = widget.aiApiToken;
    }
    if (oldWidget.llmModel != widget.llmModel) {
      _llmModelController.text = widget.llmModel;
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _aiApiKeyController.dispose();
    _aiApiTokenController.dispose();
    _llmModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.offset.dx,
      top: widget.offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) => widget.callbacks.onDrag(details.delta),
        child: Material(
          elevation: 20,
          color: Colors.transparent,
          child: Container(
            width: 400,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.cyanAccent, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF252525),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.settings, color: Colors.cyanAccent, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Device Configuration',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: widget.callbacks.onClose,
                      ),
                    ],
                  ),
                ),
                // Body
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSettingsField(
                        _ipController,
                        'Oscilloscope IP Address',
                      ),
                      const SizedBox(height: 16),
                      _buildSettingsField(
                        _aiApiKeyController,
                        'AI API Key Name',
                        hint: 'e.g. OPENAI_API_KEY',
                      ),
                      const SizedBox(height: 16),
                      _buildSettingsField(
                        _aiApiTokenController,
                        'AI API Token',
                        hint: 'Your Provider API token',
                        obscureText: true,
                      ),
                      const SizedBox(height: 16),
                      _buildSettingsField(
                        _llmModelController,
                        'LLM Model',
                        hint: 'e.g. gpt-4o',
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        value: widget.saveWithParams,
                        onChanged: widget.onSaveWithParamsChanged,
                        title: const Text(
                          'Save waveform csv data',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        activeThumbColor: Colors.cyanAccent,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: widget.isRunningDiagnostic
                                  ? null
                                  : widget.onRunDiagnostic,
                              icon: widget.isRunningDiagnostic
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.biotech, size: 18),
                              label: const Text('TEST CONNECTION'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.cyanAccent,
                                side: const BorderSide(
                                  color: Colors.cyanAccent,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (widget.diagnosticResults.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          height: 120,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: ListView.builder(
                            itemCount: widget.diagnosticResults.length,
                            itemBuilder: (context, index) {
                              final line = widget.diagnosticResults[index];
                              Color color = Colors.white70;
                              if (line.startsWith('SUCCESS')) {
                                color = Colors.greenAccent;
                              }
                              if (line.startsWith('FAILURE') ||
                                  line.startsWith('ERROR')) {
                                color = Colors.redAccent;
                              }
                              return Text(
                                line,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyan[800],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => widget.callbacks.onSave(
                          _ipController.text,
                          _aiApiKeyController.text,
                          _aiApiTokenController.text,
                          _llmModelController.text,
                        ),
                        child: const Text(
                          'SAVE CONFIGURATION',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsField(
    TextEditingController controller,
    String label, {
    String? hint,
    TextInputType? keyboardType,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 14),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Colors.cyanAccent),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontSize: 14),
    );
  }
}
