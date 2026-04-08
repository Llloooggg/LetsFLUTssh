import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/connection/connection.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/tabs/tab_model.dart';
import 'package:letsflutssh/features/workspace/drop_zone_overlay.dart';
import 'package:letsflutssh/features/workspace/panel_tab_bar.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/theme/app_theme.dart';

void main() {
  TabEntry makeTab({
    required String id,
    String label = 'Server',
    TabKind kind = TabKind.terminal,
    SSHConnectionState connState = SSHConnectionState.connected,
  }) {
    return TabEntry(
      id: id,
      label: label,
      connection: Connection(
        id: 'conn-$id',
        label: label,
        sshConfig: const SSHConfig(
          server: ServerAddress(host: '10.0.0.1', user: 'root'),
        ),
        state: connState,
      ),
      kind: kind,
    );
  }

  Widget buildApp({required Widget child}) {
    return MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );
  }

  group('DropZone enum', () {
    test('has all expected values', () {
      expect(
        DropZone.values,
        containsAll([
          DropZone.center,
          DropZone.left,
          DropZone.right,
          DropZone.top,
          DropZone.bottom,
        ]),
      );
      expect(DropZone.values.length, 5);
    });
  });

  group('buildDropZoneOverlay', () {
    testWidgets('center returns SizedBox.shrink', (tester) async {
      await tester.pumpWidget(
        buildApp(
          child: Stack(children: [buildDropZoneOverlay(DropZone.center)]),
        ),
      );

      // SizedBox.shrink has zero width and height.
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final shrinks = sizedBoxes.where(
        (s) => s.width == 0.0 && s.height == 0.0,
      );
      expect(shrinks, isNotEmpty);
    });

    testWidgets('left renders Positioned.fill with left alignment', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(child: Stack(children: [buildDropZoneOverlay(DropZone.left)])),
      );

      expect(find.byType(Positioned), findsWidgets);

      final align = tester.widget<Align>(find.byType(Align));
      expect(align.alignment, Alignment.centerLeft);

      final fraction = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(fraction.widthFactor, 0.5);
      expect(fraction.heightFactor, 1.0);
    });

    testWidgets('right renders Positioned.fill with right alignment', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          child: Stack(children: [buildDropZoneOverlay(DropZone.right)]),
        ),
      );

      final align = tester.widget<Align>(find.byType(Align));
      expect(align.alignment, Alignment.centerRight);

      final fraction = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(fraction.widthFactor, 0.5);
      expect(fraction.heightFactor, 1.0);
    });

    testWidgets('top renders Positioned.fill with top alignment', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(child: Stack(children: [buildDropZoneOverlay(DropZone.top)])),
      );

      final align = tester.widget<Align>(find.byType(Align));
      expect(align.alignment, Alignment.topCenter);

      final fraction = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(fraction.widthFactor, 1.0);
      expect(fraction.heightFactor, 0.5);
    });

    testWidgets('bottom renders Positioned.fill with bottom alignment', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          child: Stack(children: [buildDropZoneOverlay(DropZone.bottom)]),
        ),
      );

      final align = tester.widget<Align>(find.byType(Align));
      expect(align.alignment, Alignment.bottomCenter);

      final fraction = tester.widget<FractionallySizedBox>(
        find.byType(FractionallySizedBox),
      );
      expect(fraction.widthFactor, 1.0);
      expect(fraction.heightFactor, 0.5);
    });

    testWidgets('overlay container uses accent color and border', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(child: Stack(children: [buildDropZoneOverlay(DropZone.left)])),
      );

      final containers = tester.widgetList<Container>(find.byType(Container));
      final decorated = containers.where((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration) {
          return dec.color == AppTheme.accent.withValues(alpha: 0.15) &&
              dec.border != null;
        }
        return false;
      }).toList();
      expect(decorated, isNotEmpty);
    });

    testWidgets('overlay is wrapped in IgnorePointer', (tester) async {
      await tester.pumpWidget(
        buildApp(
          child: Stack(children: [buildDropZoneOverlay(DropZone.right)]),
        ),
      );

      // Find the IgnorePointer that is a descendant of Positioned.fill.
      final ignorePointers = tester.widgetList<IgnorePointer>(
        find.descendant(
          of: find.byType(Positioned),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignorePointers, isNotEmpty);
      expect(ignorePointers.first.ignoring, isTrue);
    });
  });

  group('PanelDropTarget', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(
        buildApp(
          child: SizedBox(
            width: 400,
            height: 400,
            child: PanelDropTarget(
              panelId: 'panel-0',
              onDrop: (_, _) {},
              child: const Text('Panel Content'),
            ),
          ),
        ),
      );

      expect(find.text('Panel Content'), findsOneWidget);
    });

    testWidgets('accepts TabDragData drag targets', (tester) async {
      await tester.pumpWidget(
        buildApp(
          child: SizedBox(
            width: 400,
            height: 400,
            child: PanelDropTarget(
              panelId: 'panel-0',
              onDrop: (_, _) {},
              child: const Text('Panel Content'),
            ),
          ),
        ),
      );

      // A DragTarget<TabDragData> should be in the widget tree.
      expect(find.byType(DragTarget<TabDragData>), findsOneWidget);
    });

    testWidgets('does not show overlay when no drag is active', (tester) async {
      await tester.pumpWidget(
        buildApp(
          child: SizedBox(
            width: 400,
            height: 400,
            child: PanelDropTarget(
              panelId: 'panel-0',
              onDrop: (_, _) {},
              child: const Text('Panel Content'),
            ),
          ),
        ),
      );

      // No overlay widgets (FractionallySizedBox is part of overlay).
      expect(find.byType(FractionallySizedBox), findsNothing);
    });

    testWidgets('onDrop callback is invoked on successful drop', (
      tester,
    ) async {
      DropZone? droppedZone;
      TabDragData? droppedData;
      final tab = makeTab(id: 'drag-tab');
      final dragData = TabDragData(tab: tab, sourcePanelId: 'panel-src');

      await tester.pumpWidget(
        buildApp(
          child: SizedBox(
            width: 400,
            height: 400,
            child: Row(
              children: [
                Draggable<TabDragData>(
                  data: dragData,
                  feedback: const SizedBox(width: 50, height: 50),
                  child: const SizedBox(
                    width: 50,
                    height: 50,
                    child: Text('Drag Me'),
                  ),
                ),
                Expanded(
                  child: PanelDropTarget(
                    panelId: 'panel-target',
                    onDrop: (data, zone) {
                      droppedData = data;
                      droppedZone = zone;
                    },
                    child: const Text('Target'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Find the drag source and the target.
      final dragSource = find.text('Drag Me');
      final target = find.text('Target');
      final targetCenter = tester.getCenter(target);

      // Drag from source to the left edge of the target.
      final targetLeft = Offset(
        tester.getTopLeft(target).dx + 10,
        targetCenter.dy,
      );

      await tester.timedDragFrom(
        tester.getCenter(dragSource),
        targetLeft - tester.getCenter(dragSource),
        const Duration(milliseconds: 300),
      );
      await tester.pumpAndSettle();

      expect(droppedData, isNotNull);
      expect(droppedData!.tab.id, 'drag-tab');
      expect(droppedData!.sourcePanelId, 'panel-src');
      expect(droppedZone, DropZone.left);
    });

    testWidgets('onLeave clears active zone', (tester) async {
      await tester.pumpWidget(
        buildApp(
          child: SizedBox(
            width: 400,
            height: 400,
            child: Row(
              children: [
                Draggable<TabDragData>(
                  data: TabDragData(
                    tab: makeTab(id: 't'),
                    sourcePanelId: 'p',
                  ),
                  feedback: const SizedBox(width: 50, height: 50),
                  child: const SizedBox(
                    width: 50,
                    height: 50,
                    child: Text('Src'),
                  ),
                ),
                Expanded(
                  child: PanelDropTarget(
                    panelId: 'panel-target',
                    onDrop: (_, _) {},
                    child: const Text('Target'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final src = tester.getCenter(find.text('Src'));
      final targetLeft = Offset(
        tester.getTopLeft(find.text('Target')).dx + 10,
        tester.getCenter(find.text('Target')).dy,
      );

      // Start drag, move into target, then move away.
      final gesture = await tester.startGesture(src);
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(targetLeft);
      await tester.pump();

      // Overlay should appear.
      expect(find.byType(FractionallySizedBox), findsOneWidget);

      // Move away from the target entirely.
      await gesture.moveTo(const Offset(-100, -100));
      await tester.pump();

      // Overlay should disappear after leaving.
      expect(find.byType(FractionallySizedBox), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
