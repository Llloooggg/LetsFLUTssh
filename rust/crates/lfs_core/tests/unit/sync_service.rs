/// Unit tests extracted from sync/service.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use crate::archive::{export_archive, ExportInput, ExportOptions};
use crate::db::{bootstrap_schema, Connection, Db};
use crate::migration::SchemaVersions;
use crate::webdav::{AuthMethod, Credentials, WebDavClient};
use wiremock::matchers::{header_exists, method as match_method, path as match_path};
use wiremock::{Mock, MockServer, Request, Respond, ResponseTemplate};

const TEST_PASSPHRASE: &str = "test-sync-passphrase";

fn fresh_db() -> Arc<Db> {
    let conn = Connection::open_in_memory().unwrap();
    conn.raw()
        .execute_batch("PRAGMA foreign_keys = ON")
        .unwrap();
    bootstrap_schema(&conn).unwrap();
    Arc::new(Db::from_raw_for_tests(conn))
}

fn build_test_client(server: &MockServer) -> WebDavClient {
    let base = format!("{}/dav/", server.uri());
    WebDavClient::new(
        &base,
        Credentials {
            method: AuthMethod::Basic,
            username: Some("alice".into()),
            password_or_token: zeroize::Zeroizing::new("p".into()),
        },
        None,
        false,
    )
    .unwrap()
}

fn base_cfg() -> SyncConfig {
    SyncConfig {
        enabled: true,
        webdav_url: "https://dav.example.com/dav/".into(),
        webdav_username: "alice".into(),
        webdav_password_ref: crate::config::SYNC_PASSWORD_SECRET_ID.into(),
        webdav_auth_method: "basic".into(),
        passphrase_ref: crate::config::SYNC_PASSPHRASE_SECRET_ID.into(),
        remote_path: "letsflutssh.lfs".into(),
        ..SyncConfig::default()
    }
}

fn build_archive_bytes(sync_origin: Option<&str>) -> Vec<u8> {
    // A separate Db so the producer-side state never contaminates
    // the consumer-side merge target.
    let conn = Connection::open_in_memory().unwrap();
    conn.raw()
        .execute_batch("PRAGMA foreign_keys = ON")
        .unwrap();
    bootstrap_schema(&conn).unwrap();
    let input = ExportInput {
        options: ExportOptions {
            include_sessions: true,
            include_known_hosts: true,
            include_config: true,
            include_tags: true,
            include_snippets: true,
            include_all_manager_keys: true,
            has_manager_keys: true,
            include_recordings: false,
        },
        selected_session_ids: Vec::new(),
        selected_empty_folders: Vec::new(),
        config_json: "{}".into(),
        schema_version: i64::from(SchemaVersions::ARCHIVE),
        app_version: Some("0.0.0-test".into()),
        master_password: Some(TEST_PASSPHRASE.into()),
        kdf_memory_kib: 8,
        kdf_iterations: 1,
        kdf_parallelism: 1,
        created_at_ms: 1_700_000_000_000,
        sync_origin: sync_origin.map(String::from),
        recordings_root: None,
        recording_db_key: None,
    };
    export_archive(&conn, &input).expect("compose archive")
}

/// Wiremock responder that captures the inbound `If-None-Match`
/// header on every request so tests can assert the exact value
/// the sync orchestrator stamped without an extra round-trip.
struct CapturingResponder {
    captured: Arc<std::sync::Mutex<Vec<Option<String>>>>,
    body: Vec<u8>,
    etag: String,
}

impl Respond for CapturingResponder {
    fn respond(&self, req: &Request) -> ResponseTemplate {
        let header_value = req
            .headers
            .get("if-none-match")
            .and_then(|v| v.to_str().ok())
            .map(String::from);
        self.captured.lock().unwrap().push(header_value);
        ResponseTemplate::new(200)
            .insert_header("ETag", self.etag.as_str())
            .set_body_bytes(self.body.clone())
    }
}

#[tokio::test]
async fn pull_304_returns_uptodate_without_persisting() {
    let server = MockServer::start().await;
    Mock::given(match_method("GET"))
        .and(match_path("/dav/letsflutssh.lfs"))
        .and(header_exists("if-none-match"))
        .respond_with(ResponseTemplate::new(304))
        .expect(1)
        .mount(&server)
        .await;
    let client = build_test_client(&server);
    let db = fresh_db();
    let cfg = SyncConfig {
        last_pushed_etag: "etag-pushed".into(),
        last_pulled_etag: "etag-pulled".into(),
        last_pulled_sha256: "deadbeef".into(),
        ..base_cfg()
    };
    let outcome = pull_with_client(&client, &cfg, TEST_PASSPHRASE, "install-x", db)
        .await
        .unwrap();
    assert!(matches!(outcome.result, SyncResult::UpToDate));
    assert!(outcome.updated_cfg.is_none());
}

