/// Pure validators for the port-forwarding rule editor. Thin
/// wrappers around the Rust-side `port_forward_validate_*_field`
/// FRB sync helpers — the grammar (port range 1–65535, host
/// required-unless-dynamic) lives one place
/// (`lfs_core::portforward`) so the editor pre-flight and the
/// runtime checks cannot drift.
///
/// The two sentinel strings rendered under the field are
/// intentionally not localised: the port range `1–65535` is the
/// spec, and the em-dash on an empty host field is the project's
/// standard "required" marker. Returning them from Dart (rather
/// than the Rust shim) keeps the localisation surface honest —
/// these are display constants, not error keys.
library;

import '../../core/ssh/port_forward_rule.dart';
import '../../src/rust/api/forward.dart' as rust_forward;
import '../../src/rust/api/forward.dart' show DbPortForwardFieldValidationError;

/// Sentinel error string returned when the parsed port is outside
/// the valid TCP range. The caller renders this verbatim under the
/// field; locale-aware formatting is intentional — the range itself
/// is the spec, not a translation target.
const portValidationError = '1–65535';

/// Sentinel error string for an empty bind / remote host on a
/// non-dynamic forward. Dynamic forwards (`-D`) have no remote
/// endpoint so the host field is optional and the validator returns
/// `null`; static forwards (`-L` / `-R`) require a host.
const hostValidationEmpty = '—';

/// Validate a TCP port input. Returns `null` for valid input
/// (1‒65535 inclusive), [portValidationError] otherwise. Routes
/// through the Rust `port_forward_validate_port_field` sync helper
/// so the parse + range rule stays single-sourced.
String? validatePortForwardPort(String? raw) {
  final err = rust_forward.portForwardValidatePortField(raw: raw ?? '');
  if (err == null) return null;
  return _fieldErrorSentinel(err);
}

/// Validate a host input. Dynamic forwards always pass (no remote
/// endpoint to reach); static forwards require a non-empty trimmed
/// value. Routes through the Rust
/// `port_forward_validate_host_field` sync helper.
String? validatePortForwardHost(String? raw, PortForwardKind kind) {
  final err = rust_forward.portForwardValidateHostField(
    raw: raw ?? '',
    kind: kind,
  );
  if (err == null) return null;
  return _fieldErrorSentinel(err);
}

/// Map the typed FRB rejection to the matching display sentinel.
/// Switch is exhaustive over the enum — Dart's static analyser
/// flags a missing variant if Rust adds one without an updated
/// case here.
String _fieldErrorSentinel(DbPortForwardFieldValidationError err) {
  switch (err) {
    case DbPortForwardFieldValidationError.portOutOfRange:
      return portValidationError;
    case DbPortForwardFieldValidationError.hostRequired:
      return hostValidationEmpty;
  }
}
