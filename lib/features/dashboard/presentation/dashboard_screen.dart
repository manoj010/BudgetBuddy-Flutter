import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/finance_models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/icon_for_name.dart';

final dashboardMonthProvider = StateProvider<DateTime>((ref) => DateTime.now());
final dashboardTotalsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(financeRefreshProvider);
  return ref
      .watch(repositoryProvider)
      .totalsForMonth(ref.watch(dashboardMonthProvider));
});
final dashboardCategoriesProvider = FutureProvider.autoDispose((ref) {
  ref.watch(financeRefreshProvider);
  return ref
      .watch(repositoryProvider)
      .categoryTotals(ref.watch(dashboardMonthProvider));
});
final usernameProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(repositoryProvider).username(),
);

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final transactions = ref.watch(transactionsProvider);
    final categories = ref.watch(categoriesProvider);
    final totals = ref.watch(dashboardTotalsProvider);
    final month = ref.watch(dashboardMonthProvider);
    final username = ref.watch(usernameProvider).value ?? 'there';
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final categoryMap = {
      for (final c in categories.value ?? <Category>[]) c.id: c,
    };
    final balance = (accounts.value ?? <Account>[]).fold<int>(
      0,
      (sum, account) => sum + account.currentBalance,
    );
    final recent = (transactions.value ?? <TransactionsTableData>[])
        .take(5)
        .toList();

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 12, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    username == 'there' ? greeting : '$greeting, $username',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  IconButton(
                    onPressed: () => _showNotifications(context, ref),
                    icon: const Icon(Icons.notifications_none),
                    tooltip: 'Notifications',
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Card(
                  color: Theme.of(context).colorScheme.primary,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current balance',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimary.withValues(alpha: .8),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          formatMoney(balance),
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Across ${accounts.value?.length ?? 0} account(s)',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimary.withValues(alpha: .8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                totals.when(
                  data: (value) => Row(
                    children: [
                      _SummaryCard(
                        label: 'Income',
                        amount: value.income,
                        icon: Icons.arrow_downward,
                        color: Colors.green,
                        onTap: () => context.go('/add?type=income'),
                      ),
                      const SizedBox(width: 12),
                      _SummaryCard(
                        label: 'Expenses',
                        amount: value.expenses,
                        icon: Icons.arrow_upward,
                        color: Theme.of(context).colorScheme.error,
                        onTap: () => context.go('/add?type=expense'),
                      ),
                      const SizedBox(width: 12),
                      _SummaryCard(
                        label: 'Savings',
                        amount: value.savings,
                        icon: Icons.savings_outlined,
                        color: Theme.of(context).colorScheme.tertiary,
                        onTap: () => context.go('/add?type=savings'),
                      ),
                    ],
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, s) => Text('$e'),
                ),
                const SizedBox(height: 22),
                DropdownButtonFormField<DateTime>(
                  initialValue: DateTime(month.year, month.month),
                  decoration: const InputDecoration(
                    labelText: 'Month',
                    prefixIcon: Icon(Icons.calendar_month_outlined),
                  ),
                  items: List.generate(12, (index) {
                    final date = DateTime(
                      DateTime.now().year,
                      DateTime.now().month - index,
                    );
                    return DropdownMenuItem(
                      value: date,
                      child: Text(
                        MaterialLocalizations.of(context).formatMonthYear(date),
                      ),
                    );
                  }),
                  onChanged: (value) {
                    if (value != null)
                      ref.read(dashboardMonthProvider.notifier).state = value;
                  },
                ),
                const SizedBox(height: 26),
                Text(
                  'Spending overview',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Card(
                  child: SizedBox(
                    height: 108,
                    child: totals.when(
                      data: (value) => _SpendingBars(
                        expenses: value.expenses,
                        income: value.income,
                      ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, state) => const Center(child: Text('No data')),
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  'Expense categories',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ref
                        .watch(dashboardCategoriesProvider)
                        .when(
                          data: (items) {
                            if (items.isEmpty)
                              return const Text('No expenses for this month');
                            return Column(
                              children: items
                                  .take(5)
                                  .map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(child: Text(item.name)),
                                          Text(
                                            formatMoney(item.amount),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (_, state) => const Text('No data'),
                        ),
                  ),
                ),
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent transactions',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    TextButton(
                      onPressed: () => context.go('/transactions'),
                      child: const Text('View all'),
                    ),
                  ],
                ),
                if (recent.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No transactions yet. Add your first one below.',
                      ),
                    ),
                  ),
                ...recent.map((transaction) {
                  final category = categoryMap[transaction.categoryId];
                  final income = transaction.type == 'income';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Icon(iconForName(category?.icon ?? 'category')),
                      ),
                      title: Text(
                        transaction.note?.isNotEmpty == true
                            ? transaction.note!
                            : category?.name ?? 'Transaction',
                      ),
                      subtitle: Text(category?.name ?? 'Other'),
                      trailing: Text(
                        '${income ? '+' : '-'} ${formatMoney(transaction.amount)}',
                        style: TextStyle(
                          color: income
                              ? Colors.green
                              : Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  );
                }),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showNotifications(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => FutureBuilder<List<FinanceAlert>>(
      future: ref.read(repositoryProvider).alerts(),
      builder: (context, snapshot) {
        final alerts = snapshot.data ?? const <FinanceAlert>[];
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SafeArea(
            child: SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Notifications',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                if (alerts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: Text('You are all caught up.')),
                  ),
                ...alerts.map(
                  (alert) => ListTile(
                    leading: CircleAvatar(child: Icon(_alertIcon(alert.icon))),
                    title: Text(alert.title),
                    subtitle: Text(alert.message),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

IconData _alertIcon(String icon) => switch (icon) {
  'warning' => Icons.warning_amber_outlined,
  'budget' => Icons.account_balance_wallet_outlined,
  'repeat' => Icons.repeat,
  'savings' => Icons.savings_outlined,
  _ => Icons.notifications_none,
};

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final int amount;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 10),
                Text(label, style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                FittedBox(
                  child: Text(
                    formatMoney(amount),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpendingBars extends StatelessWidget {
  const _SpendingBars({required this.expenses, required this.income});
  final int expenses;
  final int income;
  @override
  Widget build(BuildContext context) {
    final maxValue = (income > expenses ? income : expenses).toDouble();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Bar(
            label: 'Income',
            value: income,
            maxValue: maxValue,
            color: Colors.green,
          ),
          const SizedBox(height: 12),
          _Bar(
            label: 'Expenses',
            value: expenses,
            maxValue: maxValue,
            color: Theme.of(context).colorScheme.error,
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
  });
  final String label;
  final int value;
  final double maxValue;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 72, child: Text(label)),
      Expanded(
        child: LinearProgressIndicator(
          value: maxValue == 0 ? 0 : value / maxValue,
          minHeight: 12,
          borderRadius: BorderRadius.circular(8),
          color: color,
        ),
      ),
      const SizedBox(width: 10),
      Text(formatMoney(value)),
    ],
  );
}
