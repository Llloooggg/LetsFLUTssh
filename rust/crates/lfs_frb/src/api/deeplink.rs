//! FRB adapter for `lfs_core::deeplink`.
//!
//! - [`parse_connect_uri`] is a stateless parser exposed for the
//!   Dart-side `DeepLinkHandler.parseConnectUri` static helper
//!   (used by the deeplink fuzz suite, which needs a no-state
//!   entry point so a fuzzer can drive parse-only inputs without
//!   warming up the dispatcher's dedup window).
//! - [`deeplink_dispatch`] is the dispatcher entry point: the Dart
//!   `app_links` listener pumps every URI through this call and
//!   switches on the typed [`DbDeeplinkOutcome`] to route to the right
//!   UI action. Dedup, scheme routing, file-extension routing, and
//!   QR-payload staging live in `lfs_core::deeplink::DeeplinkDispatcher`.

/// FRB mirror of `lfs_core::deeplink::ConnectLink`. Same shape.
#[derive(Debug, Clone)]
pub struct DbConnectLink {
    pub host: String,
    pub port: u16,
    pub user: String,
}

impl From<lfs_core::deeplink::ConnectLink> for DbConnectLink {
    fn from(c: lfs_core::deeplink::ConnectLink) -> Self {
        Self {
            host: c.host,
            port: c.port,
            user: c.user,
        }
    }
}

/// Parse `uri` as a `letsflutssh://connect?host=…&user=…&port=…`
/// link. Returns `None` for any malformed / non-connect URI.
#[flutter_rust_bridge::frb(sync)]
pub fn parse_connect_uri(uri: String) -> Option<DbConnectLink> {
    lfs_core::deeplink::parse_connect_uri(&uri).map(DbConnectLink::from)
}

/// FRB mirror of `lfs_core::deeplink::DeeplinkOutcome`. Tagged enum
/// because FRB cleanly maps a Rust enum-with-data to a Dart freezed
/// sealed class — Dart consumers pattern-match per branch.
///
/// Note: the QR-import variant carries a hydrated [`DbImportPreview`]
/// (looked up from `AppState::imports` right after staging) so the
/// Dart side does not have to round-trip back to fetch counts before
/// rendering the import-preview dialog.
#[derive(Debug, Clone)]
pub enum DbDeeplinkOutcome {
    /// `letsflutssh://connect?host=…&user=…[&port=…]`.
    Connect {
        host: String,
        port: u16,
        user: String,
    },
    /// `letsflutssh://import?d=…` decoded successfully. The
    /// pending payload is staged in `AppState::imports` under
    /// `handle_id`; `preview` carries the sanitised counts +
    /// session labels for the dialog (no plaintext entries).
    QrImport {
        handle_id: String,
        preview: super::archive::DbImportPreview,
    },
    /// QR payload carries a wire version newer than this build
    /// understands.
    QrImportRejected { found: i64, supported: i64 },
    /// `file://…/*.lfs` or `content://…/*.lfs`.
    OpenLfs { path: String },
    /// `file://…/*.{pem,key,pub}` or `content://…/*.{pem,key,pub}`.
    OpenKeyFile { path: String },
    /// Recognised URI but no actionable mapping (unknown action,
    /// unsupported extension, unknown scheme).
    Unknown,
    /// URI matched the dispatcher's last-seen entry inside the
    /// dedup window — Dart UI does nothing.
    Duplicate,
}

fn hydrate_preview(handle_id: &str, schema_version: i64) -> super::archive::DbImportPreview {
    let app = lfs_core::app::instance();
    if let Some(pending) = app.imports.get_clone(handle_id) {
        pending.preview(schema_version).into()
    } else {
        // Defensive: registry was wiped between stage + lookup. Fall
        // back to a zero preview so the Dart side still sees a usable
        // shape (the apply call will then surface the missing handle).
        super::archive::DbImportPreview {
            schema_version,
            session_count: 0,
            session_labels: Vec::new(),
            manager_key_count: 0,
            tag_count: 0,
            snippet_count: 0,
            empty_folder_count: 0,
            has_config: false,
            has_known_hosts: false,
            recording_count: 0,
        }
    }
}

fn from_core(o: lfs_core::deeplink::DeeplinkOutcome) -> DbDeeplinkOutcome {
    use lfs_core::deeplink::DeeplinkOutcome as Core;
    match o {
        Core::Connect { host, port, user } => DbDeeplinkOutcome::Connect { host, port, user },
        Core::QrImport {
            handle_id,
            schema_version,
        } => {
            let preview = hydrate_preview(&handle_id, schema_version);
            DbDeeplinkOutcome::QrImport { handle_id, preview }
        }
        Core::QrImportRejected { found, supported } => {
            DbDeeplinkOutcome::QrImportRejected { found, supported }
        }
        Core::OpenLfs { path } => DbDeeplinkOutcome::OpenLfs { path },
        Core::OpenKeyFile { path } => DbDeeplinkOutcome::OpenKeyFile { path },
        Core::Unknown => DbDeeplinkOutcome::Unknown,
        Core::Duplicate => DbDeeplinkOutcome::Duplicate,
    }
}

/// Dispatch a URI through `lfs_core::deeplink::DeeplinkDispatcher`.
/// Routes to the matching [`DbDeeplinkOutcome`] variant; the Dart
/// caller switches on the variant to drive the right UI action
/// (open terminal, show import dialog, …). Dedup happens inside the
/// singleton dispatcher so cold-start `getInitialLink` +
/// `uriLinkStream` do not double-fire the same payload.
///
/// `async` because future bus-event hooks may push side effects;
/// the inner work today is sync but the FRB shape stays stable.
pub async fn deeplink_dispatch(uri: String) -> DbDeeplinkOutcome {
    let app = lfs_core::app::instance();
    from_core(app.deeplinks.dispatch(&uri))
}

#[cfg(test)]
mod tests {
    use super::*;

    // `deeplink_dispatch` and `hydrate_preview` route through
    // `lfs_core::app::instance()` and need the FRB worker bootstrap;
    // covered by the Dart `deeplink_handler_test.dart` integration
    // suite. The standalone tests below pin the stateless
    // `parse_connect_uri` helper that the Dart fuzz suite reads off
    // directly.

    #[test]
    fn parse_connect_uri_returns_some_for_valid_link() {
        let parsed =
            parse_connect_uri("letsflutssh://connect?host=example.org&user=alice&port=2222".into())
                .expect("valid connect URI");
        assert_eq!(parsed.host, "example.org");
        assert_eq!(parsed.user, "alice");
        assert_eq!(parsed.port, 2222);
    }

    #[test]
    fn parse_connect_uri_returns_none_for_unrelated_scheme() {
        assert!(parse_connect_uri("https://example.org/".into()).is_none());
    }

    #[test]
    fn parse_connect_uri_returns_none_for_garbage_input() {
        assert!(parse_connect_uri("not a uri at all".into()).is_none());
    }
}
