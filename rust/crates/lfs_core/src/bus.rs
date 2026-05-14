//! Typed Command / Event bus — Rust-core foundation.
//!
//! Frontend dispatches `Command`s (operation envelopes); domain
//! actors mutate state and publish `Event`s onto the bus broker.
//! Subscribers receive an `Event` stream filtered by topic, so a
//! per-screen view picks up only the events that affect it.
//!
//! The foundation surface defines just the scaffolding: a
//! `NoopEcho` command + an `Echoed` event used as smoke test for
//! the FRB plumbing. Concrete domain enums (`Connection*`,
//! `PortForward*`, `Transfer*`, ...) extend in lockstep with the
//! actor moves below.
//!
//! # Design choices
//!
//! - `tokio::sync::broadcast` for the broker: multi-subscriber
//!   fan-out, drops the slowest receiver on overflow rather than
//!   stalling the publisher. Capacity is generous (256) since
//!   most domains emit at most a handful of events per user
//!   action; the recorder / transfer paths post per-frame /
//!   per-chunk events but those have their own coalescing inside
//!   the actor before reaching the bus.
//! - Subscribers receive a *clone* of every event (the broadcast
//!   channel handles that). Filtering happens in the subscriber
//!   loop — cheap per-event topic match keeps the hot path
//!   lock-free.
//! - Drop-on-overflow is intentional: the bus is a notification
//!   surface, not a queue. Authoritative state lives in the
//!   actors; if a subscriber lags badly enough to lose events it
//!   re-syncs through a snapshot command rather than replaying.

use std::collections::HashMap;

use tokio::sync::broadcast;

use crate::error::Error;

/// Generous capacity. Domain actors emit a handful of events per
/// user action; per-frame / per-chunk traffic coalesces inside the
/// actor before reaching the bus.
const EVENT_CHANNEL_CAPACITY: usize = 4096;

/// Topic tag attached to every event. Subscribers filter by the
/// topic they care about; a per-screen view typically subscribes
/// to one or two topics.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EventTopic {
    /// Smoke / debug events — foundation echo, future bus self-tests.
    Diagnostics,
    /// Connection lifecycle.
    Connection,
    /// Port forward rule status.
    PortForward,
    /// Transfer queue task progress.
    Transfer,
    /// Recorder lifecycle.
    Recorder,
    /// Auto-lock state machine.
    AutoLock,
    /// `.lfs` import handle progress.
    Import,
    /// Auto-update channel — fetch / download progress.
    Update,
    /// Known-hosts table — refresh notification for the
    /// settings panel + any cached snapshot mirrors.
    KnownHosts,
    /// Sessions / folders tables — refresh notification for the
    /// session-store cache mirror. Fires after every write
    /// (upsert / delete / move / folder rename / collapsed-flag
    /// toggle) so the Dart shim can re-fetch in one
    /// microtask-coalesced refresh rather than per-call.
    Sessions,
    /// `ssh_keys` + `ssh_key_certificates` tables — refresh
    /// notification for the SSH-key store cache mirror. Fires
    /// after every write (upsert / delete / replace-all /
    /// import / cert upsert/delete / hardware-row mutation) so
    /// the Dart shim can re-fetch in one microtask-coalesced
    /// refresh rather than per-call. Symmetric with the Sessions
    /// topic — same shape, same publish discipline.
    Keys,
    /// `config.json` actor — fires after a debounced save lands
    /// on disk. Subscribers re-snapshot the canonical state
    /// without polling.
    Config,
    /// Tier state machine — Locked / Unlocking / Unlocked /
    /// Wiping transitions. Subscribers (Dart unlock dialog,
    /// auto-lock path, lock indicator) react to state changes
    /// without polling.
    Tier,
    /// Per-prompt-type request channels — keychain pepper read,
    /// keychain op (write/delete/contains), biometric probe,
    /// keychain reachability probe, hardware-vault probe,
    /// credential prompt. The Dart subscriber multiplexes by
    /// event variant.
    SecurityPrompt,
    /// `SecurityCapabilities` snapshot — fired by
    /// `lfs_core::security::capabilities_cache::Cache` whenever
    /// the cached snapshot changes (or is explicitly cleared).
    /// Subscribers (wizard dialog, Settings security cards)
    /// re-render against the canonical snapshot without polling.
    SecurityCapabilities,
    /// Rust-core log fan-out — every `lfs_core::app_log::log!`
    /// call publishes here so the Dart `AppLogger` subscriber
    /// can forward the line into the same on-disk file the rest
    /// of the app's logging routes through. Without this, Rust
    /// failures inside catch-arms / panics caught by FRB would
    /// disappear silently.
    CoreLog,
    /// In-process ssh-agent endpoint — per-key confirmation
    /// requests + cancellation notices. The Dart Settings UI
    /// subscribes here and mounts an `AgentSignatureRequestDialog`
    /// per `SshAgentSignaturePrompt` event; the dialog calls back
    /// through the FRB `ssh_agent_respond_to_signature_request`
    /// surface with the user's decision. See
    /// `lfs_core::ssh_agent::per_key_confirm`.
    SshAgent,
}

impl EventTopic {
    /// Every variant in declaration order. Used by [`EventBus::new`]
    /// to pre-allocate one broadcast channel per topic. A new
    /// variant added above this list MUST be appended here or
    /// `publish` would panic at runtime trying to send to a
    /// missing channel.
    pub const ALL: &'static [EventTopic] = &[
        EventTopic::Diagnostics,
        EventTopic::Connection,
        EventTopic::PortForward,
        EventTopic::Transfer,
        EventTopic::Recorder,
        EventTopic::AutoLock,
        EventTopic::Import,
        EventTopic::Update,
        EventTopic::KnownHosts,
        EventTopic::Sessions,
        EventTopic::Keys,
        EventTopic::Config,
        EventTopic::Tier,
        EventTopic::SecurityPrompt,
        EventTopic::SecurityCapabilities,
        EventTopic::CoreLog,
        EventTopic::SshAgent,
    ];
}

/// State change envelope published onto the bus. Variants accrete
/// as actor lifts land.
#[derive(Debug, Clone)]
pub enum Event {
    /// Foundation smoke event. `bus_dispatch(NoopEcho)` publishes
    /// this with the same payload so the FRB plumbing can be
    /// verified end-to-end before any real domain command lands.
    Echoed { payload: String },

    /// Connection lifecycle — emitted whenever an actor
    /// transitions between `Disconnected / Connecting / Connected`.
    /// Subscribers re-snapshot their connection-level views off
    /// this signal; the snapshot itself is fetched via a separate
    /// `ConnectionSnapshot` command (cheap copy of the actor's
    /// plain-data view).
    ConnectionStateChanged {
        id: crate::connection::ConnId,
        state: crate::connection::ConnectionState,
    },

