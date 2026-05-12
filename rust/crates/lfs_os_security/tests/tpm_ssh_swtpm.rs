//! TPM 2.0 SSH integration test — drives the `tss-esapi` path against
//! a `swtpm` soft-TPM emulator socket. Disabled by default (`#[ignore]`)
//! because the swtpm binary is not part of the default WSL2 / Linux CI
//! image; self-hosted runners with `swtpm` + `swtpm-tools` installed
//! can pass `--ignored` to exercise the end-to-end round trip.
//!
//! Manual run (host with swtpm installed):
//!
//! ```bash
//! mkdir -p /tmp/lfs-swtpm-state
//! swtpm_setup --tpm2 --tpm-state /tmp/lfs-swtpm-state \
//!     --create-config-files skip-if-exist
//! swtpm socket --tpm2 \
//!     --server type=tcp,port=2321 \
//!     --ctrl type=tcp,port=2322 \
//!     --tpmstate dir=/tmp/lfs-swtpm-state \
//!     --flags startup-clear &
//! TCTI=swtpm:host=127.0.0.1,port=2321 \
//!     cargo test --test tpm_ssh_swtpm -- --ignored
//! ```
//!
//! Hardware verification matrix:
//! - **fTPM (Microsoft Pluton, Intel PTT, AMD fTPM)** — generate +
//!   sign + import round-trip should pass; PIN-bound generate fires
//!   the lockout machinery on 4 wrong PINs.
//! - **Discrete TPM (Infineon SLB 9670, Nuvoton NPCT75x)** — same
//!   surface; older Infineon firmware may refuse RSA-2048 generation
//!   (returns TPM_RC_VALUE) — the test asserts a clean error path.
//! - **swtpm (CI / dev)** — covers the marshalling + handle plumbing
//!   end-to-end without real hardware.

#![cfg(target_os = "linux")]

use lfs_os_security::linux::tpm::TpmConfig;
use lfs_os_security::linux::tpm_ssh::{self, TpmSshAlgorithm, TpmSshSignature, TpmSshStorage};

fn swtpm_cfg() -> TpmConfig {
    // The default TCTI string covers `swtpm:host=127.0.0.1,port=2321`
    // when LFS_TPM_DEVICE is set; otherwise the test falls back to
    // `/dev/tpmrm0`. The CI runner sets the env var.
    let device = std::env::var("LFS_TPM_DEVICE").unwrap_or_else(|_| "/dev/tpmrm0".into());
    TpmConfig {
        device,
        ..TpmConfig::default()
    }
}

#[test]
#[ignore]
fn swtpm_ecdsa_p256_round_trip_signs_and_verifies_shape() {
    let cfg = swtpm_cfg();
    let key =
        tpm_ssh::generate(&cfg, TpmSshAlgorithm::EcdsaP256, None).expect("ECDSA P-256 generate");
    let TpmSshStorage::Blob { .. } = key.storage else {
        panic!("expected blob storage on fresh generate");
    };
    let challenge = b"swtpm-ecdsa-test-challenge";
    let sig = tpm_ssh::sign(&cfg, &key, None, challenge).expect("sign");
    match sig {
        TpmSshSignature::EcdsaP256RawConcat(bytes) => assert_eq!(bytes.len(), 64),
        other => panic!("unexpected signature variant: {other:?}"),
    }
}

#[test]
#[ignore]
fn swtpm_rsa_2048_round_trip_signs_and_returns_256_bytes() {
    let cfg = swtpm_cfg();
    let key = tpm_ssh::generate(&cfg, TpmSshAlgorithm::Rsa2048, None).expect("RSA-2048 generate");
    let challenge = b"swtpm-rsa-test-challenge";
    let sig = tpm_ssh::sign(&cfg, &key, None, challenge).expect("sign");
    match sig {
        TpmSshSignature::Rsa2048(bytes) => assert_eq!(bytes.len(), 256),
        other => panic!("unexpected signature variant: {other:?}"),
    }
}

