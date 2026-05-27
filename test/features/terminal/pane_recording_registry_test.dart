/// Unit tests for [PaneRecordingRegistry] — the paneId → recording
/// handle lookup the connection bar uses to drive a focused pane's
/// record button from outside its widget subtree.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/terminal/pane_recording_registry.dart';

void main() {
  final registry = PaneRecordingRegistry.instance;

  PaneRecordingHandle handle({bool canRecord = true}) => PaneRecordingHandle(
    isRecording: ValueNotifier(false),
    canRecord: canRecord,
    toggle: () async {},
  );

  // The registry is a process singleton; keep test ids unique and tidy
  // up so one test can't see another's registration.
  tearDown(() {
    registry.unregister('p1');
    registry.unregister('p2');
  });

  test('get returns null for an unregistered pane', () {
    expect(registry.get('p1'), isNull);
  });

  test('register then get returns the same handle', () {
    final h = handle();
    registry.register('p1', h);
    expect(registry.get('p1'), same(h));
  });

  test('register is per-pane — ids do not collide', () {
    final h1 = handle();
    final h2 = handle(canRecord: false);
    registry.register('p1', h1);
    registry.register('p2', h2);
    expect(registry.get('p1'), same(h1));
    expect(registry.get('p2'), same(h2));
    expect(registry.get('p2')!.canRecord, isFalse);
  });

  test('re-registering a pane id replaces the handle', () {
    final first = handle();
    final second = handle();
    registry.register('p1', first);
    registry.register('p1', second);
    expect(registry.get('p1'), same(second));
  });

  test('unregister drops the entry', () {
    registry.register('p1', handle());
    registry.unregister('p1');
    expect(registry.get('p1'), isNull);
  });
}
