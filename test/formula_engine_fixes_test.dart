import 'package:flutter_test/flutter_test.dart';
import 'package:anydb_flutter/core/formula_engine.dart';

void main() {
  group('FormulaEngine Fixes Tests', () {
    test('Fix 1: Title-to-Key Mapping', () {
      final List<Map<String, dynamic>> data = [
        {'Total Amount': '100', 'Payment Mode': 'Cash'},
        {'Total Amount': '200', 'Payment Mode': 'UPI'},
        {'Total Amount': '150', 'Payment Mode': 'Cash'},
      ];
      final List<String> headers = ['Total Amount', 'Payment Mode'];
      final Map<String, String> titleToKeyMap = {
        'total_amt': 'Total Amount',
        'Total Amount': 'total_amt',
        'mode': 'Payment Mode',
        'Payment Mode': 'mode',
      };

      // SUM using the mapped key
      final sumVal = FormulaEngine.evaluate(
        'SUM(\$total_amt.START:\$total_amt.END)',
        data,
        headers,
        titleToKeyMap,
      );
      expect(sumVal, 450.0);

      // SUMIF using mapped keys for both criteria range and sum range
      final sumIfVal = FormulaEngine.evaluate(
        'SUMIF(\$mode.START:\$mode.END, "Cash", \$total_amt.START:\$total_amt.END)',
        data,
        headers,
        titleToKeyMap,
      );
      expect(sumIfVal, 250.0);
    });

    test('Fix 2: Robust Numeric Sanitization', () {
      final List<Map<String, dynamic>> data = [
        {'Paid': '\$ 1,200.50'},
        {'Paid': 'Rs. 50'},
        {'Paid': '- 50.25'},
        {'Paid': 'N/A'},
      ];
      final List<String> headers = ['Paid'];

      final sumVal = FormulaEngine.evaluate(
        'SUM(\$Paid.START:\$Paid.END)',
        data,
        headers,
      );
      expect(sumVal, 1200.25); // 1200.50 + 50.0 - 50.25 + 0.0 = 1200.25
    });

    test('Fix 3: Conditional Evaluation Context (SUMIF/COUNTIF)', () {
      final List<Map<String, dynamic>> data = [
        {'Charges': 100, 'Paid': 100, 'Discount': 0}, // Paid == Charges
        {'Charges': 150, 'Paid': 100, 'Discount': 50}, // Paid != Charges
        {'Charges': 80, 'Paid': 80, 'Discount': 0}, // Paid == Charges
      ];
      final List<String> headers = ['Charges', 'Paid', 'Discount'];

      // COUNTIF charges equals paid (i.e. Paid == Charges)
      // When criteria is reference (e.g. $Paid), it should evaluate to the specific row's Paid value
      final countIfVal = FormulaEngine.evaluate(
        'COUNTIF(\$Charges.START:\$Charges.END, \$Paid)',
        data,
        headers,
      );
      expect(countIfVal, 2);

      // SUMIF charges when Charges == Paid
      final sumIfVal = FormulaEngine.evaluate(
        'SUMIF(\$Charges.START:\$Charges.END, \$Paid, \$Charges.START:\$Charges.END)',
        data,
        headers,
      );
      expect(sumIfVal, 180.0); // 100 + 80 = 180
    });
  });
}
