/// Pure helpers for tag UI surfaces (manager + assign dialog). The
/// case-insensitive name filter is shared, and the assign dialog's
/// "select all" tristate (all / none / partial) gets pinned here so
/// the off-by-one cases (zero tags, all assigned, none assigned, n
/// assigned out of m) have a clear test target.
library;

import '../../core/tags/tag.dart';

/// Apply the search filter to [tags]. Match is case-insensitive and
/// limited to the tag name — colour codes / metadata are not
/// surfaced in the UI list and would only add noise. Empty filter
/// returns the input list verbatim.
List<Tag> filterTagsByName(List<Tag> tags, String filter) {
  if (filter.isEmpty) return tags;
  final q = filter.toLowerCase();
  return tags.where((t) => t.name.toLowerCase().contains(q)).toList();
}

/// Tristate for the "select all" row in the assign dialog. Returns
/// `true` when every tag is in [assignedIds], `false` when none
/// are, and `null` for the partial state (the indeterminate /
/// "mixed" checkbox visual). The empty-tag-list edge case returns
/// `false` — there is nothing to flip "all on" against, and the
/// checkbox renders unchecked rather than mixed.
bool? allAssignedTristate({
  required List<Tag> allTags,
  required Set<String> assignedIds,
}) {
  if (allTags.isEmpty) return false;
  final n = assignedIds.length;
  if (n == 0) return false;
  if (n == allTags.length) return true;
  return null;
}
