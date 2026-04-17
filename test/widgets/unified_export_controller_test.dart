import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/snippets/snippet.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/tags/tag.dart';
import 'package:letsflutssh/widgets/unified_export_controller.dart';
import 'package:letsflutssh/widgets/unified_export_dialog.dart';

/// Pure-logic tests for [UnifiedExportController]. No widget tree —
/// driving the controller directly exercises the selection / option /
/// preset / cache-invalidation rules that the dialog's build() relies
/// on. Widget-level UI tests live in unified_export_dialog_test.dart.

Session _s(
  String id,
  String label, {
  String folder = '',
  String password = '',
  AuthType authType = AuthType.password,
  String keyData = '',
  String keyId = '',
}) => Session(
  id: id,
  label: label,
  folder: folder,
  server: ServerAddress(host: '$label.com', user: 'u'),
  auth: SessionAuth(
    authType: authType,
    password: password,
    keyData: keyData,
    keyId: keyId,
  ),
);

UnifiedExportController _ctrl({
  List<Session> sessions = const [],
  Set<String> emptyFolders = const {},
  AppConfig? config,
  String? knownHostsContent,
  Map<String, String> managerKeys = const {},
  List<Tag> tags = const [],
  List<Snippet> snippets = const [],
  bool isQrMode = false,
}) {
  return UnifiedExportController(
    data: UnifiedExportDialogData(
      sessions: sessions,
      emptyFolders: emptyFolders,
      config: config,
      knownHostsContent: knownHostsContent,
      managerKeys: managerKeys,
      tags: tags,
      snippets: snippets,
    ),
    isQrMode: isQrMode,
  );
}

