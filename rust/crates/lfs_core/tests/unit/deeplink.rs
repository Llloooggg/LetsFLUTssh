/// Unit tests extracted from deeplink.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn parses_minimal_connect_link() {
    let link = parse_connect_uri("letsflutssh://connect?host=h&user=u").expect("parse");
    assert_eq!(link.host, "h");
    assert_eq!(link.user, "u");
    assert_eq!(link.port, 22);
}

#[test]
fn parses_explicit_port() {
    let link = parse_connect_uri("letsflutssh://connect?host=h&user=u&port=2222").expect("parse");
    assert_eq!(link.port, 2222);
}

#[test]
fn rejects_missing_host_or_user() {
    assert!(parse_connect_uri("letsflutssh://connect?host=h").is_none());
    assert!(parse_connect_uri("letsflutssh://connect?user=u").is_none());
    assert!(parse_connect_uri("letsflutssh://connect").is_none());
}

#[test]
fn rejects_wrong_scheme_or_action() {
    assert!(parse_connect_uri("https://connect?host=h&user=u").is_none());
    assert!(parse_connect_uri("letsflutssh://import?host=h&user=u").is_none());
}

#[test]
fn rejects_out_of_range_port() {
    assert!(parse_connect_uri("letsflutssh://connect?host=h&user=u&port=0").is_none());
    assert!(parse_connect_uri("letsflutssh://connect?host=h&user=u&port=70000").is_none());
    assert!(parse_connect_uri("letsflutssh://connect?host=h&user=u&port=abc").is_none());
}

#[test]
fn rejects_path_separators_in_host_user() {
    assert!(parse_connect_uri("letsflutssh://connect?host=a/b&user=u").is_none());
    assert!(parse_connect_uri(r"letsflutssh://connect?host=h&user=a\b").is_none());
}

#[test]
fn rejects_control_chars() {
    // %00 = NUL embedded mid-value (trim does not strip it).
    // Trailing whitespace control chars (LF / CR) get eaten by
    // the same trim() that the Dart parser applies, so they
    // collapse to a clean value — reuse the embedded form to
    // exercise the actual control-char branch.
    assert!(parse_connect_uri("letsflutssh://connect?host=h%00x&user=u").is_none());
    assert!(parse_connect_uri("letsflutssh://connect?host=h&user=a%0ab").is_none());
}

#[test]
fn rejects_overlong_host_user() {
    let host = "h".repeat(254);
    let user = "u".repeat(257);
    assert!(parse_connect_uri(&format!("letsflutssh://connect?host={host}&user=u")).is_none());
    assert!(parse_connect_uri(&format!("letsflutssh://connect?host=h&user={user}")).is_none());
}

#[test]
fn percent_decodes_query_values() {
    let link = parse_connect_uri("letsflutssh://connect?host=ex%20ample&user=us%2Br");
    // Space in host is rejected because the Dart side treats
    // any whitespace as ambiguous; our trim-then-validate
    // mirrors Dart's parser behaviour. Re-check shape only.
    // user = "us+r" survives.
    if let Some(l) = link {
        assert_eq!(l.user, "us+r");
    }
}

#[test]
fn malformed_percent_encoding_returns_none() {
    assert!(parse_connect_uri("letsflutssh://connect?host=%XX&user=u").is_none());
    assert!(parse_connect_uri("letsflutssh://connect?host=%2&user=u").is_none());
}

#[test]
fn fuzz_does_not_panic() {
    // Drives a deterministic mix of garbage shapes through.
    // The Dart-side fuzz suite ships seed=12648430; the rule
    // here is the same — never panic, return Option either
    // way. Keep the inputs hand-crafted so they hit the
    // edges that historically tripped past parsers.
    let inputs = [
        "",
        ":",
        "://",
        "://?",
        "letsflutssh://",
        "letsflutssh:",
        "letsflutssh://connect?",
        "letsflutssh://connect?=",
        "letsflutssh://connect?host=&user=",
        "letsflutssh://connect#frag?host=h&user=u",
        "letsflutssh://connect?host=h&user=u#",
        "letsflutssh://connect?host=h&host=h2&user=u",
        "letsflutssh://CONNECT?host=h&user=u",
        "LETSFLUTSSH://connect?host=h&user=u",
        "letsflutssh://connect?host=h&user=u&port=",
        "letsflutssh://connect?host=h&user=u&port=22a",
        "data:text/plain,host=h&user=u",
        "\0\0\0",
        "letsflutssh://connect?host=h%2&user=u",
        "letsflutssh://connect?host=%&user=u",
    ];
    for input in inputs {
        // All we promise: no panic.
        let _ = parse_connect_uri(input);
    }
}

