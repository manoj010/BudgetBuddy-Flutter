import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/providers/app_providers.dart';
import 'features/onboarding/presentation/onboarding_screen.dart';
import 'router/app_router.dart';

class BudgetBuddyApp extends ConsumerWidget {
  const BudgetBuddyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final onboarding = ref.watch(onboardingCompleteProvider);
    return onboarding.when(
      loading: () =>
          MaterialApp(theme: AppTheme.light, home: const _SplashScreen()),
      error: (error, stack) =>
          MaterialApp(theme: AppTheme.light, home: const _ErrorScreen()),
      data: (complete) => complete
          ? MaterialApp.router(
              title: 'BudgetBuddy',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: ThemeMode.system,
              routerConfig: appRouter,
            )
          : MaterialApp(
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              home: const OnboardingScreen(),
            ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: Text('Unable to open your local budget data.')),
  );
}
