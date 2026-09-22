import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:excel/excel.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/finance_models.dart';
import '../utils/date_ranges.dart';

class FinanceFailure implements Exception {
  const FinanceFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class FinanceRepository {
  FinanceRepository(this.db);
  final AppDatabase db;
  static const _uuid = Uuid();

  Future<bool> isOnboardingComplete() async =>
      (await _setting('onboarding_complete')) == 'true';

  Future<void> completeOnboarding({
    required String username,
    required String currency,
    required int openingBalance,
  }) async {
    await seedCategories();
    final now = DateTime.now();
    await db.transaction(() async {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              id: _uuid.v4(),
              name: 'Cash',
              type: const Value('cash'),
              openingBalance: Value(openingBalance),
              currentBalance: Value(openingBalance),
              icon: const Value('payments'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _setSetting('username', username.trim());
      await _setSetting('currency', currency);
      await _setSetting('onboarding_complete', 'true');
    });
  }

  Future<void> seedCategories() async {
    if (await db.select(db.categories).get().then((rows) => rows.isNotEmpty))
      return;
    final now = DateTime.now();
    const expenses = {
      'Food': 'restaurant',
      'Transport': 'directions_car',
      'Shopping': 'shopping_bag',
      'Bills': 'receipt_long',
      'Rent': 'home',
      'Entertainment': 'movie',
      'Health': 'medical_services',
      'Education': 'school',
      'Travel': 'flight',
      'Other': 'category',
    };
    const incomes = {
      'Salary': 'work',
      'Freelance': 'laptop',
      'Business': 'storefront',
      'Investment': 'trending_up',
      'Gift': 'card_giftcard',
      'Other': 'category',
    };
    await db.batch((batch) {
      for (final entry in expenses.entries) {
        batch.insert(
          db.categories,
          CategoriesCompanion.insert(
            id: _uuid.v4(),
            name: entry.key,
            type: 'expense',
            icon: Value(entry.value),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      for (final entry in incomes.entries) {
        batch.insert(
          db.categories,
          CategoriesCompanion.insert(
            id: _uuid.v4(),
            name: entry.key,
            type: 'income',
            icon: Value(entry.value),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    });
  }

  Future<List<Account>> accounts() =>
      (db.select(db.accounts)
            ..where((a) => a.archivedAt.isNull())
            ..orderBy([(a) => OrderingTerm(expression: a.name)]))
          .get();
  Future<List<Category>> categories() =>
      (db.select(db.categories)
            ..where((c) => c.archivedAt.isNull())
            ..orderBy([(c) => OrderingTerm(expression: c.name)]))
          .get();
  Future<List<TransactionsTableData>> transactions() =>
      (db.select(db.transactionsTable)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm(
                expression: t.transactionDate,
                mode: OrderingMode.desc,
              ),
            ]))
          .get();

  Future<void> addAccount({
    required String name,
    required String type,
    required int openingBalance,
  }) async {
    final now = DateTime.now();
    await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            id: _uuid.v4(),
            name: name.trim(),
            type: Value(type),
            openingBalance: Value(openingBalance),
            currentBalance: Value(openingBalance),
            icon: const Value('wallet'),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> deleteAccount(String accountId) async {
    final account = await (db.select(
      db.accounts,
    )..where((row) => row.id.equals(accountId))).getSingleOrNull();
    if (account == null) return;

    final linkedTransactions =
        await (db.select(db.transactionsTable)..where(
              (row) => row.accountId.equals(accountId) & row.deletedAt.isNull(),
            ))
            .get();
    final linkedTransfers =
        await (db.select(db.transfers)..where(
              (row) =>
                  row.fromAccountId.equals(accountId) |
                  row.toAccountId.equals(accountId),
            ))
            .get();
    if (linkedTransactions.isNotEmpty || linkedTransfers.isNotEmpty) {
      throw const FinanceFailure(
        'This account has financial history and cannot be deleted.',
      );
    }
    await (db.update(
      db.accounts,
    )..where((row) => row.id.equals(accountId))).write(
      AccountsCompanion(
        archivedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> addTransaction({
    required String accountId,
    required String categoryId,
    required TransactionType type,
    required int amount,
    required DateTime date,
    String? note,
    String? recurringId,
  }) async {
    if (amount <= 0)
      throw const FinanceFailure('Amount must be greater than zero.');
    final account = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(accountId))).getSingleOrNull();
    if (account == null) throw const FinanceFailure('Account not found.');
    final delta = type.isCredit ? amount : -amount;
    if (!await allowNegative() && account.currentBalance + delta < 0)
      throw const FinanceFailure('Insufficient balance for this transaction.');
    final now = DateTime.now();
    await db.transaction(() async {
      await db
          .into(db.transactionsTable)
          .insert(
            TransactionsTableCompanion.insert(
              id: _uuid.v4(),
              accountId: accountId,
              categoryId: categoryId,
              type: type.value,
              amount: amount,
              transactionDate: date,
              note: Value(note?.trim().isEmpty == true ? null : note?.trim()),
              recurringTransactionId: Value(recurringId),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await (db.update(
        db.accounts,
      )..where((a) => a.id.equals(accountId))).write(
        AccountsCompanion(
          currentBalance: Value(account.currentBalance + delta),
          updatedAt: Value(now),
        ),
      );
    });
  }

  Future<void> addRecurring({
    required String accountId,
    required String categoryId,
    required TransactionType type,
    required int amount,
    required RecurrenceFrequency frequency,
    required DateTime startDate,
    String? note,
  }) async {
    final now = DateTime.now();
    await db
        .into(db.recurringTransactions)
        .insert(
          RecurringTransactionsCompanion.insert(
            id: _uuid.v4(),
            accountId: accountId,
            categoryId: categoryId,
            type: type.value,
            amount: amount,
            frequency: frequency.name,
            startDate: startDate,
            nextExecutionDate: _nextDate(startDate, frequency),
            note: Value(note),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  DateTime _nextDate(DateTime date, RecurrenceFrequency frequency) =>
      switch (frequency) {
        RecurrenceFrequency.daily => date.add(const Duration(days: 1)),
        RecurrenceFrequency.weekly => date.add(const Duration(days: 7)),
        RecurrenceFrequency.monthly => DateTime(
          date.year,
          date.month + 1,
          date.day,
        ),
        RecurrenceFrequency.yearly => DateTime(
          date.year + 1,
          date.month,
          date.day,
        ),
      };

  Future<void> updateTransaction({
    required String id,
    required String categoryId,
    required int amount,
  }) async {
    if (amount <= 0)
      throw const FinanceFailure('Amount must be greater than zero.');
    final row = await (db.select(
      db.transactionsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null || row.deletedAt != null)
      throw const FinanceFailure('Transaction not found.');
    final account = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(row.accountId))).getSingleOrNull();
    if (account == null) throw const FinanceFailure('Account not found.');
    final oldDelta = row.type == TransactionType.income.value
        ? row.amount
        : -row.amount;
    final newDelta = row.type == TransactionType.income.value
        ? amount
        : -amount;
    final balanceDelta = newDelta - oldDelta;
    if (!await allowNegative() && account.currentBalance + balanceDelta < 0) {
      throw const FinanceFailure('Insufficient balance for this transaction.');
    }
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(
        db.transactionsTable,
      )..where((t) => t.id.equals(id))).write(
        TransactionsTableCompanion(
          categoryId: Value(categoryId),
          amount: Value(amount),
          updatedAt: Value(now),
        ),
      );
      await (db.update(
        db.accounts,
      )..where((a) => a.id.equals(account.id))).write(
        AccountsCompanion(
          currentBalance: Value(account.currentBalance + balanceDelta),
          updatedAt: Value(now),
        ),
      );
    });
  }

  Future<void> deleteTransaction(String id) async {
    final row = await (db.select(
      db.transactionsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null || row.deletedAt != null) return;
    final account = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(row.accountId))).getSingleOrNull();
    if (account == null) return;
    final delta = row.type == TransactionType.income.value
        ? -row.amount
        : row.amount;
    await db.transaction(() async {
      await (db.update(
        db.transactionsTable,
      )..where((t) => t.id.equals(id))).write(
        TransactionsTableCompanion(
          deletedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await (db.update(
        db.accounts,
      )..where((a) => a.id.equals(account.id))).write(
        AccountsCompanion(
          currentBalance: Value(account.currentBalance + delta),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  Future<void> transfer({
    required String fromAccountId,
    required String toAccountId,
    required int amount,
    required DateTime date,
    String? note,
  }) async {
    if (fromAccountId == toAccountId)
      throw const FinanceFailure('Source and destination must be different.');
    if (amount <= 0)
      throw const FinanceFailure('Amount must be greater than zero.');
    final from = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(fromAccountId))).getSingle();
    final to = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(toAccountId))).getSingle();
    if (!await allowNegative() && from.currentBalance < amount)
      throw const FinanceFailure('Insufficient balance for this transfer.');
    final transferId = _uuid.v4();
    final now = DateTime.now();
    final category =
        await (db.select(db.categories)
              ..where((c) => c.name.equals('Other') & c.type.equals('expense')))
            .getSingle();
    await db.transaction(() async {
      await db
          .into(db.transfers)
          .insert(
            TransfersCompanion.insert(
              id: transferId,
              fromAccountId: fromAccountId,
              toAccountId: toAccountId,
              amount: amount,
              transferDate: date,
              note: Value(note),
              createdAt: now,
            ),
          );
      await db
          .into(db.transactionsTable)
          .insert(
            TransactionsTableCompanion.insert(
              id: _uuid.v4(),
              accountId: fromAccountId,
              categoryId: category.id,
              type: TransactionType.expense.value,
              amount: amount,
              transactionDate: date,
              note: Value('Transfer to ${to.name}'),
              transferId: Value(transferId),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.transactionsTable)
          .insert(
            TransactionsTableCompanion.insert(
              id: _uuid.v4(),
              accountId: toAccountId,
              categoryId: category.id,
              type: TransactionType.income.value,
              amount: amount,
              transactionDate: date,
              note: Value('Transfer from ${from.name}'),
              transferId: Value(transferId),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await (db.update(
        db.accounts,
      )..where((a) => a.id.equals(fromAccountId))).write(
        AccountsCompanion(
          currentBalance: Value(from.currentBalance - amount),
          updatedAt: Value(now),
        ),
      );
      await (db.update(
        db.accounts,
      )..where((a) => a.id.equals(toAccountId))).write(
        AccountsCompanion(
          currentBalance: Value(to.currentBalance + amount),
          updatedAt: Value(now),
        ),
      );
    });
  }

  Future<DashboardTotals> totalsForMonth(DateTime date) async {
    final rows =
        await (db.select(db.transactionsTable)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.transactionDate.isBetweenValues(
                    monthStart(date),
                    monthEnd(date),
                  ),
            ))
            .get();
    var income = 0, expenses = 0, savings = 0;
    for (final row in rows) {
      if (row.transferId != null) continue;
      switch (row.type) {
        case 'income':
          income += row.amount;
        case 'savings':
          savings += row.amount;
        default:
          expenses += row.amount;
      }
    }
    return DashboardTotals(
      income: income,
      expenses: expenses,
      savings: savings,
    );
  }

  Future<List<CategoryTotal>> categoryTotals(DateTime date) async {
    final rows =
        await (db.select(db.transactionsTable)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.type.equals('expense') &
                  t.transferId.isNull() &
                  t.transactionDate.isBetweenValues(
                    monthStart(date),
                    monthEnd(date),
                  ),
            ))
            .get();
    final names = {for (final c in await categories()) c.id: c};
    final totals = <String, int>{};
    for (final row in rows)
      totals[row.categoryId] = (totals[row.categoryId] ?? 0) + row.amount;
    return totals.entries
        .map(
          (e) => CategoryTotal(
            name: names[e.key]?.name ?? 'Other',
            amount: e.value,
            color: names[e.key]?.color ?? 0xFF356859,
          ),
        )
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
  }

  Future<List<Budget>> budgets({DateTime? month}) async {
    final date = month ?? DateTime.now();
    return (db.select(db.budgets)
          ..where((b) => b.month.equals(date.month) & b.year.equals(date.year)))
        .get();
  }

  Future<void> saveBudget({
    String? categoryId,
    required int amount,
    required DateTime month,
  }) async {
    final existing =
        await (db.select(db.budgets)..where(
              (b) =>
                  b.month.equals(month.month) &
                  b.year.equals(month.year) &
                  (categoryId == null
                      ? b.categoryId.isNull()
                      : b.categoryId.equals(categoryId)),
            ))
            .getSingleOrNull();
    final now = DateTime.now();
    if (existing == null)
      await db
          .into(db.budgets)
          .insert(
            BudgetsCompanion.insert(
              id: _uuid.v4(),
              categoryId: Value(categoryId),
              amount: amount,
              month: month.month,
              year: month.year,
              createdAt: now,
              updatedAt: now,
            ),
          );
    else
      await (db.update(
        db.budgets,
      )..where((b) => b.id.equals(existing.id))).write(
        BudgetsCompanion(amount: Value(amount), updatedAt: Value(now)),
      );
  }

  Future<List<SavingsGoal>> goals() =>
      (db.select(db.savingsGoals)
            ..where((g) => g.archivedAt.isNull())
            ..orderBy([
              (g) => OrderingTerm(
                expression: g.createdAt,
                mode: OrderingMode.desc,
              ),
            ]))
          .get();
  Future<void> addGoal({
    required String name,
    required int targetAmount,
    required int currentAmount,
    DateTime? targetDate,
    String? note,
  }) async {
    if (targetAmount <= 0)
      throw const FinanceFailure('Target amount must be greater than zero.');
    final now = DateTime.now();
    await db
        .into(db.savingsGoals)
        .insert(
          SavingsGoalsCompanion.insert(
            id: _uuid.v4(),
            name: name.trim(),
            targetAmount: targetAmount,
            currentAmount: Value(currentAmount),
            targetDate: Value(targetDate),
            note: Value(note),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> updateGoalAmount(String id, int amount) async {
    final goal = await (db.select(
      db.savingsGoals,
    )..where((g) => g.id.equals(id))).getSingle();
    final next = goal.currentAmount + amount;
    if (next < 0)
      throw const FinanceFailure('Goal balance cannot be negative.');
    await (db.update(db.savingsGoals)..where((g) => g.id.equals(id))).write(
      SavingsGoalsCompanion(
        currentAmount: Value(next),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<List<int>> exportExcel() async {
    final workbook = Excel.createExcel();
    workbook.delete('Sheet1');
    final headerStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('FF356859'),
      fontColorHex: ExcelColor.white,
      bold: true,
    );
    final accounts = await db.select(db.accounts).get();
    final categories = await db.select(db.categories).get();
    final transactions = await db.select(db.transactionsTable).get();
    final recurring = await db.select(db.recurringTransactions).get();
    final budgets = await db.select(db.budgets).get();
    final goals = await db.select(db.savingsGoals).get();
    final transfers = await db.select(db.transfers).get();
    final settings = await db.select(db.appSettings).get();
    final accountNames = {for (final row in accounts) row.id: row.name};
    final categoryNames = {for (final row in categories) row.id: row.name};

    void addSheet(
      String name,
      List<String> headers,
      List<List<CellValue>> rows, {
      List<double>? widths,
    }) {
      final sheet = workbook[name];
      sheet.appendRow(headers.map(TextCellValue.new).toList());
      for (final row in rows) {
        sheet.appendRow(row);
      }
      for (var column = 0; column < headers.length; column++) {
        sheet
                .cell(
                  CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0),
                )
                .cellStyle =
            headerStyle;
        sheet.setColumnWidth(
          column,
          widths != null && column < widths.length ? widths[column] : 18,
        );
      }
    }

    CellValue textValue(String? value) => TextCellValue(value ?? '');
    CellValue moneyValue(int value) => DoubleCellValue(value / 100);
    CellValue dateValue(DateTime? value) => TextCellValue(
      value == null ? '' : value.toIso8601String().split('T').first,
    );

    addSheet(
      'Transactions',
      [
        'Date',
        'Type',
        'Amount (Rs.)',
        'Account',
        'Category',
        'Note',
        'Deleted',
      ],
      transactions
          .map(
            (row) => [
              dateValue(row.transactionDate),
              TextCellValue(row.type),
              moneyValue(row.amount),
              textValue(accountNames[row.accountId]),
              textValue(categoryNames[row.categoryId]),
              textValue(row.note),
              BoolCellValue(row.deletedAt != null),
            ],
          )
          .toList(),
      widths: [14, 14, 16, 22, 22, 32, 12],
    );
    addSheet(
      'Accounts',
      [
        'Name',
        'Type',
        'Opening balance (Rs.)',
        'Current balance (Rs.)',
        'Archived',
      ],
      accounts
          .map(
            (row) => [
              TextCellValue(row.name),
              TextCellValue(row.type),
              moneyValue(row.openingBalance),
              moneyValue(row.currentBalance),
              BoolCellValue(row.archivedAt != null),
            ],
          )
          .toList(),
      widths: [24, 14, 22, 22, 12],
    );
    addSheet(
      'Categories',
      ['Name', 'Type', 'Icon', 'Color', 'Archived'],
      categories
          .map(
            (row) => [
              TextCellValue(row.name),
              TextCellValue(row.type),
              TextCellValue(row.icon),
              row.color == null ? TextCellValue('') : IntCellValue(row.color!),
              BoolCellValue(row.archivedAt != null),
            ],
          )
          .toList(),
    );
    addSheet(
      'Budgets',
      ['Month', 'Year', 'Amount (Rs.)', 'Category'],
      budgets
          .map(
            (row) => [
              IntCellValue(row.month),
              IntCellValue(row.year),
              moneyValue(row.amount),
              textValue(categoryNames[row.categoryId]),
            ],
          )
          .toList(),
    );
    addSheet(
      'Savings Goals',
      [
        'Name',
        'Target (Rs.)',
        'Current (Rs.)',
        'Target date',
        'Note',
        'Archived',
      ],
      goals
          .map(
            (row) => [
              TextCellValue(row.name),
              moneyValue(row.targetAmount),
              moneyValue(row.currentAmount),
              dateValue(row.targetDate),
              textValue(row.note),
              BoolCellValue(row.archivedAt != null),
            ],
          )
          .toList(),
      widths: [24, 16, 16, 16, 32, 12],
    );
    addSheet(
      'Recurring',
      [
        'Type',
        'Amount (Rs.)',
        'Frequency',
        'Start date',
        'Next date',
        'Account',
        'Category',
        'Active',
      ],
      recurring
          .map(
            (row) => [
              TextCellValue(row.type),
              moneyValue(row.amount),
              TextCellValue(row.frequency),
              dateValue(row.startDate),
              dateValue(row.nextExecutionDate),
              textValue(accountNames[row.accountId]),
              textValue(categoryNames[row.categoryId]),
              BoolCellValue(row.isActive),
            ],
          )
          .toList(),
      widths: [14, 16, 14, 16, 16, 22, 22, 12],
    );
    addSheet(
      'Transfers',
      ['Date', 'Amount (Rs.)', 'From account', 'To account', 'Note'],
      transfers
          .map(
            (row) => [
              dateValue(row.transferDate),
              moneyValue(row.amount),
              textValue(accountNames[row.fromAccountId]),
              textValue(accountNames[row.toAccountId]),
              textValue(row.note),
            ],
          )
          .toList(),
      widths: [14, 16, 22, 22, 32],
    );
    addSheet(
      'Settings',
      ['Setting', 'Value'],
      settings
          .map((row) => [TextCellValue(row.key), TextCellValue(row.value)])
          .toList(),
      widths: [24, 32],
    );
    return workbook.save(fileName: 'budget_buddy_export.xlsx')!;
  }

  Future<void> restoreExcel(List<int> bytes) async {
    late final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } on Object {
      throw const FinanceFailure('The selected Excel file is not valid.');
    }
    final requiredSheets = [
      'Transactions',
      'Accounts',
      'Categories',
      'Budgets',
      'Savings Goals',
      'Recurring',
      'Transfers',
      'Settings',
    ];
    if (requiredSheets.any((name) => workbook.tables[name] == null)) {
      throw const FinanceFailure(
        'This Excel file is not a Budget Buddy export.',
      );
    }

    String cellText(Sheet sheet, int row, int column) {
      final value = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row))
          .value;
      return switch (value) {
        null => '',
        TextCellValue(:final value) => value.text ?? '',
        IntCellValue(:final value) => value.toString(),
        DoubleCellValue(:final value) => value.toString(),
        BoolCellValue(:final value) => value.toString(),
        DateCellValue(:final year, :final month, :final day) =>
          '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
        DateTimeCellValue(:final year, :final month, :final day) =>
          '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
        _ => value.toString(),
      };
    }

    int cellMoney(Sheet sheet, int row, int column) =>
        ((double.tryParse(cellText(sheet, row, column)) ?? 0) * 100).round();
    bool cellBool(Sheet sheet, int row, int column) =>
        cellText(sheet, row, column).toLowerCase() == 'true';
    DateTime? cellDate(Sheet sheet, int row, int column) {
      final value = cellText(sheet, row, column);
      return value.isEmpty ? null : DateTime.tryParse(value);
    }

    final accountsSheet = workbook.tables['Accounts']!;
    final categoriesSheet = workbook.tables['Categories']!;
    final transactionsSheet = workbook.tables['Transactions']!;
    final budgetsSheet = workbook.tables['Budgets']!;
    final goalsSheet = workbook.tables['Savings Goals']!;
    final recurringSheet = workbook.tables['Recurring']!;
    final transfersSheet = workbook.tables['Transfers']!;
    final settingsSheet = workbook.tables['Settings']!;
    final now = DateTime.now();
    final accountIds = <String, String>{};
    final categoryIds = <String, String>{};
    String categoryKey(String name, String type) => '$type|$name';

    await db.transaction(() async {
      await db.delete(db.appSettings).go();
      await db.delete(db.transfers).go();
      await db.delete(db.recurringTransactions).go();
      await db.delete(db.transactionsTable).go();
      await db.delete(db.budgets).go();
      await db.delete(db.savingsGoals).go();
      await db.delete(db.categories).go();
      await db.delete(db.accounts).go();

      for (var row = 1; row < accountsSheet.maxRows; row++) {
        final name = cellText(accountsSheet, row, 0);
        if (name.isEmpty) continue;
        final id = _uuid.v4();
        accountIds[name] = id;
        await db
            .into(db.accounts)
            .insert(
              AccountsCompanion.insert(
                id: id,
                name: name,
                type: Value(cellText(accountsSheet, row, 1)),
                openingBalance: Value(cellMoney(accountsSheet, row, 2)),
                currentBalance: Value(cellMoney(accountsSheet, row, 3)),
                icon: const Value('wallet'),
                createdAt: now,
                updatedAt: now,
                archivedAt: Value(cellBool(accountsSheet, row, 4) ? now : null),
              ),
            );
      }
      for (var row = 1; row < categoriesSheet.maxRows; row++) {
        final name = cellText(categoriesSheet, row, 0);
        final type = cellText(categoriesSheet, row, 1);
        if (name.isEmpty || type.isEmpty) continue;
        final id = _uuid.v4();
        categoryIds[categoryKey(name, type)] = id;
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: id,
                name: name,
                type: type,
                icon: Value(cellText(categoriesSheet, row, 2)),
                color: Value(int.tryParse(cellText(categoriesSheet, row, 3))),
                createdAt: now,
                updatedAt: now,
                archivedAt: Value(
                  cellBool(categoriesSheet, row, 4) ? now : null,
                ),
              ),
            );
      }
      for (var row = 1; row < transactionsSheet.maxRows; row++) {
        final accountId = accountIds[cellText(transactionsSheet, row, 3)];
        final type = cellText(transactionsSheet, row, 1);
        final categoryId =
            categoryIds[categoryKey(
              cellText(transactionsSheet, row, 4),
              type == 'income' ? 'income' : 'expense',
            )];
        final date = cellDate(transactionsSheet, row, 0);
        if (accountId == null || categoryId == null || date == null) continue;
        await db
            .into(db.transactionsTable)
            .insert(
              TransactionsTableCompanion.insert(
                id: _uuid.v4(),
                accountId: accountId,
                categoryId: categoryId,
                type: type,
                amount: cellMoney(transactionsSheet, row, 2),
                transactionDate: date,
                note: Value(
                  cellText(transactionsSheet, row, 5).isEmpty
                      ? null
                      : cellText(transactionsSheet, row, 5),
                ),
                createdAt: now,
                updatedAt: now,
                deletedAt: Value(
                  cellBool(transactionsSheet, row, 6) ? now : null,
                ),
              ),
            );
      }
      for (var row = 1; row < budgetsSheet.maxRows; row++) {
        final categoryName = cellText(budgetsSheet, row, 3);
        final categoryId = categoryName.isEmpty
            ? null
            : categoryIds[categoryKey(categoryName, 'expense')];
        await db
            .into(db.budgets)
            .insert(
              BudgetsCompanion.insert(
                id: _uuid.v4(),
                categoryId: Value(categoryId),
                amount: cellMoney(budgetsSheet, row, 2),
                month: int.tryParse(cellText(budgetsSheet, row, 0)) ?? 1,
                year: int.tryParse(cellText(budgetsSheet, row, 1)) ?? now.year,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      for (var row = 1; row < goalsSheet.maxRows; row++) {
        final name = cellText(goalsSheet, row, 0);
        if (name.isEmpty) continue;
        await db
            .into(db.savingsGoals)
            .insert(
              SavingsGoalsCompanion.insert(
                id: _uuid.v4(),
                name: name,
                targetAmount: cellMoney(goalsSheet, row, 1),
                currentAmount: Value(cellMoney(goalsSheet, row, 2)),
                targetDate: Value(cellDate(goalsSheet, row, 3)),
                note: Value(
                  cellText(goalsSheet, row, 4).isEmpty
                      ? null
                      : cellText(goalsSheet, row, 4),
                ),
                createdAt: now,
                updatedAt: now,
                archivedAt: Value(cellBool(goalsSheet, row, 5) ? now : null),
              ),
            );
      }
      for (var row = 1; row < recurringSheet.maxRows; row++) {
        final accountId = accountIds[cellText(recurringSheet, row, 5)];
        final type = cellText(recurringSheet, row, 0);
        final categoryId =
            categoryIds[categoryKey(
              cellText(recurringSheet, row, 6),
              type == 'income' ? 'income' : 'expense',
            )];
        final startDate = cellDate(recurringSheet, row, 3);
        final nextDate = cellDate(recurringSheet, row, 4);
        if (accountId == null ||
            categoryId == null ||
            startDate == null ||
            nextDate == null)
          continue;
        await db
            .into(db.recurringTransactions)
            .insert(
              RecurringTransactionsCompanion.insert(
                id: _uuid.v4(),
                accountId: accountId,
                categoryId: categoryId,
                type: type,
                amount: cellMoney(recurringSheet, row, 1),
                frequency: cellText(recurringSheet, row, 2),
                startDate: startDate,
                nextExecutionDate: nextDate,
                isActive: Value(cellBool(recurringSheet, row, 7)),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
      for (var row = 1; row < transfersSheet.maxRows; row++) {
        final fromId = accountIds[cellText(transfersSheet, row, 2)];
        final toId = accountIds[cellText(transfersSheet, row, 3)];
        final date = cellDate(transfersSheet, row, 0);
        if (fromId == null || toId == null || date == null) continue;
        await db
            .into(db.transfers)
            .insert(
              TransfersCompanion.insert(
                id: _uuid.v4(),
                fromAccountId: fromId,
                toAccountId: toId,
                amount: cellMoney(transfersSheet, row, 1),
                transferDate: date,
                note: Value(
                  cellText(transfersSheet, row, 4).isEmpty
                      ? null
                      : cellText(transfersSheet, row, 4),
                ),
                createdAt: now,
              ),
            );
      }
      for (var row = 1; row < settingsSheet.maxRows; row++) {
        final key = cellText(settingsSheet, row, 0);
        if (key.isEmpty) continue;
        await db
            .into(db.appSettings)
            .insert(
              AppSettingsCompanion.insert(
                key: key,
                value: cellText(settingsSheet, row, 1),
              ),
            );
      }
    });
  }

  Future<String> exportBackup() async {
    String date(DateTime value) => value.toIso8601String();
    String? nullableDate(DateTime? value) => value?.toIso8601String();
    final payload = <String, dynamic>{
      'format': 'budget_buddy_backup',
      'version': 1,
      'exportedAt': date(DateTime.now()),
      'accounts': (await db.select(db.accounts).get())
          .map(
            (row) => {
              'id': row.id,
              'name': row.name,
              'type': row.type,
              'openingBalance': row.openingBalance,
              'currentBalance': row.currentBalance,
              'icon': row.icon,
              'createdAt': date(row.createdAt),
              'updatedAt': date(row.updatedAt),
              'archivedAt': nullableDate(row.archivedAt),
            },
          )
          .toList(),
      'categories': (await db.select(db.categories).get())
          .map(
            (row) => {
              'id': row.id,
              'name': row.name,
              'type': row.type,
              'icon': row.icon,
              'color': row.color,
              'createdAt': date(row.createdAt),
              'updatedAt': date(row.updatedAt),
              'archivedAt': nullableDate(row.archivedAt),
            },
          )
          .toList(),
      'transactions': (await db.select(db.transactionsTable).get())
          .map(
            (row) => {
              'id': row.id,
              'accountId': row.accountId,
              'categoryId': row.categoryId,
              'type': row.type,
              'amount': row.amount,
              'transactionDate': date(row.transactionDate),
              'note': row.note,
              'recurringTransactionId': row.recurringTransactionId,
              'transferId': row.transferId,
              'createdAt': date(row.createdAt),
              'updatedAt': date(row.updatedAt),
              'deletedAt': nullableDate(row.deletedAt),
            },
          )
          .toList(),
      'recurringTransactions': (await db.select(db.recurringTransactions).get())
          .map(
            (row) => {
              'id': row.id,
              'accountId': row.accountId,
              'categoryId': row.categoryId,
              'type': row.type,
              'amount': row.amount,
              'frequency': row.frequency,
              'startDate': date(row.startDate),
              'nextExecutionDate': date(row.nextExecutionDate),
              'endDate': nullableDate(row.endDate),
              'note': row.note,
              'isActive': row.isActive,
              'createdAt': date(row.createdAt),
              'updatedAt': date(row.updatedAt),
            },
          )
          .toList(),
      'budgets': (await db.select(db.budgets).get())
          .map(
            (row) => {
              'id': row.id,
              'categoryId': row.categoryId,
              'amount': row.amount,
              'month': row.month,
              'year': row.year,
              'createdAt': date(row.createdAt),
              'updatedAt': date(row.updatedAt),
            },
          )
          .toList(),
      'savingsGoals': (await db.select(db.savingsGoals).get())
          .map(
            (row) => {
              'id': row.id,
              'name': row.name,
              'targetAmount': row.targetAmount,
              'currentAmount': row.currentAmount,
              'targetDate': nullableDate(row.targetDate),
              'note': row.note,
              'createdAt': date(row.createdAt),
              'updatedAt': date(row.updatedAt),
              'archivedAt': nullableDate(row.archivedAt),
            },
          )
          .toList(),
      'transfers': (await db.select(db.transfers).get())
          .map(
            (row) => {
              'id': row.id,
              'fromAccountId': row.fromAccountId,
              'toAccountId': row.toAccountId,
              'amount': row.amount,
              'transferDate': date(row.transferDate),
              'note': row.note,
              'createdAt': date(row.createdAt),
            },
          )
          .toList(),
      'appSettings': (await db.select(db.appSettings).get())
          .map((row) => {'key': row.key, 'value': row.value})
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<void> restoreBackup(String content) async {
    late final Map<String, dynamic> backup;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic> ||
          decoded['format'] != 'budget_buddy_backup') {
        throw const FormatException('Unsupported backup format.');
      }
      backup = decoded;
    } on FormatException catch (error) {
      throw FinanceFailure(error.message);
    } on Object {
      throw const FinanceFailure('The selected backup file is not valid JSON.');
    }

    List<Map<String, dynamic>> rows(String key) {
      final value = backup[key];
      if (value is! List) throw FinanceFailure('Backup is missing $key data.');
      return value.map((row) => Map<String, dynamic>.from(row as Map)).toList();
    }

    String text(Map<String, dynamic> row, String key) => row[key] as String;
    int number(Map<String, dynamic> row, String key) =>
        (row[key] as num).toInt();
    bool flag(Map<String, dynamic> row, String key) => row[key] as bool;
    DateTime instant(Map<String, dynamic> row, String key) =>
        DateTime.parse(text(row, key));
    DateTime? optionalInstant(Map<String, dynamic> row, String key) =>
        row[key] == null ? null : DateTime.parse(text(row, key));
    String? optionalText(Map<String, dynamic> row, String key) =>
        row[key] as String?;

    final accounts = rows('accounts');
    final categories = rows('categories');
    final transactions = rows('transactions');
    final recurring = rows('recurringTransactions');
    final budgets = rows('budgets');
    final goals = rows('savingsGoals');
    final transfers = rows('transfers');
    final settings = rows('appSettings');

    await db.transaction(() async {
      await db.delete(db.appSettings).go();
      await db.delete(db.transfers).go();
      await db.delete(db.recurringTransactions).go();
      await db.delete(db.transactionsTable).go();
      await db.delete(db.budgets).go();
      await db.delete(db.savingsGoals).go();
      await db.delete(db.categories).go();
      await db.delete(db.accounts).go();

      for (final row in accounts) {
        await db
            .into(db.accounts)
            .insert(
              AccountsCompanion.insert(
                id: text(row, 'id'),
                name: text(row, 'name'),
                type: Value(text(row, 'type')),
                openingBalance: Value(number(row, 'openingBalance')),
                currentBalance: Value(number(row, 'currentBalance')),
                icon: Value(text(row, 'icon')),
                createdAt: instant(row, 'createdAt'),
                updatedAt: instant(row, 'updatedAt'),
                archivedAt: Value(optionalInstant(row, 'archivedAt')),
              ),
            );
      }
      for (final row in categories) {
        await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                id: text(row, 'id'),
                name: text(row, 'name'),
                type: text(row, 'type'),
                icon: Value(text(row, 'icon')),
                color: Value((row['color'] as num?)?.toInt()),
                createdAt: instant(row, 'createdAt'),
                updatedAt: instant(row, 'updatedAt'),
                archivedAt: Value(optionalInstant(row, 'archivedAt')),
              ),
            );
      }
      for (final row in transactions) {
        await db
            .into(db.transactionsTable)
            .insert(
              TransactionsTableCompanion.insert(
                id: text(row, 'id'),
                accountId: text(row, 'accountId'),
                categoryId: text(row, 'categoryId'),
                type: text(row, 'type'),
                amount: number(row, 'amount'),
                transactionDate: instant(row, 'transactionDate'),
                note: Value(optionalText(row, 'note')),
                recurringTransactionId: Value(
                  optionalText(row, 'recurringTransactionId'),
                ),
                transferId: Value(optionalText(row, 'transferId')),
                createdAt: instant(row, 'createdAt'),
                updatedAt: instant(row, 'updatedAt'),
                deletedAt: Value(optionalInstant(row, 'deletedAt')),
              ),
            );
      }
      for (final row in recurring) {
        await db
            .into(db.recurringTransactions)
            .insert(
              RecurringTransactionsCompanion.insert(
                id: text(row, 'id'),
                accountId: text(row, 'accountId'),
                categoryId: text(row, 'categoryId'),
                type: text(row, 'type'),
                amount: number(row, 'amount'),
                frequency: text(row, 'frequency'),
                startDate: instant(row, 'startDate'),
                nextExecutionDate: instant(row, 'nextExecutionDate'),
                endDate: Value(optionalInstant(row, 'endDate')),
                note: Value(optionalText(row, 'note')),
                isActive: Value(flag(row, 'isActive')),
                createdAt: instant(row, 'createdAt'),
                updatedAt: instant(row, 'updatedAt'),
              ),
            );
      }
      for (final row in budgets) {
        await db
            .into(db.budgets)
            .insert(
              BudgetsCompanion.insert(
                id: text(row, 'id'),
                categoryId: Value(optionalText(row, 'categoryId')),
                amount: number(row, 'amount'),
                month: number(row, 'month'),
                year: number(row, 'year'),
                createdAt: instant(row, 'createdAt'),
                updatedAt: instant(row, 'updatedAt'),
              ),
            );
      }
      for (final row in goals) {
        await db
            .into(db.savingsGoals)
            .insert(
              SavingsGoalsCompanion.insert(
                id: text(row, 'id'),
                name: text(row, 'name'),
                targetAmount: number(row, 'targetAmount'),
                currentAmount: Value(number(row, 'currentAmount')),
                targetDate: Value(optionalInstant(row, 'targetDate')),
                note: Value(optionalText(row, 'note')),
                createdAt: instant(row, 'createdAt'),
                updatedAt: instant(row, 'updatedAt'),
                archivedAt: Value(optionalInstant(row, 'archivedAt')),
              ),
            );
      }
      for (final row in transfers) {
        await db
            .into(db.transfers)
            .insert(
              TransfersCompanion.insert(
                id: text(row, 'id'),
                fromAccountId: text(row, 'fromAccountId'),
                toAccountId: text(row, 'toAccountId'),
                amount: number(row, 'amount'),
                transferDate: instant(row, 'transferDate'),
                note: Value(optionalText(row, 'note')),
                createdAt: instant(row, 'createdAt'),
              ),
            );
      }
      for (final row in settings) {
        await db
            .into(db.appSettings)
            .insert(
              AppSettingsCompanion.insert(
                key: text(row, 'key'),
                value: text(row, 'value'),
              ),
            );
      }
    });
  }

  Future<bool> allowNegative() async =>
      (await _setting('allow_negative')) == 'true';
  Future<String?> _setting(String key) async => (await (db.select(
    db.appSettings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;
  Future<void> _setSetting(String key, String value) async => await db
      .into(db.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: key, value: value),
      );
  Future<String> currency() async => await _setting('currency') ?? 'NPR';
  Future<String> username() async {
    final value = await _setting('username');
    return value?.trim().isNotEmpty == true ? value!.trim() : 'there';
  }

  Future<void> setUsername(String value) =>
      _setSetting('username', value.trim());

  Future<void> setAllowNegative(bool value) =>
      _setSetting('allow_negative', value.toString());

  Future<String> themeMode() async => await _setting('theme_mode') ?? 'dark';

  Future<void> setThemeMode(String value) => _setSetting('theme_mode', value);

  Future<List<FinanceAlert>> alerts() async {
    final result = <FinanceAlert>[];
    final now = DateTime.now();
    final current = await totalsForMonth(now);
    final currentBudgets = await budgets(month: now);
    final overallBudget = currentBudgets
        .where((budget) => budget.categoryId == null)
        .firstOrNull;
    if (overallBudget != null && overallBudget.amount > 0) {
      final usage = current.expenses / overallBudget.amount;
      if (usage >= 1) {
        result.add(
          FinanceAlert(
            title: 'Budget exceeded',
            message:
                'You have spent ${(usage * 100).round()}% of your monthly budget.',
            icon: 'warning',
          ),
        );
      } else if (usage >= .9) {
        result.add(
          FinanceAlert(
            title: 'Budget almost reached',
            message:
                'You have used ${(usage * 100).round()}% of your monthly budget.',
            icon: 'warning',
          ),
        );
      } else if (usage >= .75) {
        result.add(
          FinanceAlert(
            title: 'Budget check-in',
            message:
                'You have used ${(usage * 100).round()}% of your monthly budget.',
            icon: 'budget',
          ),
        );
      }
    }
    final upcoming =
        await (db.select(db.recurringTransactions)
              ..where(
                (rule) =>
                    rule.isActive &
                    rule.nextExecutionDate.isBetweenValues(
                      now,
                      now.add(const Duration(days: 7)),
                    ),
              )
              ..orderBy([
                (rule) => OrderingTerm(expression: rule.nextExecutionDate),
              ]))
            .get();
    if (upcoming.isNotEmpty) {
      result.add(
        FinanceAlert(
          title: 'Upcoming recurring payments',
          message:
              '${upcoming.length} recurring transaction(s) are due within 7 days.',
          icon: 'repeat',
        ),
      );
    }
    final activeGoals = await (db.select(
      db.savingsGoals,
    )..where((goal) => goal.archivedAt.isNull())).get();
    final goalsNeedingAttention = activeGoals.where((goal) {
      final nearTarget =
          goal.targetDate != null &&
          goal.targetDate!.difference(now).inDays <= 30 &&
          goal.currentAmount < goal.targetAmount;
      final behind =
          goal.targetAmount > 0 && goal.currentAmount / goal.targetAmount < .25;
      return nearTarget || behind;
    }).length;
    if (goalsNeedingAttention > 0) {
      result.add(
        FinanceAlert(
          title: 'Savings goals need attention',
          message:
              '$goalsNeedingAttention goal(s) are behind their target progress.',
          icon: 'savings',
        ),
      );
    }
    return result;
  }
}
