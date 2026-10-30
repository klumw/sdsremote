/// Error taxonomy of the engineering calculator.
///
/// Every failure is reported with a stable [CalcErrorType] so the UI, the
/// service facade and an AI tool can distinguish a syntax error from a
/// physical dimension error without parsing message text.
library;

enum CalcErrorType {
  syntax,
  name,
  argument,
  domain,
  divisionByZero,
  overflow,
  unit,
  dimension,
  convergence,
  limit,
  unsupported,
}

/// An error raised while parsing or evaluating a calculator expression.
class CalcException implements Exception {
  const CalcException(this.type, this.message, {this.position});

  final CalcErrorType type;
  final String message;

  /// Character offset in the source, when the error is positional.
  final int? position;

  /// Stable lower-case identifier used by JSON-facing callers.
  String get typeName {
    switch (type) {
      case CalcErrorType.syntax:
        return 'syntax';
      case CalcErrorType.name:
        return 'name';
      case CalcErrorType.argument:
        return 'argument';
      case CalcErrorType.domain:
        return 'domain';
      case CalcErrorType.divisionByZero:
        return 'division_by_zero';
      case CalcErrorType.overflow:
        return 'overflow';
      case CalcErrorType.unit:
        return 'unit';
      case CalcErrorType.dimension:
        return 'dimension';
      case CalcErrorType.convergence:
        return 'convergence';
      case CalcErrorType.limit:
        return 'limit';
      case CalcErrorType.unsupported:
        return 'unsupported';
    }
  }

  String get formattedMessage {
    final offset = position;
    if (offset == null) return message;
    return 'position $offset: $message';
  }

  @override
  String toString() => formattedMessage;
}

/// Convenience constructors used throughout the engine.
CalcException syntaxError(String message, [int? position]) =>
    CalcException(CalcErrorType.syntax, message, position: position);

CalcException nameError(String message, [int? position]) =>
    CalcException(CalcErrorType.name, message, position: position);

CalcException argumentError(String message) =>
    CalcException(CalcErrorType.argument, message);

CalcException domainError(String message) =>
    CalcException(CalcErrorType.domain, message);

CalcException divisionByZero([String message = 'Division by zero']) =>
    CalcException(CalcErrorType.divisionByZero, message);

CalcException overflowError(String message) =>
    CalcException(CalcErrorType.overflow, message);

CalcException unitError(String message) =>
    CalcException(CalcErrorType.unit, message);

CalcException dimensionError(String message) =>
    CalcException(CalcErrorType.dimension, message);

CalcException convergenceError(String message) =>
    CalcException(CalcErrorType.convergence, message);

CalcException limitError(String message) =>
    CalcException(CalcErrorType.limit, message);

CalcException unsupportedError(String message) =>
    CalcException(CalcErrorType.unsupported, message);
