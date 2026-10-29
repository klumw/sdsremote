---
name: sdsremote-dev
description: Development workflow for SDS-Remote (Flutter desktop app for Siglent SDS1000X-E oscilloscopes) — code changes, analysis, running the app, and Linux/Windows builds. Always asks first whether the test suite should run.
---

# SDS-Remote development workflow

## 1. Always ask first: should the test suite run?

Do this before reading code, editing files, or running any command.

Ask the user with `AskUserQuestion`:

- Question: "Should the test suite run for this change?"
- Option 1: "Yes — run tests" — run `flutter test` after the change (full suite;
  see the caveats in section 4).
- Option 2: "No — skip tests" — only run `flutter analyze` and targeted manual
  checks.

Do not start the actual work until the question has been answered.

## 2. Coding

- All identifiers, comments, log and error messages, UI strings and
  documentation must be English (global project rule).
- Match the surrounding code style and comment density.
- Format every changed Dart file with `dart format <files>`.
- Run static analysis before reporting the work as done: `flutter analyze`
  (or at least the changed files).
- Keep AI agent prompts in `lib/src/ai/agents/systemprompts.dart` in sync with
  the tools they describe.
- Patched dependencies live in `packages/dartantic_ai_patched/` and
  `packages/usbtmc_dart_patched/`; edit those, never the pub cache.
- Tests live under `test/`, mostly in `test/src/`. Note that `.gitignore`
  ignores `/test/*` and most of `/test/src/*`; only
  `test/src/signal_generator/` and `test/src/bode/` are tracked. Still add
  test files where they belong.
- Never commit or push unless the user asks.

## 3. Run and build

- Install dependencies after pubspec changes: `flutter pub get`
- Run on Linux: `flutter run -d linux`
- Run on Windows: `flutter run -d windows`
- Build Linux release: `flutter build linux`
  → `build/linux/x64/release/bundle/`
- Build Windows release: `flutter build windows`
  → `build/windows/x64/runner/Release/`
- Debug logging: append `-- --loglevel=DEBUG` to `flutter run`, or build/run
  with `--dart-define=loglevel=DEBUG`. The application log is written to
  `<system temp>/sds/logging/sds.log`.

## 4. Tests

- Full suite from the project root: `flutter test`
- Targeted tests: `flutter test test/src/<name>_test.dart`
- `test/ai_search_accuracy_test.dart` performs real API calls (needs
  `EDENAI_API_KEY` and `DEEPSEEK_API_KEY`), evaluates 20 cases and can take
  several minutes. If the keys are unavailable, run the remaining tests
  instead of the full suite.
- The application window has a minimum size of 1400×900; widget tests often
  set `tester.view.physicalSize` to that or a larger size.
- `test/src/*` tests are gitignored but must still be kept in good shape.