    /// Connection lifecycle — fan-out per progress step
    /// (`socketConnect / hostKeyVerify / authenticate / openChannel`
    /// at `inProgress / success / failed`). The Dart-era
    /// `Connection.progressStream` retires in favour of subscribing
    /// here and filtering by id.
    ConnectionProgress {
        id: crate::connection::ConnId,
        step: crate::connection::ProgressStep,
    },

    /// Connection lifecycle — emitted when an actor records a
    /// fresh connect-time error. Detail is the localised /
    /// sanitised message; subscribers pair this with the matching
    /// `ConnectionStateChanged(Disconnected)` for UI feedback.
    ConnectionError {
        id: crate::connection::ConnId,
        detail: String,
    },

    /// Connection lifecycle — emitted when an actor is
    /// removed from the registry (manual disconnect, parent of a
    /// disconnected bastion chain).
    ConnectionRemoved { id: crate::connection::ConnId },

    /// Connection lifecycle — count of user-visible Connected
    /// actors changed (excludes internal bastion hops). The
    /// Android foreground-service binding subscribes here to
    /// start / stop the persistent service. Re-published after
    /// every state transition that flips at least one actor's
    /// `Connected` predicate; coalesced inside the publisher so
    /// repeated emits with the same count don't fan out.
    ConnectionActiveCountChanged { count: i64 },

    /// Auto-lock — fired when the idle timer expires, when
    /// the app backgrounds with a non-zero timeout, or when the
    /// user explicitly requests a lock. The payload is empty —
    /// subscribers re-fetch any state they need from the
    /// machine snapshot or the DB.
    AutoLockLocked,
    /// Auto-lock — fired after the Dart unlock dialog
    /// supplies a fresh key + reopens the DB.
    AutoLockUnlocked,
    /// Auto-lock — fired when the configured idle timeout
    /// changes. Carries the new value in minutes (0 = off).
    AutoLockTimeoutChanged { minutes: i64 },

    /// Config — fired by `lfs_core::config_store::Store` after
    /// a debounced atomic write of `config.json` lands on disk.
    /// Carries the freshly-written JSON so subscribers can swap
    /// in the snapshot without a follow-up `get_json` round-trip.
    ConfigChanged { json: String },

    /// Tier state machine — fired by
    /// `lfs_core::security::tier_machine::Machine` on every
    /// successful state transition. Carries the new state's wire
    /// name (`locked` / `unlocking` / `unlocked` / `wiping`) so
    /// subscribers branch without parsing an enum across FRB.
    TierStateChanged { state_wire_name: String },

    /// Post-unlock cascade settled Rust-side — the orchestrator
    /// staged the DB key, opened the rusqlite handle, and
    /// persisted the resolved tier into `config.json`. Fires
    /// AFTER `TierStateChanged.unlocked` on the same `Tier`
    /// topic; the Dart `TierUnlockedListener` subscribes here
    /// to run the Riverpod half (cache invalidations +
    /// `securityStateProvider` flip) off a single payload
    /// instead of round-tripping back through
    /// `tier_machine_active_tier_wire_name` +
    /// `secrets_has(ACTIVE_DBKEY_SECRET_ID)`.
    ///
    /// `tier_wire`: the resolved tier (`plaintext` / `keychain` /
    /// `hardware` / `paranoid`) that just unlocked.
    /// `has_key`: whether the canonical `ACTIVE_DBKEY_SECRET_ID`
    /// slot carries a staged key — true on every tier the
    /// orchestrator stages a non-empty buffer for (the plaintext
    /// branch stages an empty buffer; the slot is still present
    /// so this flag follows the SecretStore probe shape the Dart
    /// listener used to perform itself).
    UnlockCascadeReady { tier_wire: String, has_key: bool },

    /// Connection credential prompt — fired by the connection
    /// actor when a saved session needs a password / passphrase
    /// the SecretStore doesn't already carry. `kind_wire_name`
    /// is `password` / `passphrase`; `session_id` lets the
    /// Dart UI render the right session label in the dialog
    /// caption. Resolved through
    /// `lfs_core::security::credential_prompt::PromptRegistry`.
    CredentialPromptRequest {
        prompt_id: String,
        session_id: String,
        kind_wire_name: String,
    },

    /// Keychain-reachability probe — fired by the capabilities
    /// orchestrator. Dart subscriber pings the OS
    /// secure-storage backend (Linux: zbus `SecretService::connect`
    /// against `org.freedesktop.secrets`; non-Linux: live
    /// `lfs_os_security::secure_key_storage` write/read/delete
    /// round-trip) and dispatches the `KeyringProbeResult` wire
    /// name back via `keychain_probe_prompt::instance().resolve`.
    KeychainProbePromptRequest { prompt_id: String },
    /// Hardware-vault probe — fired by the capabilities
    /// orchestrator on Apple / Android / Windows. Dart
    /// subscriber calls `HardwareTierVault.probeDetail()` —
    /// which routes through FRB into
    /// `lfs_os_security::hardware_tier_vault::probe_detail` —
    /// and dispatches the platform-specific reason code
    /// (`available` / `no_secure_enclave` /
    /// `strongbox_unavailable` / ...) via
    /// `hardware_vault_probe_prompt::instance().resolve`.
    /// Linux uses the in-process TPM probe and never
    /// publishes this event.
    HardwareVaultProbePromptRequest { prompt_id: String },
    /// Hardware-vault unlock — fired by the T2 tier-unlock
    /// orchestrator. Dart subscriber calls
    /// `HardwareTierVault.read(pin)` which routes through FRB
    /// into the per-platform Rust vault (Apple SE / Android
    /// Keystore / Windows CNG / Linux TPM2 subprocess);
    /// resolves with the unsealed key bytes (or `None` on
    /// wrong PIN / cancelled dialog, or `Err` on plugin
    /// failure) via
    /// `hardware_vault_unlock_prompt::instance().resolve`.
    /// `pin` is `None` for the passwordless variant where the
    /// vault was sealed without a user secret.
    HardwareVaultUnlockPromptRequest {
        prompt_id: String,
        pin: Option<String>,
    },
    /// Hardware-vault seal — fired by the T2 first-launch
    /// orchestrator. Dart subscriber takes the staged bytes via
    /// [`crate::secrets::SecretStore::take`] (atomic
    /// read-and-remove), calls
    /// `HardwareTierVault.store(dbKey: bytes, pin: pin)` which
    /// fans out per-platform; resolves `Ok(())` on success or
    /// `Err(message)` on plugin failure via
    /// `hardware_vault_seal_prompt::instance().resolve`.
    /// `pin_secret_id` is `None` for the passwordless variant.
    ///
    /// **Why secret-id indirection.** **Don't carry plaintext
    /// (`db_key: Vec<u8>` / `pin: Option<String>`) inline on the
    /// broadcast.** `tokio::sync::broadcast` clones every event
    /// to every subscriber on the SecurityPrompt topic and buffers
    /// the bytes until each one consumes them; the FRB stream
    /// then delivers them to Dart as a plain `Vec<u8>` whose
    /// lifetime no zeroize discipline reaches. The opaque
    /// SecretStore id keeps the bytes Rust-side in pinned
    /// allocator memory; the legitimate subscriber takes them on
    /// demand and they never enter the broadcast or cross FRB
    /// inline.
    HardwareVaultSealPromptRequest {
        prompt_id: String,
        db_key_secret_id: String,
        pin_secret_id: Option<String>,
    },
    /// Vault-recovery dialog — fired by the Rust recovery
    /// orchestrator when it needs the user to pick between
    /// destructive reset / quit / retry-under-different-tier. Dart
    /// subscriber renders the matching widget (`DbCorruptDialog` or
    /// `TierResetDialog`) keyed off `kind`, dispatches the
    /// user's choice back via
    /// `recovery_prompt_resolve(prompt_id, response_wire_name)`.
    /// The orchestrator awaits the
    /// [`crate::security::recovery_prompt::PromptRegistry`] receiver
    /// inside its `recovery_handle_*` entry points.
    ///
    /// `choices` carries the wire names of the legal responses for
    /// this prompt (subset of
    /// `RecoveryPromptResponse::wire_name`) so the Dart shell can
    /// keep its dialog buttons aligned without having to mirror the
    /// kind→choice-set table separately. The legacy-state prompt
    /// drops `tryOtherTier`; the other two carry the full triple.
    RecoveryPromptRequest {
        prompt_id: String,
        kind: crate::security::recovery_prompt::RecoveryPromptKind,
        choices: Vec<String>,
    },
    /// Security capabilities snapshot updated — fired by
    /// `lfs_core::security::capabilities_cache::Cache::set` when
    /// the new snapshot differs from the cached one, and by
    /// `Cache::clear` (with `json` empty) when the cache is
    /// dropped. Subscribers (wizard / Settings cards) re-render
    /// off the carried JSON without a follow-up `view` call.
    SecurityCapabilitiesChanged { json: String },

