import '../app/app_config.dart';

/// The connection settings needed to create an AI agent outside the main chat.
///
/// The main AI chat is configured by [AiChatService] from the settings panel.
/// Widgets that need their own agent — the Macro Editor's AI assistant — get
/// the same provider/token/model combination through this value object.
///
/// A null [AiSettings] (or [isConfigured] == false) means the user has not
/// configured the AI yet, so AI features must stay disabled.
class AiSettings {
  /// Environment variable name of the provider API key, e.g.
  /// `DEEPSEEK_API_KEY`.
  final String apiKeyName;

  /// The actual API token value.
  final String apiToken;

  /// Full model string in `provider:model` form, e.g.
  /// `deepseek:deepseek-v4-flash`.
  final String model;

  const AiSettings({
    required this.apiKeyName,
    required this.apiToken,
    required this.model,
  });

  /// Whether a provider, token, and model are present. Mirrors the validation
  /// used by the main AI chat: a token shorter than 8 characters is treated as
  /// not configured.
  bool get isConfigured =>
      apiKeyName.trim().isNotEmpty &&
      apiToken.trim().length >= 8 &&
      model.trim().isNotEmpty;

  /// Builds settings from the values stored by the settings panel, using the
  /// canonical [providerConfigs] table to resolve the API key name and model
  /// prefix.
  ///
  /// Unknown provider names fall back to `<provider>_API_KEY` and the
  /// lower-cased provider name, matching the main AI chat's behaviour.
  factory AiSettings.fromProviderConfig({
    required String providerName,
    required String apiToken,
    required String modelName,
  }) {
    final config = providerConfigs.firstWhere(
      (c) => c.providerName == providerName,
      orElse: () => ProviderConfig(
        modelPrefix: providerName.toLowerCase(),
        providerName: providerName,
        apiKeyName: '${providerName.toUpperCase()}_API_KEY',
      ),
    );

    return AiSettings(
      apiKeyName: config.apiKeyName,
      apiToken: apiToken.trim(),
      model: '${config.modelPrefix}:${modelName.trim()}',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AiSettings &&
      other.apiKeyName == apiKeyName &&
      other.apiToken == apiToken &&
      other.model == model;

  @override
  int get hashCode => Object.hash(apiKeyName, apiToken, model);

  @override
  String toString() => 'AiSettings(model: $model)';
}
