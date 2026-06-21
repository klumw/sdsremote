# Macro Expression Precedence

This document describes the operator precedence rules for the SDS Remote macro expression engine.

## Precedence Table

Operators are listed from highest to lowest precedence. Operators on the same level are **left-associative** (evaluated left-to-right).

| Precedence | Category | Operators | Associativity |
|-----------|----------|-----------|---------------|
| 1 | Parentheses | `( )` | — |
| 2 | Unary | `!` (logical NOT), `-` (unary minus) | Right-to-left |
| 3 | Multiplicative | `*` `/` | Left-to-right |
| 4 | Additive | `+` `-` | Left-to-right |
| 5 | Relational | `>` `>=` `<` `<=` | Left-to-right |
| 6 | Equality | `==` `!=` | Left-to-right |
| 7 | Logical AND | `&&` (also accepts `&`) | Left-to-right |
| 8 | Logical OR | `\|\|` (also accepts `\|`) | Left-to-right |

## Expression Grammar

The precedence is enforced structurally by the grammar:

```text
Expression        → OrExpression
OrExpression      → AndExpression (('||' | '|') AndExpression)*
AndExpression     → EqualityExpression (('&&' | '&') EqualityExpression)*
EqualityExpression → RelationalExpression (('==' | '!=') RelationalExpression)*
RelationalExpression → AdditiveExpression (('>' | '>=' | '<' | '<=') AdditiveExpression)*
AdditiveExpression → MultiplicativeExpression (('+' | '-') MultiplicativeExpression)*
MultiplicativeExpression → UnaryExpression (('*' | '/') UnaryExpression)*
UnaryExpression   → '!' UnaryNotOperand | '-' UnaryExpression | PrimaryExpression
UnaryNotOperand   → '-' UnaryExpression | PrimaryExpression
PrimaryExpression → number | string_literal | 'true' | 'false'
                  | 'query' '(' ... ')'
                  | 'scpi' '(' ... ')'
                  | identifier
                  | '(' Expression ')'
```

## Evaluation Rules

### Type Coercion

- **Arithmetic operators** (`+`, `-`, `*`, `/`): Both operands must be numbers. Strings that parse as numbers (e.g., `"3.14"`) are coerced automatically. Boolean values and non-numeric strings cause a runtime error.
- **Relational operators** (`>`, `>=`, `<`, `<=`): Both operands must be numbers. Same coercion rules as arithmetic.
- **Equality operators** (`==`, `!=`): If both operands parse as numbers, numeric comparison is used. Otherwise, string comparison is used.
- **Logical operators** (`&&`, `||`): Both operands must be booleans. Numbers (non-zero → `true`) and strings (truthiness rules) are coerced.
- **Unary minus** (`-`): Operand must be a number. Coerces numeric strings.
- **Logical NOT** (`!`): Operand must be a boolean. Coerces numbers and strings.

### Truthiness Rules

A string value is **truthy** unless it is:
- Empty (`""`)
- Exactly `"0"`
- Exactly `"OFF"` (case-insensitive)

A number is truthy unless it is `0`.

### Short-Circuit Evaluation

- `a && b`: If `a` evaluates to `false`, `b` is **not evaluated**.
- `a || b`: If `a` evaluates to `true`, `b` is **not evaluated**.

## Examples

### Parentheses Override Everything

```
(2 + 3) * 4  →  20
2 * (3 + 4)  →  14
```

### Multiplication Before Addition

```
2 + 3 * 4    →  14   (not 20)
20 - 10 / 2  →  15   (not 5)
```

### Left-to-Right for Same Precedence

```
20 / 5 * 2   →  8    (not 2)
100 / 10 / 2 →  5    (not 20)
10 - 5 + 2   →  7    (not 3)
```

### Unary Minus

```
-5 + 10      →  5
-(2 + 3)     →  -5
2 * -3       →  -6
```

### Boolean NOT

```
!(5 > 3)     →  false
!(5 < 3)     →  true
!true        →  false
!false       →  true
```

### Comparison Before Logical Operators

```
5 > 3 && 2 < 4  →  true          // interpreted as (5 > 3) && (2 < 4)
5 > 3 || 10 < 2 →  true          // interpreted as (5 > 3) || (10 < 2)
```

### Equality After Relational

```
5 > 3 == true  →  true           // interpreted as (5 > 3) == true
```

### Logical AND Before Logical OR

```
true || false && false  →  true  // interpreted as true || (false && false)
```

### Mixed Precedence

```
2 + 3 * 4 > 10                →  true
2 + 3 * 4 > 20                →  false
!(5 > 3 && 10 > 2)            →  false
!(5 > 3) || 2 + 3 * 4 > 20    →  false
```

## AST Structure

The AST directly reflects operator precedence. For example, `2 + 3 * 4` produces:

```text
BinaryExpr
├─ left: NumberLiteral(2)
├─ op: "+"
└─ right: BinaryExpr
    ├─ left: NumberLiteral(3)
    ├─ op: "*"
    └─ right: NumberLiteral(4)
```

## Linter Rules

The macro linter provides additional diagnostics for expression usage:

### SuspiciousMixedOperators (Warning)

Detects expressions mixing arithmetic, comparison, and logical operators without clarifying parentheses.

```
a + b * c > d && e == f
```

**Suggestion:** Add parentheses to make evaluation order explicit.

### RedundantParentheses (Info)

Detects unnecessary double-wrapping of simple expressions.

```
((a))      →  a
((42))     →  42
```

### ComparisonChain (Error)

Detects chained comparisons, which are **not supported**.

```
a > b > c   →  Error: Chained comparisons are not supported.
                  Use explicit logical operators instead:
                  a > b && b > c
```

Because relational operators are left-associative, `a > b > c` parses as `(a > b) > c` (comparing a boolean with a number), which is almost certainly not what was intended.

### MixedEqualityAndRelational (Warning)

Detects potentially confusing mixtures of equality and relational operators.

```
a > b == true
```

This is evaluated correctly as `(a > b) == true`, but the linter warns to ensure the intent is clear. Add explicit parentheses to suppress the warning:

```
(a > b) == true
```
