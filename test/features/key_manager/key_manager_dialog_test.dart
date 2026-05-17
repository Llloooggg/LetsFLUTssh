import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/security/ssh_key.dart';
import 'package:letsflutssh/features/key_manager/key_manager_dialog.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/providers/key_provider.dart';
import 'package:letsflutssh/theme/app_theme.dart';
import 'package:letsflutssh/widgets/hardware_key_badge.dart';
import 'package:letsflutssh/widgets/toast.dart';

import '../../helpers/frb_bootstrap.dart';

/// Minimal [SshKeysMutator] test double — returns the seeded
/// metadata on every `loadAllMetadata` so the dialog can hydrate
/// its row list without booting FRB / the rusqlite DB.
class _StubKeysMutator extends SshKeysMutator {
  _StubKeysMutator(this._rows);

  final List<SshKeyMetadata> _rows;

  @override
  Future<Map<String, SshKeyMetadata>> loadAllMetadata() async {
    return {for (final r in _rows) r.id: r};
  }
}

SshKeyMetadata _meta({
  required String id,
  required String label,
  String keyType = 'ssh-ed25519',
  String backend = 'software',
  bool importedAsStub = false,
}) => SshKeyMetadata(
  id: id,
  label: label,
  publicKey: 'pub-$id',
  keyType: keyType,
  createdAt: DateTime(2024, 1, 1),
  isGenerated: false,
  privateFingerprint: 'priv-$id',
  publicFingerprint: 'pub-$id',
  backend: backend,
  importedAsStub: importedAsStub,
);

void main() {
  // Key row rendering routes the created_at timestamp through
  // `format.dart::formatDate`, which calls Rust over FRB. The widget
  // tests need the Rust library bootstrapped before pumping.
  setUpAll(() async {
    await requireFrbLoaded();
  });

  // The dialog's toolbar opens a Scaffold + MaterialApp surface
  // whose system-overlay-style writes touch `flutter/platform`;
  // flutter_test does not stub that channel by default. Stub it so
  // any platform-method call drains cleanly in pumpAndSettle.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
  });

  tearDown(() {
    Toast.clearAllForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget buildApp({required List<SshKeyMetadata> seed}) {
    return ProviderScope(
      overrides: [
        sshKeysMutatorProvider.overrideWithValue(_StubKeysMutator(seed)),
      ],
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: SizedBox(height: 600, width: 800, child: KeyManagerPanel()),
        ),
      ),
    );
  }

  group('KeyManagerPanel row rendering', () {
    testWidgets('shows spinner before metadata resolves, then transitions to '
        'the row list', (tester) async {
      await tester.pumpWidget(
        buildApp(
          seed: [_meta(id: '1', label: 'Production')],
        ),
      );
      // The `_loadKeys` future has not resolved on the first frame.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Production'), findsOneWidget);
    });

    testWidgets(
      'FIDO2 sk-* row renders the HardwareKeyBadge from _KeyRowBadges',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(
                id: 'sk1',
                label: 'YubiKey 5',
                keyType: 'sk-ssh-ed25519@openssh.com',
                backend: 'fido2',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(HardwareKeyBadge), findsOneWidget);
      },
    );

    testWidgets('non-stub row exposes copy / delete actions; cert-add slot is '
        'present when no cert is attached', (tester) async {
      await tester.pumpWidget(
        buildApp(
          seed: [_meta(id: '1', label: 'Production')],
        ),
      );
      await tester.pumpAndSettle();
      // The action cluster lives inside `_KeyRowActions`; tooltip
      // strings (`S.of(context).publicKey` etc.) are the public
      // surface to assert against.
      expect(find.byTooltip('Public Key'), findsOneWidget);
      expect(find.byTooltip('Import certificate'), findsOneWidget);
      expect(find.byTooltip('Delete Key'), findsOneWidget);
      // Stub-only actions must not appear on a non-stub row.
      expect(find.byTooltip('Re-generate here'), findsNothing);
    });

    testWidgets(
      'stub row swaps the action set to [Re-generate, Remove] and hides the '
      'copy / cert affordances',
      (tester) async {
        await tester.pumpWidget(
          buildApp(
            seed: [
              _meta(
                id: 'stub1',
                label: 'Old laptop key',
                backend: 'enclave',
                importedAsStub: true,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        // Stub action cluster — `_KeyRowActions` branches on
        // `entry.importedAsStub` and renders the regenerate + remove
        // affordances instead of the copy / cert / delete trio.
        expect(find.byTooltip('Re-generate here'), findsOneWidget);
        expect(find.byTooltip('Remove stub'), findsOneWidget);
        expect(find.byTooltip('Public Key'), findsNothing);
        expect(find.byTooltip('Import certificate'), findsNothing);
      },
    );
  });
}
