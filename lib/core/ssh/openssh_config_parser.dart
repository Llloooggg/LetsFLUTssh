import 'dart:convert' show LineSplitter;
import 'dart:io';

import '../../src/rust/api/ssh_config.dart' as rust_ssh_config;
import '../../utils/logger.dart';
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
/// directive, or null when the file does not exist / cannot be read. Injected
/// for test isolation — tests pass a canned in-memory map instead of hitting
/// the real filesystem.
typedef IncludeReader = String? Function(String path);

/// Parse OpenSSH config file contents into a list of concrete host entries.
///
/// Wildcard blocks (`Host *`, `Host *.internal`, …) are NOT emitted as their
/// own entries, but their directives do cascade onto every concrete host
/// whose alias matches the pattern, using OpenSSH's first-value-wins rule.
///
/// `Include` directives are expanded against [includeReader] (defaults to the
/// real filesystem). The `baseDir` argument anchors relative paths — defaults
/// to `~/.ssh`, matching `ssh_config(5)` semantics. Recursion is bounded by
/// [maxIncludeDepth] to stop pathological configs (`Include ./config`) from
/// stack-overflowing. Negation patterns (`!`) are treated as non-matching.
/// Unknown directives are ignored silently.
List<OpenSshConfigEntry> parseOpenSshConfig(
  String content, {
  IncludeReader? includeReader,
  String? baseDir,
  int maxIncludeDepth = 8,
}) {
  final reader = includeReader ?? _defaultIncludeReader;
  final base = baseDir ?? _defaultSshDir();
  final expanded = _expandIncludes(content, reader, base, maxIncludeDepth, {});
  // Hand the fully-expanded content (no remaining Include directives)
  // to the Rust parser. Dart owns the filesystem walk so per-platform
  // home semantics — Android's `EXTERNAL_STORAGE` fallback, in
  // particular — stay where they belong. Block resolution + wildcard
  // cascading + PreferredAuthentications mapping live Rust-side now.
  final rustEntries = rust_ssh_config.parseOpensshConfig(content: expanded);
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

/// Expand `Include` directives into a single config string. Matches OpenSSH
/// behaviour: relative paths resolve against [baseDir] (typically `~/.ssh`);
/// absolute paths pass through; glob patterns (`*`, `?`) expand to matching
/// files. Nested includes are honoured up to [remainingDepth] levels.
String _expandIncludes(
  String content,
  IncludeReader reader,
  String baseDir,
  int remainingDepth,
  Set<String> visited,
) {
  if (remainingDepth <= 0) {
    AppLogger.instance.log(
      'Include depth limit reached — further includes ignored',
      name: 'SshConfigParser',
    );
    return content;
  }
  final buffer = StringBuffer();
  for (final rawLine in const LineSplitter().convert(content)) {
    final expansion = _maybeExpandIncludeLine(
      rawLine,
      reader,
      baseDir,
      remainingDepth,
      visited,
    );
    if (expansion == null) {
      buffer.writeln(rawLine);
    } else {
      buffer.write(expansion);
    }
  }
  return buffer.toString();
}

/// Returns the expanded content for [rawLine] if it is a valid `Include`
/// directive, otherwise null so the caller can pass the line through
/// unchanged. Blank lines, comments, and non-Include directives all return
/// null — only a well-formed `Include <tokens>` line produces expansion
/// output.
String? _maybeExpandIncludeLine(
  String rawLine,
  IncludeReader reader,
  String baseDir,
  int remainingDepth,
  Set<String> visited,
) {
  final line = _stripComment(rawLine).trim();
  if (line.isEmpty) return null;
  final (keyword, value) = _splitKeywordValue(line);
  if (keyword == null || value == null || keyword.toLowerCase() != 'include') {
    return null;
  }
  return _expandIncludeTokens(value, reader, baseDir, remainingDepth, visited);
}

/// Resolve and concatenate every file referenced by a single `Include`
/// directive. Each whitespace-separated token is a pattern — e.g.
/// `Include config.d/* extra`. The contents of every matched file are
/// emitted inline so host blocks read as if they were written in place.
String _expandIncludeTokens(
  String value,
  IncludeReader reader,
  String baseDir,
  int remainingDepth,
  Set<String> visited,
) {
  final buffer = StringBuffer();
  for (final token in _splitHostPatterns(value)) {
    for (final resolved in _resolveIncludePaths(token, baseDir)) {
      if (!visited.add(resolved)) continue;
      final included = reader(resolved);
      if (included == null) continue;
      buffer.writeln(
        _expandIncludes(included, reader, baseDir, remainingDepth - 1, visited),
      );
    }
  }
  return buffer.toString();
}

/// Resolve one include pattern to the concrete files it matches.
///
/// `~` expands to the user home. Relative paths are anchored at [baseDir].
/// Globs use [_globMatches] on the basename so nested globs like `**` are
/// NOT supported — same limitation as OpenSSH 7.x.
List<String> _resolveIncludePaths(String pattern, String baseDir) {
  var resolved = pattern;
  if (resolved == '~') resolved = homeDirectory;
  if (resolved.startsWith('~/')) {
    resolved = '$homeDirectory${resolved.substring(1)}';
  } else if (!_isAbsolutePath(resolved)) {
    resolved = '$baseDir${Platform.pathSeparator}$resolved';
  }
  if (!resolved.contains('*') && !resolved.contains('?')) return [resolved];
  return _globFiles(resolved);
}

bool _isAbsolutePath(String path) {
  if (path.startsWith('/')) return true;
  // Windows drive letter (`C:\...`) or UNC path.
  if (path.length >= 2 && path[1] == ':') return true;
  if (path.startsWith(r'\\')) return true;
  return false;
}

/// List every real file that matches a glob like `~/.ssh/config.d/*`.
/// Only the basename portion is globbed; the parent directory must exist.
List<String> _globFiles(String pattern) {
  final normalized = pattern.replaceAll('\\', '/');
  final idx = normalized.lastIndexOf('/');
  if (idx < 0) return const [];
  final dirPath = pattern.substring(0, idx);
  final basePattern = normalized.substring(idx + 1);
  try {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return const [];
    final matches = <String>[];
    for (final entry in dir.listSync(followLinks: false)) {
      if (entry is! File) continue;
      final name = entry.path.split(Platform.pathSeparator).last;
      if (_globMatches(basePattern, name)) matches.add(entry.path);
    }
    matches.sort();
    return matches;
  } catch (_) {
    return const [];
  }
}

String _defaultSshDir() => '$homeDirectory${Platform.pathSeparator}.ssh';

String? _defaultIncludeReader(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    // Match the single-file size limit used elsewhere in the import flow —
    // an include that ships megabytes of text is almost certainly malicious.
    if (file.lengthSync() > 1024 * 1024) return null;
    return file.readAsStringSync();
  } catch (_) {
    return null;
  }
}

