import 'package:drift/drift.dart';
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
  Future<void> setUsername(String value) => _setSetting('username', value.trim());

  Future<void> setAllowNegative(bool value) =>
      _setSetting('allow_negative', value.toString());

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
