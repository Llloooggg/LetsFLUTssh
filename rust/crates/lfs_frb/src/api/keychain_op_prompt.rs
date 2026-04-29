//! FRB adapter for the unified keychain op prompt registry +
//! the L2 gate setPassword / clear / isConfigured actor commands
//! that ride on it.
//!
//! The Dart subscriber for `BusEvent::KeychainOpPromptRequest`
//! branches on `op_wire_name` (`"read" | "contains" | "write" |
//! "delete"`) and executes the matching `flutter_secure_storage`
//! call, then resolves via [`keychain_op_prompt_resolve`] /
//! [`keychain_op_prompt_resolve_error`] / [`keychain_op_prompt_cancel`].

use lfs_core::security::keychain_op_prompt;

/// Resolve a pending keychain op prompt with success bytes.
///
/// Wire mapping per op kind:
/// * `Read` — `bytes` carries the keychain payload (raw bytes,
///   already base64-decoded by the Dart subscriber); pass an
///   empty `Vec` for "entry missing / read failed".
/// * `Contains` — pass an empty `Vec` for "key present"; a
///   `null` / no-call means "key absent" (use the `_absent`
///   helper for clarity).
/// * `Write` / `Delete` — pass an empty `Vec` for success.
///
/// Returns `true` when a receiver was actually woken; `false`
/// for an unknown / already-resolved prompt id.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_op_prompt_resolve(prompt_id: String, bytes: Vec<u8>) -> bool {
    let payload = if bytes.is_empty() { None } else { Some(bytes) };
    keychain_op_prompt::instance().resolve(&prompt_id, Ok(payload))
}

/// Resolve a `Contains` prompt explicitly with the "present"
/// signal — `Ok(Some(empty))`. Distinguishes the Dart-side
/// "key found, no payload to return" case from the more
/// ambiguous "send empty bytes" path used by Read.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_op_prompt_resolve_contains_present(prompt_id: String) -> bool {
    keychain_op_prompt::instance().resolve(&prompt_id, Ok(Some(Vec::new())))
}

/// Resolve a `Contains` / `Read` prompt with the "absent"
/// signal — `Ok(None)`. Same semantics as passing an empty
/// `Vec` to [`keychain_op_prompt_resolve`] for `Read`, but
/// surfaces the absence intent clearly at the Dart call site.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_op_prompt_resolve_absent(prompt_id: String) -> bool {
    keychain_op_prompt::instance().resolve(&prompt_id, Ok(None))
}

/// Resolve a pending prompt with a plugin error. The L2 actor
/// branches on `Err` to roll back any prior disk side-effect
/// (the set_password write path); the clear path appends the
/// error to its log + continues.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_op_prompt_resolve_error(prompt_id: String, message: String) -> bool {
    keychain_op_prompt::instance().resolve(&prompt_id, Err(message))
}

/// Cancel a pending prompt without resolving — used by the Dart
/// subscriber when it can't dispatch the keychain call (e.g. the
/// user interrupted the flow with a tier reset from the lock
/// screen). Idempotent on a missing id.
#[flutter_rust_bridge::frb(sync)]
pub fn keychain_op_prompt_cancel(prompt_id: String) {
    keychain_op_prompt::instance().cancel(&prompt_id);
}

// ---- Composite L2 gate actor commands -------------------------

/// True when the L2 gate is configured on this install — disk
/// hash present AND keychain pepper present. Composes a disk
/// presence check + a `Contains` prompt round-trip; the Dart
/// subscriber executes
/// `flutter_secure_storage.containsKey('letsflutssh_l2_pepper')`.
///
/// Returns `Ok(false)` on any miss (file absent, pepper absent,
/// prompt cancelled, plugin error). `Err` is reserved for
/// unrecoverable infra failures.
pub async fn keychain_password_gate_is_configured(support_dir: String) -> Result<bool, String> {
    use lfs_core::security::keychain_password_gate_actor::is_configured;
    let path = std::path::PathBuf::from(support_dir);
    is_configured(&path).await
}

/// Configure the gate with `password`. Generates fresh salt +
/// pepper, writes the disk hash atomically, then asks Dart to
/// write the pepper to the keychain. On Dart write failure
/// rolls back the disk hash. Also clears the persisted
/// rate-limit state file (best effort).
pub async fn keychain_password_gate_set_password(
    support_dir: String,
    password: String,
) -> Result<(), String> {
    use lfs_core::security::keychain_password_gate_actor::set_password;
    let path = std::path::PathBuf::from(support_dir);
    set_password(&path, &password).await
}

/// Drop every artifact the gate writes — disk hash + keychain
/// pepper. Best-effort: a disk error or a plugin error surfaces
/// as `Err` so the caller can log, but each side runs
/// independently of the other.
pub async fn keychain_password_gate_clear(support_dir: String) -> Result<(), String> {
    use lfs_core::security::keychain_password_gate_actor::clear;
    let path = std::path::PathBuf::from(support_dir);
    clear(&path).await
}
