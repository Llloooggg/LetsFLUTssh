/// Unit tests extracted from known_hosts.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn split_host_port_basic() {
    assert_eq!(
        split_host_port("example.com:22"),
        Some(("example.com".to_string(), 22))
    );
    assert_eq!(split_host_port("badport:abc"), None);
    assert_eq!(split_host_port(":22"), None);
    assert_eq!(split_host_port("noport"), None);
    assert_eq!(split_host_port("h:0"), None);
    assert_eq!(split_host_port("h:70000"), None);
}

#[test]
fn split_host_port_ipv6_bracketed() {
    // Regression: `[::1]:2222` must round-trip as `(::1, 2222)`.
    // Pre-fix the writer emitted `::1:2222` and `rsplit_once(':')`
    // produced `(":1", 2222)` — orphaning every IPv6 known-hosts
    // row at connect time.
    assert_eq!(
        split_host_port("[::1]:2222"),
        Some(("::1".to_string(), 2222))
    );
    assert_eq!(
        split_host_port("[2001:db8::1]:22"),
        Some(("2001:db8::1".to_string(), 22))
    );
}

#[test]
fn split_host_port_ipv6_rejects_unclosed_bracket() {
    assert_eq!(split_host_port("[::1:2222"), None);
    assert_eq!(split_host_port("[::1]"), None);
    assert_eq!(split_host_port("[::1]:abc"), None);
}

// Exhaustive mapping of every `HostCheckMismatch` variant to
// its `KnownHostPromptKind`. The match inside `prompt_kind_for`
// is exhaustive at compile time; this test pins the
// *semantics* of that mapping so a future variant added to
// `HostCheckMismatch` cannot silently relabel an existing case.
#[test]
fn prompt_kind_for_covers_every_mismatch_variant() {
    assert_eq!(
        prompt_kind_for(&HostCheckMismatch::Unknown),
        KnownHostPromptKind::NewHost,
    );
    assert_eq!(
        prompt_kind_for(&HostCheckMismatch::Changed {
            stored_key_b64: "AAAA".to_string(),
        }),
        KnownHostPromptKind::KeyChanged,
    );
}

// `HostCheckResult` carries two top-level shapes — `Accepted`
// short-circuits the TOFU handler, `Mismatch` carries the data
// the prompt needs. The caller in `ssh::check_server_key_via_tofu`
// matches both arms exhaustively; this test pins the surface so
// a future variant added to `HostCheckResult` cannot bypass the
// mismatch path silently.
#[test]
fn host_check_result_round_trip() {
    let accepted = HostCheckResult::Accepted;
    match accepted {
        HostCheckResult::Accepted => {}
        HostCheckResult::Mismatch(_) => panic!("Accepted must not match Mismatch"),
    }

    let unknown = HostCheckResult::Mismatch(HostCheckMismatch::Unknown);
    match unknown {
        HostCheckResult::Mismatch(HostCheckMismatch::Unknown) => {}
        other => panic!("expected Mismatch(Unknown), got {other:?}"),
    }

    let changed = HostCheckResult::Mismatch(HostCheckMismatch::Changed {
        stored_key_b64: "AAAA".to_string(),
    });
    match changed {
        HostCheckResult::Mismatch(HostCheckMismatch::Changed { stored_key_b64 }) => {
            assert_eq!(stored_key_b64, "AAAA");
        }
        other => panic!("expected Mismatch(Changed), got {other:?}"),
    }
}
