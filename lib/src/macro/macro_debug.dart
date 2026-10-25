import 'macro_ast.dart';

/// Whether [line] has a breakpoint that is currently enabled.
///
/// Breakpoints can be disabled from the gutter context menu. Disabled
/// breakpoints stay visible but must not pause the debugger.
bool isMacroBreakpointActive({
  required int? line,
  required Set<int> breakpoints,
  required Set<int> inactiveBreakpoints,
}) =>
    line != null &&
    breakpoints.contains(line) &&
    !inactiveBreakpoints.contains(line);

/// Whether at least one breakpoint is enabled.
bool hasActiveMacroBreakpoint({
  required Set<int> breakpoints,
  required Set<int> inactiveBreakpoints,
}) => breakpoints.any((line) => !inactiveBreakpoints.contains(line));

/// Whether at least one breakpoint is disabled.
bool hasInactiveMacroBreakpoint({
  required Set<int> breakpoints,
  required Set<int> inactiveBreakpoints,
}) => breakpoints.any(inactiveBreakpoints.contains);

/// Returns a short, human-readable description of [statement] for the Macro
/// Editor's debug status line.
///
/// The description is intentionally compact: it identifies the statement
/// without reproducing the full source, which would be too long for the
/// status bar.
String describeMacroStatement(Statement statement) {
  return switch (statement) {
    ConnectStmt(:final ip, :final isVariable, :final concatString) =>
      concatString != null
          ? 'connect(<expression>)'
          : ip == null
          ? 'connect(usb)'
          : isVariable
          ? 'connect($ip)'
          : 'connect("$ip")',
    WaitStmt(:final seconds, :final variableName) =>
      variableName != null ? 'wait($variableName)' : 'wait($seconds)',
    ScpiStmt(:final command, :final variableName, :final concatString) =>
      concatString != null
          ? 'scpi(<expression>)'
          : variableName != null
          ? 'scpi($variableName)'
          : 'scpi("$command")',
    QueryStmt(:final command, :final variableName, :final concatString) =>
      concatString != null
          ? 'query(<expression>)'
          : variableName != null
          ? 'query($variableName)'
          : 'query("$command")',
    AssignStmt(:final varName) => '$varName = <expression>',
    PrintStmt() => 'print(...)',
    AssertStmt(:final text, :final concatText) =>
      concatText != null ? 'assert(<text>, ...)' : 'assert("$text", ...)',
    LoadProfileStmt(:final path, :final concatString) =>
      concatString != null
          ? 'loadProfile(<expression>)'
          : 'loadProfile("$path")',
    IfStmt() => 'if (...) { ... }',
    WhileStmt() => 'while (...) { ... }',
    BreakStmt() => 'break',
    ContinueStmt() => 'continue',
    FailStmt(:final message, :final concatMessage) =>
      concatMessage != null ? 'fail(<expression>)' : 'fail("$message")',
    Comment() => '# comment',
  };
}
