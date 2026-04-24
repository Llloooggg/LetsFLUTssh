// Strip generated + localisation files from `coverage/lcov.info`
// in place.
//
// `flutter test --coverage` writes `coverage/lcov.info` listing every
// `lib/` file it saw. Drift `*.g.dart` and the 15
// `l10n/app_localizations_*.dart` files together add ~15 K lines that
// no unit test can reasonably cover — keeping them inflates the
// denominator and masks real gaps.
//
// Exclude patterns below must match `sonar-project.properties` →
// `sonar.coverage.exclusions` so the local `make test` coverage
// number and the SonarCloud dashboard agree.
//
// Dart-native so the only host dependency is the Flutter toolchain
// that is already required to build the app — no `lcov` binary,
// no Python.
//
// Usage:
//
//     dart run scripts/filter_lcov.dart coverage/lcov.info

import 'dart:io';

/// Mirror of `sonar.coverage.exclusions`. Keep synchronised.
const _excludeSuffixes = <String>['.g.dart', '.freezed.dart'];
const _excludePrefixes = <String>['lib/l10n/'];

bool _shouldExclude(String path) {
  for (final suffix in _excludeSuffixes) {
    if (path.endsWith(suffix)) return true;
  }
  for (final prefix in _excludePrefixes) {
    if (path.startsWith(prefix)) return true;
  }
  return false;
}

Future<int> main(List<String> argv) async {
  if (argv.length != 1) {
    stderr.writeln(
      'usage: dart run scripts/filter_lcov.dart <path-to-lcov.info>',
    );
    return 2;
  }
  final file = File(argv.single);
  if (!await file.exists()) {
    // Tests ran with --no-coverage or the file was cleaned. Nothing
    // to filter; silently exit so the Makefile target does not fail
    // on a clean checkout.
    return 0;
  }

  final text = await file.readAsString();
  final records = text.trim().split('end_of_record\n');
  final kept = <String>[];
  var dropped = 0;
  for (final raw in records) {
    final record = raw.trim();
    if (record.isEmpty) continue;
    String? sourcePath;
    for (final line in record.split('\n')) {
      if (line.startsWith('SF:')) {
        sourcePath = line.substring(3).trim();
        break;
      }
    }
    if (sourcePath == null) continue;
    if (_shouldExclude(sourcePath)) {
      dropped++;
      continue;
    }
    kept.add('$record\nend_of_record\n');
  }

  await file.writeAsString(kept.join());
  stdout.writeln('filter-lcov: kept ${kept.length} records, dropped $dropped');
  return 0;
}