    /// Recorder — fired when a fresh recording actor enters
    /// the registry.
    RecorderStarted { id: String, path: String },
    /// Recorder — fired when an actor leaves the registry
    /// (close / shutdown / file rotation).
    RecorderStopped { id: String },
    /// Recorder — fired after the frame-write driver records
    /// a chunk of bytes. Carries the running total so subscribers
    /// can render progress without polling.
    RecorderBytesWritten { id: String, total_bytes: u64 },
    /// Recorder — fired by the per-id worker when the running
    /// total crosses [`crate::recorder::MAX_FILE_BYTES`]. The
    /// Dart shim subscribes, prepares a fresh path under the
    /// session's recording dir, and enqueues a
    /// [`crate::recorder::queue::QueueEntry::Rotate`]. The
    /// worker latches the request flag so a single overflow
    /// emits one event regardless of how many writes follow
    /// before the rotate enqueue arrives.
    RecorderRotateRequested { id: String, bytes_written: u64 },
    /// Recorder — surfaced by the per-id worker when one of
    /// `record_header` / `record_event` / `rotate_to` /
    /// `close_with_io` returns an error. Dart side switches the
    /// row to an error chip; the worker keeps draining its
    /// mailbox so a transient failure on a single frame does
    /// not stop subsequent ones.
    ///
    /// `kind` is a stable wire-name discriminator (`"header"`,
    /// `"event"`, `"rotate"`, `"close"`); `detail` carries the
    /// underlying error message (sanitized upstream by the log
    /// pipeline so paths / hostnames don't surface here).
    RecorderWriteFailed {
        id: String,
        kind: String,
        detail: String,
    },

    /// Transfer queue — task entered the queue.
    TransferTaskAdded { id: String },
    /// Transfer queue — task transitioned to a new state.
    TransferTaskState {
        id: String,
        state: crate::transfer::TaskState,
    },
    /// Transfer queue — bytes-done counter advanced.
    TransferTaskProgress {
        id: String,
        bytes_done: u64,
        bytes_total: u64,
    },
    /// Transfer queue — terminal failure on a task.
    TransferTaskError { id: String, detail: String },

    /// Port forward — rule actor entered the registry.
    PortForwardRegistered { id: String },
    /// Port forward — rule status transitioned.
    PortForwardStatus {
        id: String,
        status: crate::portforward::RuleStatus,
        detail: Option<String>,
    },
    /// Port forward — rule actor left the registry.
    PortForwardRemoved { id: String },

    /// Auto-update — bytes-written tick during a streaming
    /// download. `total_bytes` is `None` when the server did not
    /// declare a `Content-Length`. Subscribers tick the progress
    /// bar; the URL identifies the active download for UIs that
    /// drive multiple in parallel.
    UpdateDownloadProgress {
        url: String,
        written_bytes: u64,
        total_bytes: Option<u64>,
    },
    /// Auto-update — HTTP bytes are on disk; the orchestrator
    /// is now hashing + fetching the signed manifest + verifying
    /// the Ed25519 signature. UI swaps the determinate progress
    /// bar for an indeterminate "Verifying…" caption.
    UpdateVerifyingStarted { url: String },
    /// Auto-update — every verification step passed; the asset
    /// is at `path` ready to install.
    UpdateDownloadCompleted { url: String, path: String },

    /// Known-hosts table mutated (upsert / delete / clear /
    /// import). No detail — Dart subscribers re-fetch the full
    /// list via `db_known_hosts_list_all`. One coalesced event
    /// per write; bulk imports emit a single event for the whole
    /// batch.
    KnownHostsChanged,
    /// Sessions / folders tables mutated. No detail — Dart
    /// subscribers re-fetch the full list via the session DAOs.
    /// One event per write covers both session-row changes and
    /// folder-cascade ripples (rename / move / delete / collapsed
    /// toggle) — the cache mirror picks the canonical state up
    /// from the DB after the FRB layer publishes here.
    SessionsChanged,
    /// `ssh_keys` + `ssh_key_certificates` tables mutated. No
    /// detail — Dart subscribers re-fetch the full metadata
    /// listing via the SSH-key DAOs. One event per write covers
    /// every row mutation (software upsert / delete / replace-all
    /// / import-merge / cert upsert/delete / hardware-row
    /// stub-clear / PKCS#11 module-path rebind) so the cache
    /// mirror picks the canonical state off the DB after the
    /// FRB layer publishes here. Symmetric with
    /// [`Event::SessionsChanged`].
    KeysChanged,

    /// TOFU prompt — russh's `check_server_key` saw a host key
    /// that does not match a stored entry. The prompt id is
    /// caller-allocated (UUIDv4 from the Dart shim that subscribes
    /// to this topic); the response command echoes the same id so
    /// concurrent prompts (parallel reconnect storm) don't
    /// cross-wire. `kind` distinguishes "first time we've seen
    /// this host" from "host key changed under us — possible
    /// MITM" so the UI picks the matching dialog wording.
    KnownHostPromptRequest {
        prompt_id: String,
        host: String,
        port: i64,
        key_type: String,
        fingerprint: String,
        kind: KnownHostPromptKind,
    },
    /// TOFU prompt result — published after the dispatcher resolves
    /// the user's choice from the bus command back into the
    /// awaiting handler. Subscribers (the russh handler that fired
    /// the request) match on `prompt_id`.
    KnownHostPromptResolved { prompt_id: String, accepted: bool },

