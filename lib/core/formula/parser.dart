import 'lexer.dart';
import 'ast.dart';

class Parser {
  final List<Token> tokens;
  int _current = 0;

  Parser(this.tokens);

  Expression parse() {
    return _expression();
  }

  Expression _expression() {
    return _comparison();
  }

  Expression _comparison() {
    Expression expr = _term();

    while (_match([
      TokenType.equal,
      TokenType.notEqual,
      TokenType.greater,
      TokenType.greaterEqual,
      TokenType.less,
      TokenType.lessEqual
    ])) {
      String operator = _previous().value;
      Expression right = _term();
      expr = BinaryExpression(expr, operator, right);
    }

    return expr;
  }

  Expression _term() {
    Expression expr = _factor();

    while (_match([TokenType.plus, TokenType.minus])) {
      String operator = _previous().value;
      Expression right = _factor();
      expr = BinaryExpression(expr, operator, right);
    }

    return expr;
  }

  Expression _factor() {
    Expression expr = _unary();

    while (_match([TokenType.star, TokenType.slash])) {
      String operator = _previous().value;
      Expression right = _unary();
      expr = BinaryExpression(expr, operator, right);
    }

    return expr;
  }

  Expression _unary() {
    if (_match([TokenType.minus, TokenType.plus])) {
      String operator = _previous().value;
      Expression right = _unary();
      return UnaryExpression(operator, right);
    }

    return _primary();
  }

  Expression _primary() {
    if (_match([TokenType.number])) {
      return LiteralExpression(double.parse(_previous().value));
    }

    if (_match([TokenType.string])) {
      return LiteralExpression(_previous().value);
    }

    if (_match([TokenType.leftParen])) {
      Expression expr = _expression();
      _consume(TokenType.rightParen, "Expect ')' after expression.");
      return expr;
    }

    if (_match([TokenType.reference])) {
      ReferenceExpression ref = ReferenceExpression(_previous().value);
      if (_match([TokenType.colon])) {
        Token next = _consume(TokenType.reference, "Expect reference after ':'.");
        return RangeExpression(ref, ReferenceExpression(next.value));
      }
      return ref;
    }

    if (_match([TokenType.identifier])) {
      String name = _previous().value.toUpperCase();
      if (_match([TokenType.leftParen])) {
        List<Expression> arguments = [];
        if (!_check(TokenType.rightParen)) {
          do {
            arguments.add(_expression());
          } while (_match([TokenType.comma]));
        }
        _consume(TokenType.rightParen, "Expect ')' after arguments.");
        return FunctionCallExpression(name, arguments);
      }
      // If no parens, it might be a named constant or something?
      // For now, treat as literal string if not a function.
      return LiteralExpression(name);
    }

    throw _error(_peek(), "Expect expression.");
  }

  bool _match(List<TokenType> types) {
    for (TokenType type in types) {
      if (_check(type)) {
        _advance();
        return true;
      }
    }
    return false;
  }

  bool _check(TokenType type) {
    if (_isAtEnd()) return false;
    return _peek().type == type;
  }

  Token _advance() {
    if (!_isAtEnd()) _current++;
    return _previous();
  }

  bool _isAtEnd() => _peek().type == TokenType.eof;

  Token _peek() => tokens[_current];

  Token _previous() => tokens[_current - 1];

  Token _consume(TokenType type, String message) {
    if (_check(type)) return _advance();
    throw _error(_peek(), message);
  }

  Exception _error(Token token, String message) {
    return Exception("[at ${token.position}] $message");
  }
}
