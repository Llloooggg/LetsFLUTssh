import 'package:flutter/material.dart' show Axis;
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/workspace/drop_zone_overlay.dart';
import 'package:letsflutssh/features/workspace/workspace_drop_logic.dart';

void main() {
  group('dropZoneToSplitParams', () {
    test('center returns null — tab bar handles in-panel reorder', () {
      expect(dropZoneToSplitParams(DropZone.center), isNull);
    });

    test('left zone → horizontal axis, insertBefore=true', () {
      final p = dropZoneToSplitParams(DropZone.left)!;
      expect(p.axis, Axis.horizontal);
      expect(p.insertBefore, isTrue);
    });

    test('right zone → horizontal axis, insertBefore=false', () {
      final p = dropZoneToSplitParams(DropZone.right)!;
      expect(p.axis, Axis.horizontal);
      expect(p.insertBefore, isFalse);
    });

    test('top zone → vertical axis, insertBefore=true', () {
      final p = dropZoneToSplitParams(DropZone.top)!;
      expect(p.axis, Axis.vertical);
      expect(p.insertBefore, isTrue);
    });

    test('bottom zone → vertical axis, insertBefore=false', () {
      final p = dropZoneToSplitParams(DropZone.bottom)!;
      expect(p.axis, Axis.vertical);
      expect(p.insertBefore, isFalse);
    });

    test('every non-center zone returns a non-null params record', () {
      for (final zone in DropZone.values) {
        final result = dropZoneToSplitParams(zone);
        if (zone == DropZone.center) {
          expect(result, isNull);
        } else {
          expect(result, isNotNull, reason: '$zone must yield split params');
        }
      }
    });
  });
}
