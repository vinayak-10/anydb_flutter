import '../core/formula_engine.dart';
import '../core/cell_helper.dart';

/// ReportFormulaService: Decoupled formula calculation module.
/// Computes static formula values, processes title-to-key translations,
/// and returns evaluation maps.
class ReportFormulaService {
  /// Computes summary formulas and creates a map of cell references to calculated results.
  /// Used for pre-calculating results that will be injected into the spreadsheet XML.
  static FormulaCalculationResult calculateSummaryFormulas({
    required Map<String, dynamic> jo,
    required String sheetName,
    required int summaryValRow,
    required int dataStartRow,
  }) {
    final Map<String, dynamic> formulasMap = Map<String, dynamic>.from(jo['summaryFormulas'] ?? jo['summary'] ?? {});
    final List<dynamic> formulaValues = formulasMap.values.toList();
    final List<dynamic> tableData = jo['data'] ?? [];
    
    final List<String> columnNames = tableData.isNotEmpty
        ? Map<String, dynamic>.from(tableData.first as Map).keys.toList()
        : [];
        
    final List<Map<String, dynamic>> records = tableData
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();

    // Map column titles to keys
    final Map<String, String> titleToKeyMap = {};
    final List<dynamic> columns = jo['columns'] ?? [];
    for (var col in columns) {
      if (col is Map) {
        final title = col['title']?.toString() ?? "";
        final column = col['column']?.toString() ?? col['title']?.toString() ?? "";
        if (title.isNotEmpty && column.isNotEmpty) {
          titleToKeyMap[title] = column;
          titleToKeyMap[column] = title;
        }
      }
    }

    final Map<String, String> formulaValuesCache = {};
    final List<String> compiledFormulaStrings = [];

    // Excel is 1-indexed for row strings
    final int sr = dataStartRow + 1;
    final int er = sr + (tableData.isNotEmpty ? tableData.length - 1 : 0);

    for (int i = 0; i < formulaValues.length; i++) {
      final vs = CellHelper.unwrap(formulaValues[i]).toString();
      
      // Calculate using AST Engine
      final dynamic calculatedValue = FormulaEngine.evaluate(
        vs,
        records,
        columnNames,
        titleToKeyMap,
      );

      // Translate formula referencing column names into Excel cell ranges
      final formulated = FormulaEngine.formulate(
        vs,
        columnNames,
        sr,
        er,
        sheetName: sheetName,
      );
      
      String formulaStr = formulated ?? vs;
      if (formulaStr.startsWith('=')) {
        formulaStr = formulaStr.substring(1);
      }
      
      compiledFormulaStrings.add(formulaStr);
      final cellRef = _getCellRef(i, summaryValRow);
      formulaValuesCache["$sheetName!$cellRef"] = calculatedValue.toString();
    }

    return FormulaCalculationResult(
      formulaValuesCache: formulaValuesCache,
      compiledFormulas: compiledFormulaStrings,
      columnNames: columnNames,
      records: records,
    );
  }

  static String _getCellRef(int colIdx, int rowIdx) {
    int temp = colIdx;
    String columnLetter = "";
    while (temp >= 0) {
      columnLetter = String.fromCharCode((temp % 26) + 65) + columnLetter;
      temp = (temp ~/ 26) - 1;
    }
    return "$columnLetter${rowIdx + 1}";
  }
}

class FormulaCalculationResult {
  final Map<String, String> formulaValuesCache;
  final List<String> compiledFormulas;
  final List<String> columnNames;
  final List<Map<String, dynamic>> records;

  FormulaCalculationResult({
    required this.formulaValuesCache,
    required this.compiledFormulas,
    required this.columnNames,
    required this.records,
  });
}
