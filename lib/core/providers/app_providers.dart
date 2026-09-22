import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../repositories/finance_repository.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final repositoryProvider = Provider<FinanceRepository>(
  (ref) => FinanceRepository(ref.watch(databaseProvider)),
);

final financeRefreshProvider = StateProvider<int>((ref) => 0);

final onboardingCompleteProvider = FutureProvider<bool>(
  (ref) => ref.watch(repositoryProvider).isOnboardingComplete(),
);
final themeModeProvider = FutureProvider<String>(
  (ref) => ref.watch(repositoryProvider).themeMode(),
);
final allowNegativeProvider = FutureProvider<bool>(
  (ref) => ref.watch(repositoryProvider).allowNegative(),
);
final accountsProvider = FutureProvider.autoDispose<List<Account>>(
  (ref) => ref.watch(repositoryProvider).accounts(),
);
final categoriesProvider = FutureProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(repositoryProvider).categories(),
);
final transactionsProvider =
    FutureProvider.autoDispose<List<TransactionsTableData>>(
      (ref) => ref.watch(repositoryProvider).transactions(),
    );

void refreshFinance(WidgetRef ref) {
  ref.read(financeRefreshProvider.notifier).state++;
  ref.invalidate(accountsProvider);
  ref.invalidate(categoriesProvider);
  ref.invalidate(transactionsProvider);
}
