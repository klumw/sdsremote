import 'package:mcp_dart/mcp_dart.dart' as mcp;

import '../agent/agent.dart';
import '../mcp_client.dart';

/// Gets an environment variable from the [Agent.environment] map.
///
/// Throws an exception if the environment variable is not set.
String getEnv(String name) {
  if (name.isEmpty) throw Exception('Environment variable name is empty');
  final value = tryGetEnv(name);
  return value ?? (throw Exception('Environment variable $name is not set'));
}

/// Gets an environment variable from the [Agent.environment] map.
///
/// Returns `null` if the environment variable is not set.
String? tryGetEnv(String? name) =>
    name == null || name.isEmpty ? null : Agent.environment[name];

/// Gets the transport for the MCP server.
///
/// For web, this function only returns a [mcp.StreamableHttpClientTransport].
/// Throws an exception if the transport is not supported.
mcp.Transport getTransport({
  required McpServerKind kind,
  required String? command,
  required List<String> args,
  required Map<String, String> environment,
  required String? workingDirectory,
  required Uri? url,
  Map<String, String>? headers,
  Map<String, String>? requestInit,
}) => switch (kind) {
  McpServerKind.local => throw Exception(
    'Local MCP servers are not supported on web.',
  ),
  McpServerKind.remote => mcp.StreamableHttpClientTransport(
    url!,
    opts: headers == null
        ? null
        : mcp.StreamableHttpClientTransportOptions(
            requestInit: {'headers': headers},
          ),
  ),
};