void main() {
  group('UnifiedExportController — initial state', () {
    test('QR mode initial options mirror "Sessions only" without keys', () {
      final c = _ctrl(sessions: [_s('1', 'A')], isQrMode: true);
      expect(c.options.includeSessions, isTrue);
      expect(c.options.includePasswords, isTrue);
      expect(c.options.includeTags, isTrue);
      expect(c.options.includeSnippets, isTrue);
      // Keys OFF — they drive QR payload growth.
      expect(c.options.includeEmbeddedKeys, isFalse);
      expect(c.options.includeManagerKeys, isFalse);
      expect(c.options.includeAllManagerKeys, isFalse);
      // Global-scope flags OFF in QR mode.
      expect(c.options.includeConfig, isFalse);
      expect(c.options.includeKnownHosts, isFalse);
    });

    test('LFS mode initial options carry every flag', () {
      final c = _ctrl(sessions: [_s('1', 'A')], isQrMode: false);
      expect(c.options.includeConfig, isTrue);
      expect(c.options.includePasswords, isTrue);
      expect(c.options.includeEmbeddedKeys, isTrue);
      expect(c.options.includeAllManagerKeys, isTrue);
      expect(c.options.includeKnownHosts, isTrue);
      expect(c.options.includeTags, isTrue);
      expect(c.options.includeSnippets, isTrue);
    });

    test('every session starts selected', () {
      final c = _ctrl(sessions: [_s('1', 'A'), _s('2', 'B'), _s('3', 'C')]);
      expect(c.selectedIds, {'1', '2', '3'});
      expect(c.allSelected, isTrue);
    });
  });

  group('UnifiedExportController — selection mutations', () {
    test('toggleSession adds / removes ids and notifies', () {
      final c = _ctrl(sessions: [_s('1', 'A'), _s('2', 'B')]);
      var notifications = 0;
      c.addListener(() => notifications++);

      c.toggleSession('1');
      expect(c.selectedIds, {'2'});
      c.toggleSession('1');
      expect(c.selectedIds, {'1', '2'});
      expect(notifications, 2);
    });

    test(
      'toggleAll(false) clears, toggleAll(true) re-selects every session',
      () {
        final c = _ctrl(sessions: [_s('1', 'A'), _s('2', 'B')]);
        c.toggleAll(false);
        expect(c.selectedIds, isEmpty);
        expect(c.allSelected, isFalse);
        c.toggleAll(true);
        expect(c.selectedIds, {'1', '2'});
      },
    );

    test('toggleFolder toggles every session in / under that folder', () {
      final sessions = [
        _s('1', 'A', folder: 'prod'),
        _s('2', 'B', folder: 'prod/web'),
        _s('3', 'C', folder: 'stg'),
      ];
      final c = _ctrl(sessions: sessions);
      c.toggleAll(false);

      c.toggleFolder('prod');
      expect(c.selectedIds, {
        '1',
        '2',
      }, reason: 'prod + every prod/* descendant');

      c.toggleFolder('prod');
      expect(
        c.selectedIds,
        isEmpty,
        reason: 'tap again when all are selected → deselect',
      );
    });

    test('tristate is true / null / false as selection count changes', () {
      final c = _ctrl(sessions: [_s('1', 'A'), _s('2', 'B')]);
      expect(c.tristateValue, isTrue);

      c.toggleSession('1');
      expect(
        c.tristateValue,
        isNull,
        reason: 'partial selection must show indeterminate state',
      );

      c.toggleSession('2');
      expect(c.tristateValue, isFalse);
    });
  });

  group('UnifiedExportController — presets', () {
    test('fresh LFS controller reports activePreset = fullBackup', () {
      final c = _ctrl(sessions: [_s('1', 'A')], isQrMode: false);
      expect(c.activePreset, ExportPreset.fullBackup);
    });

    test(
      'applyFullBackupPreset flips every flag and re-selects every session',
      () {
        final c = _ctrl(sessions: [_s('1', 'A'), _s('2', 'B')], isQrMode: true);
        c.toggleAll(false);
        c.applyFullBackupPreset();

        expect(c.selectedIds, {'1', '2'});
        expect(c.options.includeSessions, isTrue);
        expect(c.options.includeConfig, isTrue);
        expect(c.options.includeKnownHosts, isTrue);
        expect(c.options.includeAllManagerKeys, isTrue);
        expect(c.activePreset, ExportPreset.fullBackup);
      },
    );

    test(
      'applySessionsPreset drops global-scope flags but keeps session-scoped',
      () {
        final c = _ctrl(sessions: [_s('1', 'A')], isQrMode: false);
        c.applySessionsPreset();

        expect(c.options.includeConfig, isFalse);
        expect(c.options.includeKnownHosts, isFalse);
        expect(c.options.includeAllManagerKeys, isFalse);
        expect(c.options.includePasswords, isTrue);
        expect(c.options.includeManagerKeys, isTrue);
        expect(c.options.includeTags, isTrue);
        expect(c.options.includeSnippets, isTrue);
        expect(c.activePreset, ExportPreset.sessions);
      },
    );

    test('deselecting any session drops the active preset to custom', () {
      // A preset is "full" only if every session is selected. Removing
      // even one session means the export is no longer a complete
      // preset — the chip must stop claiming otherwise.
      final c = _ctrl(sessions: [_s('1', 'A'), _s('2', 'B')]);
      expect(c.activePreset, ExportPreset.fullBackup);
      c.toggleSession('1');
      expect(c.activePreset, ExportPreset.custom);
    });
  });

  group('UnifiedExportController — mutually-exclusive key flags', () {
    test('setIncludeAllManagerKeys(true) clears includeManagerKeys', () {
      // Spec: the two key-scope flags are mutually exclusive —
      // otherwise the archive would double-encode the subset of keys
      // referenced by sessions.
      final c = _ctrl(sessions: [_s('1', 'A')], isQrMode: true);
      c.setIncludeManagerKeys(true);
      expect(c.options.includeManagerKeys, isTrue);

      c.setIncludeAllManagerKeys(true);
      expect(c.options.includeAllManagerKeys, isTrue);
      expect(c.options.includeManagerKeys, isFalse);
    });

    test('setIncludeManagerKeys(true) clears includeAllManagerKeys', () {
      final c = _ctrl(sessions: [_s('1', 'A')], isQrMode: false);
      expect(c.options.includeAllManagerKeys, isTrue);
      c.setIncludeManagerKeys(true);
      expect(c.options.includeManagerKeys, isTrue);
      expect(c.options.includeAllManagerKeys, isFalse);
    });
  });

  group('UnifiedExportController — QR warnings', () {
    test('QR warnings fire only in QR mode with the matching flag on', () {
      final qr = _ctrl(sessions: [_s('1', 'A')], isQrMode: true);
      qr.setIncludeEmbeddedKeys(true);
      expect(qr.showEmbeddedKeysWarning, isTrue);
      qr.setIncludeManagerKeys(true);
      expect(qr.showManagerKeysWarning, isTrue);

      final lfs = _ctrl(sessions: [_s('1', 'A')], isQrMode: false);
      expect(
        lfs.showEmbeddedKeysWarning,
        isFalse,
        reason: '.lfs archive has no payload ceiling — no warning needed',
      );
    });
  });

  group('UnifiedExportController — relevantEmptyFolders', () {
    test(
      'selected-session folders pull their ancestor paths into the export',
      () {
        // Spec: every ancestor of a selected session's folder must land
        // in emptyFolders so the receiving side can reconstruct the
        // hierarchy even if intermediate folders have no sessions of
        // their own in the export.
        final c = _ctrl(
          sessions: [_s('1', 'A', folder: 'a/b/c')],
          emptyFolders: const {},
        );
        expect(c.relevantEmptyFolders, {'a', 'a/b'});
      },
    );

    test(
      'source-set folders included when any selected session lives inside',
      () {
        // Use 2 sessions with partial selection so the "all sessions
        // selected" short-circuit (which unconditionally includes every
        // empty folder) does NOT fire. Otherwise the "stg is skipped"
        // branch is unreachable.
        final c = _ctrl(
          sessions: [
            _s('1', 'A', folder: 'prod/web'),
            _s('2', 'B', folder: 'prod/web'),
          ],
          emptyFolders: const {'prod', 'stg'},
        );
        c.toggleSession('2');
        final result = c.relevantEmptyFolders;
        expect(
          result,
          containsAll(['prod']),
          reason: 'prod is an ancestor of a selected session',
        );
        expect(
          result.contains('stg'),
          isFalse,
          reason: 'stg has no selected session inside → skip',
        );
      },
    );

    test('every source-set folder included when every session is selected', () {
      // Rationale: "export everything" should carry the full hierarchy
      // even if specific folders happen to be empty — otherwise a
      // round-trip loses structure.
      final c = _ctrl(
        sessions: [_s('1', 'A', folder: 'prod/web')],
        emptyFolders: const {'prod', 'stg', 'archive'},
      );
      expect(c.relevantEmptyFolders, {'prod', 'stg', 'archive'});
    });
  });

  group('UnifiedExportController — isFolderPartial', () {
    test('returns true / false / null based on selection coverage', () {
      final c = _ctrl(
        sessions: [
          _s('1', 'A', folder: 'prod'),
          _s('2', 'B', folder: 'prod'),
        ],
      );
      expect(c.isFolderPartial('prod'), isTrue);
      c.toggleSession('1');
      expect(c.isFolderPartial('prod'), isNull);
      c.toggleSession('2');
      expect(c.isFolderPartial('prod'), isFalse);
    });

    test('unknown / empty folder returns false, not null', () {
      final c = _ctrl(sessions: [_s('1', 'A')]);
      expect(c.isFolderPartial('nonexistent'), isFalse);
    });
  });

  group('UnifiedExportController — buildResult', () {
    test('buildResult snapshots current options + selection', () {
      final c = _ctrl(sessions: [_s('1', 'A'), _s('2', 'B')], isQrMode: false);
      c.toggleSession('1');
      c.setIncludePasswords(false);

      final r = c.buildResult();
      expect(r.selectedSessions.map((s) => s.id), ['2']);
      expect(r.options.includePasswords, isFalse);
    });
  });

  group('UnifiedExportController — cache invalidation', () {
    test('payload size cache invalidates on selection change', () {
      // The cached-size fields are a common source of stale-data bugs.
      // We verify the contract: after mutation, the next payloadSize
      // read must reflect the new selection — not the prior value.
      final c = _ctrl(sessions: [_s('1', 'A'), _s('2', 'B')], isQrMode: false);
      final before = c.payloadSize;
      c.toggleAll(false);
      final after = c.payloadSize;
      expect(
        after,
        isNot(before),
        reason:
            'dropping every session must change the archive size — '
            'stale cache would return the original value',
      );
    });

    test('payload size cache invalidates on option flip', () {
      // QR mode — the payload is deflate+base64 with no archive
      // framing, so a single credential-flag flip produces a
      // deterministic size delta. LFS mode has ZIP + AES-GCM padding
      // that can mask a tiny credential's contribution.
      final c = _ctrl(
        sessions: [
          _s('1', 'A', password: 'some-reasonably-long-secret-password'),
        ],
        isQrMode: true,
      );
      final before = c.payloadSize;
      c.setIncludePasswords(false);
      final after = c.payloadSize;
      expect(
        after,
        isNot(before),
        reason:
            'dropping a credential must shrink the payload — stale '
            'cache would keep the inflated size',
      );
    });
  });

  group('UnifiedExportController — formatSize', () {
    test('formats sub-kilobyte as bytes, otherwise KB with one decimal', () {
      expect(UnifiedExportController.formatSize(0), '0 B');
      expect(UnifiedExportController.formatSize(512), '512 B');
      expect(UnifiedExportController.formatSize(1024), '1.0 KB');
      expect(UnifiedExportController.formatSize(1536), '1.5 KB');
    });
  });
}
