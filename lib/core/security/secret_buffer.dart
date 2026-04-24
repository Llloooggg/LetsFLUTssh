import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../utils/logger.dart';
import 'libc_loader.dart';

/// Heap-allocated, page-locked buffer for cryptographic secrets.
///
/// Wraps a small chunk of native memory (allocated via [calloc]) plus a
/// best-effort `mlock`/`VirtualLock` call so the OS cannot page the bytes
/// out to swap or hibernation. Dart `Uint8List` lives on the managed heap:
/// the GC can relocate it, and we have no hook to pin it. Secrets (DB key,
/// master-password-derived KEK, PBKDF2 intermediate) therefore go through
/// this class instead of a plain `Uint8List`.
///
/// Lifecycle:
///   1. `SecretBuffer.allocate(32)` → zero-filled native buffer, locked.
///   2. `buf.bytes` (Uint8List view) → mutate in place; no copy.
///   3. `buf.dispose()` → overwrite with zeros, unlock, `free`.
///
/// `mlock` may return EPERM when `RLIMIT_MEMLOCK` is exhausted (e.g. a
/// bare-bones Linux box with the default 64 KB cap and other processes
/// already holding locks). The class logs and continues — the buffer still
/// exists, it just isn't pinned. Failing hard would turn a hardening nicety
/// into a liveness bug.
///
/// **Finalizer safety-net**. A [NativeFinalizer] is attached on every
/// allocation so that, if a caller forgets to call [dispose], the native
/// memory is still `free`d when the Dart object is GC'd. The finalizer
/// does NOT zero the bytes (it cannot run Dart code) and does NOT
/// `munlock` the page — so the leaked window between the last reference
/// drop and GC still holds plaintext in RAM, potentially in a locked
/// page. Call `dispose` explicitly: the finalizer is a backstop against
/// leak-on-exception, not a replacement for deterministic cleanup.
class SecretBuffer implements Finalizable {
  final Pointer<Uint8> _ptr;
  final int _length;
  bool _disposed = false;
  final bool _locked;

  SecretBuffer._(this._ptr, this._length, this._locked);

  /// Auto-cleanup hook. If the `SecretBuffer` is GC'd without an explicit
  /// `dispose()`, the calloc allocator's native `free` runs against the
  /// pointer — plugging the memory leak at the cost of skipping the zeroing
  /// + munlock steps `dispose()` would have performed. [dispose] detaches
  /// this finalizer so the deterministic path is not followed by a
  /// double-free from the allocator.
  static final _finalizer = NativeFinalizer(calloc.nativeFree);

  /// Allocate a zero-filled buffer of [length] bytes and attempt to lock it
  /// into RAM. Returns a managed [SecretBuffer]; call [dispose] when done.
  factory SecretBuffer.allocate(int length) {
    if (length <= 0) {
      throw ArgumentError.value(length, 'length', 'must be positive');
    }
    final ptr = calloc<Uint8>(length);
    final locked = _lock(ptr, length);
    final buf = SecretBuffer._(ptr, length, locked);
    _finalizer.attach(buf, ptr.cast(), detach: buf, externalSize: length);
    return buf;
  }

  /// Copy bytes from [source] into a fresh locked buffer. The source is
  /// *not* zeroed — the caller is responsible for its own hygiene (e.g.
  /// overwriting the original Dart `Uint8List` produced by PBKDF2 before
  /// dropping it).
  factory SecretBuffer.fromBytes(List<int> source) {
    final buf = SecretBuffer.allocate(source.length);
    buf.bytes.setAll(0, source);
    return buf;
  }

  /// Length in bytes.
  int get length => _length;

  /// Whether the OS accepted the page-lock request. Informational; the
  /// buffer works either way.
  bool get isLocked => _locked;

  /// Mutable view aliasing the native memory — no copy. The returned
  /// `Uint8List` is only valid until [dispose]; using it afterwards is
  /// use-after-free (Dart will dereference a freed pointer and likely
  /// segfault rather than returning stale data, but don't do it).
  Uint8List get bytes {
    _assertAlive();
    return _ptr.asTypedList(_length);
  }

