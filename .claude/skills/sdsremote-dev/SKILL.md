---
name: sdsremote-dev
description: Development workflow for SDS-Remote (Flutter desktop app for Siglent SDS1000X-E oscilloscopes) — code changes, analysis, running the app, and Linux/Windows builds. Always asks first whether the test suite should run.
---

# SDS-Remote development workflow



## 1. Coding

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
  test files where they belong. Always ask if you can run a live test, if not skip it.
- Never commit or push unless the user asks.

## 2. Run and build

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

## 3. Tests
After code changes, always ask if the test suite should run. If yes, run `flutter test` (full suite) or targeted tests. If no, only run `flutter analyze` and targeted manual checks.
- Question: "Should the test suite run for this change?"
- Option 1: "Yes — run tests" — run `flutter test` after the change (full suite;
  see the caveats in section 4).
- Option 2: "No — skip tests" — only run `flutter analyze` and targeted manual
  checks.


- If a live test is needed/useful to validate the implementation, ask if you should run a live test against scope and/or signal generator
  always prefer live tests over mock tests. If you are allowed to, you can manipulate all devices freely for live testing. 
  Report that you are done with a live test.
  For a live test ask the following questions with `AskUserQuestion`:
- Check if scope (usb or IP) and/or Signalgenerator (only usb) is connected, don't repeat the question if you already know the answer.
  default IP-adresses for scopes are (SDS1202X-E=192.168.178.95, SDS1104X-E=192.168.178.91)

- Full suite from the project root: `flutter test`
- Targeted tests: `flutter test test/src/<name>_test.dart`
- `test/ai_search_accuracy_test.dart` performs real API calls (needs
  `EDENAI_API_KEY` and `DEEPSEEK_API_KEY`), evaluates 20 cases and can take
  several minutes. If the keys are unavailable, run the remaining tests
  instead of the full suite.
- The application window has a minimum size of 1400×900; widget tests often
  set `tester.view.physicalSize` to that or a larger size.
- `test/src/*` tests are gitignored but must still be kept in good shape.

## 4. Documentation updates
- Once all features are implemented and all tests are green ask if you should update the SDS-Remote documentation in confluence
  Option 1: "Update confluence and README"
  Option 2: "Update confluence only"
  Option 2: "No - do nothing"
- Update assets/manuals/sds_manual.md only when completely new features or major feature changes were introduced, don't put technical information of underlying systems or technical details in, use only english no german words, don't put information of version changes in the manual. Before updating the manual report the changes and ask if you should update the manual.
- NEVER update the README.  
