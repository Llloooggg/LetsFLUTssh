import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the lock-screen keyboard-isolation contract wired in
/// `main_app.dart`: while locked, the workspace subtree is wrapped in
/// `ExcludeFocus(excluding: locked)` so its focus nodes (the terminal
/// pane's key handler, which forwards to the LIVE SSH shell) cannot
/// hold focus and cannot receive keystrokes. The opaque LockScreen
/// overlay only blocks the pointer; without this, keys typed at a
/// locked machine reached the authenticated remote shell.
///
/// The test reproduces the `Stack` shape main_app builds (workspace
/// child wrapped in `ExcludeFocus` + `IgnorePointer`, lock overlay on
/// top) rather than booting the full app builder, which needs the
/// FRB bootstrap + provider graph.
void main() {
  testWidgets('locked workspace cannot hold focus or receive keys', (
    tester,
  ) async {
    final keysSeen = <LogicalKeyboardKey>[];
    final workspaceFocus = FocusNode(debugLabel: 'workspace');
    var locked = false;
    late void Function(bool) setLocked;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setLocked = (v) => setState(() => locked = v);
            return Stack(
              children: [
                ExcludeFocus(
                  excluding: locked,
                  child: IgnorePointer(
                    ignoring: locked,
                    child: Focus(
                      focusNode: workspaceFocus,
                      onKeyEvent: (_, event) {
                        keysSeen.add(event.logicalKey);
                        return KeyEventResult.handled;
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                if (locked)
                  const Positioned.fill(
                    child: ColoredBox(color: Color(0xFF000000)),
                  ),
              ],
            );
          },
        ),
      ),
    );

    // Unlocked: the workspace holds focus and receives keystrokes —
    // the normal terminal-input path.
    workspaceFocus.requestFocus();
    await tester.pump();
    expect(workspaceFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    expect(keysSeen, isNotEmpty);

    // Lock: ExcludeFocus must drop the workspace's focus immediately
    // and no subsequent keystroke may reach its handler.
    keysSeen.clear();
    setLocked(true);
    await tester.pump();
    expect(
      workspaceFocus.hasFocus,
      isFalse,
      reason: 'ExcludeFocus must unfocus the workspace when locked',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    expect(
      keysSeen,
      isEmpty,
      reason: 'no keystroke may reach the workspace while locked',
    );

    workspaceFocus.dispose();
  });
}
