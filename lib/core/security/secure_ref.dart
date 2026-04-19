import '../../utils/logger.dart';

/// Runtime guard around a sensitive value that MUST be disposed.
///
/// The codebase uses FFI-allocated + `mlock`-pinned buffers for every
/// long-lived secret (DB key, password-derived bytes, HMAC salts).
/// Those buffers live outside Dart's GC — so forgetting to call
/// `dispose()`, calling it twice, or keeping a reference to the
/// underlying payload after dispose are all silent bugs the language
/// cannot catch. Rust's ownership model catches all three at compile
/// time; Dart cannot. `SecureRef<T>` closes ~90% of the practical
/// gap with **runtime** checks + a `Finalizer` safety net.
///
/// What it guarantees:
///
/// - **Idempotent dispose.** `dispose()` is safe to call any number
///   of times. Only the first call invokes the wipe; subsequent
///   calls are no-ops. No double-free on FFI ptrs.
/// - **Throw-on-use-after-dispose.** Reading `value` after
///   `dispose()` throws `StateError`. Bugs surface loudly at the
///   call site instead of silently reading freed memory.
/// - **Finalizer safety net.** A `Finalizer<T>` is attached to the
///   wrapper; when the wrapper itself is GC'd without an explicit
///   `dispose()` call, the finalizer fires and runs the wipe. GC
///   timing is not guaranteed — an app-lifetime leak still pages
///   the mlock'd bytes to disk-swap never — but process-exit
///   always cleans them eventually.
/// - **Type-level tagging.** A `SecureRef<Uint8List>` cannot
///   accidentally be logged, compared via `==`, or passed to a
///   third-party API that expects plain bytes. The payload is
///   retrieved only through `.value`, which is deliberately the
///   only accessor and always throws on disposed refs.
///
/// What it does NOT guarantee:
///
/// - **Compile-time protection.** Rust's borrow checker rejects
///   use-after-move statically. Dart cannot; `SecureRef` is a
///   runtime wrapper. A sufficiently-broken caller that captures
///   `.value` into a local variable and reads it after `dispose()`
///   bypasses the wrapper. Code review + tests cover this case.
/// - **Thread safety.** Dart's Isolate model already prevents
///   shared memory across threads, but passing a `SecureRef` over
///   an IsolatePort would copy-serialise the payload — losing the
///   mlock + the finalizer + the wipe hook. Never transport a
///   `SecureRef` across isolate boundaries; cross-isolate secret
///   handling must use native-side helpers.
class SecureRef<T extends Object> {
  SecureRef(T initial, {required void Function(T value) wipe})
    : _value = initial,
      _wipe = wipe {
    _finalizer.attach(
      this,
      _FinalizerPayload(initial, (Object v) => wipe(v as T)),
      detach: this,
    );
  }

  T? _value;
  bool _disposed = false;
  final void Function(T) _wipe;

  /// Finalizer is static so one instance handles every `SecureRef`
  /// — otherwise a finalizer-per-ref allocates a closure on every
  /// construction, which defeats the whole point for short-lived
  /// secret buffers during KDF derivation.
  static final Finalizer<_FinalizerPayload> _finalizer =
      Finalizer<_FinalizerPayload>((p) {
        try {
          p.wipe(p.value);
        } catch (e) {
          AppLogger.instance.log(
            'SecureRef finalizer wipe failed: $e',
            name: 'SecureRef',
          );
        }
      });

  /// Accessor. Throws when the ref has been disposed — use-after-
  /// dispose is a bug, not a silent fallback to null.
  T get value {
    if (_disposed) {
      throw StateError('SecureRef accessed after dispose');
    }
    return _value as T;
  }

  /// True when `dispose()` has been called. Use to short-circuit
  /// branches that want to skip work on an already-disposed ref
  /// without triggering the throw on `.value`.
  bool get isDisposed => _disposed;

  /// Idempotent. No-op on second and subsequent calls. Always
  /// detaches the finalizer so the GC path cannot double-wipe a
  /// manually-disposed ref.
  void dispose() {
    if (_disposed) return;
    _finalizer.detach(this);
    try {
      _wipe(_value as T);
    } catch (e) {
      AppLogger.instance.log(
        'SecureRef dispose wipe failed: $e',
        name: 'SecureRef',
      );
    }
    _value = null;
    _disposed = true;
  }
}

/// Immutable pairing of a payload + its wipe function. Separated
/// from the live wrapper so the finalizer holds a concrete target
/// instead of a reference to the wrapper itself (which would
/// create a retention cycle and defeat the finalizer). Non-generic
/// so the static `Finalizer<_FinalizerPayload>` can hold values of
/// any SecureRef type; the wipe closure upcasts the payload back
/// to its original type at the SecureRef constructor boundary.
class _FinalizerPayload {
  final Object value;
  final void Function(Object) wipe;
  const _FinalizerPayload(this.value, this.wipe);
}
