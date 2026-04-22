import 'dart:ffi';

/// Open the process-wide libc on Linux **or** Android.
///
/// Glibc ships `libc.so.6` (the `.6` is the ABI-version suffix); Bionic
/// on Android ships `libc.so` with no version suffix. Trying `libc.so.6`
/// first and falling back to `libc.so` keeps the release binary portable
/// across both without a compile-time `Platform` check — `Platform.isAndroid`
/// would miss ChromeOS / WSL-ish edge cases where the reverse is true, and
/// the dlopen cost of the miss is negligible.
///
/// Throws [ArgumentError] when neither name resolves (static-linked libc,
/// exotic musl image). Callers must handle the throw as "libc unavailable"
/// and degrade gracefully.
DynamicLibrary openLibc() {
  try {
    return DynamicLibrary.open('libc.so.6');
  } catch (_) {
    return DynamicLibrary.open('libc.so');
  }
}