/// Compiled globs keyed by raw pattern. OpenSSH config rarely declares
/// more than a handful of distinct `Host` patterns, so the cache stays
/// tiny for the life of the process. Without it, [_globMatches] recompiled
/// a [RegExp] per `(pattern, name)` pair on every Include expansion.
final _globRegexCache = <String, RegExp>{};

RegExp _compileGlob(String pattern) {
  final regex = StringBuffer('^');
  for (final c in pattern.split('')) {
    if (c == '*') {
      regex.write('.*');
    } else if (c == '?') {
      regex.write('.');
    } else {
      regex.write(RegExp.escape(c));
    }
  }
  regex.write(r'$');
  return RegExp(regex.toString());
}

/// Minimal OpenSSH-style glob: `*` matches any run (including empty), `?`
/// matches exactly one char, everything else is literal. Case-sensitive.
bool _globMatches(String pattern, String text) {
  final compiled = _globRegexCache.putIfAbsent(
    pattern,
    () => _compileGlob(pattern),
  );
  return compiled.hasMatch(text);
}

String _stripComment(String line) {
  // Comments start with '#' but only outside quoted strings.
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final c = line[i];
    if (c == '"') inQuotes = !inQuotes;
    if (c == '#' && !inQuotes) return line.substring(0, i);
  }
  return line;
}

/// Matches the first whitespace character; pre-compiled so the
/// per-line [_splitKeywordValue] scan does not recompile the regex on
/// every config line.
final _whitespaceRegex = RegExp(r'\s');

(String?, String?) _splitKeywordValue(String line) {
  // OpenSSH allows `keyword value` or `keyword = value` (optional equals).
  final eqIdx = line.indexOf('=');
  final spaceMatch = _whitespaceRegex.firstMatch(line);
  final spaceIdx = spaceMatch?.start ?? -1;

  int sepIdx;
  if (eqIdx < 0) {
    sepIdx = spaceIdx;
  } else if (spaceIdx < 0) {
    sepIdx = eqIdx;
  } else {
    sepIdx = eqIdx < spaceIdx ? eqIdx : spaceIdx;
  }
  if (sepIdx < 0) return (null, null);

  final keyword = line.substring(0, sepIdx).trim();
  var rest = line.substring(sepIdx + 1).trim();
  // Strip optional `=` between keyword and value.
  if (rest.startsWith('=')) rest = rest.substring(1).trim();
  if (keyword.isEmpty || rest.isEmpty) return (null, null);
  return (keyword, _unquote(rest));
}

String _unquote(String value) {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

List<String> _splitHostPatterns(String value) {
  // Host line can list multiple patterns separated by whitespace.
  // Quoted patterns preserve spaces.
  final result = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < value.length; i++) {
    final c = value[i];
    if (c == '"') {
      inQuotes = !inQuotes;
      continue;
    }
    if (!inQuotes && (c == ' ' || c == '\t')) {
      if (buf.isNotEmpty) {
        result.add(buf.toString());
        buf.clear();
      }
      continue;
    }
    buf.write(c);
  }
  if (buf.isNotEmpty) result.add(buf.toString());
  return result;
}
