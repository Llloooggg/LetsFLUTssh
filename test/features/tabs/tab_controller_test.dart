import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/tabs/tab_controller.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';

void main() {
  Connection makeConn({String label = 'Server', String id = 'conn-1'}) {
    return Connection(
      id: id,
      label: label,
      sshConfig: const SSHConfig(host: '10.0.0.1', user: 'root'),
    );
  }

  group('TabState', () {
    test('default state has no tabs and activeIndex -1', () {
      const state = TabState();
      expect(state.tabs, isEmpty);
      expect(state.activeIndex, -1);
      expect(state.activeTab, isNull);
    });

    test('activeTab returns tab at activeIndex', () {
      final conn = makeConn();
      final tab = TabEntry(
        id: 't1', label: 'SSH', connection: conn, kind: TabKind.terminal,
      );
      final state = TabState(tabs: [tab], activeIndex: 0);
      expect(state.activeTab, tab);
    });

    test('activeTab returns null for out-of-range index', () {
      const state = TabState(tabs: [], activeIndex: 0);
      expect(state.activeTab, isNull);
    });

    test('activeTab returns null for negative index', () {
      const state = TabState(tabs: [], activeIndex: -1);
      expect(state.activeTab, isNull);
    });

    test('copyWith updates fields', () {
      const state = TabState();
      final updated = state.copyWith(activeIndex: 2);
      expect(updated.activeIndex, 2);
      expect(updated.tabs, isEmpty);
    });
  });

  group('TabNotifier', () {
    late TabNotifier notifier;

    setUp(() {
      notifier = TabNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    test('initial state is empty', () {
      expect(notifier.state.tabs, isEmpty);
      expect(notifier.state.activeIndex, -1);
    });

    group('addTerminalTab', () {
      test('adds tab and sets active', () {
        final conn = makeConn();
        final id = notifier.addTerminalTab(conn);
        expect(id, isNotEmpty);
        expect(notifier.state.tabs.length, 1);
        expect(notifier.state.activeIndex, 0);
        expect(notifier.state.tabs.first.kind, TabKind.terminal);
        expect(notifier.state.tabs.first.label, 'Server');
      });

      test('uses custom label', () {
        final conn = makeConn();
        notifier.addTerminalTab(conn, label: 'Custom');
        expect(notifier.state.tabs.first.label, 'Custom');
      });

      test('second tab becomes active', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        expect(notifier.state.tabs.length, 2);
        expect(notifier.state.activeIndex, 1);
        expect(notifier.state.activeTab!.label, 'B');
      });
    });

    group('addSftpTab', () {
      test('adds SFTP tab with suffix', () {
        final conn = makeConn(label: 'MyServer');
        notifier.addSftpTab(conn);
        expect(notifier.state.tabs.first.kind, TabKind.sftp);
        expect(notifier.state.tabs.first.label, 'MyServer (SFTP)');
      });

      test('uses custom label', () {
        notifier.addSftpTab(makeConn(), label: 'Files');
        expect(notifier.state.tabs.first.label, 'Files');
      });
    });

    group('closeTab', () {
      test('removes tab by id', () {
        final conn = makeConn();
        final id = notifier.addTerminalTab(conn);
        notifier.closeTab(id);
        expect(notifier.state.tabs, isEmpty);
        expect(notifier.state.activeIndex, -1);
      });

      test('closing nonexistent id does nothing', () {
        notifier.addTerminalTab(makeConn());
        notifier.closeTab('nonexistent');
        expect(notifier.state.tabs.length, 1);
      });

      test('adjusts active index when closing active tab', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        final idB = notifier.state.tabs[1].id;
        // Active is 1 (B), close B -> active should be 0
        notifier.closeTab(idB);
        expect(notifier.state.tabs.length, 1);
        expect(notifier.state.activeIndex, 0);
      });

      test('adjusts active index when closing tab before active', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.addTerminalTab(makeConn(label: 'C'));
        // Active is 2 (C), close A (index 0)
        final idA = notifier.state.tabs[0].id;
        notifier.closeTab(idA);
        expect(notifier.state.tabs.length, 2);
        // activeIndex was 2, still valid since length is now 2, clamp to 1
        expect(notifier.state.activeIndex, 1);
      });

      test('closing last tab sets activeIndex to -1', () {
        final id = notifier.addTerminalTab(makeConn());
        notifier.closeTab(id);
        expect(notifier.state.activeIndex, -1);
      });
    });

    group('closeOthers', () {
      test('keeps only the specified tab', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.addTerminalTab(makeConn(label: 'C'));
        final idB = notifier.state.tabs[1].id;
        notifier.closeOthers(idB);
        expect(notifier.state.tabs.length, 1);
        expect(notifier.state.tabs.first.id, idB);
        expect(notifier.state.activeIndex, 0);
      });
    });

    group('closeToTheRight', () {
      test('closes tabs to the right', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.addTerminalTab(makeConn(label: 'C'));
        notifier.selectTab(0);
        notifier.closeToTheRight(0);
        expect(notifier.state.tabs.length, 1);
        expect(notifier.state.tabs.first.label, 'A');
      });

      test('no-op when index is last', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.closeToTheRight(1);
        expect(notifier.state.tabs.length, 2);
      });

      test('adjusts active index if it was in removed range', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.addTerminalTab(makeConn(label: 'C'));
        // Active is 2 (C), close right of 0 -> removes B, C
        notifier.closeToTheRight(0);
        expect(notifier.state.activeIndex, 0);
      });
    });

    group('closeToTheLeft', () {
      test('closes tabs to the left', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.addTerminalTab(makeConn(label: 'C'));
        notifier.closeToTheLeft(2);
        expect(notifier.state.tabs.length, 1);
        expect(notifier.state.tabs.first.label, 'C');
      });

      test('no-op when index is 0', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.closeToTheLeft(0);
        expect(notifier.state.tabs.length, 2);
      });

      test('adjusts active index', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.addTerminalTab(makeConn(label: 'C'));
        notifier.selectTab(0);
        // Active is 0, close left of 2 -> removes A, B
        notifier.closeToTheLeft(2);
        expect(notifier.state.activeIndex, 0);
      });
    });

    group('selectTab', () {
      test('selects tab by index', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.selectTab(0);
        expect(notifier.state.activeIndex, 0);
        expect(notifier.state.activeTab!.label, 'A');
      });

      test('ignores out-of-range index', () {
        notifier.addTerminalTab(makeConn());
        notifier.selectTab(5);
        expect(notifier.state.activeIndex, 0);
      });

      test('ignores negative index', () {
        notifier.addTerminalTab(makeConn());
        notifier.selectTab(-1);
        expect(notifier.state.activeIndex, 0);
      });
    });

    group('reorderTabs', () {
      test('moves tab forward', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.addTerminalTab(makeConn(label: 'C'));
        notifier.selectTab(0);
        // Move A from 0 to 2
        notifier.reorderTabs(0, 2);
        expect(notifier.state.tabs.map((t) => t.label).toList(), ['B', 'A', 'C']);
      });

      test('moves tab backward', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.addTerminalTab(makeConn(label: 'C'));
        notifier.selectTab(2);
        // Move C from 2 to 0
        notifier.reorderTabs(2, 0);
        expect(notifier.state.tabs.map((t) => t.label).toList(), ['C', 'A', 'B']);
      });

      test('active tab follows reorder when it is the moved tab', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.addTerminalTab(makeConn(label: 'C'));
        notifier.selectTab(0);
        // Move active tab A from 0 to 2
        notifier.reorderTabs(0, 2);
        // A is now at index 1 (since newIndex > oldIndex, newIndex--)
        expect(notifier.state.activeIndex, 1);
      });

      test('active tab adjusts when tab moves past it', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.addTerminalTab(makeConn(label: 'C'));
        notifier.selectTab(1);
        // Move A (0) past active (1): active should decrement
        notifier.reorderTabs(0, 2);
        expect(notifier.state.activeIndex, 0);
      });

      test('active tab adjusts when tab moves before it', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.addTerminalTab(makeConn(label: 'C'));
        notifier.selectTab(1);
        // Move C (2) to position 0: active should increment
        notifier.reorderTabs(2, 0);
        expect(notifier.state.activeIndex, 2);
      });
    });

    group('swapTabs', () {
      test('swaps two tabs', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.addTerminalTab(makeConn(label: 'C'));
        notifier.selectTab(0);
        notifier.swapTabs(0, 2);
        expect(notifier.state.tabs.map((t) => t.label).toList(), ['C', 'B', 'A']);
      });

      test('no-op for same index', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.swapTabs(0, 0);
        expect(notifier.state.tabs.first.label, 'A');
      });

      test('no-op for out of range', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.swapTabs(-1, 0);
        expect(notifier.state.tabs.length, 1);
        notifier.swapTabs(0, 5);
        expect(notifier.state.tabs.length, 1);
      });

      test('active index follows swap when active is swapped', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.selectTab(0);
        notifier.swapTabs(0, 1);
        expect(notifier.state.activeIndex, 1);
      });

      test('active index follows swap when active is target', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.selectTab(1);
        notifier.swapTabs(0, 1);
        expect(notifier.state.activeIndex, 0);
      });

      test('active index unchanged when not involved in swap', () {
        notifier.addTerminalTab(makeConn(label: 'A'));
        notifier.addTerminalTab(makeConn(label: 'B'));
        notifier.addTerminalTab(makeConn(label: 'C'));
        notifier.selectTab(1);
        notifier.swapTabs(0, 2);
        expect(notifier.state.activeIndex, 1);
      });
    });
  });
}
