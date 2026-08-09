/// Unit tests extracted from snippet_template.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn ctx<I: IntoIterator<Item = (&'static str, &'static str)>>(pairs: I) -> BTreeMap<String, String> {
    pairs
        .into_iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect()
}

#[test]
fn substitutes_a_known_token() {
    let r = render("ssh {{host}}", &ctx([("host", "example.com")]));
    assert_eq!(r.rendered, "ssh example.com");
    assert!(r.unresolved.is_empty());
}

#[test]
fn multiple_tokens_substitute_in_one_pass() {
    let r = render(
        "ssh -p {{port}} {{user}}@{{host}}",
        &ctx([("port", "2200"), ("user", "root"), ("host", "h.example")]),
    );
    assert_eq!(r.rendered, "ssh -p 2200 root@h.example");
}

#[test]
fn unknown_tokens_collect_first_seen_order_no_duplicates() {
    let r = render("echo {{name}} {{name}} {{age}}", &ctx([]));
    assert_eq!(r.rendered, "echo {{name}} {{name}} {{age}}");
    assert_eq!(r.unresolved, vec!["name".to_string(), "age".to_string()]);
}

#[test]
fn mix_of_known_and_unknown_tokens() {
    let r = render(
        "curl http://{{host}}/{{path}}",
        &ctx([("host", "example.com")]),
    );
    assert_eq!(r.rendered, "curl http://example.com/{{path}}");
    assert_eq!(r.unresolved, vec!["path".to_string()]);
}

#[test]
fn token_name_is_trimmed() {
    let r = render("{{  host  }}", &ctx([("host", "x")]));
    assert_eq!(r.rendered, "x");
}

#[test]
fn empty_token_is_kept_literal() {
    let r = render("a{{}}b", &ctx([]));
    assert_eq!(r.rendered, "a{{}}b");
    assert!(r.unresolved.is_empty());
}

#[test]
fn unterminated_open_keeps_tail() {
    let r = render("echo {{host", &ctx([("host", "x")]));
    assert_eq!(r.rendered, "echo {{host");
}

#[test]
fn quad_brace_escape_emits_literal_double_brace() {
    let r = render("{{{{not-a-token}}", &ctx([]));
    assert_eq!(r.rendered, "{{not-a-token}}");
    assert!(r.unresolved.is_empty());
}

#[test]
fn substituted_value_is_not_re_scanned_for_tokens() {
    let r = render("a {{x}} b", &ctx([("x", "{{y}}"), ("y", "NOPE")]));
    // `x`'s value contains `{{y}}` literally, but the renderer
    // does not re-scan substituted output, so `y` stays as the
    // literal substring (no recursion contract).
    assert_eq!(r.rendered, "a {{y}} b");
    assert!(r.unresolved.is_empty());
}

#[test]
fn fill_unresolved_finishes_a_partially_rendered_template() {
    let first = render("{{a}} {{b}}", &ctx([]));
    assert_eq!(first.unresolved, vec!["a".to_string(), "b".to_string()]);
    let filled = fill_unresolved(&first.rendered, &ctx([("a", "alpha"), ("b", "beta")]));
    assert_eq!(filled, "alpha beta");
}

#[test]
fn empty_template_renders_to_empty() {
    let r = render("", &ctx([]));
    assert_eq!(r.rendered, "");
    assert!(r.unresolved.is_empty());
}

#[test]
fn template_with_no_tokens_is_passthrough() {
    let r = render("just some text", &ctx([("ignored", "x")]));
    assert_eq!(r.rendered, "just some text");
    assert!(r.unresolved.is_empty());
}
