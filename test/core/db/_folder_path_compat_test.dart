/// Coverage for the folder-path compat shim — the four pure-sync
/// wrappers around `lfs_core::folder_path` that the Dart settings UI
/// + import flow consume.
///
/// The Rust side carries the algorithmic weight (parent walk,
/// orphan-prefix tagging, deterministic dedup); the wrapper only
/// adapts the in-memory `Map<id, DbFolder>` view to the list/set
/// shapes the FRB call expects. These tests assert the wrapper does
/// not drop semantics across the conversion boundary on the
/// representative cases (empty input, top-level folder, two-level
/// nesting, orphaned parent, prefix rename cascade).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/db/_folder_path_compat.dart';
import 'package:letsflutssh/src/rust/api/db.dart' as rust_db;

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  // PlatformInt64 is `int` on native Dart, `BigInt` on the web. The
  // test runner is always native, so plain int literals satisfy the
  // typedef without an explicit conversion.
  rust_db.DbFolder folder({
    required String id,
    required String name,
    String? parentId,
    int sortOrder = 0,
  }) => rust_db.DbFolder(
    id: id,
    name: name,
    parentId: parentId,
    sortOrder: sortOrder,
    collapsed: false,
    createdAtMs: 0,
  );

  group('folderBuildPathCompat', () {
    test('null id resolves to empty string', () {
      expect(folderBuildPathCompat(null, const {}), '');
    });

    test('empty id resolves to empty string', () {
      expect(folderBuildPathCompat('', const {}), '');
    });

    test('top-level folder is its own name', () {
      final root = folder(id: 'r1', name: 'Servers');
      expect(folderBuildPathCompat('r1', {'r1': root}), 'Servers');
    });

    test('nested folder returns slash-joined path', () {
      final root = folder(id: 'r1', name: 'Servers');
      final child = folder(id: 'c1', name: 'Prod', parentId: 'r1');
      expect(
        folderBuildPathCompat('c1', {'r1': root, 'c1': child}),
        'Servers/Prod',
      );
    });

    test('orphaned parent surfaces the (orphaned) sentinel', () {
      // The folder claims a parent that does not exist in the map.
      // The Rust side tags the path with `(orphaned)` so the UI can
      // render the broken state without dropping the row entirely.
      final orphan = folder(id: 'o1', name: 'Detached', parentId: 'missing');
      final path = folderBuildPathCompat('o1', {'o1': orphan});
      expect(path, contains('orphaned'));
      expect(path, contains('Detached'));
    });
  });

  group('folderFindIdByPathCompat', () {
    test('round-trips a nested folder built by buildPathCompat', () {
      final root = folder(id: 'r1', name: 'Servers');
      final child = folder(id: 'c1', name: 'Prod', parentId: 'r1');
      final map = {'r1': root, 'c1': child};
      final path = folderBuildPathCompat('c1', map);
      expect(folderFindIdByPathCompat(path, map), 'c1');
    });

    test('returns null for an unknown path', () {
      final root = folder(id: 'r1', name: 'Servers');
      expect(
        folderFindIdByPathCompat('Servers/DoesNotExist', {'r1': root}),
        isNull,
      );
    });

    test('returns null for empty path on a populated map', () {
      final root = folder(id: 'r1', name: 'Servers');
      expect(folderFindIdByPathCompat('', {'r1': root}), isNull);
    });
  });

  group('folderAllPathsCompat', () {
    test('empty map yields an empty set', () {
      expect(folderAllPathsCompat(const {}), isEmpty);
    });

    test('returns every reachable path for a nested map', () {
      final root = folder(id: 'r1', name: 'Servers');
      final child = folder(id: 'c1', name: 'Prod', parentId: 'r1');
      final paths = folderAllPathsCompat({'r1': root, 'c1': child});
      expect(paths, containsAll(<String>['Servers', 'Servers/Prod']));
    });

    test('result is a Set — duplicates collapse', () {
      // The Rust side already dedups, but the Dart wrapper materialises
      // a Set so callers can rely on set semantics regardless of the
      // FRB list ordering.
      final root = folder(id: 'r1', name: 'Servers');
      final paths = folderAllPathsCompat({'r1': root});
      expect(paths, isA<Set<String>>());
    });
  });

  group('folderRenamePathsCascadeCompat', () {
    test('exact match moves to the new name', () {
      final renamed = folderRenamePathsCascadeCompat({'Old'}, 'Old', 'New');
      expect(renamed, {'New'});
    });

    test('children under oldPath get their prefix rewritten', () {
      final renamed = folderRenamePathsCascadeCompat(
        {'Servers', 'Servers/Prod', 'Servers/Dev'},
        'Servers',
        'Hosts',
      );
      expect(renamed, {'Hosts', 'Hosts/Prod', 'Hosts/Dev'});
    });

    test('paths outside the rename scope are left untouched', () {
      final renamed = folderRenamePathsCascadeCompat(
        {'Other', 'Servers/Prod'},
        'Servers',
        'Hosts',
      );
      expect(renamed, {'Other', 'Hosts/Prod'});
    });

    test('returns a Set — preserves the input collection shape', () {
      final renamed = folderRenamePathsCascadeCompat({'A'}, 'A', 'B');
      expect(renamed, isA<Set<String>>());
    });

    test('empty input returns empty set', () {
      expect(folderRenamePathsCascadeCompat(const {}, 'A', 'B'), isEmpty);
    });
  });
}
