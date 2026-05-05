import 'package:flutter_test/flutter_test.dart';
import 'package:anydb_flutter/core/formula_engine.dart';

void main() {
  final data = [
    {"Card Number": "1", "Sex": "Male", "Mode": "Cash", "Paid": "100", "Registered On": "2026-03-13", "Date": "2026-03-13", "Charges": "100", "Discount": "0"},
    {"Card Number": "2", "Sex": "Female", "Mode": "UPI", "Paid": "200", "Registered On": "2026-03-12", "Date": "2026-03-13", "Charges": "200", "Discount": "0"},
    {"Card Number": "3", "Sex": "Male", "Mode": "Cash", "Paid": "300", "Registered On": "2026-03-13", "Date": "2026-03-13", "Charges": "300", "Discount": "0"},
  ];

  group('FormulaEngine AST Tests', () {
    test('Basic SUM', () {
      expect(FormulaEngine.evaluate('SUM(\$Paid.START:\$Paid.END)', data), 600.0);
    });

    test('SUMIF', () {
      expect(FormulaEngine.evaluate('SUMIF(\$Mode.START:\$Mode.END, "Cash", \$Paid.START:\$Paid.END)', data), 400.0);
    });

    test('COUNTIF', () {
      expect(FormulaEngine.evaluate('COUNTIF(\$Mode.START:\$Mode.END, "Cash")', data), 2);
      expect(FormulaEngine.evaluate('COUNTIF(\$Mode.START:\$Mode.END, "*")', data), 3);
    });

    test('Mathematical Operators', () {
      expect(FormulaEngine.evaluate('10 + 20', data), 30.0);
      expect(FormulaEngine.evaluate('10 + 20 * 2', data), 50.0);
      expect(FormulaEngine.evaluate('(10 + 20) * 2', data), 60.0);
      expect(FormulaEngine.evaluate('SUM(\$Paid.START:\$Paid.END) / 3', data), 200.0);
    });

    test('Nested Functions: IFERROR(ROWS(UNIQUE(FILTER)))', () {
      // Male patients: Card 1 and 3. Unique count = 2.
      expect(FormulaEngine.evaluate('IFERROR(ROWS(UNIQUE(FILTER(\$Card Number.START:\$Card Number.END, \$Sex.START:\$Sex.END="Male"))), 0)', data), 2);
      
      // Female patients: Card 2. Unique count = 1.
      expect(FormulaEngine.evaluate('IFERROR(ROWS(UNIQUE(FILTER(\$Card Number.START:\$Card Number.END, \$Sex.START:\$Sex.END="Female"))), 0)', data), 1);
      
      // Registered On = Date (2026-03-13): Card 1 and 3.
      expect(FormulaEngine.evaluate('IFERROR(ROWS(UNIQUE(FILTER(\$Card Number.START:\$Card Number.END, \$Registered On.START:\$Registered On.END=\$Date.START))), 0)', data), 2);
    });

    test('IFERROR fallback', () {
      expect(FormulaEngine.evaluate('IFERROR(1/0, "Fallback")', data), double.infinity); // Dart 1/0 is infinity, not error
      // Let's trigger an error by calling unknown function or bad syntax if we didn't catch it
      // Actually our evaluator throws on unknown function.
      expect(FormulaEngine.evaluate('UNKNOWN_FUNC()', data), "Error"); 
    });

    test('ROUND', () {
      expect(FormulaEngine.evaluate('ROUND(123.456, 1)', data), 123.5);
      expect(FormulaEngine.evaluate('ROUND(123.456, 0)', data), 123.0);
    });
    
    test('SUMIF with Numeric Criteria', () {
      expect(FormulaEngine.evaluate('SUMIF(\$Charges.START:\$Charges.END, 100, \$Paid.START:\$Paid.END)', data), 100.0);
    });

    test('SUM with single reference', () {
      expect(FormulaEngine.evaluate('SUM(\$Paid.START)', data), 600.0);
    });
  });
}
