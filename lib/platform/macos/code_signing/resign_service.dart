import 'dart:io';

import 'cert_factory.dart';
import 'codesigner.dart';
import 'keychain.dart';

/// Outcome of a self-sign flow. Surfaces back to the UI so the wizard
/// can show a tailored message + suggest the right next step.
enum ResignOutcome {
  /// Fresh cert created, trust granted, bundle re-signed. T1
  /// keychain is unlocked for this install.
  succeeded,

  /// Existing cert was reused and the bundle re-signed. No password
  /// prompt was needed — the caller can silently return the user to
  /// the main screen.
  reusedExisting,

  /// The user dismissed the macOS password prompt on the
  /// `add-trusted-cert` step, or some other keychain op failed. The
  /// wizard should surface the error and leave the app on a fallback
  /// tier (T0 / Paranoid).
  cancelledOrFailed,

  /// Bundle is writable only via elevation (root-owned install in
  /// `/Applications`). The wizard suggests moving to `~/Applications`
  /// or accepting an additional admin prompt.
  bundleNotWritable,
}

/// High-level orchestrator that turns "user clicked Enable Keychain"
/// into a real bundle with a stable signing identity. Wraps
/// [CertFactory] + [Keychain] + [Codesigner] with the ordering +
/// idempotency logic the flow needs.
///
/// Critical invariant: **the cert is created exactly once per
/// install**. `ensureIdentity()` checks the keychain for an existing
/// cert under [CertFactory.defaultCommonName] and only generates +
/// imports when none is present. Regenerating the cert would invalidate
/// every keychain item already written under the old designated
/// requirement and silently lock the user out of their T1 secrets —
/// the single worst thing this service can do. A user-facing "reset
/// identity" flow exists for the rare case where the user explicitly
/// wants to rotate; it is not routed through this service.
class ResignService {
  final CertFactory certFactory;
  final Keychain keychain;
  final Codesigner codesigner;

  const ResignService({
    this.certFactory = const CertFactory(),
    Keychain? keychain,
    this.codesigner = const Codesigner(),
  }) : keychain = keychain ?? const _DefaultKeychain();

  /// Make sure the keychain holds a cert under [commonName]. Returns
  /// `true` when a cert was created in this call, `false` when one
  /// was already present. The boolean lets the caller decide whether
  /// the password prompt was shown (new cert) or the flow completed
  /// silently (existing cert).
  Future<bool> ensureIdentity({
    String commonName = CertFactory.defaultCommonName,
  }) async {
    if (await keychain.hasCertificate(commonName)) return false;
    final material = await certFactory.generate(commonName: commonName);
    try {
      await keychain.importPkcs12(
        p12Path: material.p12Path,
        passphrase: material.p12Passphrase,
      );
      // Password prompt happens here — the user-domain trust DB
      // write is always auth-gated, regardless of which keychain
      // the cert lives in.
      await keychain.addTrustedCert(material.crtPath);
    } finally {
      material.tmpDir.deleteSync(recursive: true);
    }
    return true;
  }

  /// Re-sign [appBundle] with the cert identified by [commonName].
  /// Caller must have called [ensureIdentity] first; otherwise the
  /// codesign step fails with "no identity found". We check
  /// writability up front so the caller can surface
  /// [ResignOutcome.bundleNotWritable] before the codesign spawn
  /// wastes effort and a misleading error.
  Future<ResignOutcome> resignBundle({
    required Directory appBundle,
    String commonName = CertFactory.defaultCommonName,
  }) async {
    if (!_isWritable(appBundle)) return ResignOutcome.bundleNotWritable;
    final entitlements = await codesigner.extractEntitlements(appBundle);
    await codesigner.resignInsideOut(
      appBundle: appBundle,
      commonName: commonName,
      entitlementsPlist: entitlements,
    );
    final ok = await codesigner.verify(appBundle);
    return ok ? ResignOutcome.succeeded : ResignOutcome.cancelledOrFailed;
  }

  bool _isWritable(Directory dir) {
    try {
      // Ephemeral probe — create + delete a file inside the bundle
      // root. Succeeds only when the user owns the bundle tree;
      // root-owned `/Applications/letsflutssh.app` trips the
      // exception and we route the user to the admin-prompt
      // fallback instead.
      final probe = File('${dir.path}/.lfs-write-probe');
      probe.writeAsStringSync('x');
      probe.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Uninstall path — drop the identity + cert. Leaves the .app
  /// itself alone; the user's T1 items become unreadable but the
  /// bundle is still present and will run on the original ad-hoc
  /// signature.
  ///
  /// No explicit `remove-trusted-cert` step: the user-domain trust
  /// entry written by [ensureIdentity] is keyed by the cert's SHA-1
  /// hash, and macOS's trust evaluator skips entries whose
  /// referenced cert is missing from any keychain. So once
  /// `delete-identity` + `delete-certificate` sweep the cert away,
  /// the surviving trust entry is an inactive dangling reference —
  /// equivalent to removal from every security standpoint that
  /// matters, and cheaper than the alternatives (exporting the cert
  /// to a tmp file to pass back to `remove-trusted-cert`, or
  /// rewriting the trust domain via `trust-settings-import`).
  Future<void> uninstallIdentity({
    String commonName = CertFactory.defaultCommonName,
  }) async {
    await keychain.deleteIdentity(commonName);
    await keychain.deleteCertificate(commonName);
  }

  /// Has the user previously accepted the self-sign prompt on this
  /// machine? Lets the UI decide between offering "Enable secure
  /// tiers" (no cert) and "Remove secure identity" (cert present
  /// → tier switch required before removal).
  Future<bool> hasIdentity({
    String commonName = CertFactory.defaultCommonName,
  }) => keychain.hasCertificate(commonName);
}

// Keychain's constructor reads `Platform.environment['HOME']`, so it
// can't be a const. Wrap it in a tiny placeholder that defers the
// lookup until the first call — this keeps `ResignService`'s
// constructor `const`.
class _DefaultKeychain implements Keychain {
  const _DefaultKeychain();

  Keychain _lazy() => Keychain();

  @override
  // ignore: invalid_use_of_visible_for_overriding_member
  String get keychainPath => _lazy().keychainPath;
  @override
  // ignore: invalid_use_of_visible_for_overriding_member
  get runner => _lazy().runner;

  @override
  Future<bool> hasCertificate(String commonName) =>
      _lazy().hasCertificate(commonName);
  @override
  Future<void> importPkcs12({
    required File p12Path,
    required String passphrase,
  }) => _lazy().importPkcs12(p12Path: p12Path, passphrase: passphrase);
  @override
  Future<void> addTrustedCert(File crtPath) => _lazy().addTrustedCert(crtPath);
  @override
  Future<void> deleteIdentity(String commonName) =>
      _lazy().deleteIdentity(commonName);
  @override
  Future<void> deleteCertificate(String commonName) =>
      _lazy().deleteCertificate(commonName);
}
