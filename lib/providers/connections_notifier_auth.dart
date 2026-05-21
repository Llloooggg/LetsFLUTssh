part of 'connections_notifier.dart';

/// Auth-overlay composition for [ConnectionsNotifier]: translate the
/// saved [SshAuth] config into the typed [SshAuthMethod] the bus
/// connect args carry, resolve a hardware-key PIN, and cache the
/// post-auth credentials. State-free helpers — they stage secrets
/// through Rust and never touch the Notifier's connection list.
extension _ConnectionAuth on ConnectionsNotifier {
  /// Translate the legacy [SshAuth] config bag into the typed
  /// [SshAuthMethod] family the bus connect args carry.
  /// Precedence: keyData > password.
  ///
  /// Routes through `lfs_core::connection::auth_compose::
  /// prepare_auth` (FRB async) so the saved-session-staged →
  /// manager-key-staged → quick-connect-fallback walk lives one
  /// place. The composer reads sqlite columns + stages every
  /// byte into the SecretStore inside Rust; the Dart caller
  /// only sees the typed ref + the transient id list to drop
  /// after the connect attempt settles.
  ///
  /// FRB-unreachable contexts (flutter_test) propagate the throw —
  /// every secret-staging path was itself a FRB call, so the
  /// previous "Dart fallback" pipeline collapsed to the same
  /// failure the orchestrator surfaces directly.
  Future<SshAuthMethod> _authFromConfig(
    SshAuth auth,
    String? sessionId,
    Connection conn,
  ) async {
    // System ssh-agent dispatch — short-circuit before the composer
    // runs. `SshAuthAgent` carries no per-session secret; the Rust
    // driver dials `$SSH_AUTH_SOCK` (Unix) / the OpenSSH named pipe
    // / Pageant (Windows) and walks every key the agent advertises,
    // so SecretStore never has to be staged for this path.
    if (auth.useAgent) {
      return const SshAuthAgent();
    }
    // FIDO2 manager-key dispatch: when the manager key id resolves
    // to a hardware-bound (`sk-*`) row carrying the user-verification
    // bit, prompt for a PIN before the composer runs so the staged
    // transient `key.pin.<id>` is ready by the time the Rust driver
    // reads it. Touch-only credentials skip the prompt entirely — the
    // device fires its presence challenge inside the firmware on the
    // first signing round trip.
    final pin = await _resolveHardwareKeyPin(auth.keyId);
    final prepared = await rust_auth.connectionPrepareAuth(
      input: rust_auth.DbPrepareAuthInput(
        sessionId: sessionId,
        keyId: auth.keyId,
        keyData: auth.keyData,
        password: auth.password,
        passphrase: auth.passphrase,
        pin: pin ?? '',
      ),
    );
    conn.transientSecretIds.addAll(prepared.transientSecretIds);
    return switch (prepared.auth) {
      rust_auth.DbPreparedAuthRef_Password(:final secretId) =>
        SshAuthPasswordRef(secretId),
      // Cert-paired branch runs ahead of the plain-pubkey branch
      // for symmetry with the Rust composer's `match` arm ordering
      // — both selectors privilege the stronger cert-auth path
      // whenever a cert is paired to the resolved manager key.
      rust_auth.DbPreparedAuthRef_PubkeyCert(
        :final keySecretId,
        :final certSecretId,
        :final passphraseSecretId,
      ) =>
        SshAuthPubkeyCertRef(
          keySecretId,
          certSecretId,
          passphraseSecretId: passphraseSecretId,
        ),
      rust_auth.DbPreparedAuthRef_Pubkey(
        :final keySecretId,
        :final passphraseSecretId,
      ) =>
        SshAuthPubkeyRef(keySecretId, passphraseSecretId: passphraseSecretId),
      rust_auth.DbPreparedAuthRef_PubkeySk(
        :final publicOpenssh,
        :final credentialId,
        :final application,
        :final pinSecretId,
      ) =>
        SshAuthPubkeySkRef(
          publicOpenssh: publicOpenssh,
          credentialId: credentialId,
          application: application,
          pinSecretId: pinSecretId,
        ),
      // Cert-paired sk-* branch — composed when the manager row
      // carries `credential_id` AND `ssh_key_certificates` has a
      // cert blob attached. The cert is the strictly stronger
      // credential so the composer picks this ahead of the bare
      // sk-* variant; matches the precedence software keys
      // already enforce between PubkeyCert and Pubkey.
      rust_auth.DbPreparedAuthRef_PubkeySkCert(
        :final publicOpenssh,
        :final credentialId,
        :final application,
        :final certSecretId,
        :final pinSecretId,
      ) =>
        SshAuthPubkeySkCertRef(
          publicOpenssh: publicOpenssh,
          credentialId: credentialId,
          application: application,
          certSecretId: certSecretId,
          pinSecretId: pinSecretId,
        ),
      // PKCS#11 hardware-token branch — composed by
      // `auth_compose::prepare_auth` when the resolved manager-key
      // row carries `backend = 'pkcs11'`. The PIN stages as a
      // transient SecretStore entry the Rust connect path reads
      // inside its `_owned` future, mirroring the sk-* flow.
      rust_auth.DbPreparedAuthRef_PubkeyPkcs11(
        :final publicOpenssh,
        :final modulePath,
        :final tokenSerial,
        :final ckaId,
        :final keyType,
        :final pinSecretId,
      ) =>
        SshAuthPubkeyPkcs11Ref(
          publicOpenssh: publicOpenssh,
          modulePath: modulePath,
          tokenSerial: tokenSerial,
          ckaId: ckaId,
          keyType: keyType,
          pinSecretId: pinSecretId,
        ),
      // Apple Secure Enclave branch — `auth_compose::prepare_auth`
      // routes this when the resolved manager-key row carries
      // `backend = 'enclave'`. No PIN dialog: the OS handles its
      // biometric / passcode prompt inside `SecKeyCreateSignature`
      // per the ACL flags chosen at create time.
      rust_auth.DbPreparedAuthRef_PubkeyEnclave(
        :final publicOpenssh,
        :final applicationTag,
      ) =>
        SshAuthPubkeyEnclaveRef(
          publicOpenssh: publicOpenssh,
          applicationTag: applicationTag,
        ),
      // Windows Hello branch — `auth_compose::prepare_auth` routes
      // this when the resolved manager-key row carries
      // `backend = 'hello'`. No PIN dialog: Windows fires the Hello
      // prompt (PIN / fingerprint / face) inside `NCryptSignHash`
      // per the UI policy set at create time.
      rust_auth.DbPreparedAuthRef_PubkeyHello(
        :final publicOpenssh,
        :final credentialName,
        :final keyType,
      ) =>
        SshAuthPubkeyHelloRef(
          publicOpenssh: publicOpenssh,
          credentialName: credentialName,
          keyType: keyType,
        ),
      // TPM 2.0 branch — `auth_compose::prepare_auth` routes this
      // when the resolved manager-key row carries
      // `backend = 'tpm'`. Linux PIN-bound keys ride a transient
      // SecretStore entry the Rust composer seeded under
      // `tpm.pin.<key_id>`; empty-auth rows leave `pinSecretId`
      // null. Windows silent rows sign unattended; this Dart arm
      // never collects a PIN.
      rust_auth.DbPreparedAuthRef_PubkeyTpm(
        :final publicOpenssh,
        :final provider,
        :final blob,
        :final cngKeyName,
        :final keyType,
        :final pinSecretId,
      ) =>
        SshAuthPubkeyTpmRef(
          publicOpenssh: publicOpenssh,
          provider: provider,
          blob: blob,
          cngKeyName: cngKeyName,
          keyType: keyType,
          pinSecretId: pinSecretId,
        ),
      // Android Hardware Keystore branch — `auth_compose::prepare_auth`
      // routes this when the resolved manager-key row carries
      // `backend = 'keystore'`. No PIN dialog: AndroidKeyStore
      // fires its own BiometricPrompt inside
      // `Signature.initSign` + `BiometricPrompt.CryptoObject` per
      // the auth requirement set at create time.
      rust_auth.DbPreparedAuthRef_PubkeyKeystore(
        :final publicOpenssh,
        :final keystoreAlias,
        :final keyType,
      ) =>
        SshAuthPubkeyKeystoreRef(
          publicOpenssh: publicOpenssh,
          keystoreAlias: keystoreAlias,
          keyType: keyType,
        ),
    };
  }

