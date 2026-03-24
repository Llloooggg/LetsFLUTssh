import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'package:path_provider/path_provider.dart';

/// Encrypted credential store — file-based AES-256-GCM.
///
/// Stores secrets (passwords, PEM keys, passphrases) in an encrypted JSON file
/// separate from the plaintext session data. Uses a machine-local key derived
/// from a random salt stored alongside.
class CredentialStore {
  static const _credFileName = 'credentials.enc';
  static const _keyFileName = 'credentials.key';

  String? _basePath;

  Future<String> _getBasePath() async {
    if (_basePath != null) return _basePath!;
    final dir = await getApplicationSupportDirectory();
    _basePath = dir.path;
    return _basePath!;
  }

  /// Load all credentials. Returns map of sessionId → CredentialData.
  Future<Map<String, CredentialData>> loadAll() async {
    final basePath = await _getBasePath();
    final credFile = File('$basePath/$_credFileName');
    final keyFile = File('$basePath/$_keyFileName');

    if (!await credFile.exists() || !await keyFile.exists()) {
      return {};
    }

    try {
      final keyBytes = await keyFile.readAsBytes();
      final encData = await credFile.readAsBytes();
      final json = _decrypt(encData, keyBytes);
      final map = jsonDecode(json) as Map<String, dynamic>;
      return map.map((k, v) =>
          MapEntry(k, CredentialData.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  /// Save all credentials.
  Future<void> saveAll(Map<String, CredentialData> credentials) async {
    final basePath = await _getBasePath();
    final credFile = File('$basePath/$_credFileName');
    final keyFile = File('$basePath/$_keyFileName');

    // Generate or load key
    Uint8List keyBytes;
    if (await keyFile.exists()) {
      keyBytes = await keyFile.readAsBytes();
    } else {
      keyBytes = _generateKey();
      await keyFile.writeAsBytes(keyBytes);
    }

    final json = jsonEncode(
      credentials.map((k, v) => MapEntry(k, v.toJson())),
    );
    final encData = _encrypt(json, keyBytes);
    await credFile.writeAsBytes(encData);
  }

  /// Get credentials for a session.
  Future<CredentialData?> get(String sessionId) async {
    final all = await loadAll();
    return all[sessionId];
  }

  /// Set credentials for a session.
  Future<void> set(String sessionId, CredentialData data) async {
    final all = await loadAll();
    all[sessionId] = data;
    await saveAll(all);
  }

  /// Delete credentials for a session.
  Future<void> delete(String sessionId) async {
    final all = await loadAll();
    all.remove(sessionId);
    await saveAll(all);
  }

  Uint8List _generateKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
  }

  Uint8List _encrypt(String plaintext, Uint8List key) {
    final random = Random.secure();
    final iv = Uint8List.fromList(
      List.generate(12, (_) => random.nextInt(256)),
    );

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
      );

    final input = Uint8List.fromList(utf8.encode(plaintext));
    final output = cipher.process(input);

    // Format: [iv (12)] [ciphertext+tag]
    return Uint8List.fromList([...iv, ...output]);
  }

  String _decrypt(Uint8List data, Uint8List key) {
    final iv = data.sublist(0, 12);
    final ciphertext = data.sublist(12);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
      );

    final output = cipher.process(ciphertext);
    return utf8.decode(output);
  }
}

/// Credential data for a single session.
class CredentialData {
  final String password;
  final String keyData;
  final String passphrase;

  const CredentialData({
    this.password = '',
    this.keyData = '',
    this.passphrase = '',
  });

  bool get isEmpty => password.isEmpty && keyData.isEmpty && passphrase.isEmpty;

  Map<String, dynamic> toJson() => {
    'password': password,
    'key_data': keyData,
    'passphrase': passphrase,
  };

  factory CredentialData.fromJson(Map<String, dynamic> json) {
    return CredentialData(
      password: json['password'] as String? ?? '',
      keyData: json['key_data'] as String? ?? '',
      passphrase: json['passphrase'] as String? ?? '',
    );
  }
}
