/// Abstract syntax tree of the calculator language.
///
/// The AST is a plain data structure: parsing never evaluates anything, and
/// `toSource()` renders a normalized expression for the history and for the
/// agent-facing result.
library;

sealed class CalcNode {
  const CalcNode(this.position);

  final int position;

  String toSource();
}

class CalcNumberNode extends CalcNode {
  const CalcNumberNode(this.raw, this.value, super.position);

  final String raw;
  final double value;

  @override
  String toSource() => raw;
}

class CalcNameNode extends CalcNode {
  const CalcNameNode(this.name, super.position);

  final String name;

  @override
  String toSource() => name;
}

class CalcUnaryNode extends CalcNode {
  const CalcUnaryNode(this.operator, this.operand, super.position);

  final String operator;
  final CalcNode operand;

  @override
  String toSource() {
    switch (operator) {
      case 'sqrt':
        return 'sqrt(${operand.toSource()})';
      case 'cbrt':
        return 'cbrt(${operand.toSource()})';
      case 'not':
        return 'not(${operand.toSource()})';
      default:
        final rendered = _render(operand, _precedenceOf(this));
        return '$operator$rendered';
    }
  }
}

class CalcBinaryNode extends CalcNode {
  const CalcBinaryNode(
    this.operator,
    this.left,
    this.right,
    super.position, {
    this.implicit = false,
  });

  final String operator;
  final CalcNode left;
  final CalcNode right;

  /// True for implicit multiplication such as `10 kΩ`. It binds tighter than
  /// an explicit `*` and is rendered with an explicit `*`.
  final bool implicit;

  @override
  String toSource() {
    if (operator == '∠') {
      return '${_render(left, _precedenceOf(this))}∠'
          '${_render(right, _precedenceOf(this) + 1)}';
    }
    if (operator == 'to') {
      return '${_render(left, _precedenceOf(this))} to '
          '${_render(right, _precedenceOf(this) + 1)}';
    }
    final symbol = switch (operator) {
      '&&' => ' and ',
      '||' => ' or ',
      'mod' => ' mod ',
      _ => operator,
    };
    final leftSource = _render(left, _precedenceOf(this));
    final rightSource = _render(
      right,
      _precedenceOf(this) + (operator == '^' ? 0 : 1),
    );
    return '$leftSource$symbol$rightSource';
  }
}

class CalcPostfixNode extends CalcNode {
  const CalcPostfixNode(this.operator, this.operand, super.position);

  final String operator;
  final CalcNode operand;

  @override
  String toSource() => '${_render(operand, _precedenceOf(this))}$operator';
}

class CalcCallNode extends CalcNode {
  const CalcCallNode(this.name, this.arguments, super.position);

  final String name;
  final List<CalcNode> arguments;

  @override
  String toSource() =>
      '$name(${arguments.map((argument) => argument.toSource()).join(', ')})';
}

class CalcListNode extends CalcNode {
  const CalcListNode(this.items, super.position);

  final List<CalcNode> items;

  @override
  String toSource() => '[${items.map((item) => item.toSource()).join(', ')}]';
}

class CalcIndexNode extends CalcNode {
  const CalcIndexNode(this.target, this.index, super.position);

  final CalcNode target;
  final CalcNode index;

  @override
  String toSource() =>
      '${_render(target, _precedenceOf(this))}[${index.toSource()}]';
}

class CalcAssignmentNode extends CalcNode {
  const CalcAssignmentNode(this.name, this.value, super.position);

  final String name;
  final CalcNode value;

  @override
  String toSource() => '$name = ${value.toSource()}';
}

class CalcFunctionDefinitionNode extends CalcNode {
  const CalcFunctionDefinitionNode(
    this.name,
    this.parameters,
    this.body,
    super.position,
  );

  final String name;
  final List<String> parameters;
  final CalcNode body;

  @override
  String toSource() => '$name(${parameters.join(', ')}) = ${body.toSource()}';
}

int _precedenceOf(CalcNode node) {
  if (node is CalcUnaryNode) {
    if (node.operator == 'not') return 8;
    return 8;
  }
  if (node is CalcPostfixNode) return 10;
  if (node is CalcBinaryNode) {
    if (node.operator == 'to') return 1;
    if (node.operator == '||') return 2;
    if (node.operator == '&&') return 3;
    if (node.operator == '<' ||
        node.operator == '>' ||
        node.operator == '<=' ||
        node.operator == '>=' ||
        node.operator == '==' ||
        node.operator == '!=') {
      return 4;
    }
    if (node.operator == '+' || node.operator == '-') return 5;
    if (node.operator == '*' ||
        node.operator == '/' ||
        node.operator == '∠' ||
        node.operator == 'mod') {
      return node.implicit ? 7 : 6;
    }
    if (node.operator == '^') return 9;
  }
  return 11;
}

String _render(CalcNode node, int parentPrecedence) {
  final source = node.toSource();
  return _precedenceOf(node) < parentPrecedence ? '($source)' : source;
}
