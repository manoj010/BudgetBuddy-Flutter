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

final onboardingCompleteProvider = FutureProvider<bool>(
  (ref) => ref.watch(repositoryProvider).isOnboardingComplete(),
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

void refreshFinance(Ref ref) {
  ref.invalidate(accountsProvider);
  ref.invalidate(categoriesProvider);
  ref.invalidate(transactionsProvider);
}
