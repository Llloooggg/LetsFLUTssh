// Standalone fuzz target for JSON session parsing.
//
// Reads raw bytes from stdin, attempts to interpret them as JSON,
// and feeds the result to Session-like and AppConfig-like fromJson parsers.
// Compiled to native via `dart compile exe` for AFL++/ClusterFuzzLite.
//
// Usage:
//   dart compile exe fuzz/fuzz_json_parser.dart -o fuzz/out/fuzz_json_parser
//   echo '{"id":"x","host":"h","user":"u"}' | ./fuzz/out/fuzz_json_parser

import 'dart:convert';
import 'dart:io';

void main() {
  final input = stdin.readLineSync(encoding: utf8) ?? '';
  if (input.isEmpty) return;

  // Try to parse as JSON map
  final Object? decoded;
  try {
    decoded = jsonDecode(input);
  } catch (_) {
    return; // Not valid JSON — expected for random input
  }

  if (decoded is! Map<String, dynamic>) return;
  final json = decoded;

  // --- Session.fromJson simulation ---
  _parseSession(json);

  // --- AppConfig.fromJson simulation ---
  _parseAppConfig(json);

  // --- QR codec simulation ---
  _parseQrPayload(input);
}

/// Simulates Session.fromJson parsing logic without Flutter dependencies.
void _parseSession(Map<String, dynamic> json) {
  try {
    final id = json['id'] as String?;
    final host = json['host'] as String?;
    final user = json['user'] as String?;
    final port = json['port'] as int? ?? 22;
    final label = json['label'] as String? ?? '';
    final folder = json['folder'] as String? ?? json['group'] as String? ?? '';
    final authType = json['auth_type'] as String? ?? 'password';

    // Validate enum
    const validAuthTypes = ['password', 'key', 'keyWithPassword'];
    if (!validAuthTypes.contains(authType)) {
      // Use default
    }

    // Validate port
    if (port < 0 || port > 65535) {
      // Invalid but should not crash
    }

    // Parse dates
    final createdAt = json['created_at'] as String?;
    if (createdAt != null) {
      DateTime.tryParse(createdAt);
    }

    // Access all fields to trigger type errors
    json['password'] as String?;
    json['key_path'] as String?;
    json['key_data'] as String?;
    json['passphrase'] as String?;
    json['incomplete'] as bool?;

    // Use parsed values to prevent tree-shaking
    if (id != null && host != null && user != null) {
      label.hashCode;
      folder.hashCode;
    }
  } on TypeError {
    // Expected for type mismatches
  }
}

/// Simulates AppConfig.fromJson parsing logic without Flutter dependencies.
void _parseAppConfig(Map<String, dynamic> json) {
  try {
    // TerminalConfig
    final fontSize = (json['font_size'] as num?)?.toDouble() ?? 14.0;
    final theme = json['theme'] as String? ?? 'system';
    final scrollback = json['scrollback'] as int? ?? 5000;

    // Sanitize
    if (fontSize < 6 || fontSize > 72 || fontSize.isNaN) {
      // Clamp to default
    }
    const validThemes = ['dark', 'light', 'system'];
    if (!validThemes.contains(theme)) {
      // Use default
    }
    if (scrollback < 100) {
      // Clamp
    }

    // SshDefaults
    final keepAlive = json['keepalive_sec'] as int? ?? 30;
    final port = json['default_port'] as int? ?? 22;
    final timeout = json['ssh_timeout_sec'] as int? ?? 10;

    if (keepAlive < 0 || port < 1 || port > 65535 || timeout < 1) {
      // Sanitize
    }

    // UiConfig
    json['toast_duration_ms'] as int?;
    (json['window_width'] as num?)?.toDouble();
    (json['window_height'] as num?)?.toDouble();
    (json['ui_scale'] as num?)?.toDouble();
    json['show_folder_sizes'] as bool?;

    // BehaviorConfig
    json['enable_logging'] as bool?;
    json['check_updates_on_start'] as bool?;
    json['skipped_version'] as String?;

    // Top-level
    json['transfer_workers'] as int?;
    json['max_history'] as int?;
    json['locale'] as String?;
  } on TypeError {
    // Expected
  }
}

/// Simulates QR payload decoding without Flutter dependencies.
void _parseQrPayload(String input) {
  try {
    final json = jsonDecode(input);
    if (json is! Map<String, dynamic>) return;

    final version = json['v'] as int?;
    if (version != 1) return;

    final sessionList = json['s'] as List?;
    if (sessionList == null) return;

    for (final item in sessionList) {
      if (item is! Map<String, dynamic>) continue;
      item['l'] as String?;
      item['h'] as String?;
      item['u'] as String?;
      item['p'] as int?;
      item['g'] as String?;
      item['a'] as String?;
    }

    final emptyFolders = json['eg'] as List?;
    if (emptyFolders != null) {
      for (final f in emptyFolders) {
        f as String;
      }
    }
  } on TypeError {
    // Expected
  } on FormatException {
    // Expected — invalid JSON
  }
}