    /// Rust-core log line. Published by `lfs_core::app_log::log!`
    /// at every internal log site so the Dart `AppLogger`
    /// subscriber can fold the line into the on-disk
    /// `letsflutssh.log`. Topic: [`EventTopic::CoreLog`].
    ///
    /// `level`: `"info"` / `"warn"` / `"error"`.
    /// `name`: short tag (module / subsystem) — same shape Dart
    /// passes via `AppLogger.log(name: …)`.
    /// `message`: the line body. Sanitization is the publisher's
    /// responsibility; the bus does not re-sanitize.
    CoreLog {
        level: CoreLogLevel,
        name: String,
        message: String,
    },

    /// In-process ssh-agent endpoint — a SIGN_REQUEST landed against
    /// a key whose `agent_policy = 'ask'` and the endpoint parked
    /// the signer waiting on a verdict from the Dart side. The
    /// Settings UI subscribes to [`EventTopic::SshAgent`] and mounts
    /// an `AgentSignatureRequestDialog` for each event; the dialog
    /// dispatches the user's verdict via
    /// `ssh_agent_respond_to_signature_request(request_id, decision)`.
    ///
    /// `request_id` is the opaque correlation id parked in
    /// [`crate::ssh_agent::per_key_confirm`]; routing back through
    /// the same id resolves the matching oneshot.
    /// `key_id` / `key_label` identify the stored row so the dialog
    /// can render the human-readable name. `requester` is the
    /// best-effort process name behind the agent socket — `None`
    /// on platforms that cannot resolve it cheaply (macOS), so the
    /// dialog renders "Unknown" in that case.
    SshAgentSignaturePrompt {
        request_id: String,
        key_id: String,
        key_label: String,
        requester: Option<String>,
    },
}

/// Severity tag for [`Event::CoreLog`]. Mirrors the Dart
/// `LogLevel` enum case-for-case so the FRB shim can map without
/// branching on a discriminant string.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CoreLogLevel {
    Info,
    Warn,
    Error,
}

/// Distinguish the two TOFU prompt shapes:
/// - `NewHost` — first time we've seen this `host:port`. The dialog
///   shows the new fingerprint with a "trust this server?" prompt.
/// - `KeyChanged` — we have a stored entry for this `host:port` but
///   the offered key does not match. The dialog warns about
///   possible MITM and shows both fingerprints; accepting overwrites
///   the stored entry.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KnownHostPromptKind {
    NewHost,
    KeyChanged,
}

impl Event {
    pub fn topic(&self) -> EventTopic {
        match self {
            Event::Echoed { .. } => EventTopic::Diagnostics,
            Event::ConnectionStateChanged { .. }
            | Event::ConnectionProgress { .. }
            | Event::ConnectionError { .. }
            | Event::ConnectionRemoved { .. }
            | Event::ConnectionActiveCountChanged { .. } => EventTopic::Connection,
            Event::AutoLockLocked
            | Event::AutoLockUnlocked
            | Event::AutoLockTimeoutChanged { .. } => EventTopic::AutoLock,
            Event::RecorderStarted { .. }
            | Event::RecorderStopped { .. }
            | Event::RecorderBytesWritten { .. }
            | Event::RecorderRotateRequested { .. }
            | Event::RecorderWriteFailed { .. } => EventTopic::Recorder,
            Event::TransferTaskAdded { .. }
            | Event::TransferTaskState { .. }
            | Event::TransferTaskProgress { .. }
            | Event::TransferTaskError { .. } => EventTopic::Transfer,
            Event::PortForwardRegistered { .. }
            | Event::PortForwardStatus { .. }
            | Event::PortForwardRemoved { .. } => EventTopic::PortForward,
            Event::UpdateDownloadProgress { .. }
            | Event::UpdateVerifyingStarted { .. }
            | Event::UpdateDownloadCompleted { .. } => EventTopic::Update,
            Event::KnownHostsChanged => EventTopic::KnownHosts,
            Event::SessionsChanged => EventTopic::Sessions,
            Event::KeysChanged => EventTopic::Keys,
            Event::ConfigChanged { .. } => EventTopic::Config,
            Event::TierStateChanged { .. } | Event::UnlockCascadeReady { .. } => EventTopic::Tier,
            Event::CoreLog { .. } => EventTopic::CoreLog,
            Event::SshAgentSignaturePrompt { .. } => EventTopic::SshAgent,
            Event::CredentialPromptRequest { .. } => EventTopic::SecurityPrompt,
            Event::KeychainProbePromptRequest { .. } => EventTopic::SecurityPrompt,
            Event::HardwareVaultProbePromptRequest { .. } => EventTopic::SecurityPrompt,
            Event::HardwareVaultUnlockPromptRequest { .. } => EventTopic::SecurityPrompt,
            Event::HardwareVaultSealPromptRequest { .. } => EventTopic::SecurityPrompt,
            Event::RecoveryPromptRequest { .. } => EventTopic::SecurityPrompt,
            Event::SecurityCapabilitiesChanged { .. } => EventTopic::SecurityCapabilities,
            Event::KnownHostPromptRequest { .. } | Event::KnownHostPromptResolved { .. } => {
                EventTopic::KnownHosts
            }
        }
    }
}

/// Operation envelope dispatched by the frontend. New variants
/// extend this enum with concrete domain commands.
#[derive(Debug, Clone)]
pub enum Command {
    /// Foundation smoke command — emits `Event::Echoed` with the
    /// same payload. No state mutation; use only for FRB plumbing
    /// tests.
    NoopEcho { payload: String },

    /// Remove an actor from the registry. Idempotent on a
    /// missing id. Drops the held russh handle (which sends
    /// `SSH_MSG_DISCONNECT` on Drop) before clearing the row.
    ConnectionDisconnect { id: crate::connection::ConnId },

    /// Tear down every active connection actor. Convenience for
    /// "lock now" / shutdown paths — emits `ConnectionRemoved`
    /// per actor as it walks the registry.
    ConnectionDisconnectAll,

    /// Auto-lock — pointer activity ping. Resets the idle
    /// timer; the Dart side fires this once per significant
    /// pointer event so the lock doesn't trip mid-typing.
    AutoLockOnPointerActivity,
    /// Auto-lock — lifecycle change. `background = true` is
    /// the Dart-era `paused / inactive / hidden` umbrella;
    /// `background = false` is `resumed`.
    AutoLockOnLifecycleChange { background: bool },
    /// Auto-lock — configure the idle timeout in minutes
    /// (0 disables the timer). Mirrors the Settings → Auto-lock
    /// preset list.
    AutoLockSetTimeout { minutes: i64 },
    /// Auto-lock — explicit lock request (Settings →
    /// "Lock now", deeplink, etc).
    AutoLockRequestLock,
    /// Auto-lock — unlock signal from the Dart-side unlock
    /// dialog. The dialog has already supplied the master key +
    /// reopened the DB; the machine just resets its activity
    /// clock and emits the matching event.
    AutoLockUnlock,

