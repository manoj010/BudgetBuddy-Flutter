import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/models/finance_models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/repositories/finance_repository.dart';
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
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 12, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Transactions',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  IconButton(
                    onPressed: () => _showSearch(context),
                    icon: const Icon(Icons.search),
                    tooltip: 'Search transactions',
                  ),
                ],
              ),
            ),
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
                      direction: DismissDirection.horizontal,
                      background: Container(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.only(left: 24),
                        child: const Icon(Icons.edit_outlined),
                      ),
                      secondaryBackground: Container(
                        color: Theme.of(context).colorScheme.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        child: const Icon(Icons.delete_outline),
                      ),
                      confirmDismiss: (direction) {
                        if (direction == DismissDirection.startToEnd) {
                          return _editTransaction(transaction);
                        }
                        return _confirmDelete(transaction);
                      },
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
      refreshFinance(ref);
    }
    return confirmed;
  }

  Future<bool> _editTransaction(TransactionsTableData transaction) async {
    final categories = await ref.read(categoriesProvider.future);
    final categoryType = transaction.type == TransactionType.income.value
        ? 'income'
        : 'expense';
    final availableCategories = categories
        .where((category) => category.type == categoryType)
        .toList();
    if (availableCategories.isEmpty) return false;
    final categoryIds = availableCategories.map((category) => category.id);
    final result = await showDialog<_EditTransactionValues>(
      context: context,
      builder: (dialogContext) {
        final amountController = TextEditingController(
          text: formatInputAmount(transaction.amount),
        );
        var selectedCategoryId = categoryIds.contains(transaction.categoryId)
            ? transaction.categoryId
            : availableCategories.first.id;
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Edit transaction'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    prefixText: 'Rs. ',
                    errorText: errorText,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedCategoryId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: availableCategories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(
                    () => selectedCategoryId = value ?? selectedCategoryId,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final amount = parseMinorUnits(amountController.text);
                  if (amount <= 0) {
                    setDialogState(
                      () => errorText = 'Enter an amount greater than zero.',
                    );
                    return;
                  }
                  Navigator.pop(
                    dialogContext,
                    _EditTransactionValues(
                      categoryId: selectedCategoryId,
                      amount: amount,
                    ),
                  );
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return false;
    try {
      await ref
          .read(repositoryProvider)
          .updateTransaction(
            id: transaction.id,
            categoryId: result.categoryId,
            amount: result.amount,
          );
      refreshFinance(ref);
    } on FinanceFailure catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
    }
    return false;
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

class _EditTransactionValues {
  const _EditTransactionValues({
    required this.categoryId,
    required this.amount,
  });
  final String categoryId;
  final int amount;
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
