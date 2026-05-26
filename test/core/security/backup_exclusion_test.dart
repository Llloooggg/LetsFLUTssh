import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/backup_exclusion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('invokes the exclude impl on Apple platforms', () async {
    // The directory the exclusion targets is the one pinned Rust-side
    // at config_store_init; this test verifies only the Apple-gate
    // dispatch (the path resolution + native call live in Rust).
    var called = false;
    await BackupExclusion(
      isApplePlatform: true,
      excludeImpl: () => called = true,
    ).applyOnStartup();
    expect(called, isTrue);
  });

  test('is a no-op off Apple platforms', () async {
    var called = false;
    await BackupExclusion(
      isApplePlatform: false,
      excludeImpl: () => called = true,
    ).applyOnStartup();
    expect(called, isFalse);
  });

  test('swallows native errors', () async {
    // The startup path must never crash on a backup-exclusion failure
    // — the user gets a usable app even when the OS rejected the call.
    await BackupExclusion(
      isApplePlatform: true,
      excludeImpl: () => throw StateError('exclude failed'),
    ).applyOnStartup();
  });
}
