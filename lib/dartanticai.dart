/// A reusable AI agent library built on [dartantic_ai](https://pub.dev/packages/dartantic_ai).
///
/// Provides an [InstrumentAgent] class that wraps the dartantic_ai framework
/// and is pre-configured for use with various AI model providers.
///
/// Also provides a VXI-11 tool for sending SCPI commands and queries
/// to remote instruments.
///
/// This library can be used in both console applications and Flutter apps.
library;

export 'src/ai/agents/instrument_agent.dart';
export 'src/ai/agents/frontend_agent.dart';
export 'src/ai/agents/search_agent.dart';
export 'src/ai/tools/vxi11_tool.dart';
