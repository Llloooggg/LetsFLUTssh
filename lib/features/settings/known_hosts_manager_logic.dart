/// Pure helpers for the [`KnownHostsManagerPanel`] state — extracted
/// so the search / filter rules can be exercised against fixed
/// payloads without a Riverpod scope or a `KnownHostsMutator`
/// instance.
library;

/// Sort host entries alphabetically by host:port and apply the
/// case-insensitive [filter] over both the host:port key and the
/// SSH-key payload value. An empty filter returns every entry in
/// sorted order; otherwise the filter substring matches against
/// either side. Sorting happens before filtering so the user-visible
/// order is stable as the user types.
List<MapEntry<String, String>> filterKnownHostEntries(
  Map<String, String> entries,
  String filter,
) {
  final sorted = entries.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  if (filter.isEmpty) return sorted;
  final lower = filter.toLowerCase();
  return sorted.where((e) {
    return e.key.toLowerCase().contains(lower) ||
        e.value.toLowerCase().contains(lower);
  }).toList();
}

/// Split a `known_hosts` value (`<keyType> <base64KeyData>` and
/// optional comment / fingerprint suffix) into its first two
/// whitespace-separated components. Returns `('', '')` for an empty
/// value, `(keyType, '')` when only the type is present, and
/// `(keyType, keyData)` for the well-formed shape.
({String keyType, String keyData}) splitKnownHostValue(String value) {
  final parts = value.split(' ');
  final keyType = parts.isNotEmpty ? parts[0] : '';
  final keyData = parts.length > 1 ? parts[1] : '';
  return (keyType: keyType, keyData: keyData);
}
