import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/session_manager/session_panel_controller.dart';

/// Pure-logic tests for [SessionPanelController]. The widget-level
/// behaviour (dialog opening, context menus, keyboard shortcuts) is
/// covered by session_panel_test.dart; this file exercises only the
/// state rules that the `@visibleForTesting` shims on the State class
/// used to assert through widget pumps.

void main() {
  group('SessionPanelController — initial state', () {
    test('starts out of select mode, empty selection, no focus', () {
      final c = SessionPanelController();
      expect(c.selectMode, isFalse);
      expect(c.selectedIds, isEmpty);
      expect(c.selectedFolderPaths, isEmpty);
      expect(c.focusedSessionId, isNull);
      expect(c.focusedFolderPath, isNull);
      expect(c.focusedFolderItemCount, 0);
      expect(c.copiedSessionId, isNull);
      expect(c.marqueeInProgress, isFalse);
      expect(c.hasSelection, isFalse);
    });
  });

  group('SessionPanelController — select mode', () {
    test('enterSelectModeWithSession pre-checks that one session', () {
      final c = SessionPanelController();
      c.enterSelectModeWithSession('s1');
      expect(c.selectMode, isTrue);
      expect(c.selectedIds, {'s1'});
      expect(c.selectedFolderPaths, isEmpty);
    });

    test('enterSelectModeWithFolder pre-checks that one folder', () {
      final c = SessionPanelController();
      c.enterSelectModeWithFolder('prod');
      expect(c.selectMode, isTrue);
      expect(c.selectedFolderPaths, {'prod'});
      expect(c.selectedIds, isEmpty);
    });

    test('re-entering select mode replaces the pre-check', () {
      // Spec: enterSelectModeWith* is the "tap select on row X" entry
      // point. Subsequent taps on other rows while already in select
      // mode should not stack — they pick a new anchor.
      final c = SessionPanelController();
      c.enterSelectModeWithSession('s1');
      c.enterSelectModeWithSession('s2');
      expect(c.selectedIds, {'s2'});
    });

    test('exitSelectMode clears both selection sets', () {
      final c = SessionPanelController();
      c.enterSelectModeWithSession('s1');
      c.toggleFolderSelected('prod');
      c.exitSelectMode();
      expect(c.selectMode, isFalse);
      expect(c.selectedIds, isEmpty);
      expect(c.selectedFolderPaths, isEmpty);
    });
  });

  group('SessionPanelController — toggles', () {
    test('toggleSelected adds, then removes, and notifies both times', () {
      final c = SessionPanelController();
      var notifications = 0;
      c.addListener(() => notifications++);
      c.toggleSelected('s1');
      expect(c.selectedIds, {'s1'});
      c.toggleSelected('s1');
      expect(c.selectedIds, isEmpty);
      expect(notifications, 2);
    });

    test('toggleFolderSelected independent of session selection', () {
      final c = SessionPanelController();
      c.toggleSelected('s1');
      c.toggleFolderSelected('prod');
      expect(c.selectedIds, {'s1'});
      expect(c.selectedFolderPaths, {'prod'});
      c.toggleFolderSelected('prod');
      expect(c.selectedFolderPaths, isEmpty);
      expect(c.selectedIds, {
        's1',
      }, reason: 'folder toggle must not touch session selection');
    });
  });

  group('SessionPanelController — clearing', () {
    test('clearDesktopSelection wipes both sets but keeps focus', () {
      // Spec: desktop "click empty space" drops marquee / Ctrl-click
      // selection but the details panel continues to show whatever
      // was focused before — otherwise the panel empties whenever the
      // user misses a row.
      final c = SessionPanelController();
      c.toggleSelected('s1');
      c.toggleFolderSelected('prod');
      c.setFocusedSession('sX');
      c.clearDesktopSelection();
      expect(c.selectedIds, isEmpty);
      expect(c.selectedFolderPaths, isEmpty);
      expect(
        c.focusedSessionId,
        'sX',
        reason: 'desktop clear preserves focus — keeps details panel alive',
      );
    });

    test('clearDesktopSelection is a no-op when already empty (no notify)', () {
      final c = SessionPanelController();
      var notifications = 0;
      c.addListener(() => notifications++);
      c.clearDesktopSelection();
      expect(
        notifications,
        0,
        reason:
            'idempotent clears must not trigger rebuilds — otherwise every '
            'empty-space click churns the tree',
      );
    });

    test('deselectAll mirrors clearDesktopSelection', () {
      final c = SessionPanelController();
      c.toggleSelected('s1');
      c.deselectAll();
      expect(c.hasSelection, isFalse);
    });
  });

  group('SessionPanelController — select all', () {
    test('selectAllIds adds every id without touching folder paths', () {
      final c = SessionPanelController();
      c.toggleFolderSelected('keep');
      c.selectAllIds(['a', 'b', 'c']);
      expect(c.selectedIds, {'a', 'b', 'c'});
      expect(c.selectedFolderPaths, {'keep'});
    });
  });

  group('SessionPanelController — marquee', () {
    test('setMarqueeSelection replaces both sets atomically', () {
      final c = SessionPanelController();
      c.toggleSelected('old');
      c.toggleFolderSelected('oldFolder');
      c.setMarqueeSelection({'m1', 'm2'}, {'fx'});
      expect(c.selectedIds, {'m1', 'm2'});
      expect(c.selectedFolderPaths, {'fx'});
    });

    test('setMarqueeInProgress is idempotent — no notify on same value', () {
      final c = SessionPanelController();
      var notifications = 0;
      c.addListener(() => notifications++);
      c.setMarqueeInProgress(false);
      expect(notifications, 0);
      c.setMarqueeInProgress(true);
      expect(notifications, 1);
      c.setMarqueeInProgress(true);
      expect(
        notifications,
        1,
        reason:
            'redundant marquee-in-progress writes must not trigger rebuilds',
      );
    });
  });

  group('SessionPanelController — focus', () {
    test('setFocusedSession clears folder focus and vice versa', () {
      // Spec: focusing a session hides the folder details panel; focusing
      // a folder hides the session details panel. Both cannot be shown
      // at once — the widget builds a single details row driven by these
      // fields.
      final c = SessionPanelController();
      c.setFocusedFolder('prod', 3);
      expect(c.focusedFolderPath, 'prod');
      expect(c.focusedFolderItemCount, 3);
      expect(c.focusedSessionId, isNull);

      c.setFocusedSession('s1');
      expect(c.focusedSessionId, 's1');
      expect(
        c.focusedFolderPath,
        isNull,
        reason: 'focusing a session must drop folder focus',
      );
    });

    test('setFocusedSession(null) clears focus', () {
      final c = SessionPanelController();
      c.setFocusedSession('s1');
      c.setFocusedSession(null);
      expect(c.focusedSessionId, isNull);
    });
  });

  group('SessionPanelController — clipboard', () {
    test('copyFocused is a no-op without a focused session', () {
      // Spec: Ctrl+C on an empty panel must not poison the clipboard —
      // otherwise a stale id from a deleted session could be pasted.
      final c = SessionPanelController();
      c.copyFocused();
      expect(c.copiedSessionId, isNull);
    });

    test('copyFocused snapshots the current focused session id', () {
      final c = SessionPanelController();
      c.setFocusedSession('s1');
      c.copyFocused();
      expect(c.copiedSessionId, 's1');
      // Refocusing doesn't move the clipboard — copy is explicit.
      c.setFocusedSession('s2');
      expect(c.copiedSessionId, 's1');
    });
  });

  group('SessionPanelController — hasSelection', () {
    test('true when any session OR folder is selected', () {
      final c = SessionPanelController();
      expect(c.hasSelection, isFalse);
      c.toggleSelected('s1');
      expect(c.hasSelection, isTrue);
      c.toggleSelected('s1');
      expect(c.hasSelection, isFalse);
      c.toggleFolderSelected('prod');
      expect(
        c.hasSelection,
        isTrue,
        reason:
            'folder-only selection still counts — the bulk action bar and '
            'delete/move flows both respect folder-only picks',
      );
    });
  });
}