    /// TOFU prompt response — the Dart UI's host-key dialog
    /// resolved (user tapped Accept / Reject). `prompt_id` echoes
    /// the id from the matching [`Event::KnownHostPromptRequest`]
    /// so the awaiting russh handler matches the right pending
    /// prompt. `accepted` is the user's choice; the dispatcher
    /// persists the new entry into `known_hosts` when accepted.
    KnownHostPromptResponse { prompt_id: String, accepted: bool },
}

/// Per-topic broadcast event broker. Owned by `AppState` (process
/// singleton); domain actors hold references and call `publish`,
/// FRB subscribers call `subscribe(topic)` to get a `Receiver`
/// scoped to one topic.
///
/// One [`broadcast::Sender`] per [`EventTopic`] — events publish
/// only to the channel matching `event.topic()`, so a subscriber
/// to (say) [`EventTopic::Recorder`] never sees a clone of an
/// unrelated [`EventTopic::Connection`] event. Eliminates the
/// "broadcast → 13 receivers each filter out 12/13" waste the
/// earlier single-channel shape paid on every event.
pub struct EventBus {
    senders: HashMap<EventTopic, broadcast::Sender<Event>>,
}

impl EventBus {
    /// Construct a bus with one channel per [`EventTopic::ALL`].
    /// Channels are pre-allocated so `publish` never has to grow
    /// the map under contention; lookup is a single HashMap hit
    /// keyed by the event's topic.
    pub fn new() -> Self {
        let mut senders = HashMap::with_capacity(EventTopic::ALL.len());
        for topic in EventTopic::ALL {
            let (sender, _) = broadcast::channel(EVENT_CHANNEL_CAPACITY);
            senders.insert(*topic, sender);
        }
        Self { senders }
    }

    /// Publish an event to the matching topic's channel only.
    /// Returns the number of live receivers on that topic
    /// (`0` when the event evaporates with no listener — not an
    /// error condition for a notification bus).
    ///
    /// Panics in debug if a topic somehow has no backing channel
    /// (would mean [`EventTopic::ALL`] missed a variant); in
    /// release the missing-key branch silently drops the event.
    pub fn publish(&self, event: Event) -> usize {
        let topic = event.topic();
        let Some(sender) = self.senders.get(&topic) else {
            debug_assert!(false, "EventBus: missing channel for topic {topic:?}");
            return 0;
        };
        sender.send(event).unwrap_or(0)
    }

    /// Subscribe to events on a single topic. Yields the topic's
    /// dedicated `Receiver`; consumers see only events whose
    /// `topic()` equals the requested one — no per-event filter
    /// loop in the subscriber needed.
    pub fn subscribe(&self, topic: EventTopic) -> broadcast::Receiver<Event> {
        // The map is initialised with every `EventTopic::ALL` entry,
        // so the lookup is infallible by construction. A panic here
        // would mean the enum-vs-ALL drift the constructor's
        // assertion above guards against has slipped.
        self.senders
            .get(&topic)
            .expect("EventBus: missing channel for topic — see EventTopic::ALL")
            .subscribe()
    }

    /// Live receiver count summed across every topic. Diagnostic
    /// only — callers MUST NOT gate `publish` on subscriber
    /// presence (a late subscriber would then miss the bootstrap
    /// event).
    pub fn subscriber_count(&self) -> usize {
        self.senders.values().map(|s| s.receiver_count()).sum()
    }

    /// Live receiver count for a single topic. Used by tests + the
    /// future "no subscribers, dropping" log line a noisy actor
    /// might want to emit before a publish.
    #[allow(dead_code)] // documented surface, not yet called outside tests
    pub fn subscriber_count_for(&self, topic: EventTopic) -> usize {
        self.senders
            .get(&topic)
            .map(|s| s.receiver_count())
            .unwrap_or(0)
    }

    /// Helper for the ssh-agent endpoint — publishes a
    /// [`Event::SshAgentSignaturePrompt`] without forcing the
    /// caller to import the `Event` variant directly. Returns the
    /// receiver count (`0` if nobody is listening — that case is
    /// the no-Dart-UI integration-test path; the prompt times out
    /// on the server side after [`crate::ssh_agent::per_key_confirm::PROMPT_TIMEOUT`]
    /// and defaults to Deny).
    pub fn publish_ssh_agent_prompt(
        &self,
        request_id: String,
        key_id: String,
        key_label: String,
        requester: Option<String>,
    ) -> usize {
        self.publish(Event::SshAgentSignaturePrompt {
            request_id,
            key_id,
            key_label,
            requester,
        })
    }
}

impl Default for EventBus {
    fn default() -> Self {
        Self::new()
    }
}

