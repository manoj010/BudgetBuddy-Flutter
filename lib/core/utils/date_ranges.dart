DateTime monthStart(DateTime date) => DateTime(date.year, date.month);
DateTime monthEnd(DateTime date) =>
    DateTime(date.year, date.month + 1, 0, 23, 59, 59);

String monthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';