  /// Overwrite with zeros, unlock, and free. Idempotent — calling twice is a
  /// no-op on the second call, so tests and error-path cleanups don't need
  /// guards.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Zero before unlock so a surviving copy in swap (if lock wasn't granted)
    // doesn't keep the plaintext.
    for (var i = 0; i < _length; i++) {
      _ptr[i] = 0;
    }
    if (_locked) {
      _unlock(_ptr, _length);
    }
    // Detach the finalizer BEFORE we free the pointer ourselves — otherwise
    // a post-`dispose` GC would fire the native-free hook on an already-freed
    // pointer, which is a use-after-free on the allocator and can corrupt
    // unrelated native memory.
    _finalizer.detach(this);
    calloc.free(_ptr);
  }

  void _assertAlive() {
    if (_disposed) {
      throw StateError('SecretBuffer used after dispose()');
    }
  }

  // ── Platform bindings ────────────────────────────────────────────────
  //
  // Resolved lazily and cached. A failure to resolve the symbol (static
  // build, Android bionic quirk, exotic musl image) is cached as an
  // unavailable-bindings sentinel so the dlopen + exception cost is paid
  // at most once per process — subsequent allocations hit the cache and
  // skip the native call. The buffer still works, it just isn't pinned.

  static _NativeBindings? _cachedBindings;

  static _NativeBindings _bindings() {
    final cached = _cachedBindings;
    if (cached != null) return cached;
    final fresh = _resolveBindings();
    _cachedBindings = fresh;
    return fresh;
  }

  static bool _lock(Pointer<Uint8> ptr, int len) {
    final b = _bindings();
    if (!b.available) return false;
    final rc = b.lock(ptr.cast(), len);
    if (rc == 0) return true;
    AppLogger.instance.log(
      'Memory lock returned non-zero ($rc) — secret buffer not pinned',
      name: 'SecretBuffer',
    );
    return false;
  }

  static void _unlock(Pointer<Uint8> ptr, int len) {
    final b = _bindings();
    if (!b.available) return;
    b.unlock(ptr.cast(), len);
  }

  static _NativeBindings _resolveBindings() {
    try {
      if (Platform.isWindows) {
        final kernel = DynamicLibrary.open('kernel32.dll');
        final lock = kernel
            .lookup<NativeFunction<_WinLockC>>('VirtualLock')
            .asFunction<_WinLockDart>();
        final unlock = kernel
            .lookup<NativeFunction<_WinLockC>>('VirtualUnlock')
            .asFunction<_WinLockDart>();
        // VirtualLock returns non-zero on success; adapt to POSIX 0-is-success.
        return _NativeBindings(
          lock: (addr, len) => lock(addr, len) != 0 ? 0 : 1,
          unlock: (addr, len) {
            unlock(addr, len);
            return 0;
          },
        );
      }
      final libc = Platform.isMacOS || Platform.isIOS
          ? DynamicLibrary.process()
          : openLibc();
      final lock = libc
          .lookup<NativeFunction<_PosixLockC>>('mlock')
          .asFunction<_PosixLockDart>();
      final unlock = libc
          .lookup<NativeFunction<_PosixLockC>>('munlock')
          .asFunction<_PosixLockDart>();
      return _NativeBindings(lock: lock, unlock: unlock);
    } catch (e) {
      AppLogger.instance.log(
        'Memory lock unavailable: $e',
        level: LogLevel.warn,
        name: 'SecretBuffer',
      );
      return _NativeBindings.unavailable();
    }
  }
}

typedef _PosixLockC = Int32 Function(Pointer<Void>, IntPtr);
typedef _PosixLockDart = int Function(Pointer<Void>, int);
typedef _WinLockC = Int32 Function(Pointer<Void>, IntPtr);
typedef _WinLockDart = int Function(Pointer<Void>, int);

class _NativeBindings {
  final int Function(Pointer<Void>, int) lock;
  final int Function(Pointer<Void>, int) unlock;
  final bool available;
  const _NativeBindings({required this.lock, required this.unlock})
    : available = true;
  const _NativeBindings._unavailable()
    : lock = _unavailableStub,
      unlock = _unavailableStub,
      available = false;
  factory _NativeBindings.unavailable() => const _NativeBindings._unavailable();

  static int _unavailableStub(Pointer<Void> _, int _) => -1;
}
