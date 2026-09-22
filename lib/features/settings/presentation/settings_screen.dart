import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/repositories/finance_repository.dart';
import '../../../core/utils/money.dart';
import '../../dashboard/presentation/dashboard_screen.dart';

final goalsProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(repositoryProvider).goals(),
);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final goals = ref.watch(goalsProvider);
    final themeMode = ref.watch(themeModeProvider).value ?? 'dark';
    final allowNegative = ref.watch(allowNegativeProvider).value ?? false;
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  'Your money',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.account_balance_wallet_outlined,
                        ),
                        title: const Text('Accounts'),
                        subtitle: Text(
                          '${accounts.value?.length ?? 0} active accounts',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showAccounts(context, ref),
                      ),
                      ListTile(
                        leading: const Icon(Icons.savings_outlined),
                        title: const Text('Savings goals'),
                        subtitle: Text(
                          '${goals.value?.length ?? 0} active goals',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showGoals(context, ref),
                      ),
                      ListTile(
                        leading: const Icon(Icons.account_balance_outlined),
                        title: const Text('Monthly budgets'),
                        subtitle: const Text('Set spending limits'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showBudget(context, ref),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Preferences',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      const ListTile(
                        leading: Icon(Icons.currency_rupee),
                        title: Text('Currency'),
                        subtitle: Text('NPR — Nepalese Rupee'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: const Text('Username'),
                        subtitle: const Text(
                          'Change the name shown on your dashboard',
                        ),
                        onTap: () => _editGreetingName(context, ref),
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.warning_amber_outlined),
                        title: const Text('Allow negative balances'),
                        subtitle: const Text(
                          'Permit spending beyond available balance',
                        ),
                        value: allowNegative,
                        onChanged: (value) async {
                          await ref
                              .read(repositoryProvider)
                              .setAllowNegative(value);
                          ref.invalidate(allowNegativeProvider);
                          refreshFinance(ref);
                        },
                      ),
                      ListTile(
                        leading: Icon(Icons.palette_outlined),
                        title: Text('Theme'),
                        subtitle: Text(
                          themeMode == 'light' ? 'Light theme' : 'Dark theme',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showThemePicker(context, ref),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text('Data', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.ios_share_outlined),
                        title: const Text('Export data'),
                        subtitle: const Text('Save your data as an Excel file'),
                        onTap: () => _exportData(context, ref),
                      ),
                      ListTile(
                        leading: const Icon(Icons.backup_outlined),
                        title: const Text('Backup and restore'),
                        subtitle: const Text('Restore data from an Excel file'),
                        onTap: () => _restoreData(context, ref),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editGreetingName(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(
      text: await ref.read(repositoryProvider).username(),
    );
    if (!context.mounted) {
      controller.dispose();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Username'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Your name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              await ref.read(repositoryProvider).setUsername(controller.text);
              ref.invalidate(usernameProvider);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
  }

  Future<void> _showThemePicker(BuildContext context, WidgetRef ref) async {
    final current = ref.read(themeModeProvider).value ?? 'dark';
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choose theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Dark'),
              trailing: current == 'dark'
                  ? const Icon(Icons.check)
                  : const SizedBox.shrink(),
              onTap: () => Navigator.pop(dialogContext, 'dark'),
            ),
            ListTile(
              title: const Text('Light'),
              trailing: current == 'light'
                  ? const Icon(Icons.check)
                  : const SizedBox.shrink(),
              onTap: () => Navigator.pop(dialogContext, 'light'),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await ref.read(repositoryProvider).setThemeMode(selected);
    ref.invalidate(themeModeProvider);
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    try {
      final bytes = await ref.read(repositoryProvider).exportExcel();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Budget Buddy Excel export',
        fileName: 'budget_buddy_export.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: Uint8List.fromList(bytes),
      );
      if (!context.mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Excel export saved successfully')),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
    }
  }

  Future<void> _restoreData(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose Budget Buddy backup',
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || !context.mounted) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Restore backup?'),
            content: const Text(
              'This will replace all current Budget Buddy data with the selected backup.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Restore'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      final file = result.files.single;
      final bytes = file.path != null
          ? await File(file.path!).readAsBytes()
          : file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw const FinanceFailure('Could not read the selected Excel file.');
      }
      await ref.read(repositoryProvider).restoreExcel(bytes);
      refreshFinance(ref);
      ref.invalidate(goalsProvider);
      ref.invalidate(usernameProvider);
      ref.invalidate(themeModeProvider);
      ref.invalidate(allowNegativeProvider);
      ref.invalidate(onboardingCompleteProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Backup restored successfully')),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $error')));
    }
  }

  Future<void> _showAccounts(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _AccountsSheet(),
      );
  Future<void> _showGoals(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _GoalsSheet(),
      );
  Future<void> _showBudget(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _BudgetSheet(),
      );
}

