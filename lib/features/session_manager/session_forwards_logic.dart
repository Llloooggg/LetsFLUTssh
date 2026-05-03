/// Pure validators for the port-forwarding rule editor. Extracted
/// from `_ForwardRuleEditorState` so the small but
/// edge-case-rich numeric / host validation rules can be exercised
/// without mounting the editor + a Form widget tree.
library;

import '../../core/ssh/port_forward_rule.dart';

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
/// (1‒65535 inclusive), [portValidationError] otherwise. A
/// whitespace-only or empty string fails — the editor's port field
/// is required for every forward kind.
String? validatePortForwardPort(String? raw) {
  final n = int.tryParse(raw?.trim() ?? '');
  if (n == null || n < 1 || n > 65535) return portValidationError;
  return null;
}

/// Validate a host input. Dynamic forwards always pass (no remote
/// endpoint to reach); static forwards require a non-empty trimmed
/// value.
String? validatePortForwardHost(String? raw, PortForwardKind kind) {
  if (kind == PortForwardKind.dynamic_) return null;
  if (raw == null || raw.trim().isEmpty) return hostValidationEmpty;
  return null;
}
