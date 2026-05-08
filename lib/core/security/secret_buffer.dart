import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../src/rust/api/os_security.dart' as rust_os;
import '../../utils/logger.dart';

/// Heap-allocated, page-locked buffer for cryptographic secrets.
///
/// Wraps a small chunk of native memory (allocated via [calloc]) plus
/// a best-effort `mlock` / `VirtualLock` call routed through
/// `lfs_os_security` so the OS cannot page the bytes out to swap or
/// hibernation. Dart `Uint8List` lives on the managed heap: the GC
/// can relocate it, and we have no hook to pin it. Secrets (DB key,
/// master-password-derived KEK, PBKDF2 intermediate) therefore go
/// through this class instead of a plain `Uint8List`.
///
/// Lifecycle:
///   1. `SecretBuffer.allocate(32)` → zero-filled native buffer, locked.
///   2. `buf.bytes` (Uint8List view) → mutate in place; no copy.
///   3. `buf.dispose()` → overwrite with zeros, unlock, `free`.
///
/// `mlock` may return non-zero when `RLIMIT_MEMLOCK` is exhausted
/// (e.g. a bare-bones Linux box with the default 64 KB cap and other
/// processes already holding locks). The class logs and continues —
/// the buffer still exists, it just isn't pinned. Failing hard would
/// turn a hardening nicety into a liveness bug.
///
/// **Finalizer safety-net**. A [NativeFinalizer] is attached on every
/// allocation so that, if a caller forgets to call [dispose], the
/// native memory is still `free`d when the Dart object is GC'd. The
/// finalizer does NOT zero the bytes (it cannot run Dart code) and
/// does NOT `munlock` the page — so the leaked window between the
/// last reference drop and GC still holds plaintext in RAM,
/// potentially in a locked page. Call `dispose` explicitly: the
/// finalizer is a backstop against leak-on-exception, not a
/// replacement for deterministic cleanup.
class SecretBuffer implements Finalizable {
  final Pointer<Uint8> _ptr;
  final int _length;
  bool _disposed = false;
  final bool _locked;

  SecretBuffer._(this._ptr, this._length, this._locked);

  /// Auto-cleanup hook. If the `SecretBuffer` is GC'd without an
  /// explicit `dispose()`, the calloc allocator's native `free` runs
  /// against the pointer — plugging the memory leak at the cost of
  /// skipping the zeroing + munlock steps `dispose()` would have
  /// performed. [dispose] detaches this finalizer so the
  /// deterministic path is not followed by a double-free from the
  /// allocator.
  static final _finalizer = NativeFinalizer(calloc.nativeFree);

  /// Allocate a zero-filled buffer of [length] bytes and attempt to
  /// lock it into RAM. Returns a managed [SecretBuffer]; call
  /// [dispose] when done.
  factory SecretBuffer.allocate(int length) {
    if (length <= 0) {
      throw ArgumentError.value(length, 'length', 'must be positive');
    }
    final ptr = calloc<Uint8>(length);
    final locked = _lock(ptr.address, length);
    final buf = SecretBuffer._(ptr, length, locked);
    _finalizer.attach(buf, ptr.cast(), detach: buf, externalSize: length);
    return buf;
  }

  /// Copy bytes from [source] into a fresh locked buffer. The source
  /// is *not* zeroed — the caller is responsible for its own hygiene
  /// (e.g. overwriting the original Dart `Uint8List` produced by
  /// PBKDF2 before dropping it).
  factory SecretBuffer.fromBytes(List<int> source) {
    final buf = SecretBuffer.allocate(source.length);
    buf.bytes.setAll(0, source);
    return buf;
  }

  /// Length in bytes.
  int get length => _length;

  /// Whether the OS accepted the page-lock request. Informational;
  /// the buffer works either way.
  bool get isLocked => _locked;

  /// Mutable view aliasing the native memory — no copy. The returned
  /// `Uint8List` is only valid until [dispose]; using it afterwards
  /// is use-after-free (Dart will dereference a freed pointer and
  /// likely segfault rather than returning stale data, but don't do
  /// it).
  Uint8List get bytes {
    _assertAlive();
    return _ptr.asTypedList(_length);
  }

  /// Overwrite with zeros, unlock, and free. Idempotent — calling
  /// twice is a no-op on the second call, so tests and error-path
  /// cleanups don't need guards.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Zero before unlock so a surviving copy in swap (if lock wasn't
    // granted) doesn't keep the plaintext.
    for (var i = 0; i < _length; i++) {
      _ptr[i] = 0;
    }
    if (_locked) {
      _unlock(_ptr.address, _length);
    }
    // Detach the finalizer BEFORE we free the pointer ourselves —
    // otherwise a post-`dispose` GC would fire the native-free hook
    // on an already-freed pointer, which is a use-after-free on the
    // allocator and can corrupt unrelated native memory.
    _finalizer.detach(this);
    calloc.free(_ptr);
  }

  void _assertAlive() {
    if (_disposed) {
      throw StateError('SecretBuffer used after dispose()');
    }
  }

  /// Page-lock via `lfs_os_security::lock_memory` (POSIX `mlock` on
  /// non-Windows, Win32 `VirtualLock` on Windows). Returns `true`
  /// when the OS accepted the request; logs + returns `false` on
  /// any failure so the buffer stays usable but unpinned.
  static bool _lock(int addr, int len) {
    try {
      final ok = rust_os.osSecurityLockMemory(
        addr: BigInt.from(addr),
        len: BigInt.from(len),
      );
      if (!ok) {
        // Promoted from Info to Warn: a declined memory lock means
        // the secret buffer is paging-eligible, which is a real
        // security degrade the user should be able to see in
        // support traces without lowering the global log threshold.
        AppLogger.instance.log(
          'Memory lock declined — secret buffer not pinned',
          name: 'SecretBuffer',
          level: LogLevel.warn,
        );
      }
      return ok;
    } catch (e) {
      AppLogger.instance.log(
        'Memory lock unavailable: $e',
        level: LogLevel.warn,
        name: 'SecretBuffer',
      );
      return false;
    }
  }

  static void _unlock(int addr, int len) {
    try {
      rust_os.osSecurityUnlockMemory(
        addr: BigInt.from(addr),
        len: BigInt.from(len),
      );
    } catch (_) {
      // Best-effort cleanup; teardown path doesn't care.
    }
  }
}
