# Budget Buddy

Budget Buddy is a production-quality Flutter Android expense tracker designed to make personal finances easier to understand. It works offline, stores data locally, and provides a simple dashboard for tracking income, expenses, savings, budgets, accounts, and recurring transactions.

## Features

- First-run setup for username, currency, and opening balance
- Dashboard with time-based greeting, balance, income, expenses, savings, and spending overview
- Add and manage income and expense transactions
- Categories, notes, dates, and account selection for transactions
- Multiple accounts with opening balances and safe account deletion/archive behavior
- Monthly spending budgets with progress tracking
- Savings goals with progress tracking
- Recurring transaction rules and upcoming-transaction notifications
- In-app notification center for budget, savings, and recurring-transaction reminders
- Reports with monthly income, expenses, category breakdowns, and period selection
- Dark Material 3 interface with a custom Budget Buddy launcher icon
- Offline-first local SQLite storage; no account or cloud service is required

## Technology

- Flutter and Dart
- Material 3
- Riverpod for state management
- GoRouter for navigation
- Drift with SQLite for local persistence
- FL Chart for reports and visual summaries

## Requirements

- Flutter SDK compatible with Dart 3.11 or newer
- Android Studio with an Android SDK and emulator, or a physical Android device

## Getting started

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

To build a release APK:

```bash
flutter build apk --release
```

The generated APK is written to `build/app/outputs/flutter-apk/app-release.apk`. A shareable copy is also kept at `apks/BudgetBuddy.apk` when a release build is prepared.

## Project structure

```text
lib/
  core/          Database, models, repositories, providers, theme, utilities
  features/      Onboarding, dashboard, transactions, reports, settings
  router/        Application navigation
  shared/        Reusable widgets
assets/          Launcher icon and other application assets
test/            Unit and widget tests
android/         Android application configuration
```

## Privacy

Budget Buddy is local-first. Financial data is stored on the device using SQLite and is not sent to a remote server by the application.

## License

This project is currently maintained as a personal application. Add a license here before distributing the source for reuse.
