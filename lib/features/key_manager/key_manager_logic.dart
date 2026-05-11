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

/// Labels carried into the cert tertiary text. Living one place so
/// the test can pass the equivalent of `S.of(context).certPrincipals`
/// without booting Flutter localizations. The keys mirror the ARB
/// names the row renders against.
class CertRowLabels {
  final String principals;
  final String validTo;
  final String criticalOptions;
  final String localizedDate; // formatted YYYY-MM-DD of validity.to

  const CertRowLabels({
    required this.principals,
    required this.validTo,
    required this.criticalOptions,
    required this.localizedDate,
  });
}

/// Build the cert tertiary line for [entry] using [labels]. Returns
/// `null` when no cert is attached (the row renders without a
/// tertiary slot). Order of segments matches the visual reading
/// order: principals (most distinguishing), validity, options.
String? buildCertTertiary(SshKeyMetadata entry, CertRowLabels labels) {
  if (!entry.hasCertificate) return null;
  final parts = <String>[];
  if (entry.principals.isNotEmpty) {
    final visible = entry.principals.take(3).join(', ');
    final extra = entry.principals.length > 3
        ? ' +${entry.principals.length - 3}'
        : '';
    parts.add('${labels.principals}: $visible$extra');
  }
  if (entry.validity != null) {
    parts.add('${labels.validTo} ${labels.localizedDate}');
  }
  if (entry.criticalOptions.isNotEmpty) {
    parts.add('${labels.criticalOptions}: ${entry.criticalOptions.length}');
  }
  return parts.join('  •  ');
}
