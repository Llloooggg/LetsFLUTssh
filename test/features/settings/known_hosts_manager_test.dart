import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/features/settings/known_hosts_manager.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/known_hosts_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/core/app_empty_state.dart';
import 'package:letsflutssh/widgets/core/app_icon_button.dart';

import '../../helpers/frb_bootstrap.dart';

/// Fake mutator that records the calls the panel routes to it instead
/// of touching FRB. The panel owns no removal logic itself — it only
/// dispatches the confirmed `host:port` to the mutator — so asserting
/// the recorded args is the spec for the CRUD wiring.
class _FakeMutator extends KnownHostsMutator {
  const _FakeMutator(this.removed, this.clearedFlag);

  final List<String> removed;
  final List<bool> clearedFlag;

  @override
  Future<void> removeHost(String hostPort) async {
    removed.add(hostPort);
  }

  @override
  Future<void> clearAll() async {
    clearedFlag.add(true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The per-row fingerprint compute calls a sync FRB helper
  // (`sshFormatHostKeyFingerprint`). Loading the real lib lets the
  // entry rows render their fingerprint instead of the '?' fallback;
  // every other surface here is pure Dart.
  setUpAll(requireFrbLoaded);

  Widget wrap({
    required Map<String, String> entries,
    List<String>? removed,
    List<bool>? clearedFlag,
  }) {
    return ProviderScope(
      overrides: [
        knownHostsStreamProvider.overrideWith((_) => Stream.value(entries)),
        if (removed != null || clearedFlag != null)
          knownHostsMutatorProvider.overrideWithValue(
            _FakeMutator(removed ?? [], clearedFlag ?? []),
          ),
      ],
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: SizedBox(height: 600, child: KnownHostsManagerPanel()),
        ),
      ),
    );
  }

  const sample = {
    'github.com:22':
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl',
    'gitlab.com:2222': 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDjN9TZSpXz==',
  };

  group('KnownHostsManagerPanel — list rendering', () {
    testWidgets('empty store shows the empty-state message, no rows', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(entries: const {}));
      await tester.pumpAndSettle();
      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(
        find.text('No known hosts yet. Connect to a server to add one.'),
        findsOneWidget,
      );
    });

    testWidgets('renders one row per host entry with its host:port key', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(entries: sample));
      await tester.pumpAndSettle();
      expect(find.text('github.com:22'), findsOneWidget);
      expect(find.text('gitlab.com:2222'), findsOneWidget);
      expect(find.byType(AppEmptyState), findsNothing);
    });

    testWidgets('count label reflects the number of stored hosts', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(entries: sample));
      await tester.pumpAndSettle();
      // The plural form for 2 hosts.
      expect(find.text('2 known hosts'), findsOneWidget);
    });

    testWidgets('clear-all sweep action is hidden when the store is empty', (
      tester,
    ) async {
      // Action surfaces hide controls that can't do anything — with no
      // hosts there is nothing to clear, so the sweep button must not
      // appear.
      await tester.pumpWidget(wrap(entries: const {}));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.delete_sweep), findsNothing);
    });

    testWidgets('clear-all sweep action appears once the store has hosts', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(entries: sample));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.delete_sweep), findsOneWidget);
    });
  });

  group('KnownHostsManagerPanel — search filter', () {
    testWidgets('typing in the search box narrows the visible rows', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(entries: sample));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'gitlab');
      await tester.pumpAndSettle();

      expect(find.text('gitlab.com:2222'), findsOneWidget);
      expect(find.text('github.com:22'), findsNothing);
    });

    testWidgets('a filter matching nothing shows the zero-count empty state', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(entries: sample));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'no-such-host');
      await tester.pumpAndSettle();

      // Store is non-empty but the filtered view is empty → the
      // "No known hosts" (count 0) branch, not the first-run hint.
      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.text('No known hosts'), findsOneWidget);
    });
  });

  group('KnownHostsManagerPanel — CRUD wiring', () {
    testWidgets('confirming a single delete routes the host:port to mutator', (
      tester,
    ) async {
      final removed = <String>[];
      await tester.pumpWidget(wrap(entries: sample, removed: removed));
      await tester.pumpAndSettle();

      // Each row has a delete (trash) icon; tap the first.
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      // Confirm dialog uses the destructive "Delete" action.
      expect(find.text('Remove Host'), findsWidgets);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(removed, hasLength(1));
      // Sorted order puts github.com first.
      expect(removed.single, 'github.com:22');

      // Drain the success Toast's auto-dismiss timer so it doesn't
      // outlive the widget tree.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('cancelling a single delete leaves the mutator untouched', (
      tester,
    ) async {
      final removed = <String>[];
      await tester.pumpWidget(wrap(entries: sample, removed: removed));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(removed, isEmpty);
    });

    testWidgets('confirming clear-all routes a clearAll to the mutator', (
      tester,
    ) async {
      final cleared = <bool>[];
      await tester.pumpWidget(wrap(entries: sample, clearedFlag: cleared));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_sweep));
      await tester.pumpAndSettle();

      // The confirm dialog re-uses the "Clear All Known Hosts" label
      // for both title and the destructive action.
      await tester.tap(find.text('Clear All Known Hosts').last);
      await tester.pumpAndSettle();

      expect(cleared, [true]);

      // Drain the success Toast's auto-dismiss timer.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('copy action writes the fingerprint to the clipboard', (
      tester,
    ) async {
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      await tester.pumpWidget(wrap(entries: sample));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.content_copy).first);
      await tester.pumpAndSettle();

      // The row copies the computed fingerprint; with FRB loaded it is
      // the real `SHA256:…` shape, never the '?' parse-failure marker.
      expect(clipboardText, isNotNull);
      expect(clipboardText, startsWith('SHA256:'));

      // Drain the "copied" Toast's auto-dismiss timer.
      await tester.pump(const Duration(seconds: 4));
    });
  });

  group('KnownHostsManagerPanel — toolbar', () {
    testWidgets('exposes a clear-all icon button with its tooltip', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(entries: sample));
      await tester.pumpAndSettle();
      final sweep = tester.widgetList<AppIconButton>(
        find.byType(AppIconButton),
      );
      expect(sweep.any((b) => b.tooltip == 'Clear All Known Hosts'), isTrue);
    });
  });
}