#[tokio::test]
async fn pull_200_with_self_origin_returns_uptodate_and_persists_pull_etag() {
    // Server returns a body whose manifest carries the local
    // install id as origin. The echo guard must short-circuit
    // before the merge runs, but the new ETag should be stamped
    // into `last_pulled_etag` so the next pull's conditional
    // GET hits 304.
    let install_id = "self-install";
    let body = build_archive_bytes(Some(&format!("{install_id}:1700000000000")));
    let server = MockServer::start().await;
    Mock::given(match_method("GET"))
        .and(match_path("/dav/letsflutssh.lfs"))
        .respond_with(
            ResponseTemplate::new(200)
                .insert_header("ETag", "\"fresh\"")
                .set_body_bytes(body),
        )
        .expect(1)
        .mount(&server)
        .await;
    let client = build_test_client(&server);
    let db = fresh_db();
    let cfg = base_cfg();
    let outcome = pull_with_client(&client, &cfg, TEST_PASSPHRASE, install_id, db.clone())
        .await
        .unwrap();
    assert!(matches!(outcome.result, SyncResult::UpToDate));
    let updated = outcome.updated_cfg.expect("etag must be persisted");
    assert_eq!(updated.last_pulled_etag, "fresh");
    assert!(!updated.last_pulled_sha256.is_empty());
    // Sanity: no rows merged into the local DB.
    let rows = db
        .with_conn(crate::db::sessions::list_all)
        .expect("sessions list");
    assert!(rows.is_empty());
}

#[tokio::test]
async fn pull_200_with_sha256_matching_last_pulled_skips_merge() {
    // Server rotated the ETag but the body hash matches what we
    // pulled last time. The plaintext gate must short-circuit
    // the decrypt + merge and persist the new ETag so the next
    // pull short-circuits at 304.
    let install_id = "self-install";
    let body = build_archive_bytes(Some(&format!("{install_id}:1700000000000")));
    let body_sha = sha256_hex(&body);
    let server = MockServer::start().await;
    Mock::given(match_method("GET"))
        .and(match_path("/dav/letsflutssh.lfs"))
        .respond_with(
            ResponseTemplate::new(200)
                .insert_header("ETag", "\"rotated\"")
                .set_body_bytes(body),
        )
        .expect(1)
        .mount(&server)
        .await;
    let client = build_test_client(&server);
    let db = fresh_db();
    let cfg = SyncConfig {
        last_pulled_etag: "stale".into(),
        last_pulled_sha256: body_sha.clone(),
        ..base_cfg()
    };
    let outcome = pull_with_client(&client, &cfg, TEST_PASSPHRASE, install_id, db)
        .await
        .unwrap();
    assert!(matches!(outcome.result, SyncResult::UpToDate));
    let updated = outcome.updated_cfg.expect("etag rotation must persist");
    assert_eq!(updated.last_pulled_etag, "rotated");
    assert_eq!(updated.last_pulled_sha256, body_sha);
}

#[tokio::test]
async fn pull_200_with_sha256_matching_last_pushed_skips_merge() {
    // Body hash matches `last_pushed_sha256` (a peer's pull of
    // our own push echoing back without the sync_origin gate
    // catching it — the gate runs only after we observe the
    // payload differs from what we last pushed).
    let body = build_archive_bytes(Some("peer-install:1700000000000"));
    let body_sha = sha256_hex(&body);
    let server = MockServer::start().await;
    Mock::given(match_method("GET"))
        .and(match_path("/dav/letsflutssh.lfs"))
        .respond_with(
            ResponseTemplate::new(200)
                .insert_header("ETag", "\"peer-etag\"")
                .set_body_bytes(body),
        )
        .mount(&server)
        .await;
    let client = build_test_client(&server);
    let db = fresh_db();
    let cfg = SyncConfig {
        last_pushed_sha256: body_sha,
        ..base_cfg()
    };
    let outcome = pull_with_client(&client, &cfg, TEST_PASSPHRASE, "self-install", db)
        .await
        .unwrap();
    assert!(matches!(outcome.result, SyncResult::UpToDate));
    let updated = outcome.updated_cfg.expect("etag must persist");
    assert_eq!(updated.last_pulled_etag, "peer-etag");
}

#[tokio::test]
async fn pull_200_with_peer_body_runs_merge_and_persists_both_caches() {
    let body = build_archive_bytes(Some("peer-install:1700000000000"));
    let body_sha = sha256_hex(&body);
    let server = MockServer::start().await;
    Mock::given(match_method("GET"))
        .and(match_path("/dav/letsflutssh.lfs"))
        .respond_with(
            ResponseTemplate::new(200)
                .insert_header("ETag", "\"peer-etag\"")
                .set_body_bytes(body),
        )
        .expect(1)
        .mount(&server)
        .await;
    let client = build_test_client(&server);
    let db = fresh_db();
    let cfg = base_cfg();
    let outcome = pull_with_client(&client, &cfg, TEST_PASSPHRASE, "self-install", db)
        .await
        .unwrap();
    assert!(matches!(outcome.result, SyncResult::PullApplied { .. }));
    let updated = outcome.updated_cfg.expect("merge must persist");
    assert_eq!(updated.last_pulled_etag, "peer-etag");
    assert_eq!(updated.last_pulled_sha256, body_sha);
    assert!(updated.last_pulled_at_ms > 0);
}

