abstract class Expression {
  R accept<R>(ExpressionVisitor<R> visitor);
}

abstract class ExpressionVisitor<R> {
  R visitBinary(BinaryExpression node);
  R visitUnary(UnaryExpression node);
  R visitLiteral(LiteralExpression node);
  R visitFunctionCall(FunctionCallExpression node);
  R visitReference(ReferenceExpression node);
  R visitRange(RangeExpression node);
}

class BinaryExpression extends Expression {
  final Expression left;
  final String operator;
  final Expression right;

  BinaryExpression(this.left, this.operator, this.right);

  @override
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitBinary(this);
}

class UnaryExpression extends Expression {
  final String operator;
  final Expression right;

  UnaryExpression(this.operator, this.right);

  @override
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitUnary(this);
}

class LiteralExpression extends Expression {
  final dynamic value;

  LiteralExpression(this.value);

  @override
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitLiteral(this);
}

class FunctionCallExpression extends Expression {
  final String name;
  final List<Expression> arguments;

  FunctionCallExpression(this.name, this.arguments);

  @override
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitFunctionCall(this);
}

class ReferenceExpression extends Expression {
  final String name; // e.g. Mode.START

  ReferenceExpression(this.name);

  @override
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitReference(this);
}

class RangeExpression extends Expression {
  final ReferenceExpression start;
  final ReferenceExpression end;

  RangeExpression(this.start, this.end);

  @override
  R accept<R>(ExpressionVisitor<R> visitor) => visitor.visitRange(this);
}
