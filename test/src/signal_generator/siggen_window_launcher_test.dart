import 'dart:async';

import 'package:sdsremote/src/signal_generator/siggen_window_launcher.dart';
import 'package:sdsremote/src/signal_generator/siggen_window_protocol.dart';
import 'package:test/test.dart';

class _FakeHandle implements MultiWindowHandle {
  _FakeHandle(this.windowId, this.arguments);

  @override
  final String windowId;

  @override
  final String arguments;

  bool shown = false;
  bool focused = false;
  bool closed = false;
  final List<String> invocations = <String>[];
  Map<String, dynamic>? lastState;

  @override
  Future<void> show() async {
    shown = true;
  }

  @override
  Future<void> focus() async {
    focused = true;
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> invoke(String method, [Map<String, dynamic>? arguments]) async {
    invocations.add(method);
    if (method == 'state') lastState = arguments;
  }
}

class _FakeBackend implements MultiWindowBackend {
  final List<_FakeHandle> windows = <_FakeHandle>[];
  final StreamController<void> _changes = StreamController<void>.broadcast();
  String? createdArguments;
  int createCount = 0;
  bool failList = false;

  @override
  Stream<void> get windowChanges => _changes.stream;

  @override
  Future<List<MultiWindowHandle>> listWindows() async {
    if (failList) throw StateError('transient window-list error');
    return List<MultiWindowHandle>.of(windows);
  }

  @override
  Future<MultiWindowHandle> createWindow(String arguments) async {
    createCount++;
    createdArguments = arguments;
    final handle = _FakeHandle('win-$createCount', arguments);
    windows.add(handle);
    _changes.add(null);
    return handle;
  }

  void removeWindow(_FakeHandle handle) {
    windows.remove(handle);
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}

void main() {
  late _FakeBackend backend;
  late SigGenWindowLauncher launcher;
  var canOpen = true;
  final openStates = <bool>[];

  setUp(() {
    canOpen = true;
    openStates.clear();
    backend = _FakeBackend();
    launcher = SigGenWindowLauncher(
      backend: backend,
      canOpen: () => canOpen,
      onOpenChanged: openStates.add,
    );
  });

  tearDown(() async {
    launcher.dispose();
    await backend.dispose();
  });

  test('creates one window with the signal-generator arguments', () async {
    final opened = await launcher.openOrFocus();

    expect(opened, isTrue);
    expect(backend.createCount, equals(1));
    expect(
      SigGenWindowArguments.isSigGenWindow(backend.createdArguments!),
      isTrue,
    );
    final handle = backend.windows.single;
    // The child engine shows itself after its first painted frame.
    expect(handle.shown, isFalse);
    expect(handle.focused, isFalse);
    expect(launcher.isOpen, isTrue);
    expect(openStates, equals([true]));
  });

  test('focuses an existing window instead of creating a duplicate', () async {
    await launcher.openOrFocus();
    final handle = backend.windows.single;

    final opened = await launcher.openOrFocus();

    expect(opened, isTrue);
    expect(backend.createCount, equals(1));
    expect(handle.shown, isTrue);
    expect(handle.focused, isTrue);
  });

  test('does nothing when opening is not allowed', () async {
    canOpen = false;

    final opened = await launcher.openOrFocus();

    expect(opened, isFalse);
    expect(backend.createCount, isZero);
    expect(launcher.isOpen, isFalse);
  });

  test(
    'focuses an existing window even when opening is no longer allowed',
    () async {
      await launcher.openOrFocus();
      canOpen = false;

      final opened = await launcher.openOrFocus();

      expect(opened, isTrue);
      expect(backend.createCount, equals(1));
      expect(backend.windows.single.focused, isTrue);
    },
  );

  test('deduplicates concurrent open requests', () async {
    final first = launcher.openOrFocus();
    final second = launcher.openOrFocus();

    await Future.wait([first, second]);

    expect(backend.createCount, equals(1));
  });

  test('detects a window closed by the user', () async {
    await launcher.openOrFocus();
    expect(launcher.isOpen, isTrue);
    final handle = backend.windows.single;

    backend.removeWindow(handle);
    await Future<void>.delayed(Duration.zero);

    expect(launcher.isOpen, isFalse);
    expect(openStates, equals([true, false]));
  });

  test('keeps the open state on a transient window-list error', () async {
    await launcher.openOrFocus();
    expect(launcher.isOpen, isTrue);
    final handle = backend.windows.single;

    backend.failList = true;
    backend.removeWindow(handle);
    await Future<void>.delayed(Duration.zero);

    expect(launcher.isOpen, isTrue);
  });

  test('close() closes signal-generator windows only', () async {
    await launcher.openOrFocus();
    final sigGen = backend.windows.single;
    final other = _FakeHandle('main', '');
    backend.windows.add(other);

    await launcher.close();

    expect(sigGen.closed, isTrue);
    expect(other.closed, isFalse);
    expect(launcher.isOpen, isFalse);
  });

  test('pushState sends the snapshot to the child window', () async {
    await launcher.openOrFocus();
    final handle = backend.windows.single;

    await launcher.pushState(
      const SigGenWindowState(
        generator: SigGenGeneratorSnapshot(connected: true, mutable: true),
      ),
    );

    expect(handle.invocations, equals(['state']));
    expect(handle.lastState?['generator']['connected'], isTrue);
  });

  test('pushState without an open window is a no-op', () async {
    await launcher.pushState(const SigGenWindowState());
    expect(backend.windows, isEmpty);
  });
}
