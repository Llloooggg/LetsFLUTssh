/// Phase 5 Command / Event bus — Dart-side wrapper.
///
/// Frontend dispatches typed [BusCommand]s through [AppBus.dispatch];
/// Riverpod views subscribe to per-topic event streams via
/// [AppBus.subscribe]. Both delegate to the FRB binding generated
/// from `rust/crates/lfs_frb/src/api/bus.rs`. The wrapper exists so
/// call sites depend on a stable Dart-side abstraction rather than
/// the regenerated FRB symbols directly — making it cheap to swap
/// the transport (mock for tests, future Tauri channel) without
/// touching every consumer.
library;

import 'dart:async';

import '../../src/rust/api/bus.dart' as rust_bus;

export '../../src/rust/api/bus.dart' show BusCommand, BusEvent, BusTopic;

/// Single instance — the Rust side is process-singleton, so a
/// matching Dart-side singleton keeps the abstraction symmetric.
class AppBus {
  AppBus._();
  static final AppBus instance = AppBus._();

  /// Dispatch a typed command. Returns when the Rust side has
  /// processed it; events emitted as a side effect arrive on the
  /// matching [subscribe] streams.
  Future<void> dispatch(rust_bus.BusCommand command) =>
      rust_bus.busDispatch(command: command);

  /// Subscribe to events on [topic]. The returned stream cancels
  /// the Rust-side subscription when the listener cancels (FRB
  /// `StreamSink.add` returns Err, the Rust loop exits, the
  /// broadcast receiver drops). No explicit close needed.
  Stream<rust_bus.BusEvent> subscribe(rust_bus.BusTopic topic) =>
      rust_bus.busSubscribe(topic: topic);
}
