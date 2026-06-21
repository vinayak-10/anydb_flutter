import 'formula/lexer.dart';
import 'formula/parser.dart';
import 'formula/evaluator.dart';
import 'logger.dart';

class FormulaEngine {
  /// Evaluates a formula based on provided data rows using AST-based engine.
  static dynamic evaluate(
    String formula,
    List<Map<String, dynamic>> data, [
    List<dynamic>? headers,
  ]) {
    if (formula.isEmpty) return "";
    String f = formula.trim();
    if (f.startsWith("=")) f = f.substring(1).trim();

    try {
      final lexer = Lexer(f);
      final tokens = lexer.tokenize();
      final parser = Parser(tokens);
      final expression = parser.parse();
      final evaluator = Evaluator(data, headers);

      final result = evaluator.evaluate(expression);
      logger.log("FormulaEngine: '$f' -> $result (Rows: ${data.length})");
      return result;
    } catch (e) {
      logger.log("FormulaEngine Error: $e for formula '$formula'");
      return "Error";
    }
  }

  static String? formulate(
    String formula,
    List<dynamic>? headers,
    int startRow,
    int endRow, {
    String? sheetName,
    int startColOffset = 0,
  }) {
    if (headers == null || headers.isEmpty) return formula;

    String getColumnOf(String colName) {
      final normalizedSearch = colName.trim().toLowerCase();
      for (int i = 0; i < headers.length; i++) {
        if (headers[i].toString().trim().toLowerCase() == normalizedSearch) {
          int colIdx = i + startColOffset;
          String columnLetter = "";
          while (colIdx >= 0) {
            columnLetter =
                String.fromCharCode((colIdx % 26) + 65) + columnLetter;
            colIdx = (colIdx ~/ 26) - 1;
          }
          return columnLetter;
        }
      }
      return "";
    }

    final regex = RegExp(r"\$([^$.(),=<>:!]+)(?:\.START|\.END)");
    String result = formula;

    final matches = regex.allMatches(formula).toList().reversed;
    for (final match in matches) {
      final colName = match.group(1)!;
      final suffix = match.group(0)!.contains(".END") ? ".END" : ".START";

      String columnLetter = getColumnOf(colName);
      if (columnLetter.isNotEmpty) {
        String excelRef =
            "$columnLetter${suffix == ".START" ? startRow : endRow}";
        result = result.replaceRange(match.start, match.end, excelRef);
      }
    }

    return result;
  }
}