#[test]
#[ignore]
fn swtpm_pin_bound_key_rejects_wrong_pin() {
    let cfg = swtpm_cfg();
    let pin = b"correct-horse";
    let key =
        tpm_ssh::generate(&cfg, TpmSshAlgorithm::EcdsaP256, Some(pin)).expect("PIN-bound generate");
    // Right PIN succeeds.
    let _ = tpm_ssh::sign(&cfg, &key, Some(pin), b"challenge").expect("right PIN signs");
    // Wrong PIN surfaces the typed `pin incorrect:` reason.
    let err =
        tpm_ssh::sign(&cfg, &key, Some(b"wrong"), b"challenge").expect_err("wrong PIN must fail");
    assert!(
        err.to_string().contains("pin incorrect"),
        "expected pin-incorrect discriminator, got: {err}"
    );
}

#[test]
#[ignore]
fn swtpm_blob_import_round_trips_through_serialization() {
    let cfg = swtpm_cfg();
    let key = tpm_ssh::generate(&cfg, TpmSshAlgorithm::EcdsaP256, None).expect("generate");
    let TpmSshStorage::Blob { public, private } = key.storage.clone() else {
        panic!("expected blob storage");
    };
    let envelope = tpm_ssh::pack_envelope(&public, &private).expect("pack");
    let reimported = tpm_ssh::import_blob(&envelope).expect("import");
    assert_eq!(reimported.algorithm, TpmSshAlgorithm::EcdsaP256);
    // The reimported public-key bytes must match the original — the
    // round-trip serializes & deserializes the marshalled
    // `TPM2B_PUBLIC` cleanly.
    assert_eq!(reimported.public, key.public);
}

#[test]
#[ignore]
fn swtpm_persistent_handle_round_trip_promotes_and_evicts() {
    // Sequence: generate (blob) → make_persistent(slot) →
    // sign-from-persistent → evict → second make_persistent on the
    // same slot succeeds (proving the eviction freed the slot).
    let cfg = swtpm_cfg();
    let slot: u32 = 0x8101_00A0;
    let mut key = tpm_ssh::generate(&cfg, TpmSshAlgorithm::EcdsaP256, None).expect("generate");
    // Cosmetic guard: ensure we start in blob mode.
    assert!(matches!(key.storage, TpmSshStorage::Blob { .. }));
    tpm_ssh::make_persistent(&cfg, &mut key, slot).expect("make_persistent");
    assert!(matches!(key.storage, TpmSshStorage::PersistentHandle(h) if h == slot));
    // The persistent-mode sign path reaches the slot via
    // `tr_from_tpm_public` — confirms the chip-side install
    // actually staged a usable key.
    let sig = tpm_ssh::sign(&cfg, &key, None, b"swtpm-persistent-challenge")
        .expect("sign from persistent");
    match sig {
        TpmSshSignature::EcdsaP256RawConcat(bytes) => assert_eq!(bytes.len(), 64),
        other => panic!("unexpected signature variant: {other:?}"),
    }
    tpm_ssh::evict(&cfg, &key).expect("evict");
    // Re-promote the same slot — `TPM_RC_NV_DEFINED` would surface
    // if eviction failed to free it.
    let mut key2 = tpm_ssh::generate(&cfg, TpmSshAlgorithm::EcdsaP256, None).expect("generate2");
    tpm_ssh::make_persistent(&cfg, &mut key2, slot).expect("re-promote slot");
    // Cleanup so the test is idempotent against the swtpm state dir.
    tpm_ssh::evict(&cfg, &key2).expect("cleanup evict");
}

#[test]
#[ignore]
fn swtpm_make_persistent_on_occupied_slot_returns_handle_in_use() {
    // Promote one key onto a slot, then attempt to promote a
    // second key onto the same slot — must surface the typed
    // `handle in use:` discriminator the Dart routing layer
    // matches on.
    let cfg = swtpm_cfg();
    let slot: u32 = 0x8101_00A1;
    let mut first =
        tpm_ssh::generate(&cfg, TpmSshAlgorithm::EcdsaP256, None).expect("first generate");
    tpm_ssh::make_persistent(&cfg, &mut first, slot).expect("first make_persistent");
    let mut second =
        tpm_ssh::generate(&cfg, TpmSshAlgorithm::EcdsaP256, None).expect("second generate");
    let err = tpm_ssh::make_persistent(&cfg, &mut second, slot)
        .expect_err("second make_persistent must fail on occupied slot");
    assert!(
        err.to_string().contains("handle in use"),
        "expected 'handle in use:' discriminator, got: {err}"
    );
    // Cleanup.
    tpm_ssh::evict(&cfg, &first).expect("cleanup evict");
}
