import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';

import '../../core/config/app_config.dart';
import '../../core/session/session.dart';

/// .lfs (LetsFLUTssh) archive format — ZIP encrypted with AES-256-GCM.
///
/// Structure inside ZIP:
///   sessions.json  — full session data WITH credentials
///   config.json    — app configuration
///   known_hosts    — TOFU host key database
///
/// The ZIP bytes are encrypted with AES-256-GCM using a key derived from
/// a master password via PBKDF2 (600k iterations, SHA-256).
class ExportImport {
  static const _saltLen = 32;
  static const _ivLen = 12;
  static const _pbkdf2Iterations = 600000;
  static const _sessionsFile = 'sessions.json';
  static const _configFile = 'config.json';
  static const _knownHostsFile = 'known_hosts';

  /// Export app data to an encrypted .lfs file.
  ///
  /// Returns the file path of the created archive.
  static Future<String> export({
    required String masterPassword,
    required List<Session> sessions,
    required AppConfig config,
    required String outputPath,
  }) async {
    // Build ZIP archive in memory
    final archive = Archive();

    // Sessions with credentials
    final sessionsJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(sessions.map((s) => s.toJsonWithCredentials()).toList());
    archive.addFile(
      ArchiveFile(
        _sessionsFile,
        utf8.encode(sessionsJson).length,
        utf8.encode(sessionsJson),
      ),
    );

    // Config
    final configJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(config.toJson());
    archive.addFile(
      ArchiveFile(
        _configFile,
        utf8.encode(configJson).length,
        utf8.encode(configJson),
      ),
    );

    // Known hosts (if exists)
    final dir = await getApplicationSupportDirectory();
    final knownHostsFile = File(p.join(dir.path, _knownHostsFile));
    if (await knownHostsFile.exists()) {
      final khBytes = await knownHostsFile.readAsBytes();
      archive.addFile(ArchiveFile(_knownHostsFile, khBytes.length, khBytes));
    }

    // Encode ZIP
    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

    // Encrypt with master password (runs in isolate — PBKDF2 600k is CPU-heavy)
    final encrypted = await Isolate.run(
      () => _encryptWithPassword(zipBytes, masterPassword),
    );

    // Write to file
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(encrypted);

    return outputPath;
  }

  /// Decrypt an .lfs file and parse the archive + sessions.
  static Future<({Archive archive, List<Session> sessions})>
  _decryptAndParseArchive({
    required String filePath,
    required String masterPassword,
  }) async {
    final file = File(filePath);
    final encData = await file.readAsBytes();

    // Decrypt in isolate — PBKDF2 600k iterations is CPU-heavy
    final zipBytes = await Isolate.run(
      () => _decryptWithPassword(encData, masterPassword),
    );
    final archive = ZipDecoder().decodeBytes(zipBytes);

    List<Session> sessions = [];
    final sessionsFile = archive.findFile(_sessionsFile);
    if (sessionsFile != null) {
      final json = utf8.decode(sessionsFile.content as List<int>);
      final list = jsonDecode(json) as List;
      sessions = list
          .map((e) => Session.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return (archive: archive, sessions: sessions);
  }

  /// Preview contents of an .lfs archive without full import.
  static Future<LfsPreview> preview({
    required String filePath,
    required String masterPassword,
  }) async {
    final (:archive, :sessions) = await _decryptAndParseArchive(
      filePath: filePath,
      masterPassword: masterPassword,
    );

    final hasConfig = archive.findFile(_configFile) != null;
    final hasKnownHosts = archive.findFile(_knownHostsFile) != null;

    return LfsPreview(
      sessions: sessions,
      hasConfig: hasConfig,
      hasKnownHosts: hasKnownHosts,
    );
  }

  /// Import data from an .lfs archive.
  ///
  /// [mode] controls how sessions are merged:
  /// - `ImportMode.merge` — add new sessions, skip existing (by ID)
  /// - `ImportMode.replace` — replace all sessions with imported ones
  static Future<ImportResult> import_({
    required String filePath,
    required String masterPassword,
    required ImportMode mode,
    required bool importConfig,
    required bool importKnownHosts,
  }) async {
    final (:archive, :sessions) = await _decryptAndParseArchive(
      filePath: filePath,
      masterPassword: masterPassword,
    );

    // Parse config
    AppConfig? config;
    if (importConfig) {
      final configFile = archive.findFile(_configFile);
      if (configFile != null) {
        final json = utf8.decode(configFile.content as List<int>);
        config = AppConfig.fromJson(jsonDecode(json) as Map<String, dynamic>);
      }
    }

    // Known hosts
    Uint8List? knownHostsData;
    if (importKnownHosts) {
      final khFile = archive.findFile(_knownHostsFile);
      if (khFile != null) {
        knownHostsData = Uint8List.fromList(khFile.content as List<int>);
      }
    }

    // Write known_hosts if requested
    if (knownHostsData != null) {
      final dir = await getApplicationSupportDirectory();
      final khFile = File(p.join(dir.path, _knownHostsFile));
      await khFile.writeAsBytes(knownHostsData);
    }

    return ImportResult(sessions: sessions, config: config, mode: mode);
  }

  // --- Crypto helpers ---

  /// Encrypt bytes with password-derived key (PBKDF2 + AES-256-GCM).
  /// Format: [salt (32)] [iv (12)] [ciphertext + GCM tag]
  static Uint8List _encryptWithPassword(Uint8List data, String password) {
    final random = Random.secure();
    final salt = Uint8List.fromList(
      List.generate(_saltLen, (_) => random.nextInt(256)),
    );
    final iv = Uint8List.fromList(
      List.generate(_ivLen, (_) => random.nextInt(256)),
    );

    final key = _deriveKey(password, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    final output = cipher.process(data);
    return Uint8List.fromList([...salt, ...iv, ...output]);
  }

  /// Decrypt bytes with password-derived key.
  static Uint8List _decryptWithPassword(Uint8List data, String password) {
    final salt = data.sublist(0, _saltLen);
    final iv = data.sublist(_saltLen, _saltLen + _ivLen);
    final ciphertext = data.sublist(_saltLen + _ivLen);

    final key = _deriveKey(password, salt);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    return cipher.process(ciphertext);
  }

  /// Derive 256-bit key from password using PBKDF2-SHA256.
  static Uint8List _deriveKey(String password, Uint8List salt) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _pbkdf2Iterations, 32));

    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }
}

/// Preview of .lfs archive contents.
class LfsPreview {
  final List<Session> sessions;
  final bool hasConfig;
  final bool hasKnownHosts;

  const LfsPreview({
    required this.sessions,
    required this.hasConfig,
    required this.hasKnownHosts,
  });
}

/// Import mode for sessions.
enum ImportMode { merge, replace }

/// Result of importing an .lfs archive.
class ImportResult {
  final List<Session> sessions;
  final AppConfig? config;
  final ImportMode mode;

  const ImportResult({required this.sessions, this.config, required this.mode});
}
