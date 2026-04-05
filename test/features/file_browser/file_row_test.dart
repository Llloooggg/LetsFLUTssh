import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/sftp/sftp_models.dart';
import 'package:letsflutssh/features/file_browser/file_row.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/marquee_mixin.dart';

void main() {
  final now = DateTime(2024, 1, 15, 10, 30);

  Widget buildApp(Widget child) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: SizedBox(width: 800, child: child)),
    );
  }

  group('FileRow', () {
    testWidgets('renders file name', (tester) async {
      await tester.pumpWidget(
        buildApp(
          FileRow(
            entry: FileEntry(
              name: 'test.txt',
              path: '/test.txt',
              size: 1024,
              mode: 0x1A4, // 0644
              modTime: now,
              isDir: false,
            ),
            isSelected: false,
            onTap: () {},
            onCtrlTap: () {},
            onDoubleTap: () {},
            onContextMenu: (_) {},
          ),
        ),
      );
      expect(find.text('test.txt'), findsOneWidget);
    });

    testWidgets('renders file icon for files', (tester) async {
      await tester.pumpWidget(
        buildApp(
          FileRow(
            entry: FileEntry(
              name: 'doc.pdf',
              path: '/doc.pdf',
              size: 2048,
              modTime: now,
              isDir: false,
            ),
            isSelected: false,
            onTap: () {},
            onCtrlTap: () {},
            onDoubleTap: () {},
            onContextMenu: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);
    });

    testWidgets('renders folder icon for directories', (tester) async {
      await tester.pumpWidget(
        buildApp(
          FileRow(
            entry: FileEntry(
              name: 'mydir',
              path: '/mydir',
              size: 0,
              modTime: now,
              isDir: true,
            ),
            isSelected: false,
            onTap: () {},
            onCtrlTap: () {},
            onDoubleTap: () {},
            onContextMenu: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.folder), findsOneWidget);
    });

    testWidgets('renders size for files, empty for dirs', (tester) async {
      await tester.pumpWidget(
        buildApp(
          FileRow(
            entry: FileEntry(
              name: 'big.bin',
              path: '/big.bin',
              size: 1048576, // 1 MB
              modTime: now,
              isDir: false,
            ),
            isSelected: false,
            onTap: () {},
            onCtrlTap: () {},
            onDoubleTap: () {},
            onContextMenu: (_) {},
          ),
        ),
      );
      expect(find.text('1.0 MB'), findsOneWidget);
    });

    testWidgets('renders owner column when owner is non-empty', (tester) async {
      await tester.pumpWidget(
        buildApp(
          FileRow(
            entry: FileEntry(
              name: 'file.txt',
              path: '/file.txt',
              size: 100,
              modTime: now,
              isDir: false,
              owner: 'root',
            ),
            isSelected: false,
            onTap: () {},
            onCtrlTap: () {},
            onDoubleTap: () {},
            onContextMenu: (_) {},
          ),
        ),
      );
      expect(find.text('root'), findsOneWidget);
    });

    testWidgets('does not render owner column when owner is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          FileRow(
            entry: FileEntry(
              name: 'file.txt',
              path: '/file.txt',
              size: 100,
              modTime: now,
              isDir: false,
              owner: '',
            ),
            isSelected: false,
            onTap: () {},
            onCtrlTap: () {},
            onDoubleTap: () {},
            onContextMenu: (_) {},
          ),
        ),
      );
      // No owner text rendered
      expect(find.text('root'), findsNothing);
    });

    testWidgets('onCtrlTap callback fires when Ctrl is held', (tester) async {
      var ctrlTapped = false;
      var normalTapped = false;
      await tester.pumpWidget(
        buildApp(
          FileRow(
            entry: FileEntry(
              name: 'ctrl.txt',
              path: '/ctrl.txt',
              size: 0,
              modTime: now,
              isDir: false,
            ),
            isSelected: false,
            onTap: () => normalTapped = true,
            onCtrlTap: () => ctrlTapped = true,
            onDoubleTap: () {},
            onContextMenu: (_) {},
          ),
        ),
      );

      // Hold Ctrl, then tap
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlRight);
      await tester.tap(find.text('ctrl.txt'));
      // GestureDetector with onDoubleTap delays onTap until double-tap timeout expires
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlRight);

      expect(ctrlTapped, isTrue);
      expect(normalTapped, isFalse);
    });

    testWidgets('onTap callback fires', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        buildApp(
          FileRow(
            entry: FileEntry(
              name: 'click.txt',
              path: '/click.txt',
              size: 0,
              modTime: now,
              isDir: false,
            ),
            isSelected: false,
            onTap: () => tapped = true,
            onCtrlTap: () {},
            onDoubleTap: () {},
            onContextMenu: (_) {},
          ),
        ),
      );
      await tester.tap(find.text('click.txt'));
      // GestureDetector with onDoubleTap delays onTap until double-tap timeout expires
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('onDoubleTap callback fires', (tester) async {
      var doubleTapped = false;
      await tester.pumpWidget(
        buildApp(
          FileRow(
            entry: FileEntry(
              name: 'dblclick.txt',
              path: '/dblclick.txt',
              size: 0,
              modTime: now,
              isDir: false,
            ),
            isSelected: false,
            onTap: () {},
            onCtrlTap: () {},
            onDoubleTap: () => doubleTapped = true,
            onContextMenu: (_) {},
          ),
        ),
      );
      // Double tap on the InkWell
      await tester.tap(find.text('dblclick.txt'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('dblclick.txt'));
      await tester.pumpAndSettle();
      expect(doubleTapped, isTrue);
    });

    testWidgets('columns use ellipsis overflow', (tester) async {
      await tester.pumpWidget(
        buildApp(
          FileRow(
            entry: FileEntry(
              name: 'file.txt',
              path: '/file.txt',
              size: 1048576,
              mode: 0x1FF, // rwxrwxrwx
              modTime: now,
              isDir: false,
              owner: 'longownername',
            ),
            isSelected: false,
            sizeWidth: 55,
            modifiedWidth: 105,
            modeWidth: 65,
            ownerWidth: 50,
            onTap: () {},
            onCtrlTap: () {},
            onDoubleTap: () {},
            onContextMenu: (_) {},
          ),
        ),
      );
      // All column Text widgets should have ellipsis overflow
      final texts = tester.widgetList<Text>(find.byType(Text));
      final ellipsisTexts = texts.where(
        (t) => t.overflow == TextOverflow.ellipsis,
      );
      // name(1) + size(1) + modified(1) + mode(1) + owner(1) = 5
      expect(ellipsisTexts.length, 5);
    });

    testWidgets('row container uses Clip.hardEdge', (tester) async {
      await tester.pumpWidget(
        buildApp(
          FileRow(
            entry: FileEntry(
              name: 'file.txt',
              path: '/file.txt',
              size: 1024,
              mode: 0x1A4,
              modTime: now,
              isDir: false,
            ),
            isSelected: false,
            sizeWidth: 55,
            modifiedWidth: 105,
            modeWidth: 65,
            ownerWidth: 50,
            onTap: () {},
            onCtrlTap: () {},
            onDoubleTap: () {},
            onContextMenu: (_) {},
          ),
        ),
      );
      final containers = tester.widgetList<Container>(find.byType(Container));
      final clipped = containers.where((c) => c.clipBehavior == Clip.hardEdge);
      expect(clipped, isNotEmpty, reason: 'FileRow should clip overflow');
    });

    testWidgets('name column has Tooltip', (tester) async {
      await tester.pumpWidget(
        buildApp(
          FileRow(
            entry: FileEntry(
              name: 'very_long_filename_that_overflows.txt',
              path: '/very_long_filename_that_overflows.txt',
              size: 1024,
              mode: 0x1A4,
              modTime: now,
              isDir: false,
            ),
            isSelected: false,
            sizeWidth: 55,
            modifiedWidth: 105,
            modeWidth: 0,
            ownerWidth: 0,
            onTap: () {},
            onCtrlTap: () {},
            onDoubleTap: () {},
            onContextMenu: (_) {},
          ),
        ),
      );
      expect(
        find.byTooltip('very_long_filename_that_overflows.txt'),
        findsOneWidget,
      );
    });

    testWidgets('columns hidden when width is zero', (tester) async {
      await tester.pumpWidget(
        buildApp(
          FileRow(
            entry: FileEntry(
              name: 'file.txt',
              path: '/file.txt',
              size: 1024,
              mode: 0x1A4,
              modTime: now,
              isDir: false,
            ),
            isSelected: false,
            sizeWidth: 0,
            modifiedWidth: 0,
            modeWidth: 0,
            ownerWidth: 0,
            onTap: () {},
            onCtrlTap: () {},
            onDoubleTap: () {},
            onContextMenu: (_) {},
          ),
        ),
      );
      // Only the name text should be present
      expect(find.text('file.txt'), findsOneWidget);
      // Size, mode texts should not appear
      expect(find.text('1.0 KB'), findsNothing);
    });

    testWidgets('selected row has highlighted background', (tester) async {
      await tester.pumpWidget(
        buildApp(
          FileRow(
            entry: FileEntry(
              name: 'selected.txt',
              path: '/selected.txt',
              size: 0,
              modTime: now,
              isDir: false,
            ),
            isSelected: true,
            onTap: () {},
            onCtrlTap: () {},
            onDoubleTap: () {},
            onContextMenu: (_) {},
          ),
        ),
      );
      // The Container has a non-null color when selected
      final containers = tester.widgetList<Container>(find.byType(Container));
      final hasColoredContainer = containers.any((c) => c.color != null);
      expect(hasColoredContainer, isTrue);
    });
  });

  group('MenuRow', () {
    testWidgets('renders icon and text', (tester) async {
      await tester.pumpWidget(
        buildApp(const MenuRow(icon: Icons.delete, text: 'Delete')),
      );
      expect(find.byIcon(Icons.delete), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });
  });

  group('MarqueePainter', () {
    test('shouldRepaint returns true when start changes', () {
      final p1 = MarqueePainter(
        start: const Offset(0, 0),
        end: const Offset(100, 100),
        color: Colors.blue,
      );
      final p2 = MarqueePainter(
        start: const Offset(10, 0),
        end: const Offset(100, 100),
        color: Colors.blue,
      );
      expect(p1.shouldRepaint(p2), isTrue);
    });

    test('shouldRepaint returns true when end changes', () {
      final p1 = MarqueePainter(
        start: const Offset(0, 0),
        end: const Offset(100, 100),
        color: Colors.blue,
      );
      final p2 = MarqueePainter(
        start: const Offset(0, 0),
        end: const Offset(200, 200),
        color: Colors.blue,
      );
      expect(p1.shouldRepaint(p2), isTrue);
    });

    test('shouldRepaint returns false when same', () {
      final p1 = MarqueePainter(
        start: const Offset(0, 0),
        end: const Offset(100, 100),
        color: Colors.blue,
      );
      final p2 = MarqueePainter(
        start: const Offset(0, 0),
        end: const Offset(100, 100),
        color: Colors.red, // color change doesn't matter
      );
      expect(p1.shouldRepaint(p2), isFalse);
    });
  });

  group('PaneDragData', () {
    test('stores source pane id and entries', () {
      final entries = [
        FileEntry(
          name: 'a.txt',
          path: '/a.txt',
          size: 100,
          modTime: now,
          isDir: false,
        ),
      ];
      const data = PaneDragData(sourcePaneId: 'left', entries: []);
      expect(data.sourcePaneId, 'left');

      final dataWithEntries = PaneDragData(
        sourcePaneId: 'right',
        entries: entries,
      );
      expect(dataWithEntries.entries.length, 1);
      expect(dataWithEntries.entries.first.name, 'a.txt');
    });
  });
}