class _AccountsSheet extends ConsumerStatefulWidget {
  const _AccountsSheet();
  @override
  ConsumerState<_AccountsSheet> createState() => _AccountsSheetState();
}

class _AccountsSheetState extends ConsumerState<_AccountsSheet> {
  final name = TextEditingController();
  final amount = TextEditingController();
  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? [];
    return _SheetFrame(
      title: 'Accounts',
      children: [
        Text('${accounts.length} active account(s)'),
        const SizedBox(height: 12),
        ...accounts.map(
          (account) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: Text(account.name),
            subtitle: Text(formatMoney(account.currentBalance)),
            trailing: IconButton(
              tooltip: 'Delete account',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteAccount(account.id, account.name),
            ),
          ),
        ),
        if (accounts.isNotEmpty) const Divider(),
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'New account name'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: amount,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Opening balance',
            prefixText: 'Rs. ',
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await ref
                  .read(repositoryProvider)
                  .addAccount(
                    name: name.text,
                    type: 'cash',
                    openingBalance: parseMinorUnits(amount.text),
                  );
              refreshFinance(ref);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Add account'),
          ),
        ),
      ],
    );
  }

  Future<void> _deleteAccount(String id, String name) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete account?'),
            content: Text(
              'Delete "$name"? Accounts with transactions cannot be deleted.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await ref.read(repositoryProvider).deleteAccount(id);
      refreshFinance(ref);
      if (mounted) setState(() {});
    } on FinanceFailure catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

class _GoalsSheet extends ConsumerStatefulWidget {
  const _GoalsSheet();
  @override
  ConsumerState<_GoalsSheet> createState() => _GoalsSheetState();
}

class _GoalsSheetState extends ConsumerState<_GoalsSheet> {
  final name = TextEditingController();
  final target = TextEditingController();
  @override
  void dispose() {
    name.dispose();
    target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final goals = ref.watch(goalsProvider).value ?? [];
    return _SheetFrame(
      title: 'Savings goals',
      children: [
        Text('${goals.length} active goal(s)'),
        const SizedBox(height: 12),
        TextField(
          controller: name,
          decoration: const InputDecoration(labelText: 'Goal name'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: target,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Target amount',
            prefixText: 'Rs. ',
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await ref
                  .read(repositoryProvider)
                  .addGoal(
                    name: name.text,
                    targetAmount: parseMinorUnits(target.text),
                    currentAmount: 0,
                  );
              ref.invalidate(goalsProvider);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Create goal'),
          ),
        ),
      ],
    );
  }
}

class _BudgetSheet extends ConsumerStatefulWidget {
  const _BudgetSheet();
  @override
  ConsumerState<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<_BudgetSheet> {
  final amount = TextEditingController();
  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SheetFrame(
    title: 'Monthly budget',
    children: [
      TextField(
        controller: amount,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'Overall monthly budget',
          prefixText: 'Rs. ',
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () async {
            await ref
                .read(repositoryProvider)
                .saveBudget(
                  amount: parseMinorUnits(amount.text),
                  month: DateTime.now(),
                );
            if (mounted) Navigator.pop(context);
          },
          child: const Text('Save budget'),
        ),
      ),
    ],
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 20,
      right: 20,
      top: 20,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}
