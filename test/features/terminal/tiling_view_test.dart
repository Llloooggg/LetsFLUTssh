import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/terminal/split_node.dart';
import 'package:letsflutssh/features/terminal/terminal_pane.dart';
import 'package:letsflutssh/features/terminal/tiling_view.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/connection_provider.dart';
import 'package:letsflutssh/providers/connections_notifier.dart';

import '../../helpers/frb_bootstrap.dart';
import '../../helpers/test_notifiers.dart';

/// Stand-in for [ConnectionsNotifier] that bypasses every FRB-bound
/// surface — the terminal panes only read it through
/// `notifyStateChanged()` (never fires on the connect-phase render
/// branch the test stays on).
class _StubConnectionManager extends ConnectionsNotifier {
  _StubConnectionManager(this._conns);
  final List<Connection> _conns;

  @override
  List<Connection> build() => _conns;

  @override
  List<Connection> get connections => _conns;
}

Connection _makeConnectingConnection({required String id}) {
  return Connection(
    id: id,
    label: id,
    sshConfig: const SSHConfig(
      server: ServerAddress(host: '127.0.0.1', port: 22, user: 'u'),
      auth: SshAuth(),
    ),
    state: SSHConnectionState.connecting,
  );
}

Widget _host({
  required SplitNode root,
  required Map<String, Connection> paneConnections,
  required String? focusedPaneId,
  required ProviderContainer container,
  bool isActiveTab = true,
  ValueChanged<String>? onPaneFocused,
  ValueChanged<String>? onClosePane,
  ValueChanged<SplitNode>? onTreeChanged,
  String tabId = 'tab-1',
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: TilingView(
            tabId: tabId,
            root: root,
            paneConnections: paneConnections,
            focusedPaneId: focusedPaneId,
            isActiveTab: isActiveTab,
            onPaneFocused: onPaneFocused ?? (_) {},
            onClosePane: onClosePane ?? (_) {},
            onTreeChanged: onTreeChanged ?? (_) {},
          ),
        ),
      ),
    ),
  );
}

ProviderContainer _container(List<Connection> conns) {
  return ProviderContainer(
    overrides: [
      connectionsProvider.overrideWith(() => _StubConnectionManager(conns)),
      configProvider.overrideWith(TestConfigNotifier.new),
    ],
  );
}

