# Migration Plan: Replace Docker Backend with FrontendAgent

## Current Architecture

```
┌──────────────┐    sendMessageStream(text)    ┌──────────────────┐    stdin/stdout    ┌──────────────┐
│  ChatWindow  │ ──────────────────────────────▶│  AiChatService   │ ────────────────▶│  Docker      │
│  (osci_chat  │                                 │  (ai_chat_       │    \n\n + EOF    │  Container   │
│   _window)   │◀──────────────────────────────│   service.dart)  │◀────────────────│  (sds-ai-    │
└──────────────┘    raw text chunks             └──────────────────┘    stdout EOF     │   server)    │
                                                                                      └──────────────┘
```

## Target Architecture

```
┌──────────────┐    sendMessageStream(text)    ┌──────────────────────┐    sendStream()    ┌──────────────┐
│  ChatWindow  │ ──────────────────────────────▶│  AiChatService      │ ────────────────▶│  FrontendAgent│
│  (osci_chat  │                                 │  (refactored to     │                   │  (uses        │
│   _window)   │◀──────────────────────────────│   wrap FrontendAgent)│◀────────────────│   dartantic_ai)│
└──────────────┘    text chunks (no EOF)        └──────────────────────┘    text chunks    └──────────────┘
```

## Key Changes

### 1. Dependencies (`pubspec.yaml`)
Add:
- `dartantic_ai` as a path dependency → `packages/dartantic_ai_patched`
- `langchain` package (needed by `query_agent.dart`)

### 2. Missing file: `vxi11_tool.dart`
The files `agent.dart` and `frontend_agent.dart` import `vxi11_tool.dart` and use `createVxi11Tool()` and `defaultVxi11Host`. This file needs to be created at `lib/src/vxi11_tool.dart` with:
- `const String defaultVxi11Host = '192.168.178.95';`
- `Tool<Map<String, dynamic>> createVxi11Tool({required String host, String agentName = 'unknown'})`

### 3. Logging Migration (`logger.dart` + multiagent files)
**Problem:** `frontend_agent.dart` and `query_agent.dart` create `AppLogger(agentName:, toolName:)` and call `.logToolCall()` — but the existing `AppLogger` in `logger.dart` is a singleton with only `log(String)`.

**Solution:** Enhance `AppLogger` in `logger.dart` to support the new interface:
- Add optional `agentName` and `toolName` parameters to the factory/named constructor
- Add `logToolCall(Map<String, dynamic> input, Map<String, dynamic> output)` method
- Keep backward compatibility with existing `log(String)` calls

### 4. Refactor `AiChatService` (`lib/ai_chat_service.dart`)
Instead of managing Docker processes:
- Accept a `FrontendAgent` instance
- Implement `sendMessageStream()` by delegating to `FrontendAgent.sendStream()`
- Remove all Docker process management (`_dockerProcess`, `_stdoutSub`, `_initProcess`, etc.)
- **Protocol change:** Previously, input used `\n\n` to signal end and output ended with EOF. Now, `sendStream()` yields chunks naturally — no delimiter needed.

### 5. Remove Docker Code from `main.dart`
Remove:
- State fields: `_aiApiKey`, `_aiApiToken`, `_llmModel` → keep for FrontendAgent config
- State fields: `_isDockerRunning`, `_isAiImagePresent`, `_isContainerRunning`, `_isAiEnabled`, `_isShuttingDown`
- Methods: `_checkDockerStatus()`, `_startDockerStatusTimer()` 
- `_initialize()` — remove `_startDockerStatusTimer()` and Docker startup
- `dispose()` — Docker cleanup
- `onWindowClose()` — Docker stop logic
- `_buildAiButton()` — simplify `_isAiEnabled` check (just check API key presence)

New AI state logic: replace `_isAiEnabled` with a simple check that API key and token are set, and create `FrontendAgent` when needed.

### 6. Update `_buildChatWindow()` in `main.dart`
Change from:
```dart
final AiChatService _aiChatService = AiChatService();
```
To creating a `FrontendAgent` instance and passing it to `AiChatService`.

### 7. Protocol Adaptation (`AiChatService.sendMessageStream`)
- **Old protocol:** Send text + `\n\n` → close stdin → read stdout until EOF
- **New protocol:** Call `FrontendAgent.sendStream(text)` → yields text chunks
- The `FrontendAgent.sendStream()` method already handles streaming with tool calls and history

## Detailed Steps

| # | Step | Files | Description |
|---|------|-------|-------------|
| 1 | Add dependencies | `pubspec.yaml` | Add `dartantic_ai` path dep and `langchain` |
| 2 | Create `vxi11_tool.dart` | `lib/src/vxi11_tool.dart` | Implement `createVxi11Tool()` and `defaultVxi11Host` |
| 3 | Enhance `AppLogger` | `lib/logger.dart` | Add `agentName`/`toolName` params, `logToolCall()` method |
| 4 | Update `agent.dart` logging | `lib/src/agent.dart` | Adapt to new `AppLogger` (singleton usage) |
| 5 | Update `query_agent.dart` logging | `lib/src/query_agent.dart` | Adapt to new `AppLogger` (singleton usage) |
| 6 | Update `frontend_agent.dart` logging | `lib/src/frontend_agent.dart` | Adapt to new `AppLogger` (singleton usage) |
| 7 | Remove `main()` from `frontend_agent.dart` | `lib/src/frontend_agent.dart` | Remove any `main()` method (if present) |
| 8 | Refactor `AiChatService` | `lib/ai_chat_service.dart` | Replace Docker with FrontendAgent, adapt protocol |
| 9 | Remove Docker code from `main.dart` | `lib/main.dart` | Remove Docker state/methods, simplify AI config |
| 10 | Wire everything together | `lib/main.dart` | Create FrontendAgent, pass to AiChatService |
