/// Coverage for [SecureScreenScope] — the wrapper that opts a subtree
/// into Android `FLAG_SECURE`.
///
/// Real `setSecure` channel calls only fire on Android; on every
/// other platform the wrapper is a transparent pass-through. What
/// we assert here is the pass-through invariant: the child renders,
/// mounting + unmounting does not throw, and (Android-specific
/// FLAG_SECURE plumbing aside) nothing about the widget tree
/// changes shape on Linux / macOS / Windows.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/widgets/security/secure_screen_scope.dart';

void main() {
  group('SecureScreenScope', () {
    testWidgets('renders the child verbatim', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SecureScreenScope(child: Text('payload'))),
        ),
      );
      expect(find.text('payload'), findsOneWidget);
    });

    testWidgets('mounting + unmounting does not throw on non-Android', (
      tester,
    ) async {
      if (Platform.isAndroid) {
        markTestSkipped('Android FLAG_SECURE channel — device QA only');
        return;
      }
      // Mount.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecureScreenScope(child: SizedBox(width: 1, height: 1)),
          ),
        ),
      );
      // Replace with a different tree to force the SecureScreenScope
      // dispose path; the `_setSecure(false)` channel call is a
      // no-op on non-Android, so the dispose chain finishes
      // without surfacing a `MissingPluginException`.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    });

    testWidgets('nested scopes both render their children', (tester) async {
      // Production wires nested scopes (e.g. an unlock dialog inside
      // the wizard); the Android side keeps a refcount, but on
      // non-Android both layers should still render their children
      // unchanged.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SecureScreenScope(
              child: SecureScreenScope(child: Text('inner')),
            ),
          ),
        ),
      );
      expect(find.text('inner'), findsOneWidget);
    });
  });
}
