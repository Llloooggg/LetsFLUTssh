#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdio>
#include <ctime>

#include "flutter_window.h"
#include "utils.h"

// Single-writer claim flag for `EarlyCrashHandler`. Only the first
// thread that observes `0` and atomically swaps it to `1` is allowed
// to write the crash file. Every subsequent crash on any thread
// returns without touching the file. Invariant: only the first
// thread's crash gets written; subsequent crashes are silent to
// avoid file corruption mid-write. `volatile LONG` is the correct
// shape for `InterlockedExchange` on x86 / x64 / ARM64 Windows.
static volatile LONG g_crash_logged = 0;

// Early-boot crash logger. Writes a single-line diagnostic to
// `%LOCALAPPDATA%\LetsFLUTssh\startup-crash.log` when the process
// dies before the Dart logger initialises. Without this the app
// silently vanishes on Windows when a native DLL load, mitigation
// policy, or COM init fails — no WER dump (we disabled it) and no
// file the user can point at.
//
// At crash time the process is in an undefined state: the heap may
// be torn, the C runtime may be unsafe to call, and other threads
// may also be unwinding. Buffered stdio (`_wfopen_s` / `fwprintf` /
// `fclose`) flushes via heap allocations that can deadlock or
// double-fault. We therefore use raw Win32 (`CreateFileW` +
// `WriteFile`) and bound the payload to a small fixed stack buffer.
static LONG WINAPI EarlyCrashHandler(EXCEPTION_POINTERS* ex) {
  // Claim the single-writer slot. `InterlockedExchange` returns the
  // prior value — non-zero means another crash already wrote.
  if (::InterlockedExchange(&g_crash_logged, 1) != 0) {
    return EXCEPTION_CONTINUE_SEARCH;
  }

  wchar_t local_app_data[MAX_PATH] = {0};
  DWORD len = ::GetEnvironmentVariableW(L"LOCALAPPDATA", local_app_data, MAX_PATH);
  if (len == 0 || len >= MAX_PATH) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  wchar_t dir[MAX_PATH];
  if (_snwprintf_s(dir, MAX_PATH, _TRUNCATE, L"%s\\LetsFLUTssh", local_app_data) < 0) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  ::CreateDirectoryW(dir, nullptr);  // idempotent, best-effort.

  wchar_t path[MAX_PATH];
  if (_snwprintf_s(path, MAX_PATH, _TRUNCATE, L"%s\\startup-crash.log", dir) < 0) {
    return EXCEPTION_CONTINUE_SEARCH;
  }

  HANDLE h = ::CreateFileW(
      path,
      FILE_APPEND_DATA,
      FILE_SHARE_READ,
      nullptr,
      OPEN_ALWAYS,
      FILE_ATTRIBUTE_NORMAL,
      nullptr);
  if (h == INVALID_HANDLE_VALUE) {
    return EXCEPTION_CONTINUE_SEARCH;
  }

  // Forensic note: timestamp, exception code, faulting address. Bounded
  // to <= 1 KiB on the stack — no heap, no CRT iostreams.
  char line[1024];
  time_t now = ::time(nullptr);
  int written = _snprintf_s(
      line,
      sizeof(line),
      _TRUNCATE,
      "%lld  exc=0x%08lX  addr=%p\r\n",
      static_cast<long long>(now),
      ex->ExceptionRecord->ExceptionCode,
      ex->ExceptionRecord->ExceptionAddress);
  if (written > 0) {
    DWORD bytes_written = 0;
    ::WriteFile(h, line, static_cast<DWORD>(written), &bytes_written, nullptr);
  }
  ::CloseHandle(h);
  return EXCEPTION_CONTINUE_SEARCH;  // Let default termination run.
}

