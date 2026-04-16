import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/config/app_config.dart';
import 'package:letsflutssh/core/security/key_store.dart';
import 'package:letsflutssh/core/session/qr_codec.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/snippets/snippet.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/core/tags/tag.dart';

void main() {
  Session makeSession({
    String label = 'test',
    String host = 'example.com',
    int port = 22,
    String user = 'root',
    String folder = '',
    AuthType authType = AuthType.password,
    String password = '',
    String keyData = '',
  }) {
    return Session(
      label: label,
      server: ServerAddress(host: host, port: port, user: user),
      folder: folder,
      auth: SessionAuth(
        authType: authType,
        password: password,
        keyData: keyData,
      ),
    );
  }

  group('encodeExportPayload', () {
    test('encodes and decodes a single session', () {
      final sessions = [
        makeSession(label: 'test', host: 'example.com', user: 'root'),
      ];
      final result = decodeExportPayload(encodeExportPayload(sessions));
      expect(result, isNotNull);
      expect(result!.sessions, hasLength(1));
      expect(result.sessions[0].label, 'test');
      expect(result.sessions[0].host, 'example.com');
      expect(result.sessions[0].user, 'root');
    });

    test('no credentials when password is empty', () {
      final sessions = [makeSession()];
      final result = decodeExportPayload(encodeExportPayload(sessions));
      expect(result!.sessions[0].password, '');
    });

    test('encodes non-default port', () {
      final sessions = [makeSession(port: 2222)];
      final result = decodeExportPayload(encodeExportPayload(sessions));
      expect(result!.sessions[0].port, 2222);
    });

    test('encodes folder', () {
      final sessions = [makeSession(folder: 'Production/Web')];
      final result = decodeExportPayload(encodeExportPayload(sessions));
      expect(result!.sessions[0].folder, 'Production/Web');
    });

    test('encodes non-default auth type', () {
      final sessions = [makeSession(authType: AuthType.key)];
      final result = decodeExportPayload(encodeExportPayload(sessions));
      expect(result!.sessions[0].authType, AuthType.key);
    });

    test('omits default auth type (password)', () {
      final sessions = [makeSession(authType: AuthType.password)];
      final result = decodeExportPayload(encodeExportPayload(sessions));
      expect(result, isNotNull);
      expect(result!.sessions[0].authType, AuthType.password);
    });

    test('encodes empty folders', () {
      final sessions = [makeSession()];
      final result = decodeExportPayload(
        encodeExportPayload(
          sessions,
          input: const ExportPayloadInput(emptyFolders: {'Staging', 'Dev'}),
        ),
      );
      expect(result!.emptyFolders, containsAll(['Staging', 'Dev']));
    });

    test('omits empty folders when none provided', () {
      final sessions = [makeSession()];
      final result = decodeExportPayload(encodeExportPayload(sessions));
      expect(result!.emptyFolders, isEmpty);
    });

    test('includes password when includePasswords=true', () {
      final sessions = [makeSession(password: 'supersecret')];
      final result = decodeExportPayload(
        encodeExportPayload(
          sessions,
          input: const ExportPayloadInput(
            options: ExportOptions(includePasswords: true),
          ),
        ),
      );
      expect(result!.sessions[0].password, 'supersecret');
    });

    test('encodes multiple sessions', () {
      final sessions = [
        makeSession(label: 'a', host: 'a.com'),
        makeSession(label: 'b', host: 'b.com'),
        makeSession(label: 'c', host: 'c.com'),
      ];
      final result = decodeExportPayload(encodeExportPayload(sessions));
      expect(result!.sessions, hasLength(3));
      expect(
        result.sessions.map((s) => s.host),
        containsAll(['a.com', 'b.com', 'c.com']),
      );
    });
  });

  group('roundtrip encode/decode', () {
    test('preserves session data', () {
      final sessions = [
        makeSession(
          label: 'nginx',
          host: 'prod.com',
          port: 2222,
          user: 'deploy',
          folder: 'Production',
        ),
        makeSession(label: 'api', host: 'api.com', user: 'admin'),
      ];
      final result = decodeExportPayload(
        encodeExportPayload(
          sessions,
          input: const ExportPayloadInput(emptyFolders: {'Staging'}),
        ),
      );
      expect(result, isNotNull);
      expect(result!.sessions, hasLength(2));
      expect(result.sessions[0].label, 'nginx');
      expect(result.sessions[0].port, 2222);
      expect(result.sessions[0].folder, 'Production');
      expect(result.emptyFolders, contains('Staging'));
    });

    test('decoded sessions without password are incomplete', () {
      final sessions = [makeSession()];
      final result = decodeExportPayload(encodeExportPayload(sessions));
      expect(result!.sessions[0].isValid, isFalse);
    });

    test('decoded sessions with password are complete', () {
      final sessions = [makeSession(password: 'secret')];
      final result = decodeExportPayload(
        encodeExportPayload(
          sessions,
          input: const ExportPayloadInput(
            options: ExportOptions(includePasswords: true),
          ),
        ),
      );
      expect(result!.sessions[0].password, 'secret');
      expect(result.sessions[0].isValid, isTrue);
    });

    test('handles missing optional fields', () {
      final sessions = [
        Session(
          label: '',
          server: const ServerAddress(host: 'host', user: 'user'),
        ),
      ];
      final result = decodeExportPayload(encodeExportPayload(sessions));
      expect(result, isNotNull);
      expect(result!.sessions[0].host, 'host');
      expect(result.sessions[0].port, 22);
    });

    test('handles empty sessions array', () {
      final result = decodeExportPayload(encodeExportPayload([]));
      expect(result, isNotNull);
      expect(result!.sessions, isEmpty);
    });

    test('decodes old QR format (base64 JSON without deflate)', () {
      // Old format: base64Url(JSON) without deflate — simulate a QR from a
      // previous app version. The decoder must fall back gracefully.
      const oldPayload =
          '{"v":1,"s":[{"l":"myserver","h":"example.com","p":2222,"u":"admin","a":"key"}]}';
      final oldEncoded = base64Url.encode(utf8.encode(oldPayload));

      final result = decodeExportPayload(oldEncoded);
      expect(result, isNotNull);
      expect(result!.sessions, hasLength(1));
      expect(result.sessions[0].label, 'myserver');
      expect(result.sessions[0].host, 'example.com');
      expect(result.sessions[0].port, 2222);
      expect(result.sessions[0].user, 'admin');
      expect(result.sessions[0].authType, AuthType.key);
    });

    test('decodes old QR format with empty folders', () {
      const oldPayload =
          '{"v":1,"s":[{"l":"s","h":"h.com","u":"u"}],"eg":["FolderA","FolderB"]}';
      final oldEncoded = base64Url.encode(utf8.encode(oldPayload));

      final result = decodeExportPayload(oldEncoded);
      expect(result, isNotNull);
      expect(result!.sessions, hasLength(1));
      expect(result.emptyFolders, containsAll(['FolderA', 'FolderB']));
    });

    test(
      'falls through to old format when deflate produces unrecognized JSON',
      () {
        // Create JSON that is valid but has no recognized keys
        const unrecognizedJson = '{"foo": "bar", "baz": 42}';
        // Compress it like the new format would
        final compressed = Deflate(utf8.encode(unrecognizedJson)).getBytes();
        final newFormatPayload = base64Url.encode(compressed);

        // This should return null (not crash) — deflate succeeds but JSON is
        // unrecognized, falls through to old format which also fails
        expect(decodeExportPayload(newFormatPayload), isNull);

        // Now create a valid old-format payload where the raw bytes happen to be
        // valid deflate but the un-deflated base64(JSON) is the real payload
        final oldFormatSession = {
          's': [
            {'l': 'test', 'h': 'host', 'u': 'user'},
          ],
        };
        final oldPayload = base64Url.encode(
          utf8.encode(jsonEncode(oldFormatSession)),
        );
        final result = decodeExportPayload(oldPayload);
        // Old format should still work
        expect(result, isNotNull);
        expect(result!.sessions, hasLength(1));
        expect(result.sessions.first.label, 'test');
      },
    );

    test('wrapInDeepLink / decodeImportUri roundtrip', () {
      final sessions = [
        makeSession(label: 'test', host: 'example.com', user: 'root'),
      ];
      final payload = encodeExportPayload(sessions);
      final deepLink = wrapInDeepLink(payload);
      final result = decodeImportUri(Uri.parse(deepLink));
      expect(result, isNotNull);
      expect(result!.sessions, hasLength(1));
      expect(result.sessions[0].label, 'test');
    });

    test('returns null for wrong scheme', () {
      expect(decodeImportUri(Uri.parse('https://example.com')), isNull);
    });

    test('returns null for missing d param', () {
      expect(decodeImportUri(Uri.parse('letsflutssh://import')), isNull);
    });

    test('returns null for invalid data', () {
      expect(decodeImportUri(Uri.parse('letsflutssh://import?d=!!!')), isNull);
    });

    test('sessions field of wrong shape is dropped without crashing', () {
      // Build a payload where `s` is a Map instead of the expected List.
      // Previously this hit `as List` and threw a TypeError (caught by the
      // outer guard, but only by accident). After the explicit `is List`
      // check, the malformed entry is silently skipped and the rest of the
      // payload survives — sessions just come out empty.
      final payload = base64Url.encode(utf8.encode('{"s": {"oops": true}}'));
      final result = decodeExportPayload(payload);
      expect(result, isNotNull);
      expect(result!.sessions, isEmpty);
    });

    test('non-string entries in eg list are filtered out', () {
      final payload = base64Url.encode(
        utf8.encode('{"s": [], "eg": ["folderA", 42, null, "folderB"]}'),
      );
      final result = decodeExportPayload(payload);
      expect(result, isNotNull);
      expect(result!.emptyFolders, {'folderA', 'folderB'});
    });
  });

  group('calculateExportPayloadSize', () {
    test('returns positive size', () {
      final sessions = [makeSession()];
      final size = calculateExportPayloadSize(sessions);
      expect(size, greaterThan(0));
    });

    test('size increases with more sessions', () {
      final s1 = [makeSession(label: 'a')];
      final s2 = [makeSession(label: 'a'), makeSession(label: 'b')];
      expect(
        calculateExportPayloadSize(s2),
        greaterThan(calculateExportPayloadSize(s1)),
      );
    });

    test('deflate compressed size is reasonable for large keys', () {
      // A realistic 2KB RSA key
      const keyData =
          'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7'
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      final sessions = List.generate(
        3,
        (i) => Session(
          label: 'server-$i',
          server: const ServerAddress(host: 'example.com', user: 'admin'),
          auth: const SessionAuth(authType: AuthType.key, keyData: keyData),
        ),
      );
      // 3 sessions with 2KB keys should fit in 2KB after dedup + deflate
      final size = calculateExportPayloadSize(
        sessions,
        input: const ExportPayloadInput(
          options: ExportOptions(includeEmbeddedKeys: true),
        ),
      );
      expect(size, lessThan(qrMaxPayloadBytes));
    });
  });

  group('config and known_hosts in QR', () {
    test('includes config in QR payload', () {
      final sessions = [makeSession()];
      final result = decodeExportPayload(
        encodeExportPayload(
          sessions,
          input: const ExportPayloadInput(config: AppConfig.defaults),
        ),
      );
      expect(result, isNotNull);
      expect(result!.config, isNotNull);
    });

    test('includes known_hosts in QR payload', () {
      final sessions = [makeSession()];
      const khContent = 'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI';
      final result = decodeExportPayload(
        encodeExportPayload(
          sessions,
          input: const ExportPayloadInput(knownHostsContent: khContent),
        ),
      );
      expect(result, isNotNull);
      expect(result!.knownHostsContent, khContent);
    });

    test('includes both config and known_hosts', () {
      final sessions = [makeSession()];
      final result = decodeExportPayload(
        encodeExportPayload(
          sessions,
          input: const ExportPayloadInput(
            config: AppConfig.defaults,
            knownHostsContent: 'host ssh-rsa AAA',
          ),
        ),
      );
      expect(result, isNotNull);
      expect(result!.config, isNotNull);
      expect(result.knownHostsContent, 'host ssh-rsa AAA');
    });
  });

  group('credentials in QR', () {
    test('includePasswords=false excludes password', () {
      final session = makeSession(password: 'secret123');
      final result = decodeExportPayload(
        encodeExportPayload(
          [session],
          input: const ExportPayloadInput(
            options: ExportOptions(includePasswords: false),
          ),
        ),
      );
      expect(result!.sessions[0].password, '');
    });

    test('includeEmbeddedKeys=true includes embedded key data', () {
      final session = Session(
        label: 'key-auth',
        server: const ServerAddress(host: 'example.com', user: 'admin'),
        auth: const SessionAuth(
          authType: AuthType.key,
          keyData: 'ssh-rsa AAAAB3...',
        ),
      );
      final result = decodeExportPayload(
        encodeExportPayload(
          [session],
          input: const ExportPayloadInput(
            options: ExportOptions(includeEmbeddedKeys: true),
          ),
        ),
      );
      expect(result!.sessions[0].keyData, 'ssh-rsa AAAAB3...');
    });

    test('includeEmbeddedKeys=false excludes embedded key data', () {
      final session = Session(
        label: 'key-auth',
        server: const ServerAddress(host: 'example.com', user: 'admin'),
        auth: const SessionAuth(
          authType: AuthType.key,
          keyData: 'ssh-rsa AAAAB3...',
        ),
      );
      final result = decodeExportPayload(
        encodeExportPayload(
          [session],
          input: const ExportPayloadInput(
            options: ExportOptions(includeEmbeddedKeys: false),
          ),
        ),
      );
      expect(result!.sessions[0].keyData, '');
    });

    test('includeManagerKeys=true exports key in km and sets mg flag', () {
      final session = Session(
        label: 'mgr-key',
        server: const ServerAddress(host: 'example.com', user: 'admin'),
        auth: const SessionAuth(
          authType: AuthType.key,
          keyId: 'mgr-123',
          keyData: 'ssh-rsa MANAGER...',
        ),
      );
      final keyEntry = SshKeyEntry(
        id: 'mgr-123',
        label: 'My Manager Key',
        privateKey: 'ssh-rsa MANAGER...',
        publicKey: 'ssh-rsa AAAA...',
        keyType: 'rsa',
        createdAt: DateTime(2024),
      );
      final result = decodeExportPayload(
        encodeExportPayload(
          [session],
          input: ExportPayloadInput(
            options: const ExportOptions(includeManagerKeys: true),
            managerKeyEntries: {'mgr-123': keyEntry},
          ),
        ),
      );
      // Manager key: keyData empty (loaded from KeyStore on import),
      // keyId set to short id for remapping.
      expect(result!.sessions[0].keyData, isEmpty);
      expect(result.sessions[0].keyId, isNotEmpty);
      // Key appears in managerKeys for insertion into KeyStore.
      expect(result.managerKeys, hasLength(1));
      expect(result.managerKeys[0].privateKey, 'ssh-rsa MANAGER...');
      expect(result.managerKeys[0].label, 'My Manager Key');
    });

    test('includeManagerKeys=false excludes manager key data', () {
      final session = Session(
        label: 'mgr-key',
        server: const ServerAddress(host: 'example.com', user: 'admin'),
        auth: const SessionAuth(
          authType: AuthType.key,
          keyId: 'mgr-123',
          keyData: 'ssh-rsa MANAGER...',
        ),
      );
      final result = decodeExportPayload(
        encodeExportPayload(
          [session],
          input: const ExportPayloadInput(
            options: ExportOptions(includeManagerKeys: false),
          ),
        ),
      );
      expect(result!.sessions[0].keyData, '');
    });

    test('deduplicates shared embedded keys', () {
      const keyData = 'ssh-rsa SHARED...';
      final sessions = [
        makeSession(label: 'a', keyData: keyData),
        makeSession(label: 'b', keyData: keyData),
        makeSession(label: 'c', keyData: keyData),
      ];
      final result = decodeExportPayload(
        encodeExportPayload(
          sessions,
          input: const ExportPayloadInput(
            options: ExportOptions(includeEmbeddedKeys: true),
          ),
        ),
      );
      expect(result!.sessions, hasLength(3));
      for (final s in result.sessions) {
        expect(s.keyData, keyData);
      }
    });

    test('decoded sessions with key data are complete', () {
      final session = Session(
        label: 'key-auth',
        server: const ServerAddress(host: 'example.com', user: 'admin'),
        auth: const SessionAuth(authType: AuthType.key, keyData: 'ssh-rsa AAA'),
      );
      final result = decodeExportPayload(
        encodeExportPayload(
          [session],
          input: const ExportPayloadInput(
            options: ExportOptions(includeEmbeddedKeys: true),
          ),
        ),
      );
      expect(result!.sessions[0].isValid, isTrue);
    });

    test('decoded sessions without credentials are incomplete', () {
      final session = makeSession();
      final result = decodeExportPayload(
        encodeExportPayload(
          [session],
          input: const ExportPayloadInput(
            options: ExportOptions(includePasswords: false),
          ),
        ),
      );
      expect(result!.sessions[0].isValid, isFalse);
    });
  });

  group('ExportOptions', () {
    test('withX methods override single values and chain', () {
      const opts = ExportOptions(
        includeSessions: true,
        includeConfig: false,
        includeKnownHosts: true,
        includePasswords: true,
        includeEmbeddedKeys: true,
        includeManagerKeys: false,
      );
      final copied = opts.withIncludeConfig(true).withIncludeManagerKeys(true);
      expect(copied.includeSessions, isTrue);
      expect(copied.includeConfig, isTrue);
      expect(copied.includeKnownHosts, isTrue);
      expect(copied.includePasswords, isTrue);
      expect(copied.includeEmbeddedKeys, isTrue);
      expect(copied.includeManagerKeys, isTrue);
    });

    test('withX methods preserve all other values', () {
      const opts = ExportOptions(
        includeSessions: false,
        includeConfig: true,
        includeKnownHosts: false,
        includePasswords: false,
        includeEmbeddedKeys: true,
        includeManagerKeys: true,
        includeAllManagerKeys: true,
        includeTags: true,
        includeSnippets: true,
      );
      // Apply each withX as a no-op (same value) and verify all fields preserved.
      final copied = opts
          .withIncludeSessions(false)
          .withIncludeConfig(true)
          .withIncludeKnownHosts(false)
          .withIncludePasswords(false)
          .withIncludeEmbeddedKeys(true)
          .withIncludeManagerKeys(true)
          .withIncludeAllManagerKeys(true)
          .withIncludeTags(true)
          .withIncludeSnippets(true);
      expect(copied.includeSessions, isFalse);
      expect(copied.includeConfig, isTrue);
      expect(copied.includeKnownHosts, isFalse);
      expect(copied.includePasswords, isFalse);
      expect(copied.includeEmbeddedKeys, isTrue);
      expect(copied.includeManagerKeys, isTrue);
      expect(copied.includeAllManagerKeys, isTrue);
      expect(copied.includeTags, isTrue);
      expect(copied.includeSnippets, isTrue);
    });

    test('hasAnySelection is true when any flag is set', () {
      expect(
        const ExportOptions(includeSessions: true).hasAnySelection,
        isTrue,
      );
      expect(const ExportOptions(includeConfig: true).hasAnySelection, isTrue);
      expect(
        const ExportOptions(includeKnownHosts: true).hasAnySelection,
        isTrue,
      );
    });

    test('hasAnySelection is false when all are false', () {
      const opts = ExportOptions(
        includeSessions: false,
        includeConfig: false,
        includeKnownHosts: false,
      );
      expect(opts.hasAnySelection, isFalse);
    });
  });

  group('ExportPayloadData getters', () {
    test('hasSessions is true when sessions present', () {
      final data = ExportPayloadData(
        sessions: [makeSession()],
        emptyFolders: {},
      );
      expect(data.hasSessions, isTrue);
    });

    test('hasSessions is false when sessions empty', () {
      const data = ExportPayloadData(sessions: [], emptyFolders: {});
      expect(data.hasSessions, isFalse);
    });

    test('hasConfig is true when config present', () {
      const data = ExportPayloadData(
        sessions: [],
        emptyFolders: {},
        config: AppConfig.defaults,
      );
      expect(data.hasConfig, isTrue);
    });

    test('hasConfig is false when config null', () {
      const data = ExportPayloadData(sessions: [], emptyFolders: {});
      expect(data.hasConfig, isFalse);
    });

    test('hasKnownHosts is true when content non-empty', () {
      const data = ExportPayloadData(
        sessions: [],
        emptyFolders: {},
        knownHostsContent: 'host ssh-rsa AAA',
      );
      expect(data.hasKnownHosts, isTrue);
    });

    test('hasKnownHosts is false when content null', () {
      const data = ExportPayloadData(sessions: [], emptyFolders: {});
      expect(data.hasKnownHosts, isFalse);
    });

    test('hasKnownHosts is false when content empty', () {
      const data = ExportPayloadData(
        sessions: [],
        emptyFolders: {},
        knownHostsContent: '',
      );
      expect(data.hasKnownHosts, isFalse);
    });
  });

  group('format versioning', () {
    test('v4 payload includes version field', () {
      final sessions = [makeSession(label: 'test', host: 'h', user: 'u')];
      final encoded = encodeExportPayload(sessions);
      // Decode the raw payload to inspect the JSON
      final compressed = base64Url.decode(encoded);
      final inflated = Inflate(compressed).getBytes();
      final json = jsonDecode(utf8.decode(inflated)) as Map<String, dynamic>;
      expect(json['v'], 4);
    });

    test('rejects payload with future version beyond current schema', () {
      // Future versions may carry unknown fields that this build cannot
      // interpret — parsing them would silently drop data. The decoder
      // throws [QrPayloadVersionTooNewException] so the UI can route the
      // user to "update the app" instead of showing a generic "invalid QR".
      final payload = jsonEncode({
        'v': 99,
        's': [
          {'l': 'future', 'h': 'host', 'u': 'user'},
        ],
      });
      final compressed = Deflate(utf8.encode(payload)).getBytes();
      final encoded = base64Url.encode(compressed);
      expect(
        () => decodeExportPayload(encoded),
        throwsA(isA<QrPayloadVersionTooNewException>()),
      );
    });

    test('decodes v1 old format without version field', () {
      // Old format had no deflate, just base64(JSON)
      final payload = jsonEncode({
        'v': 1,
        's': [
          {'l': 'old', 'h': 'h.com', 'u': 'u'},
        ],
      });
      final encoded = base64Url.encode(utf8.encode(payload));
      final result = decodeExportPayload(encoded);
      expect(result, isNotNull);
      expect(result!.sessions.first.label, 'old');
    });
  });

  group('encodeSessionCompact', () {
    test('encodeSessionCompact produces compact format', () {
      final session = Session(
        label: 'srv',
        server: const ServerAddress(host: 'h.com', port: 2222, user: 'admin'),
        auth: const SessionAuth(authType: AuthType.key, password: 'secret'),
      );
      final compact = encodeSessionCompact(session);
      expect(compact['l'], 'srv');
      expect(compact['h'], 'h.com');
      expect(compact['u'], 'admin');
      expect(compact['p'], 2222);
      expect(compact['a'], 'key');
      // Password excluded by default (includePasswords: false)
      expect(compact.containsKey('pw'), isFalse);

      // With passwords
      final withPw = encodeSessionCompact(session, includePasswords: true);
      expect(withPw['pw'], 'secret');
    });
  });

  group('tags and snippets in payload', () {
    test('tags roundtrip through encode/decode', () {
      final sessions = [makeSession(label: 's1')];
      final tags = [
        Tag(id: 't1', name: 'Production', color: '#EF5350'),
        Tag(id: 't2', name: 'Staging'),
      ];
      final sessionTags = [const ExportLink(sessionId: 's1', targetId: 't1')];
      final folderTags = [
        const ExportFolderTagLink(folderPath: 'Servers', tagId: 't2'),
      ];
      final result = decodeExportPayload(
        encodeExportPayload(
          sessions,
          input: ExportPayloadInput(
            options: const ExportOptions(includeTags: true),
            tags: tags,
            sessionTags: sessionTags,
            folderTags: folderTags,
          ),
        ),
      );
      expect(result!.tags, hasLength(2));
      expect(result.tags[0].name, 'Production');
      expect(result.tags[0].color, '#EF5350');
      expect(result.tags[1].name, 'Staging');
      expect(result.sessionTags, hasLength(1));
      expect(result.sessionTags[0].sessionId, 's1');
      expect(result.sessionTags[0].targetId, 't1');
      expect(result.folderTags, hasLength(1));
      expect(result.folderTags[0].folderPath, 'Servers');
      expect(result.folderTags[0].tagId, 't2');
    });

    test('snippets roundtrip through encode/decode', () {
      final sessions = [makeSession(label: 's1')];
      final snippets = [
        Snippet(
          id: 'sn1',
          title: 'Restart',
          command: 'systemctl restart nginx',
        ),
        Snippet(
          id: 'sn2',
          title: 'Logs',
          command: 'tail -f /var/log/syslog',
          description: 'Follow system log',
        ),
      ];
      final sessionSnippets = [
        const ExportLink(sessionId: 's1', targetId: 'sn1'),
      ];
      final result = decodeExportPayload(
        encodeExportPayload(
          sessions,
          input: ExportPayloadInput(
            options: const ExportOptions(includeSnippets: true),
            snippets: snippets,
            sessionSnippets: sessionSnippets,
          ),
        ),
      );
      expect(result!.snippets, hasLength(2));
      expect(result.snippets[0].title, 'Restart');
      expect(result.snippets[0].command, 'systemctl restart nginx');
      expect(result.snippets[1].description, 'Follow system log');
      expect(result.sessionSnippets, hasLength(1));
      expect(result.sessionSnippets[0].sessionId, 's1');
      expect(result.sessionSnippets[0].targetId, 'sn1');
    });

    test('tags and snippets excluded when options are false', () {
      final sessions = [makeSession(label: 's1')];
      final result = decodeExportPayload(
        encodeExportPayload(
          sessions,
          input: ExportPayloadInput(
            tags: [Tag(id: 't1', name: 'Prod')],
            snippets: [Snippet(id: 'sn1', title: 'X', command: 'x')],
          ),
        ),
      );
      expect(result!.tags, isEmpty);
      expect(result.snippets, isEmpty);
    });

    test('includeAllManagerKeys adds unreferenced keys', () {
      final session = Session(
        label: 'srv',
        server: const ServerAddress(host: 'h', user: 'u'),
        auth: const SessionAuth(
          authType: AuthType.key,
          keyId: 'k-used',
          keyData: 'KEY-A',
        ),
      );
      final allKeys = {
        'k-used': SshKeyEntry(
          id: 'k-used',
          label: 'Used',
          privateKey: 'KEY-A',
          publicKey: 'pub-a',
          keyType: 'ed25519',
          createdAt: DateTime(2024),
        ),
        'k-extra': SshKeyEntry(
          id: 'k-extra',
          label: 'Extra',
          privateKey: 'KEY-B',
          publicKey: 'pub-b',
          keyType: 'rsa',
          createdAt: DateTime(2024),
        ),
      };
      final result = decodeExportPayload(
        encodeExportPayload(
          [session],
          input: ExportPayloadInput(
            options: const ExportOptions(includeAllManagerKeys: true),
            managerKeyEntries: allKeys,
          ),
        ),
      );
      // Both keys should be in managerKeys (one from session, one extra).
      expect(result!.managerKeys, hasLength(2));
      final labels = result.managerKeys.map((k) => k.label).toSet();
      expect(labels, containsAll(['Used', 'Extra']));
    });
  });

  group('_relevantEmptyFolders matching logic', () {
    // Tests the exact-match / prefix-match logic via encode/decode roundtrip
    // with nested folder names that would be caught by the old startsWith bug.
    test('empty folders survive roundtrip unchanged', () {
      final sessions = [makeSession(folder: 'Production/Web')];
      final emptyFolders = {'Production', 'Staging'};
      final result = decodeExportPayload(
        encodeExportPayload(
          sessions,
          input: ExportPayloadInput(emptyFolders: emptyFolders),
        ),
      );
      expect(result!.emptyFolders, containsAll(['Production', 'Staging']));
      expect(result.emptyFolders, isNot(contains('Prod')));
    });
  });
}
