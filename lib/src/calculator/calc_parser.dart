/// Recursive-descent / Pratt parser for the calculator language.
///
/// Parsing is a pure transformation from text to [CalcNode]s. No user text is
/// ever passed to `eval`, `Function` or any other dynamic code execution.
///
/// Precedence (low to high):
///   conversion (`to`, `in`, `->`)
///   `or`
///   `and`
///   comparisons
///   `+`, `-`
///   `*`, `/`, `mod`, polar `∠`
///   implicit multiplication (`10 kΩ`, `2π`, `2(3+4)`)
///   unary `+`, `-`, `√`, `∛`, `not`
///   `^` (right-associative)
///   factorial `!` and indexing `[...]`
///
/// Implicit multiplication binds tighter than an explicit `*` or `/`, so
/// `3.3 V / 220 Ω` is `(3.3 V) / (220 Ω)` and `1/2x` is `1/(2x)`.
library;

import 'calc_ast.dart';
import 'calc_dimension.dart';
import 'calc_error.dart';
import 'calc_lexer.dart';
import 'calc_units.dart';

class CalcParser {
  CalcParser(this._tokens);

  factory CalcParser.parse(String source) => CalcParser(tokenize(source));

  final List<CalcToken> _tokens;
  int _index = 0;

  CalcToken get _current => _tokens[_index];

  CalcToken get _next =>
      _index + 1 < _tokens.length ? _tokens[_index + 1] : _tokens.last;

  bool get _atEnd => _current.type == CalcTokenType.eof;

  CalcToken _advance() {
    final token = _current;
    if (_index < _tokens.length - 1) _index++;
    return token;
  }

  bool _matchOperator(String operator) {
    if (_current.type != CalcTokenType.operator || _current.text != operator) {
      return false;
    }
    _advance();
    return true;
  }

  CalcToken _expect(CalcTokenType type, String description) {
    if (_current.type != type) {
      throw syntaxError(
        'expected $description, found "${_current.text}"',
        _current.position,
      );
    }
    return _advance();
  }

  /// Parses every statement of [source].
  List<CalcNode> parseProgram() {
    final statements = <CalcNode>[];
    while (true) {
      while (_current.type == CalcTokenType.separator) {
        _advance();
      }
      if (_atEnd) break;
      statements.add(_parseStatement());
      if (_current.type == CalcTokenType.separator) {
        _advance();
        continue;
      }
      if (_atEnd) break;
      throw syntaxError('unexpected "${_current.text}"', _current.position);
    }
    return statements;
  }

  CalcNode _parseStatement() => _parseExpression(0);

  CalcNode _parseExpression(int minimumPrecedence) {
    var left = _parsePrefix();

    while (true) {
      final token = _current;

      if (token.type == CalcTokenType.operator &&
          token.text == '!' &&
          10 >= minimumPrecedence) {
        _advance();
        left = CalcPostfixNode('!', left, token.position);
        continue;
      }

      if (token.type == CalcTokenType.leftBracket && 10 >= minimumPrecedence) {
        _advance();
        final index = _parseExpression(0);
        _expect(CalcTokenType.rightBracket, '"]"');
        left = CalcIndexNode(left, index, token.position);
        continue;
      }

      final binary = _binaryOperatorAt(token);
      if (binary != null) {
        if (binary.precedence < minimumPrecedence) break;
        _advance();
        // The polar operator takes a plain angle expression. Its right side
        // must not swallow a trailing unit such as the Ω in `75∠30° Ω`, but
        // it must include the angle unit in `30°`.
        final rightMinimum = binary.symbol == '∠'
            ? 8
            : binary.precedence + (binary.rightAssociative ? 0 : 1);
        final right = _parseExpression(rightMinimum);
        left = CalcBinaryNode(binary.symbol, left, right, token.position);
        continue;
      }

      // Implicit multiplication binds tighter than `*` and `/`. An angle
      // unit binds even tighter, so `75∠30°` captures the degree sign while
      // `75∠30° Ω` leaves Ω for the outer multiplication.
      final implicitPrecedence = _implicitPrecedence(token);
      if (implicitPrecedence >= minimumPrecedence && _startsPrimary(token)) {
        final right = _parseExpression(implicitPrecedence + 1);
        left = CalcBinaryNode('*', left, right, token.position, implicit: true);
        continue;
      }

      break;
    }

    // Assignment is the lowest-precedence, right-associative operator. It is
    // handled here so it also works inside arguments, e.g.
    // `for(i, 1, 10, total = total + i)`.
    if (minimumPrecedence == 0 && _matchOperator('=')) {
      final value = _parseExpression(0);
      if (left is CalcNameNode) {
        return CalcAssignmentNode(left.name, value, left.position);
      }
      if (left is CalcCallNode) {
        final parameters = <String>[];
        for (final argument in left.arguments) {
          if (argument is! CalcNameNode) {
            throw syntaxError(
              'function parameters must be names',
              argument.position,
            );
          }
          parameters.add(argument.name);
        }
        return CalcFunctionDefinitionNode(
          left.name,
          parameters,
          value,
          left.position,
        );
      }
      throw syntaxError(
        'the left side of "=" must be a variable or function name',
        left.position,
      );
    }

    return left;
  }

