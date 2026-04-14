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
/// Wildcard patterns (`*`, `?`, `!`) and the catch-all `Host *` block are
/// skipped — only concrete aliases are returned. Includes are not expanded.
/// Unknown directives are ignored silently.
List<OpenSshConfigEntry> parseOpenSshConfig(String content) {
  final entries = <OpenSshConfigEntry>[];
  final lines = const LineSplitter().convert(content);
  // (LineSplitter handles \r\n, \r, \n)

  List<String>? currentHosts;
  String? hostName;
  String? user;
  int? port;
  final identityFiles = <String>[];

  void flush() {
    final hosts = currentHosts;
    if (hosts == null) return;
    for (final h in hosts) {
      if (_isWildcard(h)) continue;
      entries.add(
        OpenSshConfigEntry(
          host: h,
          hostName: hostName,
          user: user,
          port: port,
          identityFiles: List.unmodifiable(identityFiles),
        ),
      );
    }
  }

  for (final rawLine in lines) {
    final line = _stripComment(rawLine).trim();
    if (line.isEmpty) continue;

    final (keyword, value) = _splitKeywordValue(line);
    if (keyword == null || value == null) continue;

    final kw = keyword.toLowerCase();
    if (kw == 'host') {
      flush();
      currentHosts = _splitHostPatterns(value);
      hostName = null;
      user = null;
      port = null;
      identityFiles.clear();
      continue;
    }

    if (currentHosts == null) continue; // Match/global scope — skip

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
  return entries;
}

bool _isWildcard(String host) =>
    host.contains('*') || host.contains('?') || host.startsWith('!');

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
