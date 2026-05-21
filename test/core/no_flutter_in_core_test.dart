/// Architecture fitness function: `lib/core/` is the domain + I/O layer
/// and must stay free of Flutter UI, platform plugins, Riverpod, l10n,
/// and the xterm terminal package. The ONLY framework dependency allowed
/// is `flutter_rust_bridge` (the Rust bridge runtime that core wraps);
/// everything else in core is pure Dart (`meta`, `uuid`, `path`, …).
///
/// UI state lives in `providers/`, plugin adapters in `platform/`,
/// rendering in `widgets/` / `features/`. See CLAUDE.md → "Rust owns
/// data AND logic; Flutter renders" and ARCHITECTURE.md §1 layering.
///
/// A new `package:flutter` / plugin import inside `core/` fails this
/// test — fix it by injecting the dependency from the boundary
/// (`platform/` / `providers/` / `app/`) rather than reaching for it in
/// the domain layer.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'lib/core imports no Flutter UI / plugins / Riverpod / l10n / xterm',
    () {
      // Each entry is matched as a substring against `import` / `export`
      // lines. `package:flutter/` covers material / widgets / services /
      // foundation in one shot; flutter_rust_bridge is deliberately NOT
      // listed (the Rust bridge is the one permitted framework edge).
      const forbidden = <String>[
        'package:flutter/',
        'package:flutter_riverpod/',
        'package:path_provider/',
        'package:app_links/',
        'package:flutter_foreground_task/',
        'package:xterm/',
        'l10n/app_localizations.dart',
      ];

      final coreDir = Directory('lib/core');
      expect(
        coreDir.existsSync(),
        isTrue,
        reason: 'run from the repo root so lib/core resolves',
      );

      final offenders = <String>[];
      for (final entity in coreDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trimLeft();
          if (!line.startsWith('import ') && !line.startsWith('export ')) {
            continue;
          }
          for (final bad in forbidden) {
            if (line.contains(bad)) {
              offenders.add('${entity.path}:${i + 1}  ${lines[i].trim()}');
            }
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'core/ must stay Flutter-free (only flutter_rust_bridge + pure '
            'Dart). Move the dependency to platform/ / providers/ / app/ and '
            'inject it. Offenders:\n${offenders.join('\n')}',
      );
    },
  );
}
