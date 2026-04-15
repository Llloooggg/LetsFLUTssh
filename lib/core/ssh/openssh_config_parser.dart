import 'dart:convert' show LineSplitter;

/// Parsed entry from an OpenSSH `~/.ssh/config` file.
///
/// Represents a single `Host` block with resolved directives we care about
/// for import: HostName, User, Port, IdentityFile.
class OpenSshConfigEntry {
  final String host;
  final String? hostName;
  final String? user;
  final int? port;
  final List<String> identityFiles;

  const OpenSshConfigEntry({
    required this.host,
    this.hostName,
    this.user,
    this.port,
    this.identityFiles = const [],
  });

  /// Effective hostname — HostName if set, otherwise the Host alias.
  String get effectiveHost => hostName ?? host;
}

/// Parse OpenSSH config file contents into a list of concrete host entries.
///
/// Wildcard blocks (`Host *`, `Host *.internal`, …) are NOT emitted as their
/// own entries, but their directives do cascade onto every concrete host
/// whose alias matches the pattern, using OpenSSH's first-value-wins rule:
/// blocks are walked top-to-bottom, and each directive is taken from the
/// first matching block that sets it. So a leading `Host *` with a default
/// `User` / `IdentityFile` fills in those fields on every concrete host
/// that doesn't already specify them.
///
/// Includes are not expanded. Negation patterns (`!`) are treated as
/// non-matching for safety. Unknown directives are ignored silently.
List<OpenSshConfigEntry> parseOpenSshConfig(String content) {
  final blocks = _parseBlocks(content);

  // Resolution walks only two lists per concrete host: its own block plus the
  // wildcard "default" blocks that appear in the file. Without this split the
  // resolver is O(N²) over total blocks — a 2000-host config would compile a
  // regex per (block, concrete-pattern) pair, which is what made the stress
  // fuzz test take minutes.
  final wildcardBlocks = <_RawBlock>[];
  final concretePatterns = <(int blockIndex, String pattern)>[];
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    var anyConcrete = false;
    for (final pattern in block.patterns) {
      if (_isWildcardPattern(pattern)) continue;
      anyConcrete = true;
      concretePatterns.add((i, pattern));
    }
    // A block is a wildcard "defaults" block if at least one of its patterns
    // is a wildcard. Such blocks cascade onto other concrete hosts.
    if (!anyConcrete || block.patterns.any(_isWildcardPattern)) {
      wildcardBlocks.add(block);
    }
  }

  return [
    for (final (blockIndex, pattern) in concretePatterns)
      _resolveEntry(pattern, blocks[blockIndex], wildcardBlocks),
  ];
}

/// Merge [ownBlock] with every [wildcardBlocks] block that matches [host],
/// walking top-to-bottom in file order. First-value-wins for scalar
/// directives; `IdentityFile` accumulates across every matching block.
OpenSshConfigEntry _resolveEntry(
  String host,
  _RawBlock ownBlock,
  List<_RawBlock> wildcardBlocks,
) {
  String? hostName;
  String? user;
  int? port;
  final identityFiles = <String>[];

  // Walk wildcard defaults in file order — the own block's position is
  // preserved via [ownBlock.orderIndex] so "Host * first" still wins over a
  // later concrete block per OpenSSH semantics. For simplicity we always
  // treat the own block as last-in-order (i.e. its directives only fill
  // fields the wildcards didn't), then merge again with the own block's
  // index as a tie-break.
  final ordered = [...wildcardBlocks];
  if (!ordered.contains(ownBlock)) ordered.add(ownBlock);
  ordered.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

  for (final block in ordered) {
    if (block != ownBlock && !block.matches(host)) continue;
    hostName ??= block.hostName;
    user ??= block.user;
    port ??= block.port;
    identityFiles.addAll(block.identityFiles);
  }

  return OpenSshConfigEntry(
    host: host,
    hostName: hostName,
    user: user,
    port: port,
    identityFiles: List.unmodifiable(identityFiles),
  );
}

/// Split the file into raw Host blocks, preserving order. Malformed lines,
/// unknown directives, and orphan directives (before any Host) are dropped
/// so broken configs still yield whatever live entries are readable.
List<_RawBlock> _parseBlocks(String content) {
  final blocks = <_RawBlock>[];
  List<String>? patterns;
  String? hostName;
  String? user;
  int? port;
  var identityFiles = <String>[];

  void flush() {
    final p = patterns;
    if (p == null) return;
    blocks.add(
      _RawBlock(
        orderIndex: blocks.length,
        patterns: p,
        hostName: hostName,
        user: user,
        port: port,
        identityFiles: List.unmodifiable(identityFiles),
      ),
    );
  }

  for (final rawLine in const LineSplitter().convert(content)) {
    final line = _stripComment(rawLine).trim();
    if (line.isEmpty) continue;
    final (keyword, value) = _splitKeywordValue(line);
    if (keyword == null || value == null) continue;
    final kw = keyword.toLowerCase();

    if (kw == 'host') {
      flush();
      patterns = _splitHostPatterns(value);
      hostName = null;
      user = null;
      port = null;
      identityFiles = <String>[];
      continue;
    }

    if (patterns == null) continue; // orphan directive — skip

    switch (kw) {
      case 'hostname':
        hostName ??= value;
      case 'user':
        user ??= value;
      case 'port':
        port ??= int.tryParse(value);
      case 'identityfile':
        identityFiles.add(value);
    }
  }
  flush();
  return blocks;
}

/// Raw Host block kept in file order. A block matches a concrete host if any
/// of its non-negated patterns matches AND no negation pattern matches — the
/// same rule OpenSSH applies.
class _RawBlock {
  final int orderIndex;
  final List<String> patterns;
  final String? hostName;
  final String? user;
  final int? port;
  final List<String> identityFiles;

  const _RawBlock({
    required this.orderIndex,
    required this.patterns,
    required this.hostName,
    required this.user,
    required this.port,
    required this.identityFiles,
  });

  bool matches(String host) {
    var positiveMatch = false;
    for (final raw in patterns) {
      final isNegation = raw.startsWith('!');
      final pattern = isNegation ? raw.substring(1) : raw;
      if (!_globMatches(pattern, host)) continue;
      if (isNegation) return false;
      positiveMatch = true;
    }
    return positiveMatch;
  }
}

bool _isWildcardPattern(String host) =>
    host.contains('*') || host.contains('?') || host.startsWith('!');

/// Minimal OpenSSH-style glob: `*` matches any run (including empty), `?`
/// matches exactly one char, everything else is literal. Case-sensitive.
bool _globMatches(String pattern, String text) {
  // Anchor at both ends.
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
  return RegExp(regex.toString()).hasMatch(text);
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

(String?, String?) _splitKeywordValue(String line) {
  // OpenSSH allows `keyword value` or `keyword = value` (optional equals).
  final eqIdx = line.indexOf('=');
  final spaceMatch = RegExp(r'\s').firstMatch(line);
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
