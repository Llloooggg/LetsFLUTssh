import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/tags/tag.dart';
import 'package:letsflutssh/features/tags/tags_logic.dart';

Tag _tag(String id, String name) =>
    Tag(id: id, name: name, createdAt: DateTime(2024, 1, 1));

void main() {
  group('filterTagsByName', () {
    final fixture = [
      _tag('1', 'production'),
      _tag('2', 'staging'),
      _tag('3', 'on-call'),
      _tag('4', 'PROD-Critical'),
    ];

    test('empty filter returns input verbatim', () {
      expect(filterTagsByName(fixture, ''), fixture);
    });

    test('case-insensitive substring match on name', () {
      expect(filterTagsByName(fixture, 'PROD').map((t) => t.id).toSet(), {
        '1',
        '4',
      });
      expect(filterTagsByName(fixture, 'on').map((t) => t.id).toSet(), {
        '1',
        '3',
      });
    });

    test('no match returns empty', () {
      expect(filterTagsByName(fixture, 'xyz'), isEmpty);
    });

    test('empty input list is a no-op', () {
      expect(filterTagsByName(const [], ''), isEmpty);
      expect(filterTagsByName(const [], 'name'), isEmpty);
    });
  });

  group('allAssignedTristate', () {
    final t1 = _tag('1', 'a');
    final t2 = _tag('2', 'b');
    final t3 = _tag('3', 'c');

    test('empty tag list → unchecked (no tristate / mixed needed)', () {
      // Empty list collapses to false even when assignedIds is also
      // empty — there is nothing to flip "all on" against.
      expect(
        allAssignedTristate(allTags: const [], assignedIds: const {}),
        isFalse,
      );
      // And the case where assignedIds carries stale ids that no
      // longer have backing tags still collapses to "no tags → false".
      expect(
        allAssignedTristate(allTags: const [], assignedIds: {'stale'}),
        isFalse,
      );
    });

    test('zero assigned ids → unchecked', () {
      expect(
        allAssignedTristate(allTags: [t1, t2, t3], assignedIds: const {}),
        isFalse,
      );
    });

    test('all assigned → checked', () {
      expect(
        allAssignedTristate(
          allTags: [t1, t2, t3],
          assignedIds: {'1', '2', '3'},
        ),
        isTrue,
      );
    });

    test('partial assigned → mixed (null)', () {
      expect(
        allAssignedTristate(allTags: [t1, t2, t3], assignedIds: {'1'}),
        isNull,
      );
      expect(
        allAssignedTristate(allTags: [t1, t2, t3], assignedIds: {'1', '2'}),
        isNull,
      );
    });
  });
}
