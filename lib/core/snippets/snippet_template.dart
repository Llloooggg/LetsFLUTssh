import '../../src/rust/api/snippet_template.dart' as rust_snip;
import 'snippet.dart';

/// Result of rendering a snippet command against a context map.
///
/// `rendered` is the substituted command — known tokens replaced,
/// unknown tokens left intact so the picker can prompt the user.
/// `unresolved` lists each unknown token name in **first-seen order
/// without duplicates**, ready to be walked by the prompt dialog.
class SnippetRender {
  final String rendered;
  final List<String> unresolved;

  const SnippetRender({required this.rendered, required this.unresolved});
}

/// Render [snippet]'s command, substituting `{{name}}` tokens against
/// [context].
///
/// Built-in keys the caller is expected to populate when present (the
/// caller may omit any of them — missing keys fall through to the
/// `unresolved` list so the user gets prompted):
///
/// | Key | Source |
/// |---|---|
/// | `host` | `Session.host` |
/// | `user` | `Session.user` |
/// | `port` | `Session.port` |
/// | `label` | `Session.label` |
/// | `folder` | `Session.folder` (path string) |
/// | `now` | ISO-8601 timestamp at render time |
///
/// User-defined tokens (anything not in the table above) are caller-
/// agnostic — the picker layer collects them and prompts before the
/// command lands in the terminal.
///
/// **No recursion.** A substituted value containing `{{x}}` is taken
/// literally; the rendered output is never re-scanned. Same contract
/// as OpenSSH config tokens — predictable beats clever.
///
/// **Escape with `{{{{`** — a literal `{{` in the output is written
/// `{{{{` in the source. The escape is consumed before token
/// detection, so `{{{{not-a-token}}}}` renders as `{{not-a-token}}`.
///
/// **No shell escaping.** The substituted value is the raw context
/// string. If the user wants quoting, that is their problem at the
/// snippet authoring site — same as `~/.ssh/config`.
SnippetRender renderSnippet(Snippet snippet, Map<String, String> context) {
  final r = rust_snip.snippetTemplateRender(
    template: snippet.command,
    context: context.entries.map((e) => (e.key, e.value)).toList(),
  );
  return SnippetRender(rendered: r.rendered, unresolved: r.unresolved);
}

/// Substitute the user-supplied [values] for `{{name}}` tokens left
/// behind by [renderSnippet]. Used by the picker after the prompt
/// dialog collects values for each unresolved token. Honours the same
/// `{{{{` escape and "no recursion" rules as the first pass.
String fillSnippetUnresolved(
  String partiallyRendered,
  Map<String, String> values,
) {
  // Re-run the same machine; values for previously unresolved keys
  // now resolve, anything still missing stays intact.
  final fakeSnippet = Snippet(
    id: 'fill',
    title: '',
    command: partiallyRendered,
  );
  return renderSnippet(fakeSnippet, values).rendered;
}
