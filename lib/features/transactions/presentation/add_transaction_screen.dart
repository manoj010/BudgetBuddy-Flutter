import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/finance_models.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/repositories/finance_repository.dart';
import '../../../core/utils/money.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({
    super.key,
    this.initialType = TransactionType.expense,
  });
  final TransactionType initialType;

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late TransactionType _type;
  String? _categoryId;
  String? _accountId;
  DateTime _date = DateTime.now();
  bool _recurring = false;
  RecurrenceFrequency _frequency = RecurrenceFrequency.monthly;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  void didUpdateWidget(covariant AddTransactionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialType != widget.initialType) {
      setState(() {
        _type = widget.initialType;
        _categoryId = null;
      });
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() ||
        _accountId == null ||
        _categoryId == null)
      return;
    setState(() => _saving = true);
    try {
      await ref
          .read(repositoryProvider)
          .addTransaction(
            accountId: _accountId!,
            categoryId: _categoryId!,
            type: _type,
            amount: parseMinorUnits(_amount.text),
            date: _date,
            note: _note.text,
          );
      if (_recurring) {
        await ref
            .read(repositoryProvider)
            .addRecurring(
              accountId: _accountId!,
              categoryId: _categoryId!,
              type: _type,
              amount: parseMinorUnits(_amount.text),
              frequency: _frequency,
              startDate: _date,
              note: _note.text,
            );
      }
      refreshFinance(ref);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Transaction saved')));
        _amount.clear();
        _note.clear();
      }
    } on FinanceFailure catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final categories = ref.watch(categoriesProvider);
    final filteredCategories =
        categories.value
            ?.where(
              (category) =>
                  category.type ==
                  (_type == TransactionType.income ? 'income' : 'expense'),
            )
            .toList() ??
        [];
    if (_categoryId == null && filteredCategories.isNotEmpty)
      _categoryId = filteredCategories.first.id;
    if (_accountId == null && accounts.value?.isNotEmpty == true)
      _accountId = accounts.value!.first.id;
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Text(
                'Add transaction',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
            sliver: SliverToBoxAdapter(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<TransactionType>(
                      segments: const [
                        ButtonSegment(
                          value: TransactionType.expense,
                          label: Text('Expense'),
                          icon: Icon(Icons.arrow_upward),
                        ),
                        ButtonSegment(
                          value: TransactionType.income,
                          label: Text('Income'),
                          icon: Icon(Icons.arrow_downward),
                        ),
                        ButtonSegment(
                          value: TransactionType.savings,
                          label: Text('Savings'),
                          icon: Icon(Icons.savings_outlined),
                        ),
                      ],
                      selected: {_type},
                      onSelectionChanged: (value) => setState(() {
                        _type = value.first;
                        _categoryId = null;
                      }),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _amount,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        prefixText: 'Rs. ',
                      ),
                      validator: (value) => parseMinorUnits(value ?? '') <= 0
                          ? 'Enter an amount greater than zero'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    categories.when(
                      data: (_) => DropdownButtonFormField<String>(
                        initialValue: _categoryId,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          prefixIcon: Icon(Icons.category_outlined),
                        ),
                        items: filteredCategories
                            .map(
                              (category) => DropdownMenuItem(
                                value: category.id,
                                child: Text(category.name),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _categoryId = value),
                        validator: (value) =>
                            value == null ? 'Choose a category' : null,
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (error, stack) =>
                          Text('Categories unavailable: $error'),
                    ),
                    const SizedBox(height: 16),
                    accounts.when(
                      data: (_) => DropdownButtonFormField<String>(
                        initialValue: _accountId,
                        decoration: const InputDecoration(
                          labelText: 'Account',
                          prefixIcon: Icon(
                            Icons.account_balance_wallet_outlined,
                          ),
                        ),
                        items: (accounts.value ?? [])
                            .map(
                              (account) => DropdownMenuItem(
                                value: account.id,
                                child: Text(
                                  '${account.name} · ${formatMoney(account.currentBalance)}',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _accountId = value),
                        validator: (value) =>
                            value == null ? 'Choose an account' : null,
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (error, stack) =>
                          Text('Accounts unavailable: $error'),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today_outlined),
                      title: const Text('Date'),
                      subtitle: Text(
                        MaterialLocalizations.of(
                          context,
                        ).formatMediumDate(_date),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          initialDate: _date,
                        );
                        if (picked != null) setState(() => _date = picked);
                      },
                    ),
                    TextFormField(
                      controller: _note,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Note (optional)',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Recurring transaction'),
                      value: _recurring,
                      onChanged: (value) => setState(() => _recurring = value),
                    ),
                    if (_recurring)
                      DropdownButtonFormField<RecurrenceFrequency>(
                        initialValue: _frequency,
                        decoration: const InputDecoration(
                          labelText: 'Frequency',
                        ),
                        items: RecurrenceFrequency.values
                            .map(
                              (frequency) => DropdownMenuItem(
                                value: frequency,
                                child: Text(frequency.label),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _frequency = value ?? _frequency),
                      ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: const Text('Save transaction'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
