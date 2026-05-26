/// Validator for the SSH / SFTP / proxy `port` field on the
/// session-edit and quick-connect dialogs. Routes through the same
/// Rust grammar (`port_forward_validate_port_field`) the port-forward
/// rule editor uses — the TCP port range `1..=65535` is one rule, so
/// the editor, the runtime port-forward, and the connection dialog
/// share a single source.
///
/// The returned sentinel is localised through `S.of(context).portRange`
/// at the call site; this helper exposes only the boolean accept /
/// reject decision so it stays usable in a `Form` validator that
/// already has `BuildContext` for the message lookup.
library;

import '../../src/rust/api/forward.dart' as rust_forward;

/// Returns `true` when [raw] parses as a TCP port in `1..=65535`.
/// Defers the parse + range check to Rust so the grammar lives in
/// one place (`lfs_core::portforward::validate_port_field`).
bool isValidConnectionPort(String? raw) =>
    rust_forward.portForwardValidatePortField(raw: raw ?? '') == null;
