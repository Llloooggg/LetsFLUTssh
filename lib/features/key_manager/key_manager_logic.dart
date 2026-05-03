/// Pure helpers for `_KeyManagerPanelState`. Extracted so the
/// search-filter rule (and any future view-projections) can be
/// exercised without mounting the panel + booting the FRB-backed
/// `sshKeysProvider`.
library;

import '../../core/security/ssh_key.dart';

/// Apply the user's search filter to the in-memory key list. Empty /
/// whitespace filter is treated as "no filter" — a stale leading or
/// trailing space in the search box must not hide every entry.
/// Match is case-insensitive over the label and the key type
/// (`ssh-ed25519`, `ssh-rsa`, …) — the two columns the row renders;
/// the public key bytes / fingerprints intentionally do not match,
/// since users searching by label expect labels first and matching
/// the binary blob would surface noise.
List<SshKeyMetadata> filterSshKeys(List<SshKeyMetadata> keys, String filter) {
  final q = filter.trim().toLowerCase();
  if (q.isEmpty) return keys;
  return keys
      .where(
        (k) =>
            k.label.toLowerCase().contains(q) ||
            k.keyType.toLowerCase().contains(q),
      )
      .toList();
}
