enum TransactionType { expense, income, savings }

extension TransactionTypeX on TransactionType {
  String get value => name;
  bool get isCredit => this == TransactionType.income;
  String get label => switch (this) {
    TransactionType.expense => 'Expense',
    TransactionType.income => 'Income',
    TransactionType.savings => 'Savings',
  };
}

enum RecurrenceFrequency { daily, weekly, monthly, yearly }

extension RecurrenceFrequencyX on RecurrenceFrequency {
  String get label => '${name[0].toUpperCase()}${name.substring(1)}';
}

class DashboardTotals {
  const DashboardTotals({
    required this.income,
    required this.expenses,
    required this.savings,
  });
  final int income;
  final int expenses;
  final int savings;
  int get netCashFlow => income - expenses;
}

class CategoryTotal {
  const CategoryTotal({
    required this.name,
    required this.amount,
    required this.color,
  });
  final String name;
  final int amount;
  final int color;
}

class FinanceAlert {
  const FinanceAlert({
    required this.title,
    required this.message,
    required this.icon,
  });
  final String title;
  final String message;
  final String icon;
}
