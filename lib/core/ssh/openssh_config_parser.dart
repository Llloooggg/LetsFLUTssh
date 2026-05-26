import 'dart:io' show Platform;

import '../../src/rust/api/ssh_config.dart' as rust_ssh_config;
import '../../utils/platform.dart';
import '../session/session.dart' show AuthType;

/// Parsed entry from an OpenSSH `~/.ssh/config` file.
///
/// Represents a single `Host` block with resolved directives we care about
/// for import: HostName, User, Port, IdentityFile, PreferredAuthentications.
class OpenSshConfigEntry {
  final String host;
  final String? hostName;
  final String? user;
  final int? port;
  final List<String> identityFiles;

  /// Resolved `PreferredAuthentications` list, mapped to the enum values we
  /// understand (`password`, `key`). Null means the user didn't set the
  /// directive — importer can fall back to "key if IdentityFile, password
  /// otherwise". An empty list means every listed method was unknown and
  /// was filtered out; treat identical to null.
  final List<AuthType>? preferredAuthTypes;

  const OpenSshConfigEntry({
    required this.host,
    this.hostName,
    this.user,
    this.port,
    this.identityFiles = const [],
    this.preferredAuthTypes,
  });

  /// Effective hostname — HostName if set, otherwise the Host alias.
  String get effectiveHost => hostName ?? host;
}

/// Reader that returns the contents of a file referenced by an `Include`
/// directive, or null when the file does not exist / cannot be read.
/// **Test-only** — production calls go through the Rust resolver which
/// performs real filesystem reads + glob enumeration directly. Unit
/// tests that want to inject canned content build a `path → content`
/// map and pass [parseOpenSshConfig] the corresponding [includeReader].
typedef IncludeReader = String? Function(String path);

/// Parse OpenSSH config file contents into a list of concrete host entries.
///
/// Wildcard blocks (`Host *`, `Host *.internal`, …) are NOT emitted as their
/// own entries, but their directives do cascade onto every concrete host
/// whose alias matches the pattern, using OpenSSH's first-value-wins rule.
///
/// `Include` directives are expanded Rust-side. Production callers leave
/// [includeReader] null and the resolver performs real filesystem reads
/// + glob enumeration via `lfs_core::ssh_config::parse_openssh_config_with_fs`.
/// Unit tests pass an in-memory map through [includeReader] so they
/// don't need to stage files on disk; that path routes through the
/// existing `parse_openssh_config_with_includes` which takes a
/// path → content map (no glob expansion — provide the resolved paths
/// the test cares about). Recursion is bounded by [maxIncludeDepth].
List<OpenSshConfigEntry> parseOpenSshConfig(
  String content, {
  IncludeReader? includeReader,
  String? baseDir,
  int maxIncludeDepth = 8,
}) {
  final base = baseDir ?? _defaultSshDir();
  final List<rust_ssh_config.DbOpenSshHostEntry> rustEntries;
  if (includeReader == null) {
    rustEntries = rust_ssh_config.parseOpensshConfigResolving(
      content: content,
      baseDir: base,
      maxIncludeDepth: maxIncludeDepth,
    );
  } else {
    rustEntries = rust_ssh_config.parseOpensshConfigWithIncludes(
      content: content,
      baseDir: base,
      includes: _collectIncludeMap(
        content,
        includeReader,
        base,
        maxIncludeDepth,
      ),
      maxIncludeDepth: maxIncludeDepth,
    );
  }
  return [for (final e in rustEntries) _fromRustEntry(e)];
}

OpenSshConfigEntry _fromRustEntry(rust_ssh_config.DbOpenSshHostEntry e) {
  final preferred = e.preferredAuthTypes
      ?.map(
        (a) => switch (a) {
          rust_ssh_config.DbOpenSshAuthType.password => AuthType.password,
          rust_ssh_config.DbOpenSshAuthType.key => AuthType.key,
        },
      )
      .toList(growable: false);
  return OpenSshConfigEntry(
    host: e.host,
    hostName: e.hostName,
    user: e.user,
    port: e.port,
    identityFiles: List.unmodifiable(e.identityFiles),
    preferredAuthTypes: preferred == null ? null : List.unmodifiable(preferred),
  );
}

/// Walk the include tree recursively via [reader], collecting every
/// path the reader is asked for into a `path → content` map. Used only
/// by the test path: production goes through Rust's real-fs resolver
/// which doesn't need this enumeration step. Per-line include-token
/// resolution lives in `lfs_core::ssh_config::resolve_include_paths_for_content`
/// (exposed via FRB); the visited set + recursion stay Dart-side
/// because the [reader] callback is Dart-side. The visited set
/// prevents `Include loop.conf` infinite loops.
Map<String, String> _collectIncludeMap(
  String content,
  IncludeReader reader,
  String baseDir,
  int maxDepth,
) {
  final out = <String, String>{};
  final visited = <String>{};
  void walk(String body, int depth) {
    if (depth <= 0) return;
    final paths = rust_ssh_config.sshConfigResolveIncludePaths(
      content: body,
      baseDir: baseDir,
    );
    for (final path in paths) {
      if (!visited.add(path)) continue;
      final included = reader(path);
      if (included == null) continue;
      out[path] = included;
      walk(included, depth - 1);
    }
  }

  walk(content, maxDepth);
  return out;
}

String _defaultSshDir() => '$homeDirectory${Platform.pathSeparator}.ssh';
