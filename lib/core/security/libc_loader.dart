import 'dart:ffi';
import 'dart:io' show Platform;

/// Open the process-wide libc on Linux **or** Android.
///
/// Glibc ships `libc.so.6` (the `.6` is the ABI-version suffix); desktop
/// Bionic / musl / alpine often ship `libc.so` with no version suffix.
/// Android bionic is slightly different: from API 24+ (Nougat) the
/// linker refuses `dlopen("libc.so")` from the app namespace — libc is
/// a "public" library that the linker considers already resolved into
/// the process, and asking for it through dlopen is blocked with a
/// "library not found" error. [`DynamicLibrary.process()`] returns a
/// handle to the current process's resolved symbols, which always
/// contains libc's exports (`mlock`, `prctl`, `setrlimit`, etc.) —
/// the same trick iOS / macOS already use.
///
/// Throws [ArgumentError] when neither path resolves (static-linked
/// libc on an exotic musl image). Callers must handle the throw as
/// "libc unavailable" and degrade gracefully.
DynamicLibrary openLibc() {
  if (Platform.isAndroid) {
    // Bionic symbols are in the process global scope; don't dlopen.
    return DynamicLibrary.process();
  }
  try {
    return DynamicLibrary.open('libc.so.6');
  } catch (_) {
    return DynamicLibrary.open('libc.so');
  }
}
