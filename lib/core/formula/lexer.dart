enum TokenType {
  number,
  string,
  identifier,
  reference, // $Col.START, $Col.END, $Col
  plus,
  minus,
  star,
  slash,
  equal,
  notEqual,
  greater,
  greaterEqual,
  less,
  lessEqual,
  leftParen,
  rightParen,
  comma,
  colon,
  eof
}

class Token {
  final TokenType type;
  final String value;
  final int position;

  Token(this.type, this.value, this.position);

  @override
  String toString() => 'Token($type, "$value", @$position)';
}

class Lexer {
  final String input;
  int _pos = 0;

  Lexer(this.input);

  List<Token> tokenize() {
    List<Token> tokens = [];
    while (_pos < input.length) {
      char c = input[_pos];
      if (_isWhitespace(c)) {
        _pos++;
      } else if (_isDigit(c)) {
        tokens.add(_readNumber());
      } else if (c == '"' || c == "'") {
        tokens.add(_readString(c));
      } else if (c == '\$') {
        tokens.add(_readReference());
      } else if (_isAlpha(c)) {
        tokens.add(_readIdentifier());
      } else {
        tokens.add(_readOperatorOrParen());
      }
    }
    tokens.add(Token(TokenType.eof, "", _pos));
    return tokens;
  }

  bool _isWhitespace(String c) => ' \t\n\r'.contains(c);
  bool _isDigit(String c) => RegExp(r'[0-9]').hasMatch(c);
  bool _isAlpha(String c) => RegExp(r'[a-zA-Z_]').hasMatch(c);
  bool _isAlphaNumeric(String c) => RegExp(r'[a-zA-Z0-9_]').hasMatch(c);

  Token _readNumber() {
    int start = _pos;
    while (_pos < input.length && (_isDigit(input[_pos]) || input[_pos] == '.')) {
      _pos++;
    }
    return Token(TokenType.number, input.substring(start, _pos), start);
  }

  Token _readString(String quote) {
    int start = _pos;
    _pos++; // skip opening quote
    int contentStart = _pos;
    while (_pos < input.length && input[_pos] != quote) {
      _pos++;
    }
    String value = input.substring(contentStart, _pos);
    if (_pos < input.length) _pos++; // skip closing quote
    return Token(TokenType.string, value, start);
  }

  Token _readIdentifier() {
    int start = _pos;
    while (_pos < input.length && _isAlphaNumeric(input[_pos])) {
      _pos++;
    }
    return Token(TokenType.identifier, input.substring(start, _pos), start);
  }

  Token _readReference() {
    int start = _pos;
    _pos++; // skip $
    // A reference can contain spaces if it's like $My Column.START
    // Current regex was: \$([^$.(),=<>:!]+)(?:\.START|\.END|(?=[,=\)<>:]|$))
    // It stops at . ( ) , = < > : ! or EOF
    
    int contentStart = _pos;
    while (_pos < input.length && !r'$.(),=<>:!'.contains(input[_pos])) {
      _pos++;
    }
    
    String colName = input.substring(contentStart, _pos).trim();
    String suffix = "";
    if (_pos < input.length && input[_pos] == '.') {
      int suffixStart = _pos;
      if (input.startsWith(".START", _pos)) {
        _pos += 6;
        suffix = ".START";
      } else if (input.startsWith(".END", _pos)) {
        _pos += 4;
        suffix = ".END";
      }
    }
    
    return Token(TokenType.reference, colName + suffix, start);
  }

  Token _readOperatorOrParen() {
    int start = _pos;
    String c = input[_pos++];
    switch (c) {
      case '(': return Token(TokenType.leftParen, "(", start);
      case ')': return Token(TokenType.rightParen, ")", start);
      case ',': return Token(TokenType.comma, ",", start);
      case ':': return Token(TokenType.colon, ":", start);
      case '+': return Token(TokenType.plus, "+", start);
      case '-': return Token(TokenType.minus, "-", start);
      case '*': return Token(TokenType.star, "*", start);
      case '/': return Token(TokenType.slash, "/", start);
      case '=': return Token(TokenType.equal, "=", start);
      case '>':
        if (_pos < input.length && input[_pos] == '=') {
          _pos++;
          return Token(TokenType.greaterEqual, ">=", start);
        }
        return Token(TokenType.greater, ">", start);
      case '<':
        if (_pos < input.length && input[_pos] == '=') {
          _pos++;
          return Token(TokenType.lessEqual, "<=", start);
        } else if (_pos < input.length && input[_pos] == '>') {
          _pos++;
          return Token(TokenType.notEqual, "<>", start);
        }
        return Token(TokenType.less, "<", start);
      default:
        throw Exception("Unknown character '$c' at position $start");
    }
  }
}

typedef char = String;
