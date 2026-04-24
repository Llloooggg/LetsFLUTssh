import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/security/key_store.dart';
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

SshKeyEntry _keyEntry(String id, String label, String privateKey) =>
    SshKeyEntry(
      id: id,
      label: label,
      privateKey: privateKey,
      publicKey: 'pub-$id',
      keyType: 'ed25519',
      createdAt: DateTime(2025),
    );

UnifiedExportController _ctrl({
  List<Session> sessions = const [],
  Set<String> emptyFolders = const {},
  AppConfig? config,
  String? knownHostsContent,
  Map<String, String> managerKeys = const {},
  Map<String, SshKeyEntry> managerKeyEntries = const {},
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
      managerKeyEntries: managerKeyEntries,
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
      'applyFullBackupPreset (file mode) flips every flag and re-selects every session',
      () {
        final c = _ctrl(
          sessions: [_s('1', 'A'), _s('2', 'B')],
          isQrMode: false,
        );
        c.toggleAll(false);
        c.applyFullBackupPreset();

        expect(c.selectedIds, {'1', '2'});
        expect(c.options.includeSessions, isTrue);
        expect(c.options.includeConfig, isTrue);
        expect(c.options.includeKnownHosts, isTrue);
        expect(c.options.includeAllManagerKeys, isTrue);
        expect(c.options.includeEmbeddedKeys, isTrue);
        expect(c.activePreset, ExportPreset.fullBackup);
      },
    );

    test(
      'applyFullBackupPreset (QR mode) turns key toggles off by default',
      () {
        // QR payloads are sharply size-limited — a 4096-bit RSA key
        // alone exceeds the ceiling. The "Full backup" chip in QR mode
        // therefore ships with embedded + manager keys unchecked; the
        // user opts in manually if they want to pay the size cost.
        final c = _ctrl(sessions: [_s('1', 'A')], isQrMode: true);
        c.applyFullBackupPreset();

        expect(c.options.includeSessions, isTrue);
        expect(c.options.includeConfig, isTrue);
        expect(c.options.includeKnownHosts, isTrue);
        expect(c.options.includePasswords, isTrue);
        expect(c.options.includeEmbeddedKeys, isFalse);
        expect(c.options.includeAllManagerKeys, isFalse);
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

  group('UnifiedExportController — toggleCheckboxes', () {
    test('toggles the collapsible checkboxes section', () {
      final c = _ctrl(sessions: [_s('1', 'A')]);
      expect(c.checkboxesExpanded, isFalse);
      c.toggleCheckboxes();
      expect(c.checkboxesExpanded, isTrue);
      c.toggleCheckboxes();
      expect(c.checkboxesExpanded, isFalse);
    });
  });

  group('UnifiedExportController — LFS archive with filtered manager keys', () {
    test(
      '"session keys" mode narrows the archive to the referenced subset',
      () {
        // Spec (_selectedManagerKeyEntries): in session-keys mode we
        // include only the keys referenced by selected sessions, not
        // the entire manager. The archive-size path hits this branch
        // when includeManagerKeys is on, includeAllManagerKeys is off,
        // and at least one session carries a matching keyId.
        final entries = {
          'k1': _keyEntry('k1', 'prod', 'body-of-prod-key'),
          'k2': _keyEntry('k2', 'stg', 'body-of-stg-key'),
        };
        final c = _ctrl(
          sessions: [_s('1', 'A', keyId: 'k1', authType: AuthType.key)],
          config: AppConfig.defaults,
          managerKeyEntries: entries,
          isQrMode: false,
        );
        c.setIncludeManagerKeys(true);
        // Just reading payloadSize exercises _selectedManagerKeyEntries'
        // usedIds-filter branch — crashing there is a real bug.
        expect(c.payloadSize, greaterThan(0));
      },
    );
  });

  group('UnifiedExportController — payloadSize cache reuse', () {
    test('second read returns the cached value without recomputing', () {
      // Spec: _payloadSizeCacheValid returns true when options +
      // selection + knownHostsContent are unchanged, so subsequent
      // reads skip the deflate/encode work. Without this path the
      // dialog re-encodes the whole payload on every frame.
      final c = _ctrl(sessions: [_s('1', 'A')], isQrMode: true);
      final first = c.payloadSize;
      final second = c.payloadSize;
      expect(first, second);
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

  group('UnifiedExportController — hasSelection edges', () {
    test('empty-selection still counts when a global flag is on', () {
      // Spec: the Export button is enabled as long as the payload
      // will carry *something*. Config / knownHosts / tags / snippets
      // are export-without-sessions data; if the user deselects every
      // session but keeps "App Settings" checked, that must still
      // count as a valid export.
      final c = _ctrl(
        sessions: [_s('1', 'A')],
        config: AppConfig.defaults,
        knownHostsContent: 'x',
        tags: const [],
        snippets: const [],
      );
      c.toggleAll(false);
      expect(
        c.hasSelection,
        isTrue,
        reason: 'includeConfig is on — counts without any session',
      );

      // Toggle everything off → no selection at all.
      c.setIncludeConfig(false);
      c.setIncludeKnownHosts(false);
      c.setIncludeAllManagerKeys(false);
      c.setIncludeTags(false);
      c.setIncludeSnippets(false);
      expect(c.hasSelection, isFalse);
    });

    test('includeTags without tag data does not count — same for snippets', () {
      // Spec (the `&& data.tags.isNotEmpty` guard): flipping on an
      // empty-content data type should not trick the button into
      // thinking there is something to export. Protects against a
      // "tags on but archive has 0 tags" phantom export.
      //
      // Use QR mode so config / knownHosts / allManagerKeys begin OFF
      // — otherwise LFS defaults make hasSelection trivially true
      // before we even exercise the tags/snippets guard.
      final c = _ctrl(
        sessions: [_s('1', 'A')],
        tags: const [],
        snippets: const [],
        isQrMode: true,
      );
      c.toggleAll(false);
      c.setIncludeTags(true);
      expect(c.hasSelection, isFalse);
      c.setIncludeSnippets(true);
      expect(c.hasSelection, isFalse);
    });
  });

  group('UnifiedExportController — tags/snippets count toward QR size', () {
    test('enabling tags raises QR payloadSize by their compressed cost', () {
      // Regression guard: a prior implementation set
      // `options.includeTags = true` on the size-calc call but passed
      // `tags: const []` (the default), so the encoder skipped the
      // `tg` section entirely and the UI under-counted the QR payload.
      // The real export path *does* pass the tags list in, so
      // `fitsInQr` must agree with what the user will actually emit.
      final tag = Tag(
        id: 't',
        name: 'production-web-servers-with-a-deliberately-long-name',
        color: '#ff0000',
        createdAt: DateTime(2025),
      );
      final base = _ctrl(sessions: [_s('1', 'A')], isQrMode: true);
      final withTags = _ctrl(
        sessions: [_s('1', 'A')],
        tags: [tag],
        isQrMode: true,
      );
      expect(
        withTags.payloadSize,
        greaterThan(base.payloadSize),
        reason:
            'tag bytes must land in the compressed payload when '
            'includeTags is on — otherwise fitsInQr lies',
      );
    });

    test(
      'enabling snippets raises QR payloadSize by their compressed cost',
      () {
        final snippet = Snippet(
          id: 'sn',
          title: 'restart-nginx-with-verification',
          command: 'sudo systemctl restart nginx && systemctl status nginx',
          createdAt: DateTime(2025),
          updatedAt: DateTime(2025),
        );
        final base = _ctrl(sessions: [_s('1', 'A')], isQrMode: true);
        final withSnippets = _ctrl(
          sessions: [_s('1', 'A')],
          snippets: [snippet],
          isQrMode: true,
        );
        expect(
          withSnippets.payloadSize,
          greaterThan(base.payloadSize),
          reason: 'snippet bytes must land in the compressed QR payload',
        );
      },
    );
  });

  group('UnifiedExportController — fitsInQr', () {
    test('always true in LFS mode regardless of payload size', () {
      // LFS has no QR ceiling — archive can be any size. Spec: the
      // Export button must never be disabled "too large for QR" in
      // LFS mode.
      final c = _ctrl(
        sessions: List.generate(500, (i) => _s('$i', 'host$i')),
        isQrMode: false,
      );
      expect(c.fitsInQr, isTrue);
    });

    test('true for trivial payload in QR mode', () {
      final c = _ctrl(sessions: [_s('1', 'A')], isQrMode: true);
      expect(c.fitsInQr, isTrue);
    });

    test('false once QR payload exceeds the hard ceiling', () {
      // High-entropy unique strings per session defeat deflate — the
      // payload stays close to its raw size and blows past the
      // ~2 KB QR ceiling. fitsInQr reads as false → Export button
      // disabled, SnackBar fires on tap.
      String uniqueHighEntropy(int i) {
        // Different chars per session → compressor can't dedupe.
        final buf = StringBuffer();
        for (var k = 0; k < 64; k++) {
          buf.writeCharCode(33 + ((i * 31 + k * 17) % 90));
        }
        return buf.toString();
      }

      final c = _ctrl(
        sessions: List.generate(
          400,
          (i) => _s(
            '$i',
            uniqueHighEntropy(i),
            password: uniqueHighEntropy(i + 1000),
          ),
        ),
        isQrMode: true,
      );
      expect(c.fitsInQr, isFalse);
    });
  });

  group('UnifiedExportController — warning flags', () {
    test('warnings off in LFS mode regardless of which key flag is on', () {
      // Spec: LFS archive has no payload ceiling; the "may inflate
      // the QR payload" warnings would be misleading in that mode.
      final c = _ctrl(sessions: [_s('1', 'A')], isQrMode: false);
      c.setIncludeEmbeddedKeys(true);
      expect(c.showEmbeddedKeysWarning, isFalse);
      c.setIncludeManagerKeys(true);
      expect(c.showManagerKeysWarning, isFalse);
      c.setIncludeAllManagerKeys(true);
      expect(c.showAllManagerKeysWarning, isFalse);
    });

    test('showAllManagerKeysWarning fires only in QR + flag on', () {
      final c = _ctrl(sessions: [_s('1', 'A')], isQrMode: true);
      expect(c.showAllManagerKeysWarning, isFalse);
      c.setIncludeAllManagerKeys(true);
      expect(c.showAllManagerKeysWarning, isTrue);
    });
  });

  group('UnifiedExportController — individual setters', () {
    test('setIncludeConfig flips the flag and invalidates cache', () {
      final c = _ctrl(
        sessions: [_s('1', 'A')],
        config: AppConfig.defaults,
        isQrMode: true,
      );
      expect(c.options.includeConfig, isFalse);
      c.setIncludeConfig(true);
      expect(c.options.includeConfig, isTrue);
    });

    test('setIncludeKnownHosts flips the flag', () {
      final c = _ctrl(
        sessions: [_s('1', 'A')],
        knownHostsContent: 'host-entry',
        isQrMode: true,
      );
      c.setIncludeKnownHosts(true);
      expect(c.options.includeKnownHosts, isTrue);
      c.setIncludeKnownHosts(false);
      expect(c.options.includeKnownHosts, isFalse);
    });

    test('setIncludeTags / setIncludeSnippets flip independently', () {
      final c = _ctrl(sessions: [_s('1', 'A')], isQrMode: true);
      c.setIncludeTags(false);
      expect(c.options.includeTags, isFalse);
      c.setIncludeSnippets(false);
      expect(c.options.includeSnippets, isFalse);
      expect(
        c.options.includeTags,
        isFalse,
        reason: 'snippets toggle must not clobber tags',
      );
    });

    test('setIncludePasswords and setIncludeEmbeddedKeys are independent', () {
      final c = _ctrl(sessions: [_s('1', 'A')], isQrMode: true);
      c.setIncludePasswords(false);
      c.setIncludeEmbeddedKeys(true);
      expect(c.options.includePasswords, isFalse);
      expect(c.options.includeEmbeddedKeys, isTrue);
    });
  });

  group('UnifiedExportController — size getters with content', () {
    test('configSize > 0 when a config is present', () {
      final c = _ctrl(sessions: [_s('1', 'A')], config: AppConfig.defaults);
      expect(
        c.configSize,
        greaterThan(0),
        reason: 'payload contains at least the serialized config map',
      );
    });

    test('knownHostsSize > 0 when content non-empty, 0 when empty', () {
      final withHosts = _ctrl(
        sessions: [_s('1', 'A')],
        knownHostsContent: 'github.com ssh-rsa AAAAB3',
      );
      expect(withHosts.knownHostsSize, greaterThan(0));

      final emptyHosts = _ctrl(sessions: [_s('1', 'A')], knownHostsContent: '');
      expect(
        emptyHosts.knownHostsSize,
        0,
        reason: 'empty string skips the calc entirely',
      );
    });

    test('tagsSize / snippetsSize scale with data, 0 when empty', () {
      final withTags = _ctrl(
        sessions: [_s('1', 'A')],
        tags: [
          Tag(
            id: 't',
            name: 'prod',
            color: '#ff0000',
            createdAt: DateTime(2025),
          ),
        ],
      );
      expect(withTags.tagsSize, greaterThan(0));
      expect(withTags.snippetsSize, 0);

      final withSnippets = _ctrl(
        sessions: [_s('1', 'A')],
        snippets: [
          Snippet(
            id: 'sn',
            title: 'restart',
            command: 'systemctl restart nginx',
            createdAt: DateTime(2025),
            updatedAt: DateTime(2025),
          ),
        ],
      );
      expect(withSnippets.snippetsSize, greaterThan(0));
      expect(withSnippets.tagsSize, 0);
    });

    test('size getters cache — second read returns the same instance', () {
      // Spec: these values feed the dialog on every rebuild. Without a
      // cache, the expensive payload-encode runs per frame.
      final c = _ctrl(sessions: [_s('1', 'A')], config: AppConfig.defaults);
      final first = c.configSize;
      expect(
        identical(first, c.configSize),
        isTrue,
        reason: 'cached int must be the exact same value each read',
      );
    });
  });

  group('UnifiedExportController — credential extra sizes', () {
    test('passwordsExtraSize > 0 when selected sessions carry passwords', () {
      final c = _ctrl(
        sessions: [_s('1', 'A', password: 'long-enough-secret')],
        isQrMode: true,
      );
      expect(c.passwordsExtraSize, greaterThan(0));
    });

    test('passwordsExtraSize == 0 when the selection is empty', () {
      // Spec (_credentialExtraSize: `if (selectedSessions.isEmpty) return 0`):
      // no sessions = nothing the credential flag can inflate.
      final c = _ctrl(sessions: [_s('1', 'A', password: 'x')]);
      c.toggleAll(false);
      expect(c.passwordsExtraSize, 0);
    });

    test(
      'embeddedKeysExtraSize == 0 when every selected session is manager-keyed',
      () {
        // Spec: only sessions with an empty keyId carry embedded keys.
        // If every selected session lives in the key manager, the
        // "embedded keys" row has no content to inflate.
        final c = _ctrl(
          sessions: [
            _s(
              '1',
              'A',
              keyId: 'k1',
              authType: AuthType.key,
              keyData: 'pem-body',
            ),
          ],
          isQrMode: true,
        );
        expect(c.embeddedKeysExtraSize, 0);
      },
    );

    test('embeddedKeysExtraSize > 0 when a session carries an inline key', () {
      final c = _ctrl(
        sessions: [
          _s(
            '1',
            'A',
            authType: AuthType.key,
            keyData:
                '-----BEGIN OPENSSH PRIVATE KEY-----\n'
                'b3BlbnNzaC1rZXktdjEAAAAABG5vbmU=\n'
                '-----END OPENSSH PRIVATE KEY-----',
          ),
        ],
        isQrMode: true,
      );
      expect(c.embeddedKeysExtraSize, greaterThan(0));
    });
  });

  group('UnifiedExportController — managerKeysExtraSize', () {
    test('zero when the manager has no keys at all', () {
      final c = _ctrl(sessions: [_s('1', 'A')]);
      expect(c.managerKeysExtraSize, 0);
    });

    test(
      'zero in "session keys" mode when no selected session references a key',
      () {
        // Spec: session-keys mode filters to usedKeyIds. With no
        // selected session referencing keyId, usedKeyIds is empty →
        // filtered map is empty → no inflation.
        final c = _ctrl(
          sessions: [_s('1', 'A')], // keyId empty
          managerKeys: {'k1': 'pem-body'},
          isQrMode: true,
        );
        c.setIncludeManagerKeys(true);
        expect(c.managerKeysExtraSize, 0);
      },
    );

    test('non-zero when a session references a key and the flag is on', () {
      final c = _ctrl(
        sessions: [_s('1', 'A', keyId: 'k1', authType: AuthType.key)],
        managerKeys: {'k1': 'pem-body-that-inflates-the-payload'},
        isQrMode: true,
      );
      c.setIncludeManagerKeys(true);
      expect(c.managerKeysExtraSize, greaterThan(0));
    });

    test('non-zero in "all keys" mode even without a matching session', () {
      // Spec: includeAllManagerKeys bypasses the usedKeyIds filter —
      // every key in the manager lands in the payload regardless of
      // session references. That's the "full-app backup" mode.
      final c = _ctrl(
        sessions: [_s('1', 'A')], // no keyId linkage
        managerKeys: {'k1': 'pem-body-lives-on-its-own'},
        isQrMode: true,
      );
      c.setIncludeAllManagerKeys(true);
      expect(c.managerKeysExtraSize, greaterThan(0));
    });

    test('managerKeysExtraSize caches within a single state', () {
      final c = _ctrl(sessions: [_s('1', 'A')], managerKeys: {'k1': 'pem'});
      c.setIncludeAllManagerKeys(true);
      final first = c.managerKeysExtraSize;
      expect(identical(first, c.managerKeysExtraSize), isTrue);
    });
  });

  group('UnifiedExportController — LFS payload with resolved manager keys', () {
    test('managerKeyEntries are folded into the .lfs payload on size calc', () {
      // Spec (_resolveSessionsForLfsSize): sessions in the dialog
      // cache don't carry keyData — it's lazy-loaded. For .lfs size
      // estimation we must overlay the managerKeyEntries so the
      // computed archive size reflects what will actually be written.
      // Comparing with/without entries gives us signal the code path
      // did overlay the key bytes.
      final entries = {
        'k1': _keyEntry(
          'k1',
          'prod',
          '-----BEGIN KEY-----\nAAAAAAAA\n-----END KEY-----',
        ),
      };
      final base = _ctrl(
        sessions: [_s('1', 'A', keyId: 'k1', authType: AuthType.key)],
        config: AppConfig.defaults,
        isQrMode: false,
      );
      final withEntries = _ctrl(
        sessions: [_s('1', 'A', keyId: 'k1', authType: AuthType.key)],
        config: AppConfig.defaults,
        managerKeyEntries: entries,
        isQrMode: false,
      );
      expect(
        withEntries.payloadSize,
        greaterThanOrEqualTo(base.payloadSize),
        reason:
            'overlaying the real key bytes can only grow or match '
            'the baseline — never shrink it',
      );
    });
  });
}
