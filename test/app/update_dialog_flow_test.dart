import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/app/update_dialog_flow.dart';
import 'package:letsflutssh/core/update/update_service.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/config_provider.dart';
import 'package:letsflutssh/providers/update_provider.dart';
import 'package:letsflutssh/utils/platform.dart' as plat;
import 'package:letsflutssh/widgets/terminal/update_progress_indicator.dart';

import '../helpers/test_notifiers.dart';

/// Test harness app that mounts a single button which opens
/// `showUpdateDialog` against the supplied [info]. Wrapped in a
/// [ProviderScope] with stubbed `configProvider` + a
/// [PrePopulatedUpdateNotifier] so the dialog's `Consumer` reads the
/// per-test [UpdateState] without an FRB-backed notifier.
Widget _buildDialogHost({
  required UpdateInfo info,
  UpdateState initial = const UpdateState(),
}) {
  return ProviderScope(
    overrides: [
      configProvider.overrideWith(TestConfigNotifier.new),
      updateProvider.overrideWith(() => PrePopulatedUpdateNotifier(initial)),
    ],
    child: MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      home: Scaffold(
        body: Consumer(
          builder: (ctx, ref, _) => ElevatedButton(
            onPressed: () =>
                showUpdateDialog(context: ctx, ref: ref, info: info),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

UpdateInfo _info({
  String latestVersion = '2.0.0',
  String currentVersion = '1.0.0',
  String releaseUrl = 'https://github.com/test/releases/tag/v2.0.0',
  String? assetUrl,
  String? changelog,
}) => UpdateInfo(
  latestVersion: latestVersion,
  currentVersion: currentVersion,
  releaseUrl: releaseUrl,
  assetUrl: assetUrl,
  changelog: changelog,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    plat.debugDesktopPlatformOverride = true;
    plat.debugMobilePlatformOverride = false;
  });

  tearDown(() {
    plat.debugDesktopPlatformOverride = null;
    plat.debugMobilePlatformOverride = null;
  });

  group('showUpdateDialog — idle / update-available state', () {
    testWidgets('renders title, version line and changelog when present', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildDialogHost(
          info: _info(changelog: 'Sample release notes for this build'),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Title — localized "Update Available".
      expect(find.text('Update Available'), findsOneWidget);
      // Version-available template — embeds latest + current numbers.
      expect(find.textContaining('2.0.0'), findsWidgets);
      expect(find.textContaining('1.0.0'), findsWidgets);
      // Release notes heading + body.
      expect(find.text('Release notes:'), findsOneWidget);
      expect(find.text('Sample release notes for this build'), findsOneWidget);
    });

    testWidgets(
      'no asset URL on desktop renders Open-in-Browser primary action',
      (tester) async {
        // Spec: when `info.assetUrl == null` the dialog cannot offer the
        // in-app install path and must surface `openInBrowser` as the
        // primary action — pairing the user with the GitHub release page.
        await tester.pumpWidget(_buildDialogHost(info: _info()));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.text('Open in Browser'), findsOneWidget);
        expect(find.text('Download & Install'), findsNothing);
      },
    );

    testWidgets(
      'assetUrl present on desktop renders Download & Install primary action',
      (tester) async {
        // Spec: `hasAsset` is `info.assetUrl != null && isDesktopPlatform`.
        // The primary CTA flips from "Open in Browser" to "Download &
        // Install" so a tap kicks off the FRB downloader inline rather
        // than handing the user off to a browser.
        await tester.pumpWidget(
          _buildDialogHost(
            info: _info(
              assetUrl:
                  'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v2.0.0/x.AppImage',
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.text('Download & Install'), findsOneWidget);
        expect(find.text('Open in Browser'), findsNothing);
      },
    );

    testWidgets('Skip This Version button is rendered in the idle footer', (
      tester,
    ) async {
      // The skip action sits alongside Cancel + the primary CTA in
      // the idle footer. The dialog wires it to `configProvider`'s
      // `skippedVersion` field; here we assert the affordance is
      // surfaced — the config plumbing is tested elsewhere through
      // `main_test.dart`.
      await tester.pumpWidget(_buildDialogHost(info: _info()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Skip This Version'), findsOneWidget);
    });

    testWidgets('mobile platform suppresses the Download & Install path', (
      tester,
    ) async {
      // Spec: `hasAsset` requires `isDesktopPlatform`. On mobile, even
      // with an asset URL present, the dialog must fall back to
      // "Open in Browser" because the mobile self-update path is not
      // wired (no installer launcher, browser hand-off only).
      plat.debugDesktopPlatformOverride = false;
      plat.debugMobilePlatformOverride = true;

      await tester.pumpWidget(
        _buildDialogHost(
          info: _info(
            assetUrl:
                'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v2.0.0/x.apk',
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Open in Browser'), findsOneWidget);
      expect(find.text('Download & Install'), findsNothing);
    });
  });

  group('showUpdateDialog — error state', () {
    testWidgets('error footer renders Cancel + Retry, no Skip', (tester) async {
      // Spec: when `updateProvider` flips to `UpdateStatus.error` the
      // footer collapses to Cancel + Retry. The Skip-This-Version /
      // primary actions vanish because the user has no resolved
      // version to skip / install at that point.
      await tester.pumpWidget(
        _buildDialogHost(
          info: _info(),
          initial: const UpdateState(
            status: UpdateStatus.error,
            error: 'network error',
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Retry'), findsOneWidget);
      // Cancel is auto-localized inside AppButton.cancel — string check
      // via the en arb.
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Skip This Version'), findsNothing);
      expect(find.text('Download & Install'), findsNothing);
      expect(find.text('Open in Browser'), findsNothing);
    });

    testWidgets(
      'error state with state.error == null surfaces the generic "Update '
      'check failed" caption',
      (tester) async {
        // Spec: the error body falls back to `S.of(ctx).updateCheckFailed`
        // when `state.error` is null — guards against an error transition
        // that loses the diagnostic detail (e.g. a future refactor that
        // forgets to thread the exception into `state.error`).
        await tester.pumpWidget(
          _buildDialogHost(
            info: _info(),
            initial: const UpdateState(status: UpdateStatus.error),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.text('Update check failed'), findsOneWidget);
      },
    );
  });

  group('showUpdateDialog — in-flight (downloading) state', () {
    testWidgets(
      'downloading state hides the action footer and shows the progress '
      'indicator',
      (tester) async {
        // Spec: while bytes are streaming, the actions list collapses to
        // empty so the user cannot start a second download or skip the
        // version mid-flight. The body swaps to UpdateProgressIndicator.
        await tester.pumpWidget(
          _buildDialogHost(
            info: _info(),
            initial: const UpdateState(
              status: UpdateStatus.downloading,
              progress: 0.42,
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.byType(UpdateProgressIndicator), findsOneWidget);
        // Footer collapsed: no Cancel / Skip / primary actions.
        expect(find.text('Cancel'), findsNothing);
        expect(find.text('Skip This Version'), findsNothing);
        expect(find.text('Download & Install'), findsNothing);
        expect(find.text('Retry'), findsNothing);
      },
    );

    testWidgets(
      'downloaded state keeps Cancel/Skip/primary footer (post-bytes terminal '
      'arm)',
      (tester) async {
        // Spec: `downloaded` is treated as a non-in-flight terminal
        // success — the actions list still renders so the user can
        // skip / launch the installer / dismiss. Only `downloading`
        // collapses the footer.
        await tester.pumpWidget(
          _buildDialogHost(
            info: _info(
              assetUrl:
                  'https://github.com/Llloooggg/LetsFLUTssh/releases/download/v2.0.0/x.AppImage',
            ),
            initial: const UpdateState(
              status: UpdateStatus.downloaded,
              progress: 1,
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // Footer is back — and asset present so the primary CTA is the
        // Download & Install affordance (idle/default arm).
        expect(find.text('Download & Install'), findsOneWidget);
        expect(find.text('Skip This Version'), findsOneWidget);
        // The progress indicator is also painted because `inFlight`
        // includes `downloaded` for body purposes.
        expect(find.byType(UpdateProgressIndicator), findsOneWidget);
      },
    );
  });

  // Deferred — Skip This Version button writes skippedVersion through
  // configProvider: the ConfigNotifier debounce path schedules a Rust-
  // store actor that doesn't drain in the pump budget. The in-memory
  // assertion is exercised by configProvider unit tests directly.

  // ── Browser-launch fallback path ───────────────────────────────────────

  // The "browser launchUrl returned false" branch in
  // `_buildPrimaryUpdateAction` (clipboard copy + "Could not open
  // browser" toast) cannot be exercised at unit-test scope because
  // it routes through the real `url_launcher` plugin and the toast
  // surface mounts via `navigatorKey.currentContext`.
  // covered by integration: routes through `url_launcher` plugin
  // channel + global navigator-key Overlay lookup.

  // ── Retry button tap on error state ────────────────────────────────────

  // The Retry button calls `ref.read(updateProvider.notifier).download()`
  // which goes through the real `UpdateService` — FRB-deep download
  // pipeline, not exercisable from a unit test without spinning up the
  // bus subscription and the FRB downloader override pair.
  // covered by integration: download() path requires FRB + bus.
}
