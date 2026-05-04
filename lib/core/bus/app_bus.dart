/// Command / Event bus — Dart-side wrapper.
///
/// Frontend dispatches typed [BusCommand]s through [AppBus.dispatch];
/// Riverpod views subscribe to per-topic event streams via
/// [AppBus.subscribe]. Both delegate to the FRB binding generated
/// from `rust/crates/lfs_frb/src/api/bus.rs`. The wrapper exists so
/// call sites depend on a stable Dart-side abstraction rather than
/// the regenerated FRB symbols directly — making it cheap to swap
/// the transport (mock for tests, future Tauri channel) without
/// touching every consumer.
///
/// Cold-start contract: `AppBus.subscribe` MUST NOT be called before
/// `_initRustCoreOrFatal` completes. Every callsite is either inside
/// the post-frame `_bootstrap` chain (or its descendants) or behind a
/// Riverpod provider whose first read happens after that point. The
/// previous architecture had `MainScreen.initState` wire the prompt
/// listeners synchronously during the first runApp frame — pre-FRB-init
/// when the Rust load is deferred — and the resulting ordering bugs
/// caused multi-minute hangs in the unlock cascade. The fix moved
/// every listener `.start()` call into `_bootstrap` (see
/// `_LetsFLUTsshAppState._bootstrap`), so this module no longer needs
/// the lazy / retry escape hatches that briefly lived here.
library;

import 'dart:async';

import '../../src/rust/api/bus.dart' as rust_bus;

export '../../src/rust/api/bus.dart' show BusCommand, BusEvent, BusTopic;

/// Single instance — the Rust side is process-singleton, so a
/// matching Dart-side singleton keeps the abstraction symmetric.
class AppBus {
  AppBus._();
  static final AppBus instance = AppBus._();

  /// Per-topic shared broadcast streams. Lazily wired on first use:
  /// the underlying FRB subscription opens once for the topic, fans
  /// out to every Dart-side subscriber through a `StreamController.
  /// broadcast()`, and stays alive for the AppBus singleton's
  /// lifetime (= the process lifetime). Concrete reason: each
  /// `bus_subscribe` call on the Rust side is a separate
  /// `StreamSink<BusEvent>`, and FRB's protocol unconditionally
  /// emits `Shell: Fail to post message to Dart` on every
  /// subscription teardown (the `StreamSinkCloser::Drop` impl in
  /// `flutter_rust_bridge::stream::closer` posts an
  /// `encode_close_stream` message whose Dart receiver is by
  /// definition already gone). Keeping a single FRB subscription
  /// per topic for the entire process lifetime collapses N
  /// per-disconnect cancels to one teardown at exit.
  final Map<rust_bus.BusTopic, _SharedTopic> _shared = {};

  /// Dispatch a typed command. Returns when the Rust side has
  /// processed it; events emitted as a side effect arrive on the
  /// matching [subscribe] streams.
  Future<void> dispatch(rust_bus.BusCommand command) =>
      rust_bus.busDispatch(command: command);

  /// Subscribe to events on [topic]. The returned stream is fed by
  /// a process-lifetime-scoped FRB subscription that fans out to
  /// every Dart subscriber via `StreamController.broadcast`. The
  /// caller cancels the returned subscription as usual; the
  /// underlying FRB stream is NOT torn down at that point — only
  /// when the process exits.
  Stream<rust_bus.BusEvent> subscribe(rust_bus.BusTopic topic) {
    final entry = _shared.putIfAbsent(topic, () => _SharedTopic(topic));
    return entry.controller.stream;
  }

  /// Convenience — subscribe to [BusTopic.connection] events and
  /// filter to a single connection id. Variants without an id are
  /// dropped.
  Stream<rust_bus.BusEvent> subscribeConnection(String connectionId) {
    return subscribe(rust_bus.BusTopic.connection).where((e) {
      final eventId = switch (e) {
        rust_bus.BusEvent_ConnectionStateChanged(:final id) => id,
        rust_bus.BusEvent_ConnectionProgress(:final id) => id,
        rust_bus.BusEvent_ConnectionError(:final id) => id,
        rust_bus.BusEvent_ConnectionRemoved(:final id) => id,
        _ => null,
      };
      return eventId == connectionId;
    });
  }

  /// Convenience — subscribe to [BusTopic.recorder] events and
  /// filter to a single recording id. Variants without an id are
  /// dropped.
  Stream<rust_bus.BusEvent> subscribeRecorder(String recorderId) {
    return subscribe(rust_bus.BusTopic.recorder).where((e) {
      final eventId = switch (e) {
        rust_bus.BusEvent_RecorderStarted(:final id) => id,
        rust_bus.BusEvent_RecorderStopped(:final id) => id,
        rust_bus.BusEvent_RecorderBytesWritten(:final id) => id,
        rust_bus.BusEvent_RecorderRotateRequested(:final id) => id,
        _ => null,
      };
      return eventId == recorderId;
    });
  }
}

/// Per-topic broadcast pipe + the underlying FRB subscription that
/// feeds it. Lives for the AppBus singleton's lifetime (= process
/// lifetime). FRB-unreachable contexts (flutter_test without the
/// native blob loaded) catch the `busSubscribe` throw and leave
/// the controller as-is — listeners receive no events but all
/// `subscribe` calls still return a valid stream, so test code
/// that wires up but never expects events keeps compiling.
class _SharedTopic {
  _SharedTopic(rust_bus.BusTopic topic) {
    try {
      _frbSub = rust_bus
          .busSubscribe(topic: topic)
          .listen(controller.add, onError: controller.addError);
    } catch (_) {
      _frbSub = null;
    }
  }

  final controller = StreamController<rust_bus.BusEvent>.broadcast();
  // ignore: unused_field
  StreamSubscription<rust_bus.BusEvent>? _frbSub;
}