/// Dispatch a typed command. Domain handlers route by command
/// variant. New variants extend the match arms in lockstep with
/// each actor move.
///
/// Async because command handlers touch tokio mutexes
/// (registry lookups, per-actor locks). Synchronous-leaf commands
/// like `NoopEcho` keep the same await shape so the FRB caller
/// never has to branch.
pub async fn dispatch(cmd: Command) -> Result<(), Error> {
    let app = crate::app::instance();
    match cmd {
        Command::NoopEcho { payload } => {
            app.bus.publish(Event::Echoed { payload });
            Ok(())
        }
        Command::ConnectionDisconnect { id } => crate::connection::disconnect(&id).await,
        Command::ConnectionDisconnectAll => {
            crate::connection::disconnect_all().await;
            Ok(())
        }
        Command::AutoLockOnPointerActivity => {
            app.autolock.on_pointer_activity();
            Ok(())
        }
        Command::AutoLockOnLifecycleChange { background } => {
            app.autolock.on_lifecycle_change(
                if background {
                    crate::autolock::LifecycleState::Background
                } else {
                    crate::autolock::LifecycleState::Foreground
                },
                &app.bus,
            );
            Ok(())
        }
        Command::AutoLockSetTimeout { minutes } => {
            app.autolock.set_timeout_minutes(minutes, &app.bus);
            Ok(())
        }
        Command::AutoLockRequestLock => {
            app.autolock.request_lock(&app.bus);
            Ok(())
        }
        Command::AutoLockUnlock => {
            app.autolock.unlock(&app.bus);
            Ok(())
        }
        Command::KnownHostPromptResponse {
            prompt_id,
            accepted,
        } => {
            let resolved = app.known_hosts_prompts.resolve(&prompt_id, accepted);
            if resolved {
                app.bus.publish(Event::KnownHostPromptResolved {
                    prompt_id,
                    accepted,
                });
            }
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn echo_round_trip() {
        let bus = EventBus::new();
        let mut rx = bus.subscribe(EventTopic::Diagnostics);
        bus.publish(Event::Echoed {
            payload: "hello".into(),
        });
        let event = rx.recv().await.expect("event");
        match event {
            Event::Echoed { payload } => assert_eq!(payload, "hello"),
            other => panic!("unexpected event: {other:?}"),
        }
    }

    #[tokio::test]
    async fn topic_filter() {
        let bus = EventBus::new();
        let mut rx = bus.subscribe(EventTopic::Diagnostics);
        bus.publish(Event::Echoed {
            payload: "x".into(),
        });
        let event = rx.recv().await.expect("event");
        assert_eq!(event.topic(), EventTopic::Diagnostics);
    }

    #[test]
    fn publish_without_subscribers_returns_zero() {
        let bus = EventBus::new();
        assert_eq!(
            bus.publish(Event::Echoed {
                payload: "noop".into()
            }),
            0
        );
    }

    // ─── Event::topic() mapping coverage ────────────────────────────
    // One test per match arm in `Event::topic()` so a forgotten / mis-
    // routed arm fails the suite loud. The Dart subscriber filters by
    // topic; a regression here silently drops every event under the
    // affected variant.

    fn cid() -> crate::connection::ConnId {
        crate::connection::ConnId::from("cid")
    }

    #[test]
    fn topic_echoed_is_diagnostics() {
        assert_eq!(
            Event::Echoed {
                payload: "x".into()
            }
            .topic(),
            EventTopic::Diagnostics
        );
    }

    #[test]
    fn topic_connection_state_changed_is_connection() {
        assert_eq!(
            Event::ConnectionStateChanged {
                id: cid(),
                state: crate::connection::ConnectionState::Connected,
            }
            .topic(),
            EventTopic::Connection
        );
    }

    #[test]
    fn topic_connection_progress_is_connection() {
        assert_eq!(
            Event::ConnectionProgress {
                id: cid(),
                step: crate::connection::ProgressStep {
                    phase: crate::connection::ConnectionPhase::SocketConnect,
                    status: crate::connection::StepStatus::InProgress,
                    detail: None,
                },
            }
            .topic(),
            EventTopic::Connection
        );
    }

    #[test]
    fn topic_connection_error_is_connection() {
        assert_eq!(
            Event::ConnectionError {
                id: cid(),
                detail: "x".into()
            }
            .topic(),
            EventTopic::Connection
        );
    }

    #[test]
    fn topic_connection_removed_is_connection() {
        assert_eq!(
            Event::ConnectionRemoved { id: cid() }.topic(),
            EventTopic::Connection
        );
    }

    #[test]
    fn topic_connection_active_count_changed_is_connection() {
        assert_eq!(
            Event::ConnectionActiveCountChanged { count: 3 }.topic(),
            EventTopic::Connection
        );
    }

    #[test]
    fn topic_autolock_locked_is_autolock() {
        assert_eq!(Event::AutoLockLocked.topic(), EventTopic::AutoLock);
    }

    #[test]
    fn topic_autolock_unlocked_is_autolock() {
        assert_eq!(Event::AutoLockUnlocked.topic(), EventTopic::AutoLock);
    }

    #[test]
    fn topic_autolock_timeout_changed_is_autolock() {
        assert_eq!(
            Event::AutoLockTimeoutChanged { minutes: 15 }.topic(),
            EventTopic::AutoLock
        );
    }

    #[test]
    fn topic_recorder_started_is_recorder() {
        assert_eq!(
            Event::RecorderStarted {
                id: "r".into(),
                path: "/tmp/x".into()
            }
            .topic(),
            EventTopic::Recorder
        );
    }

    #[test]
    fn topic_recorder_stopped_is_recorder() {
        assert_eq!(
            Event::RecorderStopped { id: "r".into() }.topic(),
            EventTopic::Recorder
        );
    }

    #[test]
    fn topic_recorder_bytes_written_is_recorder() {
        assert_eq!(
            Event::RecorderBytesWritten {
                id: "r".into(),
                total_bytes: 1024
            }
            .topic(),
            EventTopic::Recorder
        );
    }

    #[test]
    fn topic_recorder_rotate_requested_is_recorder() {
        assert_eq!(
            Event::RecorderRotateRequested {
                id: "r".into(),
                bytes_written: 1024
            }
            .topic(),
            EventTopic::Recorder
        );
    }

    #[test]
    fn topic_recorder_write_failed_is_recorder() {
        assert_eq!(
            Event::RecorderWriteFailed {
                id: "r".into(),
                kind: "header".into(),
                detail: "x".into()
            }
            .topic(),
            EventTopic::Recorder
        );
    }

    #[test]
    fn topic_transfer_task_added_is_transfer() {
        assert_eq!(
            Event::TransferTaskAdded { id: "t".into() }.topic(),
            EventTopic::Transfer
        );
    }

    #[test]
    fn topic_transfer_task_state_is_transfer() {
        assert_eq!(
            Event::TransferTaskState {
                id: "t".into(),
                state: crate::transfer::TaskState::Queued,
            }
            .topic(),
            EventTopic::Transfer
        );
    }

    #[test]
    fn topic_transfer_task_progress_is_transfer() {
        assert_eq!(
            Event::TransferTaskProgress {
                id: "t".into(),
                bytes_done: 0,
                bytes_total: 1
            }
            .topic(),
            EventTopic::Transfer
        );
    }

    #[test]
    fn topic_transfer_task_error_is_transfer() {
        assert_eq!(
            Event::TransferTaskError {
                id: "t".into(),
                detail: "x".into()
            }
            .topic(),
            EventTopic::Transfer
        );
    }

    #[test]
    fn topic_port_forward_registered_is_port_forward() {
        assert_eq!(
            Event::PortForwardRegistered { id: "p".into() }.topic(),
            EventTopic::PortForward
        );
    }

    #[test]
    fn topic_port_forward_status_is_port_forward() {
        assert_eq!(
            Event::PortForwardStatus {
                id: "p".into(),
                status: crate::portforward::RuleStatus::Idle,
                detail: None,
            }
            .topic(),
            EventTopic::PortForward
        );
    }

    #[test]
    fn topic_port_forward_removed_is_port_forward() {
        assert_eq!(
            Event::PortForwardRemoved { id: "p".into() }.topic(),
            EventTopic::PortForward
        );
    }

    #[test]
    fn topic_update_download_progress_is_update() {
        assert_eq!(
            Event::UpdateDownloadProgress {
                url: "u".into(),
                written_bytes: 0,
                total_bytes: None
            }
            .topic(),
            EventTopic::Update
        );
    }

    #[test]
    fn topic_update_verifying_started_is_update() {
        assert_eq!(
            Event::UpdateVerifyingStarted { url: "u".into() }.topic(),
            EventTopic::Update
        );
    }

    #[test]
    fn topic_update_download_completed_is_update() {
        assert_eq!(
            Event::UpdateDownloadCompleted {
                url: "u".into(),
                path: "/tmp/x".into()
            }
            .topic(),
            EventTopic::Update
        );
    }

    #[test]
    fn topic_known_hosts_changed_is_known_hosts() {
        assert_eq!(Event::KnownHostsChanged.topic(), EventTopic::KnownHosts);
    }

    #[test]
    fn topic_sessions_changed_is_sessions() {
        assert_eq!(Event::SessionsChanged.topic(), EventTopic::Sessions);
    }

    #[test]
    fn topic_keys_changed_is_keys() {
        assert_eq!(Event::KeysChanged.topic(), EventTopic::Keys);
    }

    #[test]
    fn topic_config_changed_is_config() {
        assert_eq!(
            Event::ConfigChanged { json: "{}".into() }.topic(),
            EventTopic::Config
        );
    }

    #[test]
    fn topic_tier_state_changed_is_tier() {
        assert_eq!(
            Event::TierStateChanged {
                state_wire_name: "locked".into()
            }
            .topic(),
            EventTopic::Tier
        );
    }

    #[test]
    fn topic_unlock_cascade_ready_is_tier() {
        assert_eq!(
            Event::UnlockCascadeReady {
                tier_wire: "plaintext".into(),
                has_key: true,
            }
            .topic(),
            EventTopic::Tier
        );
    }

    #[test]
    fn topic_core_log_is_core_log() {
        assert_eq!(
            Event::CoreLog {
                level: CoreLogLevel::Info,
                name: "tag".into(),
                message: "x".into(),
            }
            .topic(),
            EventTopic::CoreLog
        );
    }

    #[test]
    fn topic_credential_prompt_request_is_security_prompt() {
        assert_eq!(
            Event::CredentialPromptRequest {
                prompt_id: "p".into(),
                session_id: "s".into(),
                kind_wire_name: "password".into(),
            }
            .topic(),
            EventTopic::SecurityPrompt
        );
    }

    #[test]
    fn topic_keychain_probe_prompt_request_is_security_prompt() {
        assert_eq!(
            Event::KeychainProbePromptRequest {
                prompt_id: "p".into()
            }
            .topic(),
            EventTopic::SecurityPrompt
        );
    }

    #[test]
    fn topic_hardware_vault_probe_prompt_request_is_security_prompt() {
        assert_eq!(
            Event::HardwareVaultProbePromptRequest {
                prompt_id: "p".into()
            }
            .topic(),
            EventTopic::SecurityPrompt
        );
    }

    #[test]
    fn topic_hardware_vault_unlock_prompt_request_is_security_prompt() {
        assert_eq!(
            Event::HardwareVaultUnlockPromptRequest {
                prompt_id: "p".into(),
                pin: None
            }
            .topic(),
            EventTopic::SecurityPrompt
        );
    }

    #[test]
    fn topic_hardware_vault_seal_prompt_request_is_security_prompt() {
        assert_eq!(
            Event::HardwareVaultSealPromptRequest {
                prompt_id: "p".into(),
                db_key_secret_id: "s".into(),
                pin_secret_id: None,
            }
            .topic(),
            EventTopic::SecurityPrompt
        );
    }

    #[test]
    fn topic_recovery_prompt_request_is_security_prompt() {
        assert_eq!(
            Event::RecoveryPromptRequest {
                prompt_id: "p".into(),
                kind: crate::security::recovery_prompt::RecoveryPromptKind::DbCorruptDetected {
                    reason: "x".into(),
                },
                choices: vec!["reset".into(), "tryOtherTier".into(), "quit".into()],
            }
            .topic(),
            EventTopic::SecurityPrompt
        );
    }

    #[test]
    fn topic_security_capabilities_changed_is_security_capabilities() {
        assert_eq!(
            Event::SecurityCapabilitiesChanged { json: "{}".into() }.topic(),
            EventTopic::SecurityCapabilities
        );
    }

    #[test]
    fn topic_known_host_prompt_request_is_known_hosts() {
        assert_eq!(
            Event::KnownHostPromptRequest {
                prompt_id: "p".into(),
                host: "h".into(),
                port: 22,
                key_type: "ssh-ed25519".into(),
                fingerprint: "fp".into(),
                kind: KnownHostPromptKind::NewHost,
            }
            .topic(),
            EventTopic::KnownHosts
        );
    }

    #[test]
    fn topic_known_host_prompt_resolved_is_known_hosts() {
        assert_eq!(
            Event::KnownHostPromptResolved {
                prompt_id: "p".into(),
                accepted: true,
            }
            .topic(),
            EventTopic::KnownHosts
        );
    }

    // ─── EventBus broker behaviour ──────────────────────────────────

    #[tokio::test]
    async fn multi_subscriber_each_receives_clone() {
        let bus = EventBus::new();
        let mut a = bus.subscribe(EventTopic::Diagnostics);
        let mut b = bus.subscribe(EventTopic::Diagnostics);
        bus.publish(Event::Echoed {
            payload: "hi".into(),
        });
        let ea = a.recv().await.expect("a");
        let eb = b.recv().await.expect("b");
        match (ea, eb) {
            (Event::Echoed { payload: pa }, Event::Echoed { payload: pb }) => {
                assert_eq!(pa, "hi");
                assert_eq!(pb, "hi");
            }
            other => panic!("unexpected events: {other:?}"),
        }
    }

    #[test]
    fn subscriber_count_reflects_live_receivers() {
        let bus = EventBus::new();
        assert_eq!(bus.subscriber_count(), 0);
        let _a = bus.subscribe(EventTopic::Diagnostics);
        assert_eq!(bus.subscriber_count(), 1);
        let b = bus.subscribe(EventTopic::Diagnostics);
        assert_eq!(bus.subscriber_count(), 2);
        drop(b);
        assert_eq!(bus.subscriber_count(), 1);
    }

    #[test]
    fn publish_returns_subscriber_count_at_send_time() {
        let bus = EventBus::new();
        let _a = bus.subscribe(EventTopic::Diagnostics);
        let _b = bus.subscribe(EventTopic::Diagnostics);
        let n = bus.publish(Event::Echoed {
            payload: "x".into(),
        });
        assert_eq!(n, 2);
    }

    #[tokio::test]
    async fn slow_subscriber_lags_without_blocking_publisher() {
        let bus = EventBus::new();
        let mut rx = bus.subscribe(EventTopic::Diagnostics);
        // Overflow the channel — broadcast::channel(EVENT_CHANNEL_CAPACITY)
        // drops the slowest receiver's oldest events. The publisher
        // never blocks; the slow receiver gets a Lagged error on the
        // next recv() call.
        for i in 0..(EVENT_CHANNEL_CAPACITY + 5) {
            bus.publish(Event::Echoed {
                payload: format!("m{i}"),
            });
        }
        let result = rx.recv().await;
        assert!(
            matches!(
                result,
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_))
            ),
            "expected Lagged, got {result:?}"
        );
    }

    #[test]
    fn default_yields_a_usable_bus() {
        let bus = EventBus::default();
        assert_eq!(bus.subscriber_count(), 0);
    }

    // ─── dispatch() command routing ─────────────────────────────────
    // Each test seeds the process-wide `app::init()` singleton (one
    // call is idempotent — subsequent calls return the same handle).
    // Tests subscribe to the global bus before dispatching so the
    // emitted event isn't lost; the subscribe happens via
    // `app::instance().bus.subscribe()` to match the production path.

    /// Serializes every test that mutates the autolock state machine.
    /// `app::init()` is a `OnceLock` singleton, so the autolock guard
    /// is shared across `#[tokio::test]` runs. Without this lock,
    /// `request_lock` / `unlock` / `on_lifecycle_change` race each
    /// other into their idempotent no-op branches and the corresponding
    /// `Event::AutoLock*` never fires for the test that is waiting on
    /// it. Acquire at the top of every autolock-touching test.
    static AUTOLOCK_TEST_LOCK: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

    /// Bounded wait so a missing-event regression fails the test fast
    /// instead of hanging the whole `cargo test` run. Two seconds is
    /// long enough for the busiest CI scheduling, short enough that a
    /// real bug surfaces immediately.
    async fn next_matching<F>(rx: &mut tokio::sync::broadcast::Receiver<Event>, pred: F) -> Event
    where
        F: Fn(&Event) -> bool,
    {
        let deadline = std::time::Duration::from_secs(2);
        tokio::time::timeout(deadline, async {
            loop {
                match rx.recv().await {
                    Ok(ev) if pred(&ev) => return ev,
                    Ok(_) => continue,
                    Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                    Err(e) => panic!("recv error: {e:?}"),
                }
            }
        })
        .await
        .expect("next_matching: timed out after 2s waiting for matching event")
    }

    #[tokio::test]
    async fn dispatch_noop_echo_publishes_echoed_event() {
        let app = crate::app::init();
        let mut rx = app.bus.subscribe(EventTopic::Diagnostics);
        dispatch(Command::NoopEcho {
            payload: "ping".into(),
        })
        .await
        .expect("dispatch");
        let ev = next_matching(
            &mut rx,
            |e| matches!(e, Event::Echoed { payload } if payload == "ping"),
        )
        .await;
        match ev {
            Event::Echoed { payload } => assert_eq!(payload, "ping"),
            _ => unreachable!(),
        }
    }

    #[tokio::test]
    async fn dispatch_autolock_set_timeout_publishes_timeout_changed() {
        let _g = AUTOLOCK_TEST_LOCK.lock().await;
        let app = crate::app::init();
        let mut rx = app.bus.subscribe(EventTopic::AutoLock);
        dispatch(Command::AutoLockSetTimeout { minutes: 7 })
            .await
            .expect("dispatch");
        let ev = next_matching(
            &mut rx,
            |e| matches!(e, Event::AutoLockTimeoutChanged { minutes } if *minutes == 7),
        )
        .await;
        assert_eq!(ev.topic(), EventTopic::AutoLock);
    }

    #[tokio::test]
    async fn dispatch_autolock_request_lock_publishes_locked() {
        let _g = AUTOLOCK_TEST_LOCK.lock().await;
        let app = crate::app::init();
        // Force the machine into Unlocked so `RequestLock` actually
        // transitions and fires `Locked` — `request_lock` is
        // idempotent and silent when already locked. Direct call
        // bypasses the bus to avoid muddling our subscription with a
        // precondition event.
        app.autolock.unlock(&app.bus);
        let mut rx = app.bus.subscribe(EventTopic::AutoLock);
        dispatch(Command::AutoLockRequestLock)
            .await
            .expect("request lock");
        let ev = next_matching(&mut rx, |e| matches!(e, Event::AutoLockLocked)).await;
        assert_eq!(ev.topic(), EventTopic::AutoLock);
    }

    #[tokio::test]
    async fn dispatch_autolock_unlock_publishes_unlocked() {
        let _g = AUTOLOCK_TEST_LOCK.lock().await;
        let app = crate::app::init();
        // Force Locked so `Unlock` actually transitions — direct
        // call bypasses the bus so the subscription below only sees
        // events from our test's dispatch.
        app.autolock.request_lock(&app.bus);
        let mut rx = app.bus.subscribe(EventTopic::AutoLock);
        dispatch(Command::AutoLockUnlock).await.expect("dispatch");
        let ev = next_matching(&mut rx, |e| matches!(e, Event::AutoLockUnlocked)).await;
        assert_eq!(ev.topic(), EventTopic::AutoLock);
    }

    #[tokio::test]
    async fn dispatch_autolock_pointer_activity_does_not_fail() {
        let _g = AUTOLOCK_TEST_LOCK.lock().await;
        let _ = crate::app::init();
        // No event published — this path just resets the idle timer.
        // Verify it returns Ok and doesn't panic.
        dispatch(Command::AutoLockOnPointerActivity)
            .await
            .expect("dispatch");
    }

    #[tokio::test]
    async fn dispatch_autolock_lifecycle_change_does_not_fail() {
        let _g = AUTOLOCK_TEST_LOCK.lock().await;
        let _ = crate::app::init();
        dispatch(Command::AutoLockOnLifecycleChange { background: true })
            .await
            .expect("background");
        dispatch(Command::AutoLockOnLifecycleChange { background: false })
            .await
            .expect("foreground");
    }

    #[tokio::test]
    async fn dispatch_known_host_prompt_response_unknown_id_is_silent() {
        let app = crate::app::init();
        // No prompt registered against this id — `resolve` returns
        // `false` and the dispatcher publishes nothing. The test
        // asserts the dispatcher does not panic and does not emit an
        // unsolicited event with this id.
        dispatch(Command::KnownHostPromptResponse {
            prompt_id: "ghost-id".into(),
            accepted: true,
        })
        .await
        .expect("dispatch");
        // Probe the bus briefly; expect no `KnownHostPromptResolved`
        // for our ghost id within a tight deadline.
        let mut rx = app.bus.subscribe(EventTopic::KnownHosts);
        let r = tokio::time::timeout(std::time::Duration::from_millis(50), async {
            loop {
                match rx.recv().await {
                    Ok(Event::KnownHostPromptResolved { prompt_id, .. })
                        if prompt_id == "ghost-id" =>
                    {
                        return true;
                    }
                    Ok(_) => continue,
                    Err(_) => return false,
                }
            }
        })
        .await;
        assert!(r.is_err(), "ghost-id should not surface");
    }

    #[tokio::test]
    async fn dispatch_connection_disconnect_missing_id_is_idempotent() {
        let _ = crate::app::init();
        dispatch(Command::ConnectionDisconnect {
            id: crate::connection::ConnId::from("does-not-exist"),
        })
        .await
        .expect("idempotent on missing id");
    }

    #[tokio::test]
    async fn dispatch_connection_disconnect_all_on_empty_registry_is_ok() {
        let _ = crate::app::init();
        dispatch(Command::ConnectionDisconnectAll)
            .await
            .expect("empty registry walk");
    }
}
