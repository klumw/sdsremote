// ===========================================================================
// Provider Configuration Table
// ===========================================================================

/// Configuration for an AI provider.
///
/// Maps a [providerName] (shown in the UI dropdown) to its [modelPrefix]
/// (used to construct the model string like "openai:gpt-4o") and its
/// [apiKeyName] (the environment variable name like "OPENAI_API_KEY").
class ProviderConfig {
  final String modelPrefix;
  final String providerName;
  final String apiKeyName;

  const ProviderConfig({
    required this.modelPrefix,
    required this.providerName,
    required this.apiKeyName,
  });
}

/// The canonical list of supported AI providers.
///
/// Each entry defines:
/// - [ProviderConfig.modelPrefix]: used to prefix the model name (e.g. "openai:gpt-4o")
/// - [ProviderConfig.providerName]: displayed in the UI dropdown
/// - [ProviderConfig.apiKeyName]: the environment variable name for the API key
const List<ProviderConfig> providerConfigs = [
  ProviderConfig(
    modelPrefix: 'deepseek',
    providerName: 'DeepSeek',
    apiKeyName: 'DEEPSEEK_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'openai',
    providerName: 'OpenAI',
    apiKeyName: 'OPENAI_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'anthropic',
    providerName: 'Anthropic',
    apiKeyName: 'ANTHROPIC_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'google',
    providerName: 'Google',
    apiKeyName: 'GOOGLE_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'mistral',
    providerName: 'Mistral',
    apiKeyName: 'MISTRAL_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'cohere',
    providerName: 'Cohere',
    apiKeyName: 'COHERE_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'edenai',
    providerName: 'EdenAI',
    apiKeyName: 'EDENAI_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'openrouter',
    providerName: 'OpenRouter',
    apiKeyName: 'OPENROUTER_API_KEY',
  ),
  ProviderConfig(
    modelPrefix: 'xai',
    providerName: 'xAI',
    apiKeyName: 'XAI_API_KEY',
  ),
];

// ===========================================================================
// Application Enums
// ===========================================================================

enum ActivePanel { none, help, chat, profiles, dataLogger, macroRecorder }

/// Actions the user can take when closing with unsaved macro changes.
enum UnsavedMacroAction { save, discard }

/// Identifies a physical knob on the oscilloscope for the generic
/// [_handleKnobChanged] and [_handleKnobTapped] methods.
enum KnobId {
  intensityAdjust(15),
  ch1Voltage(35),
  ch2Voltage(36),
  ch1Position(43),
  ch2Position(44),
  horizontalTime(7),
  horizontalPosition(10),
  triggerLevel(16);

  final int scpiCommandNumber;
  const KnobId(this.scpiCommandNumber);
}

// ===========================================================================
// Button Command Map
// ===========================================================================

/// Maps button labels to their SCPI command strings.
const Map<String, String> buttonCommands = {
  // Menu buttons
  'Cursors': r'$$SY_FP 22,1',
  'Acquire': r'$$SY_FP 27,1',
  'Save/Recall': r'$$SY_FP 28,1',
  'Measure': r'$$SY_FP 26,1',
  'Clear Sweeps': r'$$SY_FP 47,1',
  'Utility': r'$$SY_FP 24,1',
  'Default': r'$$SY_FP 13,1',
  'Display/Persist': r'$$SY_FP 23,1',
  'Print': r'$$SY_FP 25,1',
  // Vertical buttons
  'Math': r'$$SY_FP 31,1',
  'Ref': r'$$SY_FP 32,1',
  'History': r'$$SY_FP 48,1',
  'Decode': r'$$SY_FP 29,1',
  'Run/Stop': r'$$SY_FP 12,1',
  'Auto\nSetup': r'$$SY_FP 11,1',
  // Horizontal buttons
  'Roll': r'$$SY_FP 49,1',
  // Trigger buttons
  'Setup': r'$$SY_FP 18,1',
  'Auto': r'$$SY_FP 17,1',
  'Normal': r'$$SY_FP 19,1',
  'Single': r'$$SY_FP 20,1',
  // Channel
  'CH1': r'$$SY_FP 39,1',
  'CH2': r'$$SY_FP 40,1',
};
