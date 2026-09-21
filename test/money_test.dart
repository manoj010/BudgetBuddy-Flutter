import 'package:flutter_test/flutter_test.dart';

import 'package:budget_buddy/core/models/finance_models.dart';
import 'package:budget_buddy/core/utils/money.dart';

void main() {
  test('stores and formats money as minor units', () {
    expect(parseMinorUnits('1,250.50'), 125050);
    expect(formatMoney(125050), 'Rs. 1,250.5');
    expect(formatMoney(-50000), '-Rs. 500');
  });

  test('savings rate handles zero income', () {
    const totals = DashboardTotals(income: 0, expenses: 100, savings: 0);
    expect(totals.netCashFlow, -100);
  });
}
