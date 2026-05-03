/// Pure helpers for snippet UI surfaces (manager + picker). The
/// search rule is shared between `_SnippetManagerDialogState` and
/// `_SnippetPickerState`; centralising it here keeps the two
/// surfaces in sync and gives one test target instead of two.
library;

import '../../core/snippets/snippet.dart';

/// Apply the search filter to [snippets]. Match is case-insensitive
/// and spans three columns the picker / manager render: title,
/// command, and description. Empty filter returns the input list
/// verbatim. The body intentionally does not search across tag
/// links / link counts; that scope would need a separate predicate
/// + a different display contract.
List<Snippet> filterSnippets(List<Snippet> snippets, String filter) {
  if (filter.isEmpty) return snippets;
  final needle = filter.toLowerCase();
  return snippets.where((sn) {
    return sn.title.toLowerCase().contains(needle) ||
        sn.command.toLowerCase().contains(needle) ||
        sn.description.toLowerCase().contains(needle);
  }).toList();
}