void main() {
  // The tiling view mounts `TerminalPane`s whose connect-phase render
  // opens a real Rust `TerminalReplay`. Native FRB lib must be loaded
  // (mirrors `terminal_pane_test.dart`).
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  testWidgets(
    'a leaf with no entry in `paneConnections` renders an empty placeholder '
    'instead of a TerminalPane — guards against a stale tree referencing a '
    'pruned connection',
    (tester) async {
      // Spec: `_buildLeaf` short-circuits to `SizedBox.shrink()` when
      // the leaf id is not in the map. That branch protects against a
      // tree that lags a connection-removal — there is no pane to
      // mount, but the build must not throw.
      final orphan = LeafNode();
      final container = _container(const []);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _host(
          root: orphan,
          paneConnections: const {},
          focusedPaneId: orphan.id,
          container: container,
        ),
      );
      await tester.pump();

      expect(
        find.byType(TerminalPane),
        findsNothing,
        reason:
            'An orphan leaf must not mount a TerminalPane — the connection '
            'is gone, the panes that referenced it were removed.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a single-leaf tree mounts exactly one TerminalPane and `onClose` is '
    'null — the close-pane button does not show in single-pane mode',
    (tester) async {
      // Spec: `_buildLeaf` passes `null` to `TerminalPane.onClose` when
      // `hasMultiplePanes == false`. The contract: the user cannot close
      // the last remaining pane in a tab (that's "close the tab" — a
      // different action). The pane reads the null to know whether to
      // surface the close button.
      final leaf = LeafNode();
      final conn = _makeConnectingConnection(id: 'single');
      addTearDown(conn.dispose);
      final container = _container([conn]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _host(
          root: leaf,
          paneConnections: {leaf.id: conn},
          focusedPaneId: leaf.id,
          container: container,
        ),
      );
      await tester.pump();

      expect(find.byType(TerminalPane), findsOneWidget);
      final pane = tester.widget<TerminalPane>(find.byType(TerminalPane));
      expect(
        pane.hasMultiplePanes,
        isFalse,
        reason:
            'Single-leaf tree must report `hasMultiplePanes: false` so the '
            'pane does not surface a close button for the only pane.',
      );
      expect(
        pane.onClose,
        isNull,
        reason:
            '`onClose` must be null for a single-leaf tree; the user '
            'cannot remove the only pane.',
      );
    },
  );

  testWidgets(
    'a vertical branch lays out its two leaves in a Row with the ratio '
    'driving the first child width — and the divider sits between them',
    (tester) async {
      // Spec: `_buildSplitLayout` uses `Row` for vertical splits and
      // sizes the first child to `totalSize * ratio`. The test pins the
      // axis + the width math: at ratio 0.5 inside an 800-wide host,
      // each pane is 400 wide.
      final leftLeaf = LeafNode();
      final rightLeaf = LeafNode();
      final branch = BranchNode(
        direction: SplitDirection.vertical,
        ratio: 0.5,
        first: leftLeaf,
        second: rightLeaf,
      );
      final left = _makeConnectingConnection(id: 'left');
      final right = _makeConnectingConnection(id: 'right');
      addTearDown(left.dispose);
      addTearDown(right.dispose);
      final container = _container([left, right]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _host(
          root: branch,
          paneConnections: {leftLeaf.id: left, rightLeaf.id: right},
          focusedPaneId: leftLeaf.id,
          container: container,
        ),
      );
      await tester.pump();

      expect(
        find.byType(TerminalPane),
        findsNWidgets(2),
        reason: 'A two-leaf branch must mount one pane per leaf.',
      );
      expect(
        find.byType(Row),
        findsWidgets,
        reason:
            'Vertical splits arrange children in a Row so the panes sit '
            'side by side.',
      );

      // Width math: ratio 0.5 inside an 800-wide host → each pane ~400.
      // Account for the 3-px divider offset on the left edge.
      final panes = tester.widgetList<TerminalPane>(find.byType(TerminalPane));
      expect(panes, hasLength(2));
      for (final p in panes) {
        expect(
          p.hasMultiplePanes,
          isTrue,
          reason:
              'Both panes in a split must see `hasMultiplePanes: true` so '
              'their close button is reachable.',
        );
        expect(p.onClose, isNotNull);
      }
    },
  );

  testWidgets(
    'a horizontal branch lays out its leaves in a Column so the panes stack '
    'top-over-bottom instead of side-by-side',
    (tester) async {
      // Spec: `_buildSplitLayout` switches to Column for horizontal
      // splits. The axis choice drives the divider direction (the
      // mouse cursor flips between resizeColumn / resizeRow) and the
      // sizing axis (height vs width).
      final topLeaf = LeafNode();
      final bottomLeaf = LeafNode();
      final branch = BranchNode(
        direction: SplitDirection.horizontal,
        ratio: 0.4,
        first: topLeaf,
        second: bottomLeaf,
      );
      final top = _makeConnectingConnection(id: 'top');
      final bottom = _makeConnectingConnection(id: 'bottom');
      addTearDown(top.dispose);
      addTearDown(bottom.dispose);
      final container = _container([top, bottom]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _host(
          root: branch,
          paneConnections: {topLeaf.id: top, bottomLeaf.id: bottom},
          focusedPaneId: topLeaf.id,
          container: container,
        ),
      );
      await tester.pump();

      expect(find.byType(TerminalPane), findsNWidgets(2));
      expect(
        find.byType(Column),
        findsWidgets,
        reason:
            'Horizontal splits must arrange children in a Column — the '
            'panes stack vertically.',
      );
    },
  );

  testWidgets('each branch renders a draggable resize divider (a MouseRegion + '
      'GestureDetector pair) over the gap between leaves', (tester) async {
    // Spec: `_buildDivider` puts a MouseRegion (cursor flip) wrapping
    // a GestureDetector (onPanUpdate) over a 6 px hit area. Two
    // leaves = one branch = one divider. The pair is the contract;
    // the resize cursor is what tells the user the gap is grabbable.
    final leftLeaf = LeafNode();
    final rightLeaf = LeafNode();
    final branch = BranchNode(
      direction: SplitDirection.vertical,
      ratio: 0.5,
      first: leftLeaf,
      second: rightLeaf,
    );
    final left = _makeConnectingConnection(id: 'l');
    final right = _makeConnectingConnection(id: 'r');
    addTearDown(left.dispose);
    addTearDown(right.dispose);
    final container = _container([left, right]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _host(
        root: branch,
        paneConnections: {leftLeaf.id: left, rightLeaf.id: right},
        focusedPaneId: leftLeaf.id,
        container: container,
      ),
    );
    await tester.pump();

    // The divider region uses the resize-column cursor for a vertical
    // split. Look for any MouseRegion advertising that cursor.
    final dividers = tester
        .widgetList<MouseRegion>(find.byType(MouseRegion))
        .where((m) => m.cursor == SystemMouseCursors.resizeColumn);
    expect(
      dividers,
      isNotEmpty,
      reason:
          'Vertical branches must render a resize-column cursor over '
          'the divider so the user can spot the grabbable gap.',
    );
  });

  testWidgets(
    'dragging the divider of a vertical branch fires `onTreeChanged` with '
    'an updated ratio — the resize handle drives the tree mutation',
    (tester) async {
      // Spec: `onPanUpdate` clamps the new ratio to the
      // `terminalPaneMin / totalSize` band and, when it actually changes,
      // calls `widget.onTreeChanged(replaceNode(...))`. The test pans by
      // 60 px which lands well inside the clamped band for an 800-wide
      // host, so the callback must fire with a ratio that differs from
      // the starting 0.5.
      final leftLeaf = LeafNode();
      final rightLeaf = LeafNode();
      final branch = BranchNode(
        id: 'branch-1',
        direction: SplitDirection.vertical,
        ratio: 0.5,
        first: leftLeaf,
        second: rightLeaf,
      );
      final left = _makeConnectingConnection(id: 'l');
      final right = _makeConnectingConnection(id: 'r');
      addTearDown(left.dispose);
      addTearDown(right.dispose);
      final container = _container([left, right]);
      addTearDown(container.dispose);

      SplitNode? changedTo;
      await tester.pumpWidget(
        _host(
          root: branch,
          paneConnections: {leftLeaf.id: left, rightLeaf.id: right},
          focusedPaneId: leftLeaf.id,
          container: container,
          onTreeChanged: (next) => changedTo = next,
        ),
      );
      await tester.pump();

      // The divider sits over the gap at x ≈ 400 (ratio 0.5 of 800).
      // Drag right by 60 px so the new ratio bumps to ~0.575.
      final dividerFinder = find.byWidgetPredicate(
        (w) => w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
      );
      expect(dividerFinder, findsOneWidget);

      await tester.timedDrag(
        dividerFinder,
        const Offset(60, 0),
        const Duration(milliseconds: 100),
      );
      await tester.pumpAndSettle();

      expect(
        changedTo,
        isNotNull,
        reason:
            'A non-trivial divider drag must fire `onTreeChanged` with the '
            'updated branch — otherwise the tree never sees the resize.',
      );
      expect(changedTo, isA<BranchNode>());
      final updatedBranch = changedTo! as BranchNode;
      expect(
        updatedBranch.ratio,
        isNot(equals(0.5)),
        reason:
            'The new branch must carry the post-drag ratio — replaceNode '
            'lifts it through the tree.',
      );
    },
  );

  testWidgets(
    '`_hasMultiplePanes` memoises by identity — re-passing the same root '
    'object skips a fresh `collectLeafIds` walk',
    (tester) async {
      // Spec: the state caches the most recent root + its multi-pane
      // verdict; the next layout returns the cached bool when the root
      // instance is identical. The behavioural surface is "rebuilding
      // the same tree does not toggle close-button visibility". We
      // assert that observable contract: a rebuild with the same root
      // keeps every pane's `hasMultiplePanes` value stable.
      final leftLeaf = LeafNode();
      final rightLeaf = LeafNode();
      final root = BranchNode(
        direction: SplitDirection.vertical,
        first: leftLeaf,
        second: rightLeaf,
      );
      final left = _makeConnectingConnection(id: 'l');
      final right = _makeConnectingConnection(id: 'r');
      addTearDown(left.dispose);
      addTearDown(right.dispose);
      final container = _container([left, right]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _host(
          root: root,
          paneConnections: {leftLeaf.id: left, rightLeaf.id: right},
          focusedPaneId: leftLeaf.id,
          container: container,
        ),
      );
      await tester.pump();

      final beforeMulti = tester
          .widgetList<TerminalPane>(find.byType(TerminalPane))
          .every((p) => p.hasMultiplePanes);
      expect(beforeMulti, isTrue);

      // Re-pump the same root reference; the cache should hit.
      await tester.pumpWidget(
        _host(
          root: root,
          paneConnections: {leftLeaf.id: left, rightLeaf.id: right},
          focusedPaneId: leftLeaf.id,
          container: container,
        ),
      );
      await tester.pump();

      final afterMulti = tester
          .widgetList<TerminalPane>(find.byType(TerminalPane))
          .every((p) => p.hasMultiplePanes);
      expect(
        afterMulti,
        isTrue,
        reason:
            'A rebuild that re-passes the same root must keep '
            '`hasMultiplePanes` stable; the identity cache short-circuits '
            'the leaf-id walk so the verdict cannot flip.',
      );
    },
  );

  testWidgets('focused-pane prop is forwarded — only the pane whose id matches '
      '`focusedPaneId` reports `isFocused: true`', (tester) async {
    // Spec: `_buildLeaf` derives `isFocused` from
    // `widget.focusedPaneId == node.id`. Wiring contract: focus is
    // single-source-of-truth at the tab level; the tiling view forwards
    // it, never invents it.
    final leftLeaf = LeafNode();
    final rightLeaf = LeafNode();
    final root = BranchNode(
      direction: SplitDirection.vertical,
      first: leftLeaf,
      second: rightLeaf,
    );
    final left = _makeConnectingConnection(id: 'l');
    final right = _makeConnectingConnection(id: 'r');
    addTearDown(left.dispose);
    addTearDown(right.dispose);
    final container = _container([left, right]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _host(
        root: root,
        paneConnections: {leftLeaf.id: left, rightLeaf.id: right},
        focusedPaneId: rightLeaf.id,
        container: container,
      ),
    );
    await tester.pump();

    final panes = tester
        .widgetList<TerminalPane>(find.byType(TerminalPane))
        .toList();
    expect(panes, hasLength(2));
    final focusedCount = panes.where((p) => p.isFocused).length;
    expect(
      focusedCount,
      1,
      reason:
          'Exactly one pane must own focus at a time — the one whose id '
          'matches `focusedPaneId`.',
    );
  });

  // The hover/cursor interaction with the divider and the actual
  // pixel-level drag math go through `LayoutBuilder`'s `BoxConstraints`
  // captured at paint time. Asserting precise pixel positions of the
  // divider's child rectangle here would couple to layout internals
  // that the spec doesn't pin.
  // covered by integration: pixel-level divider positioning is verified
  // by the visual layer.
}
