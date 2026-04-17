import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/transfer/transfer_task.dart';
import 'package:letsflutssh/features/file_browser/transfer_panel_controller.dart';

/// Pure-logic tests for [TransferPanelController]. The widget-level
/// behaviour (rendering, resize handles, sort menu) is covered by
/// transfer_panel_test.dart; this file exercises only the state rules
/// (clamps, sort cycles, auto-expand edge).

HistoryEntry _entry({
  String id = 'e',
  String name = 'file',
  TransferDirection direction = TransferDirection.upload,
  String sourcePath = 'local.txt',
  String targetPath = 'remote.txt',
  int sizeBytes = 0,
  DateTime? created,
  DateTime? started,
  DateTime? ended,
}) => HistoryEntry(
  id: id,
  name: name,
  direction: direction,
  sourcePath: sourcePath,
  targetPath: targetPath,
  status: TransferStatus.completed,
  createdAt: created ?? DateTime(2026, 1, 1),
  startedAt: started,
  endedAt: ended,
  sizeBytes: sizeBytes,
);

void main() {
  group('TransferPanelController — initial state', () {
    test('panel collapsed, time-descending, default widths', () {
      final c = TransferPanelController();
      expect(c.expanded, isFalse);
      expect(c.sortColumn, TransferSortColumn.time);
      expect(c.sortAscending, isFalse);
      expect(c.panelHeight, 200);
      expect(c.localColWidth, 110);
      expect(c.remoteColWidth, 110);
      expect(c.sizeColWidth, 55);
      expect(c.timeColWidth, 105);
    });
  });

  group('TransferPanelController — expand toggle', () {
    test('toggleExpanded flips and notifies', () {
      final c = TransferPanelController();
      var n = 0;
      c.addListener(() => n++);
      c.toggleExpanded();
      expect(c.expanded, isTrue);
      c.toggleExpanded();
      expect(c.expanded, isFalse);
      expect(n, 2);
    });

    test('setExpanded is idempotent — no notify on same value', () {
      final c = TransferPanelController();
      var n = 0;
      c.addListener(() => n++);
      c.setExpanded(false);
      expect(n, 0);
      c.setExpanded(true);
      expect(n, 1);
      c.setExpanded(true);
      expect(n, 1);
    });
  });

  group('TransferPanelController — auto-expand on running edge', () {
    test(
      'false → true transition expands; subsequent true calls do not re-expand',
      () {
        // Spec: user starts a transfer → panel opens once. If they
        // close it manually, it must NOT auto-reopen on the next build
        // while the transfer is still running — otherwise the panel
        // becomes impossible to dismiss during long uploads.
        final c = TransferPanelController();
        c.syncAutoExpand(false);
        expect(c.expanded, isFalse);

        c.syncAutoExpand(true);
        expect(c.expanded, isTrue);

        c.setExpanded(false);
        c.syncAutoExpand(true);
        expect(
          c.expanded,
          isFalse,
          reason: 'still-running (no edge) must not clobber a manual collapse',
        );
      },
    );

    test('running drops then rises again → re-expands on new edge', () {
      final c = TransferPanelController();
      c.syncAutoExpand(true);
      c.setExpanded(false);
      c.syncAutoExpand(false);
      c.syncAutoExpand(true);
      expect(
        c.expanded,
        isTrue,
        reason:
            'a second transfer after the first completed is a new false→true '
            'edge — auto-expand must fire again',
      );
    });
  });

  group('TransferPanelController — resize clamps', () {
    test('resizePanelHeightBy clamps to [min..max]', () {
      final c = TransferPanelController();
      c.resizePanelHeightBy(-10000);
      expect(c.panelHeight, TransferPanelController.panelHeightMax);
      c.resizePanelHeightBy(10000);
      expect(c.panelHeight, TransferPanelController.panelHeightMin);
    });

    test('column resizers clamp to their bounds', () {
      final c = TransferPanelController();
      c.resizeLocalColBy(-10000);
      expect(c.localColWidth, TransferPanelController.pathColMax);
      c.resizeLocalColBy(10000);
      expect(c.localColWidth, TransferPanelController.pathColMin);

      c.resizeSizeColBy(-10000);
      expect(c.sizeColWidth, TransferPanelController.sizeColMax);
      c.resizeSizeColBy(10000);
      expect(c.sizeColWidth, TransferPanelController.sizeColMin);
    });

    test('no-op resize (at clamp) does not notify', () {
      final c = TransferPanelController();
      c.resizePanelHeightBy(10000);
      var n = 0;
      c.addListener(() => n++);
      c.resizePanelHeightBy(10000);
      expect(n, 0, reason: 'already-clamped drags must not trigger rebuilds');
    });
  });

  group('TransferPanelController — sort cycle', () {
    test(
      'setSort on same column toggles direction; new column resets to asc',
      () {
        // Spec: idiomatic file-manager behaviour — clicking the active
        // header flips direction, clicking a different header starts
        // fresh with ascending order so the user doesn't inherit a
        // confusing reversal from an unrelated previous sort.
        final c = TransferPanelController();
        expect(c.sortColumn, TransferSortColumn.time);
        expect(c.sortAscending, isFalse);

        c.setSort(TransferSortColumn.time);
        expect(c.sortAscending, isTrue);

        c.setSort(TransferSortColumn.name);
        expect(c.sortColumn, TransferSortColumn.name);
        expect(
          c.sortAscending,
          isTrue,
          reason: 'new column always starts ascending',
        );
      },
    );
  });

  group('TransferPanelController — sorted() comparator', () {
    test('sort by name is case-insensitive', () {
      final c = TransferPanelController();
      c.setSort(TransferSortColumn.name);
      final out = c.sorted([
        _entry(id: '1', name: 'bravo'),
        _entry(id: '2', name: 'Alpha'),
      ]);
      expect(
        out.map((e) => e.id).toList(),
        ['2', '1'],
        reason: 'case-insensitive compare: Alpha < bravo',
      );
    });

    test('sort by size ascending vs descending', () {
      final c = TransferPanelController();
      c.setSort(TransferSortColumn.size);
      final asc = c.sorted([
        _entry(id: 'big', sizeBytes: 1000),
        _entry(id: 'small', sizeBytes: 1),
      ]);
      expect(asc.map((e) => e.id).toList(), ['small', 'big']);

      c.setSort(TransferSortColumn.size);
      final desc = c.sorted([
        _entry(id: 'big', sizeBytes: 1000),
        _entry(id: 'small', sizeBytes: 1),
      ]);
      expect(desc.map((e) => e.id).toList(), ['big', 'small']);
    });

    test(
      'sort by time uses endedAt ?? startedAt ?? createdAt fallback chain',
      () {
        // Spec: an in-flight transfer with only `startedAt` set still
        // has a stable sort position relative to a queued transfer with
        // only `createdAt`. Without the fallback, one side is null and
        // the comparator would throw on .compareTo(null).
        final c = TransferPanelController();
        c.setSort(TransferSortColumn.time);
        // Second setSort same column → descending again (toggled off
        // from ascending). We want ascending here for clarity:
        c.setSort(TransferSortColumn.name);
        c.setSort(TransferSortColumn.time); // ascending
        final out = c.sorted([
          _entry(id: 'created-only', created: DateTime(2026, 1, 1)),
          _entry(
            id: 'started-only',
            created: DateTime(2025),
            started: DateTime(2026, 2, 1),
          ),
          _entry(
            id: 'ended',
            created: DateTime(2025),
            started: DateTime(2025, 12),
            ended: DateTime(2026, 3, 1),
          ),
        ]);
        expect(out.map((e) => e.id).toList(), [
          'created-only',
          'started-only',
          'ended',
        ]);
      },
    );

    test('sort by local uses sourcePath on upload, targetPath on download', () {
      // Spec: "Local" column always shows the LOCAL filesystem path —
      // which is sourcePath on an upload (we read locally → send) and
      // targetPath on a download (we fetch remote → write locally).
      // Without this distinction, sorting by local would sometimes
      // sort by the remote path depending on transfer direction.
      final c = TransferPanelController();
      c.setSort(TransferSortColumn.name); // reset
      c.setSort(TransferSortColumn.local); // ascending
      final out = c.sorted([
        _entry(
          id: 'up',
          direction: TransferDirection.upload,
          sourcePath: '/b-local',
          targetPath: '/a-remote',
        ),
        _entry(
          id: 'down',
          direction: TransferDirection.download,
          sourcePath: '/z-remote',
          targetPath: '/a-local',
        ),
      ]);
      expect(
        out.map((e) => e.id).toList(),
        ['down', 'up'],
        reason:
            'ascending by local path — download local (/a-local) sorts '
            'before upload local (/b-local) regardless of sourcePath',
      );
    });

    test('sorted() does not mutate the input', () {
      final c = TransferPanelController();
      c.setSort(TransferSortColumn.size);
      final input = [
        _entry(id: '1', sizeBytes: 10),
        _entry(id: '2', sizeBytes: 1),
      ];
      c.sorted(input);
      expect(
        input.map((e) => e.id).toList(),
        ['1', '2'],
        reason:
            'comparator must return a copy — callers rely on original '
            'provider list being untouched',
      );
    });
  });
}
