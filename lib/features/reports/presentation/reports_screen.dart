import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money.dart';

final reportMonthProvider = StateProvider<DateTime>((ref) => DateTime.now());
final reportTotalsProvider = FutureProvider.autoDispose(
  (ref) => ref
      .watch(repositoryProvider)
      .totalsForMonth(ref.watch(reportMonthProvider)),
);
final reportCategoriesProvider = FutureProvider.autoDispose(
  (ref) => ref
      .watch(repositoryProvider)
      .categoryTotals(ref.watch(reportMonthProvider)),
);

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(reportMonthProvider);
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Text(
                'Reports',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  'Report period',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<DateTime>(
                  initialValue: DateTime(month.year, month.month),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.date_range_outlined),
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
                      ref.read(reportMonthProvider.notifier).state = value;
                  },
                ),
                const SizedBox(height: 24),
                ref
                    .watch(reportTotalsProvider)
                    .when(
                      data: (data) => Column(
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Financial summary',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 16),
                                  _Metric(
                                    label: 'Total income',
                                    amount: data.income,
                                    color: Colors.green,
                                  ),
                                  _Metric(
                                    label: 'Total expenses',
                                    amount: data.expenses,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  _Metric(
                                    label: 'Total savings',
                                    amount: data.savings,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.tertiary,
                                  ),
                                  _Metric(
                                    label: 'Net cash flow',
                                    amount: data.netCashFlow,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  _Metric(
                                    label: 'Savings rate',
                                    text: data.income == 0
                                        ? '0%'
                                        : '${(data.savings / data.income * 100).toStringAsFixed(1)}%',
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Income vs expense',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 16),
                                  _ReportBar(
                                    label: 'Income',
                                    value: data.income,
                                    max: data.income > data.expenses
                                        ? data.income
                                        : data.expenses,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(height: 16),
                                  _ReportBar(
                                    label: 'Expense',
                                    value: data.expenses,
                                    max: data.income > data.expenses
                                        ? data.income
                                        : data.expenses,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, stack) => Text('$error'),
                    ),
                const SizedBox(height: 24),
                Text(
                  'Top spending categories',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: ref
                        .watch(reportCategoriesProvider)
                        .when(
                          data: (items) {
                            if (items.isEmpty)
                              return const Text(
                                'No expenses recorded for this period.',
                              );
                            return Column(
                              children: items
                                  .take(8)
                                  .map(
                                    (item) => ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(item.name),
                                      trailing: Text(
                                        formatMoney(item.amount),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, stack) => Text('$error'),
                        ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    this.amount,
    this.text,
    required this.color,
  });
  final String label;
  final int? amount;
  final String? text;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          text ?? formatMoney(amount ?? 0),
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    ),
  );
}

class _ReportBar extends StatelessWidget {
  const _ReportBar({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
  });
  final String label;
  final int value;
  final int max;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 72, child: Text(label)),
      Expanded(
        child: LinearProgressIndicator(
          value: max == 0 ? 0 : value / max,
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