  /// Inspect the manager-key row for [keyId] and, when the row is a
  /// hardware-bound `sk-*` key that carries the user-verification
  /// bit, surface the [HardwareKeyPromptDialog] and return the
  /// user-entered PIN. Returns `null` when:
  ///   - [keyId] is empty (no manager key linked),
  ///   - the row is missing or software-only (`credentialId` null),
  ///   - the row is touch-only (`hasUserVerification` false),
  ///   - no `BuildContext` is available (FRB-unreachable
  ///     `flutter_test` runs).
  ///
  /// Throws [HardwareKeyPromptCancelled] when the user dismisses the
  /// dialog. The Rust composer treats `pin == ""` as "no PIN
  /// staged" — the connect path then surfaces the CTAP2 missing-PIN
  /// error from the device round trip rather than failing pre-flight,
  /// so a successful empty return means the device must accept a
  /// touch-only assertion.
  ///
  /// Rust owns the data: the row is re-fetched via FRB on every
  /// connect attempt rather than cached on the Dart side; a manager
  /// edit (touch-only → UV-required, or vice versa) is picked up on
  /// the next dial.
  Future<String?> _resolveHardwareKeyPin(String keyId) async {
    if (keyId.isEmpty) return null;
    rust_db.DbSshKey? row;
    try {
      row = await rust_db.dbSshKeysGet(id: keyId);
    } on StateError catch (e) {
      // FRB-unreachable in flutter_test — fall through; the existing
      // composer call will throw the same error a couple of lines
      // below if the test actually exercises the Rust path.
      AppLogger.instance.log(
        'hardware-key prompt skipped (FRB not init): $e',
        name: 'Connection',
      );
      return null;
    }
    if (row == null || row.credentialId == null) return null;
    if (!row.hasUserVerification) return null;
    final ctx = navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      AppLogger.instance.log(
        'hardware-key prompt skipped (no navigator)',
        name: 'Connection',
        level: LogLevel.warn,
      );
      return null;
    }
    // Resolve the localized cancel message synchronously — the
    // navigator's `BuildContext` is unsafe to read after the dialog's
    // await (analyzer rule `use_build_context_synchronously`).
    final cancelMessage = S.of(ctx).hardwareKeyPromptCancelled;
    final result = await HardwareKeyPromptDialog.show(
      ctx,
      deviceName: row.label,
      requiresPin: true,
    );
    if (result == null || result.cancelled) {
      throw HardwareKeyPromptCancelled(cancelMessage);
    }
    return result.pin;
  }

  /// Store the post-auth credential envelope so a later reconnect
  /// (possibly after auto-lock closed the encrypted store) does
  /// not need to re-read `Session.auth`. Cache writes only happen
  /// for stored sessions — quick-connect has no stable key, and
  /// the next `reconnect` call already carries the full config.
  void _cachePostAuthCredentials(Connection conn, SSHConfig config) {
    final cache = _credentialCache;
    final sessionId = conn.sessionId;
    if (cache == null || sessionId == null) return;
    unawaited(
      cache.store(
        sessionId: sessionId,
        password: config.auth.password.isEmpty ? null : config.auth.password,
        keyData: config.auth.keyData.isEmpty ? null : config.auth.keyData,
        keyPassphrase: config.auth.passphrase.isEmpty
            ? null
            : config.auth.passphrase,
      ),
    );
  }
}
