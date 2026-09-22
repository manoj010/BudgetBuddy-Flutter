import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/models/finance_models.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/transactions/presentation/add_transaction_screen.dart';
import '../features/transactions/presentation/transactions_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        _branch('/home', const DashboardScreen()),
        _branch('/transactions', const TransactionsScreen()),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/add',
              builder: (context, state) => AddTransactionScreen(
                initialType: _transactionTypeFromQuery(
                  state.uri.queryParameters['type'],
                ),
              ),
            ),
          ],
        ),
        _branch('/reports', const ReportsScreen()),
        _branch('/settings', const SettingsScreen()),
      ],
    ),
  ],
);

StatefulShellBranch _branch(String path, Widget screen) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (context, state) => screen)],
);

TransactionType _transactionTypeFromQuery(String? value) => switch (value) {
  'income' => TransactionType.income,
  'savings' => TransactionType.savings,
  _ => TransactionType.expense,
};

class AppShell extends StatefulWidget {
  const AppShell({required this.navigationShell, super.key});
  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  DateTime? _lastHomeBack;

  static const _backChannel = MethodChannel('budget_buddy/back');

  @override
  void initState() {
    super.initState();
    _backChannel.setMethodCallHandler((call) async {
      if (call.method == 'backPressed') await _handleBack();
    });
  }

  @override
  void dispose() {
    _backChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<void> _handleBack() async {
    final navigationShell = widget.navigationShell;
    if (navigationShell.currentIndex != 0) {
      navigationShell.goBranch(0, initialLocation: true);
      if (mounted) setState(() => _lastHomeBack = null);
      return;
    }

    final now = DateTime.now();
    final pressedAgain =
        _lastHomeBack != null &&
        now.difference(_lastHomeBack!) <= const Duration(seconds: 2);
    if (pressedAgain) {
      await _backChannel.invokeMethod<void>('exitApp');
      return;
    }
    if (!mounted) return;
    setState(() => _lastHomeBack = now);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.account_balance_wallet_rounded,
                  size: 21,
                  color: Color(0xFF1FAD48),
                ),
              ),
              SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Press BACK again to exit.',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          width: 240,
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape: StadiumBorder(),
          backgroundColor: Color(0xFF4A4A4A),
          elevation: 4,
        ),
      );
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted || _lastHomeBack != now) return;
      setState(() => _lastHomeBack = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final navigationShell = widget.navigationShell;
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Add',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
