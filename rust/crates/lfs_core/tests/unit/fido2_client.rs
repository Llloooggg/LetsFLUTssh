/// Unit tests extracted from fido2/client.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

/// Probe must not panic when no HID transport is reachable in
/// the test runner — the function is sync and the rest of the
/// fido2 module relies on it staying total. Real probe
/// behaviour depends on the CI runner's HID stack; this test
/// pins the "never panics, returns a bool" contract.
#[test]
fn probe_available_is_total() {
    let _: bool = probe_available();
}

/// Map upstream errors carrying a `wrong pin` shape to the
/// `wrong pin:` prefix so the FRB envelope's matcher routes
/// to the `errSkWrongPin` Dart toast.
#[test]
fn map_upstream_err_routes_wrong_pin() {
    let mapped = map_upstream_err("CTAP2: invalid PIN entered");
    assert!(matches!(mapped, Error::Fido2(ref s) if s.starts_with("wrong pin:")));
}

#[test]
fn map_upstream_err_routes_timeout() {
    let mapped = map_upstream_err("device timed out waiting for user");
    assert!(matches!(mapped, Error::Fido2(ref s) if s.starts_with("timeout:")));
}

#[test]
fn map_upstream_err_passes_through_generic() {
    let mapped = map_upstream_err("transport error");
    assert!(matches!(mapped, Error::Fido2(ref s) if s == "transport error"));
}
