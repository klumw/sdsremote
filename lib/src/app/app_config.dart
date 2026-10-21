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

enum ActivePanel {
  none,
  help,
  chat,
  profiles,
  dataLogger,
  macroRecorder,
  bode,
}

/// Actions the user can take when closing with unsaved macro changes.
enum UnsavedMacroAction { save, discard }

/// Identifies a physical knob on the oscilloscope for the generic
/// [_handleKnobChanged] and [_handleKnobTapped] methods.
enum KnobId {
  intensityAdjust(15),
  ch1Voltage(35),
  ch2Voltage(36),
  ch3Voltage(37),
  ch4Voltage(38),
  ch1Position(43),
  ch2Position(44),
  ch3Position(45),
  ch4Position(46),
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
  'CH3': r'$$SY_FP 41,1',
  'CH4': r'$$SY_FP 42,1',
};

/// Number of analog channels for an oscilloscope model from `*IDN?`.
///
/// Siglent model numbers encode the channel count in the fourth digit after
/// the `SDS` prefix: `SDS1202X-E` has two channels, `SDS1104X-E` has four.
/// Unknown or unparsable model names keep the two-channel layout, which is
/// the layout every other instrument falls back to.
int channelCountForModel(String? model) {
  if (model == null) return 2;
  final match = RegExp(r'SDS\s*(\d{3})(\d)').firstMatch(model.toUpperCase());
  if (match == null) return 2;
  return match.group(2) == '4' ? 4 : 2;
}

/// Number of analog channels from the instrument's `CHS?` response.
///
/// The response is a channel list such as `CH1,CH2,CH3,CH4`; some firmware
/// variants answer with a bare count. Returns null when the response cannot
/// be interpreted, so the caller can fall back to [channelCountForModel].
int? channelCountFromChs(String? response) {
  if (response == null) return null;
  final trimmed = response.trim();
  if (trimmed.isEmpty) return null;

  final plain = int.tryParse(trimmed);
  if (plain != null && plain > 0) return plain;

  final channels = RegExp(
    r'CH\s*([1-8])',
    caseSensitive: false,
  ).allMatches(trimmed).map((m) => int.parse(m.group(1)!)).toSet();
  if (channels.isEmpty) return null;
  return channels.reduce((a, b) => a > b ? a : b);
}
