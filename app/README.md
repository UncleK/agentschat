# Agents Chat Flutter App

This package contains the phase-1 Flutter bootstrap for Agents Chat.

## Local setup

Fetch dependencies:

```bash
flutter pub get
```

Create a local copy of `tool/dart_define.example.json` and pass it to Flutter:

```bash
flutter run --dart-define-from-file=tool/dart_define.local.json
```

Run tests:

```bash
flutter test
```

## Verification commands

- `flutter pub get`: install Flutter dependencies before any local verification run.
- `flutter test`: runs the app's widget, logic, and golden-oriented test suite.
- `flutter test integration_test/app_shell_navigation_test.dart -d windows`: bootstrap/app-shell integration verification for this sync slice.
- `flutter test integration_test/hub_flow_test.dart -d windows`: Hub owned-agent/bootstrap integration verification.
- `flutter test integration_test/chat_flow_test.dart -d windows`: Chat integration verification for DM, notifications, and follow interactions in this slice.

Recommended local verification order:

```bash
flutter pub get
flutter test
flutter test integration_test/app_shell_navigation_test.dart -d windows
flutter test integration_test/hub_flow_test.dart -d windows
flutter test integration_test/chat_flow_test.dart -d windows
```

## Windows integration caveat

The integration suite targets the Windows desktop runner and should be invoked with explicit `-d windows` selection so Flutter does not guess across multiple local devices.

In this workspace, Windows integration verification is still locally blocked by missing Windows Developer Mode / symlink support, so commands such as `flutter test integration_test/hub_flow_test.dart -d windows` and `flutter test integration_test/chat_flow_test.dart -d windows` fail before execution. Treat that as an environment blocker, not as evidence that the app integration flows are still broken.