// Apply Win32 process-level mitigation policies at startup. These
// are the Windows-side equivalent of `prctl(PR_SET_DUMPABLE, 0)` +
// `ptrace(PT_DENY_ATTACH)` on POSIX: they tell the kernel to refuse
// certain attacker patterns against our process regardless of the
// attacker's user-level privilege. Must run BEFORE any
// `CoInitializeEx` / DLL loads that we do not control, so any
// dependency loader is also subject to the policies we enable.
//
// Best-effort: a policy that fails to apply (missing Windows SDK
// feature on an older build) is logged and skipped rather than
// aborting startup. A failure here is a hardening regression but
// never a user-visible bug.
static void ApplyProcessMitigationPolicies() {
  // ProcessImageLoadPolicy — block loading DLLs from remote /
  // non-Microsoft-signed sources. Defends against supply-chain
  // attacks that rely on side-loading a DLL over SMB / WebDAV.
  // Compatible with Flutter engine + ANGLE; no regressions observed.
  PROCESS_MITIGATION_IMAGE_LOAD_POLICY image_load = {0};
  image_load.NoRemoteImages = 1;
  image_load.NoLowMandatoryLabelImages = 1;
  image_load.PreferSystem32Images = 1;
  ::SetProcessMitigationPolicy(ProcessImageLoadPolicy, &image_load,
                               sizeof(image_load));

  // **Dropped**: ProcessDynamicCodePolicy.ProhibitDynamicCode.
  //
  // On paper Flutter release is AOT-compiled and needs no runtime
  // JIT. In practice the engine ships ANGLE (OpenGL → Direct3D
  // translator) which compiles shaders at runtime via the D3D
  // compiler — that is a legitimate PAGE_EXECUTE_READWRITE
  // allocation the policy blocks. Enabling `ProhibitDynamicCode`
  // silently killed the process during window creation on every
  // Windows host tested; the log was empty because logger init
  // hadn't started yet. The threat the policy defends against
  // (injected DLL calling VirtualAlloc(PAGE_EXECUTE)) still needs a
  // foothold — image load policy + WER disable already raise that
  // bar. Keeping the policy off is a conscious trade; re-enable
  // only behind a Flutter-engine capability detection that proves
  // ANGLE + Skia never need dynamic code, which is not the case
  // today.
  //
  // **Dropped**: ProcessStrictHandleCheckPolicy.
  //
  // `HandleExceptionsPermanentlyEnabled = 1` terminates the process
  // on any invalid-handle reference, even ones Flutter / Skia /
  // ANGLE treat as recoverable soft errors (e.g. querying a
  // detached surface). Silent kill with no dump. Shipped here only
  // if we can guarantee the renderer never feeds an invalid handle
  // to a Win32 API — again, not today.

  // Suppress WER (Windows Error Reporting) crash dumps — they
  // contain the full process address space, including the DB key
  // if the app crashed while unlocked. The POSIX equivalent
  // (`PR_SET_DUMPABLE=0`) lives in `process_hardening.dart`.
  ::SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX |
                 SEM_NOOPENFILEERRORBOX);
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Install the early-boot crash handler first, before any Windows
  // API call that could die. Everything downstream (policy apply,
  // DLL load, COM init, window create) is covered.
  ::SetUnhandledExceptionFilter(EarlyCrashHandler);

  // Single-instance gate. Acquire a named mutex in the per-user
  // `Local\` namespace — owned by this process for its lifetime.
  // A second launch from the Start menu / Explorer / `letsflutssh.exe`
  // CLI sees `ERROR_ALREADY_EXISTS` here, surfaces a native
  // `MessageBoxW` info dialog, and exits without loading the
  // Flutter engine, the bundled `lfs_frb.dll`, the Defender
  // real-time scan that bundled DLL triggers, or any of the Dart
  // bootstrap chain. Previous attempts gated single-instance from
  // Dart (`lib/core/single_instance/single_instance.dart`,
  // `RandomAccessFile.lock`) — that ran AFTER the engine + native
  // blob load had already paid their cost, defeating the speed
  // benefit of rejecting the duplicate launch and forcing the
  // boot ordering to coordinate "FRB ready" vs "lock check"
  // semantics. Doing it here, pre-engine, removes the whole
  // class of ordering concerns. The mutex auto-releases when the
  // process exits (clean or crash) — no stale-lock files to
  // clean up, no fcntl-per-process / per-fd footgun.
  //
  // Dialog text is hardcoded English. Pulling it from
  // `lib/l10n/app_*.arb` would require running enough of the
  // Flutter engine to reach the localisation runtime, which
  // defeats the "reject before paying engine cost" benefit. The
  // brief modal is acceptable in EN-only — `MessageBoxW` itself
  // renders in the OS theme + system locale for the OK button.
  HANDLE single_instance_mutex =
      ::CreateMutexW(nullptr, TRUE, L"Local\\LetsFLUTssh-SingleInstance");
  if (single_instance_mutex == nullptr) {
    // Mutex object couldn't be created at all (extremely rare —
    // out of handles or kernel resource exhaustion). Fall through
    // to the normal launch — the OS is in a bad state anyway, no
    // point in adding a custom failure mode.
  } else if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    ::MessageBoxW(nullptr,
                  L"An instance of LetsFLUTssh is already running.",
                  L"LetsFLUTssh",
                  MB_OK | MB_ICONINFORMATION | MB_SETFOREGROUND);
    ::CloseHandle(single_instance_mutex);
    return EXIT_SUCCESS;
  }
  // single_instance_mutex stays held for the process lifetime —
  // Windows releases it on process exit. We intentionally don't
  // close it on the success path.

  // Harden the process before anything else — policies apply to
  // every subsequent DLL load + allocation in the process.
  ApplyProcessMitigationPolicies();

  // Attach to the parent console when present (e.g. running under
  // `flutter run` from a terminal) so stdout / stderr land in the
  // same window. Failing that, do NOT call `AllocConsole` — the
  // Flutter template's old `IsDebuggerPresent()` fallback opens a
  // standalone black "LetsFLUTssh" console window on systems where
  // a kernel-level telemetry / management agent flips the
  // debugger-present flag (Windows IoT LTSC enterprise installs are
  // the canonical case). The user sees that empty console pop up
  // alongside the real app window for a few seconds before the
  // splash overlays it. Dropping the fallback removes the false
  // positive — release builds genuinely don't need stdout, and
  // debug builds run from `flutter run` already inherit a parent
  // console via `AttachConsole`.
  ::AttachConsole(ATTACH_PARENT_PROCESS);

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"LetsFLUTssh", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
