/// Removes internal tool, agent and status identifiers from user answers.
///
/// The WaveformAgent prompt forbids naming internal components, but the model
/// can still leak an identifier. This deterministic pass is the last line of
/// defence before the final answer reaches the chat.
library;

/// Replaces internal identifiers with neutral, user-facing wording.
String sanitizeInternalAgentNames(String text) {
  var result = text;
  for (final entry in _replacements) {
    result = result.replaceAllMapped(entry.pattern, (match) {
      final matched = match.group(0) ?? '';
      final replacement = entry.replacement;
      // Preserve a sentence-initial capital, for example "The planner_agent"
      // must become "The measurement", not "the measurement".
      final startsUpper =
          matched.isNotEmpty &&
          matched[0].toUpperCase() == matched[0] &&
          matched[0].toLowerCase() != matched[0];
      if (!startsUpper || replacement.isEmpty) return replacement;
      return replacement[0].toUpperCase() + replacement.substring(1);
    });
  }
  return result.replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
}

final List<({RegExp pattern, String replacement})>
_replacements = <({RegExp pattern, String replacement})>[
  // Orchestrator and sub-agent tool names.
  (
    pattern: RegExp(
      r'\b(?:the\s+)?scope_analysis_agent\b',
      caseSensitive: false,
    ),
    replacement: 'the measurement',
  ),
  (
    pattern: RegExp(
      r'\b(?:the\s+)?audio_analysis_agent\b',
      caseSensitive: false,
    ),
    replacement: 'the audio measurement',
  ),
  (
    pattern: RegExp(
      r'\b(?:the\s+)?digital_analysis_agent\b',
      caseSensitive: false,
    ),
    replacement: 'the digital measurement',
  ),
  (
    pattern: RegExp(
      r'\b(?:the\s+)?scpi_instrument_agent\b',
      caseSensitive: false,
    ),
    replacement: 'the instrument',
  ),
  (
    pattern: RegExp(r'\b(?:the\s+)?planner_agent\b', caseSensitive: false),
    replacement: 'the measurement',
  ),
  (
    pattern: RegExp(r'\b(?:the\s+)?present_input_form\b', caseSensitive: false),
    replacement: 'the input form',
  ),
  (
    pattern: RegExp(r'\b(?:the\s+)?execute_plan\b', caseSensitive: false),
    replacement: 'the measurement',
  ),
  (
    pattern: RegExp(r'\b(?:the\s+)?plan_measurement\b', caseSensitive: false),
    replacement: 'the measurement',
  ),

  // Agent class names.
  (
    pattern: RegExp(r'\b(?:the\s+)?WaveformAgent\b', caseSensitive: false),
    replacement: 'the assistant',
  ),
  (
    pattern: RegExp(r'\b(?:the\s+)?PlannerAgent\b', caseSensitive: false),
    replacement: 'the assistant',
  ),
  (
    pattern: RegExp(r'\b(?:the\s+)?ScopeAnalystAgent\b', caseSensitive: false),
    replacement: 'the assistant',
  ),
  (
    pattern: RegExp(r'\b(?:the\s+)?AudioAgent\b', caseSensitive: false),
    replacement: 'the assistant',
  ),
  (
    pattern: RegExp(r'\b(?:the\s+)?DigitalAgent\b', caseSensitive: false),
    replacement: 'the assistant',
  ),
  (
    pattern: RegExp(r'\b(?:the\s+)?InstrumentAgent\b', caseSensitive: false),
    replacement: 'the assistant',
  ),
  (
    pattern: RegExp(r'\b(?:the\s+)?FrontendAgent\b', caseSensitive: false),
    replacement: 'the assistant',
  ),

  // Generic sub-agent wording.
  (
    pattern: RegExp(
      r'\b(?:the\s+)?sub[- ]?agents?(?:en)?\b',
      caseSensitive: false,
    ),
    replacement: 'the assistant',
  ),

  // Machine status and reason codes.
  (
    pattern: RegExp(
      r'\b(?:the\s+status\s+)?needs_input\b',
      caseSensitive: false,
    ),
    replacement: 'more information is needed',
  ),
  (
    pattern: RegExp(
      r'\b(?:the\s+status\s+)?plan_ready\b',
      caseSensitive: false,
    ),
    replacement: 'the plan is ready',
  ),
  (
    pattern: RegExp(
      r'\b(?:the\s+reason\s+)?too_dangerous\b',
      caseSensitive: false,
    ),
    replacement: 'unsafe',
  ),
  (
    pattern: RegExp(r'\b(?:the\s+reason\s+)?no_scope\b', caseSensitive: false),
    replacement: 'no oscilloscope is configured',
  ),
  (
    pattern: RegExp(
      r'\b(?:the\s+reason\s+)?no_generator\b',
      caseSensitive: false,
    ),
    replacement: 'no signal generator is connected',
  ),
  (
    pattern: RegExp(
      r'\b(?:the\s+reason\s+)?unsupported_method\b',
      caseSensitive: false,
    ),
    replacement: 'unsupported',
  ),
  (
    pattern: RegExp(
      r'\b(?:the\s+reason\s+)?too_complex\b',
      caseSensitive: false,
    ),
    replacement: 'too complex',
  ),
  (
    pattern: RegExp(
      r'\b(?:the\s+reason\s+)?not_feasible\b',
      caseSensitive: false,
    ),
    replacement: 'not feasible',
  ),
  (
    pattern: RegExp(
      r'\b(?:the\s+reason\s+)?input_incomplete\b',
      caseSensitive: false,
    ),
    replacement: 'the information is incomplete',
  ),
  (
    pattern: RegExp(
      r'\b(?:the\s+reason\s+)?user_input_unknown\b',
      caseSensitive: false,
    ),
    replacement: 'a required value is unknown',
  ),
  (
    pattern: RegExp(
      r'\b(?:the\s+reason\s+)?user_cancelled\b',
      caseSensitive: false,
    ),
    replacement: 'cancelled',
  ),
  (
    pattern: RegExp(
      r'\b(?:the\s+status\s+)?awaiting_approval\b',
      caseSensitive: false,
    ),
    replacement: 'waiting for approval',
  ),
  (
    pattern: RegExp(
      r'\b(?:the\s+status\s+)?awaiting_confirmation\b',
      caseSensitive: false,
    ),
    replacement: 'waiting for confirmation',
  ),
  (
    pattern: RegExp(
      r'\b(?:the\s+status\s+)?unknown_plan\b',
      caseSensitive: false,
    ),
    replacement: 'unknown measurement',
  ),
];