  CalcNode _parsePrefix() {
    final token = _current;
    if (token.type == CalcTokenType.operator) {
      switch (token.text) {
        case '+':
        case '-':
          _advance();
          return CalcUnaryNode(token.text, _parseExpression(8), token.position);
        case '√':
          _advance();
          return CalcUnaryNode('sqrt', _parseExpression(8), token.position);
        case '∛':
          _advance();
          return CalcUnaryNode('cbrt', _parseExpression(8), token.position);
      }
    }
    if (token.isIdentifier && token.text == 'not') {
      final after = _next;
      if (after.type != CalcTokenType.leftParen) {
        _advance();
        return CalcUnaryNode('not', _parseExpression(8), token.position);
      }
    }
    return _parsePrimary();
  }

  CalcNode _parsePrimary() {
    final token = _current;

    if (token.type == CalcTokenType.number) {
      _advance();
      return CalcNumberNode(
        token.text,
        token.numberValue ?? double.nan,
        token.position,
      );
    }

    if (token.type == CalcTokenType.identifier) {
      _advance();
      if (_current.type == CalcTokenType.leftParen) {
        return _parseCall(token);
      }
      return CalcNameNode(token.text, token.position);
    }

    if (token.type == CalcTokenType.leftParen) {
      _advance();
      if (_current.type == CalcTokenType.rightParen) {
        throw syntaxError('empty parentheses', token.position);
      }
      final expression = _parseExpression(0);
      _expect(CalcTokenType.rightParen, '")"');
      return expression;
    }

    if (token.type == CalcTokenType.leftBracket) {
      return _parseList(token);
    }

    throw syntaxError(
      'expected a value, found "${token.text}"',
      token.position,
    );
  }

  CalcNode _parseCall(CalcToken nameToken) {
    _expect(CalcTokenType.leftParen, '"("');
    final arguments = <CalcNode>[];
    if (_current.type != CalcTokenType.rightParen) {
      while (true) {
        arguments.add(_parseExpression(0));
        if (_current.type == CalcTokenType.comma) {
          _advance();
          continue;
        }
        break;
      }
    }
    _expect(CalcTokenType.rightParen, '")"');
    return CalcCallNode(nameToken.text, arguments, nameToken.position);
  }

  CalcNode _parseList(CalcToken bracketToken) {
    _expect(CalcTokenType.leftBracket, '"["');
    final items = <CalcNode>[];
    if (_current.type != CalcTokenType.rightBracket) {
      while (true) {
        items.add(_parseExpression(0));
        if (_current.type == CalcTokenType.comma) {
          _advance();
          continue;
        }
        break;
      }
    }
    _expect(CalcTokenType.rightBracket, '"]"');
    return CalcListNode(items, bracketToken.position);
  }

  _BinaryOperator? _binaryOperatorAt(CalcToken token) {
    if (token.type == CalcTokenType.operator) {
      switch (token.text) {
        case '->':
          return const _BinaryOperator('to', 1, false);
        case '||':
          return const _BinaryOperator('||', 2, false);
        case '&&':
          return const _BinaryOperator('&&', 3, false);
        case '<':
        case '>':
        case '<=':
        case '>=':
        case '==':
        case '!=':
          return _BinaryOperator(token.text, 4, false);
        case '+':
        case '-':
          return _BinaryOperator(token.text, 5, false);
        case '*':
        case '/':
        case 'mod':
          return _BinaryOperator(token.text, 6, false);
        case '∠':
          return const _BinaryOperator('∠', 6, false);
        case '^':
          return const _BinaryOperator('^', 9, true);
      }
      return null;
    }

    if (token.type == CalcTokenType.identifier) {
      // `to(` and `in(` are function calls, not infix conversions.
      final isCall = _next.type == CalcTokenType.leftParen;
      if (isCall) return null;
      switch (token.text) {
        // `in` is deliberately not a conversion operator: it is the inch
        // unit. Use `to` or the `in(value, unit)` function instead.
        case 'to':
          return const _BinaryOperator('to', 1, false);
        case 'or':
          return const _BinaryOperator('||', 2, false);
        case 'and':
          return const _BinaryOperator('&&', 3, false);
        case 'mod':
          return const _BinaryOperator('mod', 6, false);
      }
    }
    return null;
  }

  int _implicitPrecedence(CalcToken token) {
    if (token.type == CalcTokenType.identifier) {
      final unit = CalcUnits.resolve(token.text);
      if (unit != null &&
          unit.dimension.isCompatibleWith(CalcDimension.base('rad'))) {
        return 9;
      }
    }
    return 7;
  }

  bool _startsPrimary(CalcToken token) {
    switch (token.type) {
      case CalcTokenType.number:
      case CalcTokenType.identifier:
      case CalcTokenType.leftParen:
      case CalcTokenType.leftBracket:
        return true;
      case CalcTokenType.operator:
        return token.text == '√' || token.text == '∛';
      default:
        return false;
    }
  }
}

class _BinaryOperator {
  const _BinaryOperator(this.symbol, this.precedence, this.rightAssociative);

  final String symbol;
  final int precedence;
  final bool rightAssociative;
}