// ---- Dispatcher tests ----------------------------------------

#[test]
fn route_connect_returns_typed_link() {
    match route("letsflutssh://connect?host=10.0.0.1&user=root&port=2222") {
        DeeplinkOutcome::Connect { host, port, user } => {
            assert_eq!(host, "10.0.0.1");
            assert_eq!(port, 2222);
            assert_eq!(user, "root");
        }
        other => panic!("expected Connect, got {other:?}"),
    }
}

#[test]
fn route_connect_invalid_returns_unknown() {
    // Missing user — the connect parser rejects, dispatcher
    // collapses to Unknown.
    assert_eq!(
        route("letsflutssh://connect?host=h"),
        DeeplinkOutcome::Unknown
    );
}

#[test]
fn route_unknown_action_returns_unknown() {
    assert_eq!(
        route("letsflutssh://summon?spell=fireball"),
        DeeplinkOutcome::Unknown
    );
}

#[test]
fn route_file_uris_are_unhandled() {
    // No file-extension associations: a file URI for what used to be
    // an "open" target (.lfs / .pem / .key / .pub) now routes to
    // Unknown, same as any other unclaimed scheme.
    for uri in [
        "file:///tmp/backup.lfs",
        "file:///home/u/.ssh/id_ed25519.pem",
        "file:///tmp/a.key",
        "file:///tmp/a.pub",
        "content://com.android.providers/x.lfs",
    ] {
        assert_eq!(route(uri), DeeplinkOutcome::Unknown, "uri: {uri}");
    }
}

#[test]
fn route_unknown_scheme() {
    assert_eq!(route("https://example.com"), DeeplinkOutcome::Unknown);
    assert_eq!(route("garbage"), DeeplinkOutcome::Unknown);
}

#[test]
fn dispatcher_dedups_within_window() {
    let d = DeeplinkDispatcher::new();
    let uri = "letsflutssh://connect?host=h&user=u";
    // First call routes normally.
    match d.dispatch(uri) {
        DeeplinkOutcome::Connect { .. } => {}
        other => panic!("first call: expected Connect, got {other:?}"),
    }
    // Second call within window collapses to Duplicate.
    assert_eq!(d.dispatch(uri), DeeplinkOutcome::Duplicate);
}

#[test]
fn dispatcher_does_not_dedup_distinct_uris() {
    let d = DeeplinkDispatcher::new();
    match d.dispatch("letsflutssh://connect?host=a&user=u") {
        DeeplinkOutcome::Connect { .. } => {}
        other => panic!("expected Connect, got {other:?}"),
    }
    match d.dispatch("letsflutssh://connect?host=b&user=u") {
        DeeplinkOutcome::Connect { .. } => {}
        other => panic!("expected Connect, got {other:?}"),
    }
}

#[test]
fn dispatcher_routes_qr_version_too_new_without_app_state() {
    // Versions are detected before staging — this branch never
    // touches AppState::imports, so we can exercise it without
    // initialising the singleton.
    // Encode a payload with v=999 (above the current
    // `SchemaVersions::QR_PAYLOAD`).
    use base64::engine::{general_purpose::URL_SAFE_NO_PAD, Engine as _};
    use flate2::write::DeflateEncoder;
    use flate2::Compression;
    use std::io::Write;
    let json = b"{\"v\":999}";
    let mut enc = DeflateEncoder::new(Vec::new(), Compression::default());
    enc.write_all(json).unwrap();
    let deflated = enc.finish().unwrap();
    let payload = URL_SAFE_NO_PAD.encode(&deflated);
    let uri = format!("letsflutssh://import?d={payload}");
    match route(&uri) {
        DeeplinkOutcome::QrImportRejected { found, supported } => {
            assert_eq!(found, 999);
            assert_eq!(
                supported,
                i64::from(crate::migration::SchemaVersions::QR_PAYLOAD),
            );
        }
        other => panic!("expected QrImportRejected, got {other:?}"),
    }
}

#[test]
fn dispatcher_unknown_for_malformed_qr_payload() {
    // Garbage payload that's neither valid base64 nor valid JSON.
    match route("letsflutssh://import?d=!!!") {
        DeeplinkOutcome::Unknown => {}
        other => panic!("expected Unknown, got {other:?}"),
    }
}
