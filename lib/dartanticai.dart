/// A reusable AI agent library built on [dartantic_ai](https://pub.dev/packages/dartantic_ai).
///
/// Provides an [InstrumentAgent] class that wraps the dartantic_ai framework
/// and is pre-configured for use with various AI model providers.
///
/// Also provides a VXI-11 tool for sending SCPI commands and queries
/// to remote instruments.
///
/// This library can be used in both console applications and Flutter apps.
library ;

export 'src/instrument_agent.dart';
export 'src/frontend_agent.dart';
export 'src/search_agent.dart';
export 'src/vxi11_tool.dart';
