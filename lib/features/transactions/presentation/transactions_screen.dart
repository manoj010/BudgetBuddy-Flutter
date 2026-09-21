import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money.dart';
import '../../../shared/widgets/icon_for_name.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});
  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  String _query = '';
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsProvider);
    final categories = ref.watch(categoriesProvider);
    final categoryMap = {
      for (final c in categories.value ?? <Category>[]) c.id: c,
    };
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Transactions'),
            actions: [
              IconButton(
                onPressed: () => _showSearch(context),
                icon: const Icon(Icons.search),
              ),
              const SizedBox(width: 8),
            ],
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: ['all', 'income', 'expense', 'savings']
                    .map(
                      (filter) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            filter[0].toUpperCase() + filter.substring(1),
                          ),
                          selected: _filter == filter,
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          transactions.when(
            data: (items) {
              final filtered = items.where((transaction) {
                final matchType =
                    _filter == 'all' || transaction.type == _filter;
                final category =
                    categoryMap[transaction.categoryId]?.name.toLowerCase() ??
                    '';
                return matchType &&
                    (_query.isEmpty ||
                        category.contains(_query.toLowerCase()) ||
                        (transaction.note ?? '').toLowerCase().contains(
                          _query.toLowerCase(),
                        ));
              }).toList();
              if (filtered.isEmpty)
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyTransactions(),
                );
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final transaction = filtered[index];
                    final category = categoryMap[transaction.categoryId];
                    final isIncome = transaction.type == 'income';
                    return Dismissible(
                      key: ValueKey(transaction.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Theme.of(context).colorScheme.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(Icons.delete_outline),
                      ),
                      confirmDismiss: (_) => _confirmDelete(transaction),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Icon(
                              iconForName(category?.icon ?? 'category'),
                            ),
                          ),
                          title: Text(
                            transaction.note?.isNotEmpty == true
                                ? transaction.note!
                                : category?.name ?? 'Transaction',
                          ),
                          subtitle: Text(
                            '${category?.name ?? 'Other'} · ${MaterialLocalizations.of(context).formatMediumDate(transaction.transactionDate)}',
                          ),
                          trailing: Text(
                            '${isIncome ? '+' : '-'} ${formatMoney(transaction.amount)}',
                            style: TextStyle(
                              color: isIncome
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    );
                  }, childCount: filtered.length),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stack) => SliverFillRemaining(
              child: Center(child: Text('Could not load transactions: $error')),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(TransactionsTableData transaction) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete transaction?'),
            content: const Text('The balance adjustment will be reversed.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      await ref.read(repositoryProvider).deleteTransaction(transaction.id);
      ref.invalidate(accountsProvider);
      ref.invalidate(transactionsProvider);
    }
    return confirmed;
  }

  Future<void> _showSearch(BuildContext context) async {
    final controller = TextEditingController(text: _query);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search transactions'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Note or category'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _query = controller.text);
              Navigator.pop(context);
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
    controller.dispose();
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions yet',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Start tracking your money by adding your first transaction.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
