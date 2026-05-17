@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static cycle detection over `lib/`. Builds the import graph from
/// every `*.dart` file under `lib/` (excluding the FRB-generated
/// tree and `*.g.dart` / `*.freezed.dart`) and fails the test on any
/// cycle.
///
/// Why this exists: Dart's compiler accepts circular imports without
/// warning, but eager field initializers across the cycle abort the
/// VM before any zone error handler gets a chance to surface the
/// failure. The pre-runApp boot phase sees a silent process death;
/// stdout / stderr / log file are all empty. The fault we caught
/// landed because `lib/utils/logger.dart` imported
/// `lib/features/settings/settings_logging_parser.dart` which
/// imported `lib/utils/logger.dart` back — a non-late `final
/// StreamController of LogEntry _entriesController = ...` field
/// initializer in `AppLogger` could not resolve `LogEntry` and the
/// VM aborted before `runZonedGuarded` could record anything.
///
/// This test guards the same fault class compile-/test-time: any
/// cycle introduced into `lib/` fails `make test` before it can
/// land in a build that boots into nothing.
void main() {
  test('lib/ import graph is acyclic', () {
    final libDir = Directory('lib');
    expect(
      libDir.existsSync(),
      isTrue,
      reason: 'test must run from project root',
    );

    final files = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (!path.endsWith('.dart')) continue;
      if (path.endsWith('.g.dart')) continue;
      if (path.endsWith('.freezed.dart')) continue;
      // FRB codegen output — generated, owned by codegen; cycles
      // there would surface as a codegen bug, not a project-source
      // bug.
      final sep = Platform.pathSeparator;
      if (path.contains('${sep}src${sep}rust$sep')) continue;
      // Flutter `intl_utils` codegen: every per-locale
      // `app_localizations_<lang>.dart` extends the abstract
      // `app_localizations.dart`, which in turn imports each
      // locale class to look up by tag. The shape is generated
      // and the cycle never fires at boot — locale classes are
      // const-constructed with no eager singleton state. Skip
      // the whole `app_localizations*` family rather than
      // teaching the test about codegen-only cycles.
      if (path.contains('${sep}l10n${sep}app_localizations')) continue;
      files.add(path);
    }

    final graph = <String, Set<String>>{};
    for (final file in files) {
      graph[_canonical(file)] = _imports(file);
    }

    final cycles = <List<String>>[];
    final visited = <String>{};
    final stack = <String>{};
    for (final node in graph.keys) {
      if (!visited.contains(node)) {
        _dfs(node, graph, visited, stack, [], cycles);
      }
    }

    if (cycles.isNotEmpty) {
      final report = cycles
          .map(
            (cycle) =>
                '  - ${cycle.map((p) => p.replaceFirst(RegExp(r'^.*?lib/'), 'lib/')).join(' -> ')}',
          )
          .join('\n');
      fail(
        'Import cycle(s) detected in lib/:\n$report\n\n'
        'A cycle is a silent boot hazard. Eager field initializers '
        'across the cycle abort the VM before runZonedGuarded can '
        'record the failure — process dies with no log entry, no '
        'stderr line. Break the cycle by moving the shared type into '
        'the file at the lower layer (the one whose dependency on '
        'the higher layer creates the loop).',
      );
    }
  });
}

/// Canonical absolute-from-lib path. `import` paths are resolved
/// against the importing file's directory; canonicalising both
/// sides lets the graph use a single key per file.
String _canonical(String path) {
  return File(path).absolute.path;
}

/// Extract relative import paths from a Dart source file. Skips
/// `package:` imports (cross-package, never form intra-`lib/`
/// cycles) and `dart:` imports.
Set<String> _imports(String filePath) {
  final source = File(filePath).readAsStringSync();
  final pattern = RegExp(
    r'''^(?:import|export)\s+['"]([^'"]+)['"]''',
    multiLine: true,
  );
  final fileDir = File(filePath).parent.absolute.path;
  final out = <String>{};
  for (final match in pattern.allMatches(source)) {
    final raw = match.group(1)!;
    if (raw.startsWith('dart:')) continue;
    if (raw.startsWith('package:letsflutssh/')) {
      // Resolve `package:letsflutssh/foo/bar.dart` against `lib/`.
      final rel = raw.substring('package:letsflutssh/'.length);
      out.add(File('lib/$rel').absolute.path);
      continue;
    }
    if (raw.startsWith('package:')) continue;
    // Relative path — resolve against the importing file's dir.
    out.add(File('$fileDir/$raw').absolute.path);
  }
  return out;
}

void _dfs(
  String node,
  Map<String, Set<String>> graph,
  Set<String> visited,
  Set<String> stack,
  List<String> path,
  List<List<String>> cycles,
) {
  visited.add(node);
  stack.add(node);
  path.add(node);
  for (final next in graph[node] ?? const <String>{}) {
    if (!graph.containsKey(next)) continue; // out-of-graph ref
    if (stack.contains(next)) {
      // Cycle from `next` back to `next` along the current path.
      final start = path.indexOf(next);
      final cycle = path.sublist(start)..add(next);
      // Dedup permutations: every cycle has N rotations; keep the
      // canonical one starting at the lexicographically smallest
      // node so two different DFS starts don't double-report it.
      final canonical = _canonicaliseCycle(cycle);
      if (!cycles.any((c) => _cyclesEqual(c, canonical))) {
        cycles.add(canonical);
      }
      continue;
    }
    if (visited.contains(next)) continue;
    _dfs(next, graph, visited, stack, path, cycles);
  }
  stack.remove(node);
  path.removeLast();
}

List<String> _canonicaliseCycle(List<String> cycle) {
  final body = cycle.sublist(0, cycle.length - 1);
  var minIndex = 0;
  for (var i = 1; i < body.length; i++) {
    if (body[i].compareTo(body[minIndex]) < 0) minIndex = i;
  }
  final rotated = [
    ...body.sublist(minIndex),
    ...body.sublist(0, minIndex),
    body[minIndex],
  ];
  return rotated;
}

bool _cyclesEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
