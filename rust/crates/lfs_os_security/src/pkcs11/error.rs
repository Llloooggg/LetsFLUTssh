//! Typed PKCS#11 error envelope.
//!
//! Carves the failures Dart UI must distinguish (wrong PIN, PIN
//! locked / final-try, token absent, sign refused) into discrete
//! variants. `Display` strings carry a stable leading discriminator
//! (`wrong pin:`, `pin locked:`, `unplugged:`) so the Dart prompt
//! dialog can string-match on the prefix without re-parsing the
//! entire wire envelope. The full text after the discriminator is
//! human-readable detail for logs.

use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    /// `cryptoki::Pkcs11::new` / `initialize` returned a structural
    /// failure — module DLL not found, `C_GetFunctionList` missing,
    /// init returned anything other than `OK` or `CRYPTOKI_ALREADY_INITIALIZED`.
    /// Surfaces as `pkcs11 module did not initialise.` in the UI.
    InitFailed(String),
    /// Module loaded but no token is present in any slot the caller
    /// asked about. Surfaces as `No token present in any reader.`
    TokenAbsent,
    /// A previously-imported PKCS#11 key references a token / serial
    /// that no longer matches any present slot. Caller surfaces a
    /// "replug and retry" toast.
    TokenUnplugged(String),
    /// `C_Login` rejected the supplied PIN. Display prefix `wrong pin:`
    /// is load-bearing — the Dart UI's PIN re-prompt path string-matches
    /// against it. `remaining_tries` carries the
    /// `CKF_USER_PIN_FINAL_TRY` / `CKF_USER_PIN_COUNT_LOW` derived hint
    /// (or `None` when the token did not surface a counter).
    WrongPin { remaining_tries: Option<u32> },
    /// Token reports the user PIN as locked. Recovery requires the
    /// SO-PIN / PUK; the app does not surface a "unlock with PUK"
    /// dialog (vendor tooling owns that flow). Display prefix
    /// `pin locked:` is the Dart matcher key.
    PinLocked,
    /// The user pressed Cancel on the token's protected-authentication
    /// path (PIN-pad). Same shape as a cancelled FIDO touch.
    PinPadCancelled,
    /// `CKF_PROTECTED_AUTHENTICATION_PATH` token waited longer than
    /// the per-platform pin-pad timeout without a button press.
    Timeout,
    /// `C_Sign` refused the operation. Detail carries the underlying
    /// reason ("mechanism not allowed by policy", "key non-extractable
    /// + non-private", etc.).
    SignRefused(String),
    /// The selected object is a GOST key — PKCS#11 supports it but
    /// SSH does not. Caller renders the row disabled with the
    /// "GOST cannot be used with SSH" reason.
    UnsupportedKeyType(String),
    /// `dlopen` succeeded but `C_GetFunctionList` reports a Cryptoki
    /// version below 2.20 — the project's minimum (CKM_ECDSA + raw
    /// CKM_RSA_PKCS land in 2.20). Caller surfaces as the same kind
    /// as `InitFailed` but with a more specific log line.
    UnsupportedCryptokiVersion(String),
    /// Anything else from the underlying crate. Detail carries the
    /// `CK_RV` symbolic name or the unwrapped message.
    Other(String),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InitFailed(s) => write!(f, "init: {s}"),
            Self::TokenAbsent => f.write_str("no token present in any reader"),
            Self::TokenUnplugged(s) => write!(f, "unplugged: {s}"),
            Self::WrongPin { remaining_tries } => match remaining_tries {
                Some(n) => write!(f, "wrong pin: {n} tries remaining"),
                None => f.write_str("wrong pin: token did not report counter"),
            },
            Self::PinLocked => f.write_str("pin locked: token user PIN is locked"),
            Self::PinPadCancelled => f.write_str("cancelled: pin-pad cancel"),
            Self::Timeout => f.write_str("timeout: pin-pad / sign timeout"),
            Self::SignRefused(s) => write!(f, "sign refused: {s}"),
            Self::UnsupportedKeyType(s) => write!(f, "unsupported key type: {s}"),
            Self::UnsupportedCryptokiVersion(s) => {
                write!(f, "unsupported cryptoki version: {s}")
            }
            Self::Other(s) => write!(f, "{s}"),
        }
    }
}

impl std::error::Error for Error {}

#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
impl From<cryptoki::error::Error> for Error {
    fn from(e: cryptoki::error::Error) -> Self {
        use cryptoki::error::{Error as Ck, RvError};
        match e {
            Ck::Pkcs11(rv, _) => match rv {
                RvError::PinIncorrect => Self::WrongPin {
                    remaining_tries: None,
                },
                RvError::PinLocked => Self::PinLocked,
                RvError::FunctionCanceled => Self::PinPadCancelled,
                RvError::TokenNotPresent => Self::TokenAbsent,
                RvError::CryptokiNotInitialized => {
                    Self::InitFailed("cryptoki not initialized".into())
                }
                RvError::DeviceError | RvError::DeviceRemoved => {
                    Self::TokenUnplugged(format!("device error: {rv:?}"))
                }
                RvError::MechanismInvalid => {
                    Self::SignRefused(format!("mechanism not allowed by token: {rv:?}"))
                }
                other => Self::Other(format!("{other:?}")),
            },
            Ck::LibraryLoading(msg) => Self::InitFailed(format!("library load: {msg}")),
            other => Self::Other(format!("{other}")),
        }
    }
}
