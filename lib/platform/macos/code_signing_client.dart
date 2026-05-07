// Thin Dart-side shim over the macOS code-signing FRB surface.
//
// All actual subprocess work (`/usr/bin/openssl`, `/usr/bin/security`,
// `/usr/bin/codesign`) and the resign orchestration live in
// `rust/crates/lfs_os_security/src/macos/code_signing.rs`. This file
// is a typed dispatch table — the abstract base lets call sites
// inject fakes for unit tests, and the default `_FrbMacosCodeSigningClient`
// just forwards to the FRB calls one-line each.

import '../../src/rust/api/macos_resign.dart' as rust;

export '../../src/rust/api/macos_resign.dart' show MacosResignOutcome;

/// Subject CN for the self-signed cert. Mirrors the constant the
/// Rust side returns from `macos_resign_default_common_name`.
/// Stable across releases — see the cert-factory rationale on
/// the Rust side for why rotating it would invalidate every
/// keychain item already minted under the prior designated
/// requirement.
const String defaultMacosResignCommonName = 'LetsFLUTssh Self-Sign';

/// Public surface used by the settings UI, the first-launch
/// orchestrator, and the macOS installer. Each method maps 1:1
/// to a single FRB call.
abstract class MacosCodeSigningClient {
  /// Read-only probe — `true` when the cert under [commonName]
  /// already lives in the user's login keychain. Used by the
  /// settings UI to pick between "Enable secure tiers" and
  /// "Remove secure identity".
  Future<bool> hasIdentity({String commonName});

  /// Make sure a cert under [commonName] exists in the keychain.
  /// Returns `true` when a fresh cert was created in this call
  /// (the macOS password prompt fired), `false` when an existing
  /// one was reused silently.
  Future<bool> ensureIdentity({String commonName});

  /// Re-sign [bundlePath] leaf-first with the cert under
  /// [commonName]. Caller must have run [ensureIdentity] earlier.
  Future<rust.MacosResignOutcome> resignBundle({
    required String bundlePath,
    String commonName,
  });

  /// Drop the identity + cert under [commonName].
  Future<void> uninstallIdentity({String commonName});

  /// Read the entitlements plist embedded in the bundle's current
  /// signature. Returns `null` when no entitlements survive on
  /// the signature (ad-hoc CI build).
  Future<String?> extractEntitlements({required String bundlePath});

  /// `codesign --verify --deep --strict --verbose=2` — `true` on
  /// clean exit. Used by the installer to gate the atomic swap.
  Future<bool> verifyBundle({required String bundlePath});
}

/// Default impl — every call routes one FRB hop into
/// `lfs_os_security::macos::code_signing`. No business logic.
class _FrbMacosCodeSigningClient implements MacosCodeSigningClient {
  const _FrbMacosCodeSigningClient();

  @override
  Future<bool> hasIdentity({
    String commonName = defaultMacosResignCommonName,
  }) => rust.macosResignHasIdentity(commonName: commonName);

  @override
  Future<bool> ensureIdentity({
    String commonName = defaultMacosResignCommonName,
  }) => rust.macosResignEnsureIdentity(commonName: commonName);

  @override
  Future<rust.MacosResignOutcome> resignBundle({
    required String bundlePath,
    String commonName = defaultMacosResignCommonName,
  }) => rust.macosResignBundle(bundlePath: bundlePath, commonName: commonName);

  @override
  Future<void> uninstallIdentity({
    String commonName = defaultMacosResignCommonName,
  }) => rust.macosResignUninstallIdentity(commonName: commonName);

  @override
  Future<String?> extractEntitlements({required String bundlePath}) =>
      rust.macosResignExtractEntitlements(bundlePath: bundlePath);

  @override
  Future<bool> verifyBundle({required String bundlePath}) =>
      rust.macosResignVerifyBundle(bundlePath: bundlePath);
}

/// Const handle to the production FRB-backed client. Use the
/// Riverpod `macosCodeSigningClientProvider` (in
/// `providers/security_provider.dart`) at call sites that already
/// have a `WidgetRef` / `Ref`; this constant is for plain Dart
/// helpers that do not depend on Riverpod.
const MacosCodeSigningClient defaultMacosCodeSigningClient =
    _FrbMacosCodeSigningClient();
