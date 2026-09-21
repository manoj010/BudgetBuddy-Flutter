import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:budget_buddy/features/onboarding/presentation/onboarding_screen.dart';

void main() {
  testWidgets('shows first-launch onboarding', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: OnboardingScreen())),
    );
    await tester.pump();
    expect(find.text('Welcome to BudgetBuddy'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });
}
