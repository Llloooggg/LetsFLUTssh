import 'dart:convert' show LineSplitter;
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
/// which doesn't need this enumeration step. Each include token
/// resolves to a single canonical path (tilde / relative-anchor handled
/// the same way the Rust parser does — no glob walk because the Dart
/// side doesn't have a filesystem to walk in tests). The visited set
/// prevents `Include loop.conf` infinite loops.
Map<String, String> _collectIncludeMap(
  String content,
  IncludeReader reader,
  String baseDir,
  int maxDepth,
) {
  final out = <String, String>{};
  final visited = <String>{};
  _collectIncludeMapInto(content, reader, baseDir, maxDepth, visited, out);
  return out;
}

void _collectIncludeMapInto(
  String content,
  IncludeReader reader,
  String baseDir,
  int remainingDepth,
  Set<String> visited,
  Map<String, String> out,
) {
  if (remainingDepth <= 0) return;
  for (final rawLine in const LineSplitter().convert(content)) {
    final line = rust_ssh_config.sshConfigStripComment(line: rawLine).trim();
    if (line.isEmpty) continue;
    final pair = rust_ssh_config.sshConfigSplitKeywordValue(line: line);
    if (pair == null) continue;
    if (pair.$1.toLowerCase() != 'include') continue;
    for (final token in rust_ssh_config.sshConfigSplitHostPatterns(
      value: pair.$2,
    )) {
      final resolved = _resolveSingleIncludePath(token, baseDir);
      if (!visited.add(resolved)) continue;
      final body = reader(resolved);
      if (body == null) continue;
      out[resolved] = body;
      _collectIncludeMapInto(
        body,
        reader,
        baseDir,
        remainingDepth - 1,
        visited,
        out,
      );
    }
  }
}

/// Mirrors `lfs_core::ssh_config::resolve_include_paths` (non-glob
/// variant) for the test-only include map collector. Tilde expansion
/// uses the Dart-side `homeDirectory` so test contexts that haven't
/// bootstrapped FRB still resolve. Globs are out of scope — the test
/// path expects fully-resolved paths in its canned map.
String _resolveSingleIncludePath(String pattern, String baseDir) {
  if (pattern == '~') return homeDirectory;
  if (pattern.startsWith('~/')) return '$homeDirectory${pattern.substring(1)}';
  if (_isAbsolutePath(pattern)) return pattern;
  return '$baseDir${Platform.pathSeparator}$pattern';
}

bool _isAbsolutePath(String path) {
  if (path.startsWith('/')) return true;
  if (path.length >= 2 && path[1] == ':') return true;
  if (path.startsWith(r'\\')) return true;
  return false;
}

String _defaultSshDir() => '$homeDirectory${Platform.pathSeparator}.ssh';
