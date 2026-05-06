/// A reusable AI agent library built on [dartantic_ai](https://pub.dev/packages/dartantic_ai).
///
/// Provides a [ChatAgent] class that wraps the dartantic_ai framework
/// and is pre-configured for DeepSeek via the OpenAI-compatible API.
///
/// Also provides a VXI-11 tool for sending SCPI commands and queries
/// to remote instruments.
///
/// This library can be used in both console applications and Flutter apps.
library dartanticai;

export 'src/agent.dart';
export 'src/frontend_agent.dart';
export 'src/query_agent.dart';
export 'src/vxi11_tool.dart';