#[tokio::test]
async fn pull_404_returns_skipped_no_remote_archive() {
    let server = MockServer::start().await;
    Mock::given(match_method("GET"))
        .and(match_path("/dav/letsflutssh.lfs"))
        .respond_with(ResponseTemplate::new(404))
        .mount(&server)
        .await;
    let client = build_test_client(&server);
    let db = fresh_db();
    let cfg = base_cfg();
    let outcome = pull_with_client(&client, &cfg, TEST_PASSPHRASE, "self-install", db)
        .await
        .unwrap();
    match outcome.result {
        SyncResult::Skipped { reason } => assert_eq!(reason, "no remote archive"),
        other => panic!("expected Skipped, got {other:?}"),
    }
    assert!(outcome.updated_cfg.is_none());
}

#[tokio::test]
async fn pull_stamps_comma_separated_if_none_match_with_both_etags() {
    let captured: Arc<std::sync::Mutex<Vec<Option<String>>>> = Arc::default();
    let server = MockServer::start().await;
    let body = build_archive_bytes(Some("peer-install:1700000000000"));
    Mock::given(match_method("GET"))
        .and(match_path("/dav/letsflutssh.lfs"))
        .respond_with(CapturingResponder {
            captured: captured.clone(),
            body: body.clone(),
            etag: "\"fresh-etag\"".into(),
        })
        .mount(&server)
        .await;
    let client = build_test_client(&server);
    let db = fresh_db();
    let cfg = SyncConfig {
        last_pushed_etag: "etag-pushed".into(),
        last_pulled_etag: "etag-pulled".into(),
        ..base_cfg()
    };
    let _ = pull_with_client(&client, &cfg, TEST_PASSPHRASE, "self-install", db)
        .await
        .unwrap();
    let captured = captured.lock().unwrap();
    assert_eq!(captured.len(), 1);
    assert_eq!(
        captured[0].as_deref(),
        Some("\"etag-pushed\", \"etag-pulled\"")
    );
}

#[test]
fn build_if_none_match_returns_none_when_both_etags_empty() {
    let cfg = base_cfg();
    assert!(build_if_none_match(&cfg).is_none());
}

#[test]
fn build_if_none_match_returns_single_quoted_etag_when_only_one_present() {
    let cfg = SyncConfig {
        last_pushed_etag: "p1".into(),
        ..base_cfg()
    };
    assert_eq!(build_if_none_match(&cfg).as_deref(), Some("\"p1\""));
}

#[test]
fn build_if_none_match_deduplicates_when_pushed_equals_pulled() {
    // After a 200-with-body pull, `last_pushed_etag` and
    // `last_pulled_etag` can end up equal (when a peer pushes
    // back exactly what we just pushed). The header value
    // collapses to a single token rather than emitting a
    // duplicate.
    let cfg = SyncConfig {
        last_pushed_etag: "shared".into(),
        last_pulled_etag: "shared".into(),
        ..base_cfg()
    };
    assert_eq!(build_if_none_match(&cfg).as_deref(), Some("\"shared\""));
}

#[test]
fn sync_error_from_webdav_etag_string_maps_to_etag_mismatch() {
    let e = Error::WebDav("put: HTTP 412: etag mismatch".into());
    match SyncError::from(e) {
        SyncError::EtagMismatch => {}
        other => panic!("expected EtagMismatch, got {other:?}"),
    }
}

#[test]
fn sync_error_from_webdav_auth_string_maps_to_unauthorized() {
    let e = Error::WebDav("put: HTTP 401: authentication failed".into());
    match SyncError::from(e) {
        SyncError::Unauthorized => {}
        other => panic!("expected Unauthorized, got {other:?}"),
    }
}

#[test]
fn sync_error_from_other_webdav_string_maps_to_network() {
    let e = Error::WebDav("put: HTTP 503: service unavailable".into());
    match SyncError::from(e) {
        SyncError::Network(_) => {}
        other => panic!("expected Network, got {other:?}"),
    }
}

#[test]
fn sync_error_from_archive_future_version_passes_through() {
    let e = Error::ArchiveFutureVersion {
        found: 99,
        supported: 2,
    };
    match SyncError::from(e) {
        SyncError::ArchiveFutureVersion { found, supported } => {
            assert_eq!(found, 99);
            assert_eq!(supported, 2);
        }
        other => panic!("expected ArchiveFutureVersion, got {other:?}"),
    }
}
