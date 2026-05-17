import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Drift guard: every `letsflutssh_*` keychain slot the Dart side
/// writes to must also live in the Rust canonical
/// `lfs_core::security::wipe_keychain::MANAGED_KEYS` list, so the
/// Settings → Reset all data path actually wipes it.
///
/// Failure mode this test catches:
///
///   1. A new feature lands a `flutter_secure_storage.write(key:
///      'letsflutssh_new_thing', ...)` somewhere under `lib/`.
///   2. The author forgets to add `'letsflutssh_new_thing'` to
///      `MANAGED_KEYS` in `wipe_keychain.rs`.
///   3. Settings → Reset all data wipes every OTHER slot but
///      leaves `letsflutssh_new_thing` behind. Forensic dump
///      finds it months later when the user assumed the wipe
///      was total.
///
/// The check walks every `.dart` file under `lib/`, greps for
/// `'letsflutssh_<name>'` string literals, and asserts that the
/// set is a subset of the Rust list parsed out of
/// `wipe_keychain.rs`.
///
/// Test files are excluded — fixtures may name slots that are
/// not actually in production use. The Dart `_storage.read /
/// write / containsKey / delete` call sites are what matter.
void main() {
  test('every letsflutssh_* keychain slot used in lib/ is wiped', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue);

    // String literals like 'letsflutssh_l2_pepper' or
    // "letsflutssh_bio_db_key". Single + double quotes both
    // accepted; identifier chars after the prefix.
    final slotPattern = RegExp(r'''['"]letsflutssh_([A-Za-z0-9_]+)['"]''');

    final found = <String>{};
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      // Generated FRB code mirrors Rust constants — skip.
      if (entity.path.contains('/src/rust/')) continue;
      final text = entity.readAsStringSync();
      for (final m in slotPattern.allMatches(text)) {
        found.add('letsflutssh_${m.group(1)}');
      }
    }

    final rustListFile = File(
      'rust/crates/lfs_core/src/security/wipe_keychain.rs',
    );
    expect(
      rustListFile.existsSync(),
      isTrue,
      reason: 'wipe_keychain.rs not at expected path',
    );
    final rustText = rustListFile.readAsStringSync();
    // Match each `"letsflutssh_..."` entry inside MANAGED_KEYS.
    final managedPattern = RegExp(r'"(letsflutssh_[A-Za-z0-9_]+)"');
    final managed = managedPattern
        .allMatches(rustText)
        .map((m) => m.group(1)!)
        .toSet();

    expect(
      managed,
      isNotEmpty,
      reason: 'Failed to parse MANAGED_KEYS from wipe_keychain.rs',
    );

    final missing = found.difference(managed).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason:
          'Dart references letsflutssh_* keychain slots that are not in '
          'rust/crates/lfs_core/src/security/wipe_keychain.rs::MANAGED_KEYS. '
          'Add them so Settings → Reset all data wipes them. '
          'Missing: ${missing.join(", ")}',
    );
  });
}
