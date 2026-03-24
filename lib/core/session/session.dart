import 'dart:io';

import 'package:uuid/uuid.dart';

import '../ssh/ssh_config.dart';

/// Authentication type for a session.
enum AuthType { password, key, keyWithPassword }

/// SSH session model — stored as JSON, credentials inline (Phase 5 will move to secure storage).
class Session {
  final String id;
  final String label;
  final String group; // path like "Production/Web"
  final String host;
  final int port;
  final String user;
  final AuthType authType;
  final String password;
  final String keyPath;
  final String keyData; // raw PEM text
  final String passphrase;
  final DateTime createdAt;
  final DateTime updatedAt;

  Session({
    String? id,
    required this.label,
    this.group = '',
    required this.host,
    this.port = 22,
    required this.user,
    this.authType = AuthType.password,
    this.password = '',
    this.keyPath = '',
    this.keyData = '',
    this.passphrase = '',
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Validate required fields. Returns error message or null.
  String? validate() {
    if (host.trim().isEmpty) return 'Host is required';
    if (port < 1 || port > 65535) return 'Port must be 1-65535';
    if (user.trim().isEmpty) return 'Username is required';
    return null;
  }

  /// Display string: "label (user@host)" or "user@host" if no label.
  String get displayName =>
      label.isNotEmpty ? '$label ($user@$host)' : '$user@$host:$port';

  /// Full group path with label for tree display.
  String get fullPath => group.isNotEmpty ? '$group/$label' : label;

  /// Convert to SSHConfig for connecting.
  SSHConfig toSSHConfig() {
    final expandedKeyPath = keyPath.replaceFirst(
      '~',
      Platform.environment['HOME'] ?? '',
    );
    return SSHConfig(
      host: host,
      port: port,
      user: user,
      password: password,
      keyPath: expandedKeyPath,
      keyData: keyData,
      passphrase: passphrase,
    );
  }

  Session copyWith({
    String? label,
    String? group,
    String? host,
    int? port,
    String? user,
    AuthType? authType,
    String? password,
    String? keyPath,
    String? keyData,
    String? passphrase,
  }) {
    return Session(
      id: id,
      label: label ?? this.label,
      group: group ?? this.group,
      host: host ?? this.host,
      port: port ?? this.port,
      user: user ?? this.user,
      authType: authType ?? this.authType,
      password: password ?? this.password,
      keyPath: keyPath ?? this.keyPath,
      keyData: keyData ?? this.keyData,
      passphrase: passphrase ?? this.passphrase,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// Create a duplicate with new ID and "(copy)" suffix.
  Session duplicate() {
    return Session(
      label: '$label (copy)',
      group: group,
      host: host,
      port: port,
      user: user,
      authType: authType,
      password: password,
      keyPath: keyPath,
      keyData: keyData,
      passphrase: passphrase,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'group': group,
    'host': host,
    'port': port,
    'user': user,
    'auth_type': authType.name,
    'password': password,
    'key_path': keyPath,
    'key_data': keyData,
    'passphrase': passphrase,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      label: json['label'] as String? ?? '',
      group: json['group'] as String? ?? '',
      host: json['host'] as String,
      port: json['port'] as int? ?? 22,
      user: json['user'] as String,
      authType: AuthType.values.firstWhere(
        (e) => e.name == json['auth_type'],
        orElse: () => AuthType.password,
      ),
      password: json['password'] as String? ?? '',
      keyPath: json['key_path'] as String? ?? '',
      keyData: json['key_data'] as String? ?? '',
      passphrase: json['passphrase'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
