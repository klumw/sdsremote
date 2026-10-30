/// Tokenizer of the calculator expression language.
///
/// The lexer understands decimal, hexadecimal, binary and octal numbers,
/// Unicode unit symbols (Ω, µ, °), the polar operator ∠, superscript powers
/// and statement separators. It never executes user input.
library;

import 'calc_error.dart';

enum CalcTokenType {
  number,
  identifier,
  operator,
  leftParen,
  rightParen,
  leftBracket,
  rightBracket,
  comma,
  separator,
  eof,
}

/// One lexical token with its source offset.
class CalcToken {
  const CalcToken({
    required this.type,
    required this.text,
    required this.position,
    this.numberValue,
  });

  final CalcTokenType type;
  final String text;
  final int position;

  /// Parsed numeric value for [CalcTokenType.number].
  final double? numberValue;

  bool get isIdentifier => type == CalcTokenType.identifier;

  bool get isOperator => type == CalcTokenType.operator;

  @override
  String toString() => '$type("$text")@$position';
}

/// Converts [source] into tokens. Newlines at bracket depth zero become
/// statement separators, so multi-line programs work while matrices and
/// function arguments can span lines.
List<CalcToken> tokenize(String source) {
  final tokens = <CalcToken>[];
  var index = 0;
  var bracketDepth = 0;

  void add(
    CalcTokenType type,
    String text,
    int position, [
    double? numberValue,
  ]) {
    tokens.add(
      CalcToken(
        type: type,
        text: text,
        position: position,
        numberValue: numberValue,
      ),
    );
  }

  while (index < source.length) {
    final code = source.codeUnitAt(index);
    final char = source[index];

    // Whitespace.
    if (char == ' ' || char == '\t' || char == '\r') {
      index++;
      continue;
    }

    // Comments: # and // to end of line.
    if (char == '#' ||
        (char == '/' &&
            index + 1 < source.length &&
            source[index + 1] == '/')) {
      while (index < source.length && source[index] != '\n') {
        index++;
      }
      continue;
    }

    if (char == '\n' || char == ';') {
      if (bracketDepth == 0) {
        add(CalcTokenType.separator, ';', index);
      }
      index++;
      continue;
    }

    if (char == '(') {
      bracketDepth++;
      add(CalcTokenType.leftParen, char, index);
      index++;
      continue;
    }
    if (char == ')') {
      if (bracketDepth > 0) bracketDepth--;
      add(CalcTokenType.rightParen, char, index);
      index++;
      continue;
    }
    if (char == '[') {
      bracketDepth++;
      add(CalcTokenType.leftBracket, char, index);
      index++;
      continue;
    }
    if (char == ']') {
      if (bracketDepth > 0) bracketDepth--;
      add(CalcTokenType.rightBracket, char, index);
      index++;
      continue;
    }
    if (char == ',') {
      add(CalcTokenType.comma, char, index);
      index++;
      continue;
    }

    // Superscript powers.
    if (char == '²' || char == '³') {
      add(CalcTokenType.operator, '^', index);
      add(
        CalcTokenType.number,
        char == '²' ? '2' : '3',
        index,
        char == '²' ? 2 : 3,
      );
      index++;
      continue;
    }

    // Normalized Unicode operators.
    final normalized = _normalizeOperator(char);
    if (normalized != null) {
      add(CalcTokenType.operator, normalized, index);
      index++;
      continue;
    }

    // Percent is a unit symbol, but not a letter.
    if (char == '%') {
      add(CalcTokenType.identifier, char, index);
      index++;
      continue;
    }

    // Multi-character operators.
    String? multi;
    if (index + 1 < source.length) {
      final two = source.substring(index, index + 2);
      if (two == '<=' ||
          two == '>=' ||
          two == '==' ||
          two == '!=' ||
          two == '**' ||
          two == '&&' ||
          two == '||') {
        multi = two;
      }
    }
    if (multi != null) {
      add(CalcTokenType.operator, multi == '**' ? '^' : multi, index);
      index += 2;
      continue;
    }
    if (char == '+' ||
        char == '-' ||
        char == '*' ||
        char == '/' ||
        char == '^' ||
        char == '!' ||
        char == '=' ||
        char == '<' ||
        char == '>' ||
        char == '∠' ||
        char == '√' ||
        char == '∛') {
      add(CalcTokenType.operator, char, index);
      index++;
      continue;
    }

    // Numbers.
    if (_isDigit(code) || (char == '.' && _nextIsDigit(source, index + 1))) {
      final start = index;
      var value = 0.0;
      if (char == '0' && index + 1 < source.length) {
        final prefix = source[index + 1].toLowerCase();
        if (prefix == 'x' || prefix == 'b' || prefix == 'o') {
          final radix = prefix == 'x' ? 16 : (prefix == 'b' ? 2 : 8);
          index += 2;
          final digitsStart = index;
          while (index < source.length && _digitValue(source[index]) < radix) {
            index++;
          }
          if (index == digitsStart) {
            throw syntaxError(
              'expected digits after 0${source[start + 1]}',
              start,
            );
          }
          final text = source.substring(digitsStart, index);
          value = int.parse(text, radix: radix).toDouble();
          add(
            CalcTokenType.number,
            source.substring(start, index),
            start,
            value,
          );
          continue;
        }
      }

      var hasDigits = false;
      while (index < source.length && _isDigit(source.codeUnitAt(index))) {
        index++;
        hasDigits = true;
      }
      if (index < source.length && source[index] == '.') {
        index++;
        while (index < source.length && _isDigit(source.codeUnitAt(index))) {
          index++;
          hasDigits = true;
        }
      }
      if (!hasDigits) {
        throw syntaxError('invalid number', start);
      }
      if (index < source.length &&
          (source[index] == 'e' || source[index] == 'E')) {
        final exponentStart = index;
        index++;
        if (index < source.length &&
            (source[index] == '+' || source[index] == '-')) {
          index++;
        }
        final digitsStart = index;
        while (index < source.length && _isDigit(source.codeUnitAt(index))) {
          index++;
        }
        if (index == digitsStart) {
          // `1e` is the number 1 followed by Euler's constant, not a broken
          // exponent; roll back to that interpretation.
          index = exponentStart;
        }
      }
      final text = source.substring(start, index);
      value = double.tryParse(text) ?? double.nan;
      if (!value.isFinite) {
        throw syntaxError('number is not finite: $text', start);
      }
      add(CalcTokenType.number, text, start, value);
      continue;
    }

    // Identifiers (names, constants, units, functions).
    if (_isIdentifierStart(code)) {
      final start = index;
      // Imaginary shorthand `j25` / `i25`: keep the unit separate from the
      // number so the parser can apply implicit multiplication.
      if ((char == 'j' || char == 'i') &&
          index + 1 < source.length &&
          _isDigit(source.codeUnitAt(index + 1))) {
        add(CalcTokenType.identifier, char, start);
        index++;
        continue;
      }
      index++;
      while (index < source.length) {
        final next = source.codeUnitAt(index);
        if (_isIdentifierPart(next)) {
          index++;
          continue;
        }
        break;
      }
      add(CalcTokenType.identifier, source.substring(start, index), start);
      continue;
    }

    throw syntaxError('unexpected character "$char"', index);
  }

  add(CalcTokenType.eof, '', source.length);
  return tokens;
}

bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

bool _nextIsDigit(String source, int index) =>
    index < source.length && _isDigit(source.codeUnitAt(index));

int _digitValue(String char) {
  final code = char.codeUnitAt(0);
  if (code >= 0x30 && code <= 0x39) return code - 0x30;
  if (code >= 0x41 && code <= 0x46) return code - 0x41 + 10;
  if (code >= 0x61 && code <= 0x66) return code - 0x61 + 10;
  return 99;
}

bool _isIdentifierStart(int code) {
  if (code >= 0x41 && code <= 0x5A) return true;
  if (code >= 0x61 && code <= 0x7A) return true;
  if (code == 0x5F) return true;
  // Unicode letters and unit symbols such as Ω, µ, π, °, Å. Known operators
  // are handled before this check.
  if (code > 0x7F) {
    return !_unicodeOperators.contains(String.fromCharCode(code));
  }
  return false;
}

bool _isIdentifierPart(int code) {
  if (_isIdentifierStart(code)) return true;
  return _isDigit(code);
}

const Set<String> _unicodeOperators = {
  '²',
  '³',
  '×',
  '÷',
  '−',
  '·',
  '∙',
  '≤',
  '≥',
  '≠',
  '∠',
  '√',
  '∛',
  '→',
};

String? _normalizeOperator(String char) {
  switch (char) {
    case '×':
    case '·':
    case '∙':
      return '*';
    case '÷':
      return '/';
    case '−':
      return '-';
    case '≤':
      return '<=';
    case '≥':
      return '>=';
    case '≠':
      return '!=';
    case '→':
      return '->';
    case '∠':
      return '∠';
    case '√':
      return '√';
    case '∛':
      return '∛';
    case 'π':
      return null; // handled as an identifier
    default:
      return null;
  }
}
