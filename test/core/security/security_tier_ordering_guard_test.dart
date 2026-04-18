import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase-H acceptance guard: `SecurityTier` is deliberately unordered.
/// The language prevents `<` / `>` on enums outright, but `.index` is
/// still addressable and a well-meaning future refactor could
/// reintroduce ordinal comparisons ("upgrade only if new.index >
/// current.index") — which would be a bug against the tier model
/// that deliberately keeps Paranoid off the numbered ladder.
///
/// This test walks every Dart file under `lib/` and fails if it
/// finds a pattern that reads `SecurityTier.<member>.index` or a
/// binary `<`/`>`/`<=`/`>=` that has `SecurityTier` on either side.
void main() {
  test('no ordinal access on SecurityTier values under lib/', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue);

    final indexPattern = RegExp(r'SecurityTier\.[a-zA-Z]+\.index\b');
    // Accept `SecurityTier.foo == SecurityTier.bar` and `!=`,
    // reject ordinal comparisons on either side.
    final ordinalPattern = RegExp(
      r'SecurityTier\.[a-zA-Z]+\s*(<=|>=|<|>)'
      r'|'
      r'(<=|>=|<|>)\s*SecurityTier\.[a-zA-Z]+',
    );

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      if (indexPattern.hasMatch(text)) {
        offenders.add('${entity.path}: uses `.index` on a SecurityTier value');
      }
      if (ordinalPattern.hasMatch(text)) {
        offenders.add('${entity.path}: ordinal comparison on SecurityTier');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'SecurityTier is unordered by design (Paranoid is an '
          'alternative branch, not a rank). Use predicates — '
          'isParanoid / usesKeychain / usesHardwareVault / '
          'hasUserSecret — instead. Offenders:\n${offenders.join("\n")}',
    );
  });
}
