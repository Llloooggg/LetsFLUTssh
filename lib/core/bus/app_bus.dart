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
/// Cold-start contract: `AppBus.subscribe` may be called at any
/// point relative to `_initRustCoreOrFatal`. Listeners owned
/// directly by the boot chain (`HostKeyPromptListener.start`,
/// `TierStateObserver.start`, …) are wired from
/// `_wireFrbDependentBootstrapListeners` after FRB is up — they
/// see a ready core. Riverpod-driven subscribers can't promise
/// that ordering: a `Notifier.build()` runs lazily when the FIRST
/// `ref.watch` / `ref.read` lands on the provider, and that read
/// often originates from a widget that mounts during the first
/// runApp frame (pre-FRB-init when the Rust load is deferred to
/// paint the splash first). [_SharedTopic.ensureFrbSub] handles
/// this by retrying the FRB subscription on every `subscribe`
/// call — once `RustLib.instance.initialized` flips to true and
/// any subscriber re-enters `subscribe`, the cached `_SharedTopic`
/// promotes to a live broadcast and existing Dart listeners on
/// its controller start receiving events without re-listening. [retryFrbSubscriptions] is the explicit fast-path
/// for the bootstrap chain to promote every cached topic at the
/// FRB-ready boundary, since not every Riverpod provider re-enters
/// `subscribe` after init.
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
  ///
  /// Each call retries [_SharedTopic.ensureFrbSub] so that
  /// Riverpod `Notifier.build()` invocations that fire pre-FRB-init
  /// (a widget on the first runApp frame watches the provider)
  /// don't permanently anchor a dead subscription. See the library
  /// docstring for the cold-start contract.
  Stream<rust_bus.BusEvent> subscribe(rust_bus.BusTopic topic) {
    final entry = _shared.putIfAbsent(topic, () => _SharedTopic(topic));
    entry.ensureFrbSub();
    return entry.controller.stream;
  }

  /// Promote every cached `_SharedTopic` to a live FRB subscription.
  /// Called from `_LetsFLUTsshAppState._bootstrap` immediately after
  /// `_initRustCoreOrFatal` returns — Riverpod providers
  /// (`ConnectionsNotifier`, `connectionActiveCountProvider`, …)
  /// whose `build()` ran during the first runApp frame need their
  /// dead pre-init `_SharedTopic` entries promoted before their
  /// listeners start asking "where are my events?". Callers that
  /// land AFTER bootstrap automatically pick up a ready stream
  /// through the per-call retry in [subscribe], so this method is
  /// only the fast-path for the cold-start window.
  void retryFrbSubscriptions() {
    for (final entry in _shared.values) {
      entry.ensureFrbSub();
    }
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
/// native blob loaded, or a Riverpod `Notifier.build()` that ran
/// during the first runApp frame before `_initRustCoreOrFatal`
/// completes) leave `_frbSub` as `null`; the next [ensureFrbSub]
/// call once `RustLib` is up promotes it to a real subscription,
/// and listeners that already subscribed to the broadcast stream
/// start receiving events without re-listening.
class _SharedTopic {
  _SharedTopic(this.topic);

  final rust_bus.BusTopic topic;
  final controller = StreamController<rust_bus.BusEvent>.broadcast();
  StreamSubscription<rust_bus.BusEvent>? _frbSub;

  /// Idempotent — if a previous attempt already attached the FRB
  /// stream, returns immediately. The cold-start invariant
  /// (ARCHITECTURE.md § Cold-start ordering) means
  /// every direct `subscribe` caller wires AFTER
  /// `_initRustCoreOrFatal` returns; lazy Riverpod-driven
  /// callsites that mount during the first runApp frame land on
  /// the `StateError` catch below, leave `_frbSub` null, and
  /// promote on the next `subscribe` call after init via
  /// `retryFrbSubscriptions`. No defensive
  /// `if (!RustLib.instance.initialized) return` short-circuit
  /// — that pattern is redundant against the invariant + the
  /// typed catch, and a pre-FRB read of `RustLib.instance`
  /// would itself violate the cold-start rule.
  void ensureFrbSub() {
    if (_frbSub != null) return;
    try {
      _frbSub = rust_bus
          .busSubscribe(topic: topic)
          .listen(controller.add, onError: controller.addError);
    } on StateError {
      // Pre-FRB-init callsite (Riverpod provider mounted during
      // the first runApp pass) — leave `_frbSub` null; the next
      // post-init `subscribe` / `retryFrbSubscriptions` promotes.
    }
  }
}
