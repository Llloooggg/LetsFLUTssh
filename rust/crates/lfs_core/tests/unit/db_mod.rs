/// Unit tests extracted from db/mod.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

/// In-memory database doesn't need a key; verifies the open
/// path + smoke probe with a no-encryption shortcut.
#[test]
fn open_in_memory_with_no_key() {
    let conn = Connection::open_in_memory().unwrap();
    conn.inner()
        .execute_batch("CREATE TABLE t (x INT)")
        .unwrap();
    let db = Db {
        conn: Mutex::new(conn),
        path: std::path::PathBuf::new(),
    };
    let n = db.schema_object_count().unwrap();
    assert!(n >= 1, "schema_object_count was {n}");
}

/// `Db::open` against a freshly-created empty file with a
/// SQLCipher key must succeed — that's the path
/// `ensureRustDbOpen` hits on first launch (Dart pre-creates a
/// 0-byte file via `File.create()` before handing the path to
/// the FRB call). Without this test the schema-probe vs
/// bootstrap ordering is silently regression-prone: a probe
/// that runs before the first DDL trips on the empty file
/// because SQLCipher has no encrypted header to verify yet.
#[test]
fn open_creates_fresh_encrypted_db_when_file_is_empty() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("fresh.db");
    // Mirror Dart's `File(path).create()` — empty file on disk.
    std::fs::File::create(&path).unwrap();
    let key = [0x42u8; 32];
    let db = Db::open(&path, &key).expect("open empty file with key must succeed");
    let count = db
        .schema_object_count()
        .expect("schema count after fresh open");
    assert!(count > 0, "bootstrap_schema should have created tables");
}

/// `Db::export_plaintext_copy` writes a brand-new plaintext
/// sqlite file that mirrors every table + row of the running
/// encrypted DB. Drives the T1 → T0 downgrade path: the
/// caller renames the export over the encrypted source +
/// re-opens unkeyed.
#[test]
fn export_plaintext_copy_round_trips_under_no_key() {
    let dir = tempfile::tempdir().unwrap();
    let src = dir.path().join("src.db");
    let dst = dir.path().join("plain.db");
    let key = [0x42u8; 32];
    let db = Db::open(&src, &key).expect("open encrypted source");
    // Drop a row through a user-defined table so the export
    // carries schema + data, not just empty bootstrap output.
    db.with_conn(|c| {
        c.inner()
            .execute_batch(
                "CREATE TABLE migration_probe (id TEXT PRIMARY KEY, payload TEXT);
                 INSERT INTO migration_probe (id, payload) VALUES ('p1', 'hello');",
            )
            .map_err(|e| Error::Db(format!("probe seed: {e}")))
    })
    .unwrap();

    db.export_plaintext_copy(&dst)
        .expect("export plaintext copy");
    assert!(dst.exists(), "exported plaintext file must exist");
    assert_eq!(db.path(), src.as_path(), "source path tracked");

    // Open the export directly through rusqlite — no PRAGMA
    // key, no PRAGMA cipher_compatibility — and read the row
    // back. This is the same shape `db_init(&dst, &[])` will
    // exercise post-rename.
    let plain = rusqlite::Connection::open(&dst).unwrap();
    let payload: String = plain
        .query_row(
            "SELECT payload FROM migration_probe WHERE id = 'p1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(
        payload, "hello",
        "plaintext export must carry the row written under the encrypted source",
    );
    // Probing the source with no key now fails — confirms the
    // source DB is still encrypted (the export did not touch
    // the original file).
    let unkeyed = rusqlite::Connection::open(&src).unwrap();
    let probe = unkeyed.query_row("SELECT count(*) FROM sqlite_master", [], |r| {
        r.get::<_, i64>(0)
    });
    assert!(
        probe.is_err(),
        "encrypted source must reject a no-key open after export",
    );
}

/// Bootstrap stamps `user_version = SCHEMA_VERSION` on a fresh
/// DB and is idempotent on re-bootstrap.
#[test]
fn bootstrap_stamps_user_version() {
    let conn = Connection::open_in_memory().unwrap();
    assert_eq!(
        read_schema_version(&conn).unwrap(),
        0,
        "fresh DB starts at user_version 0",
    );
    bootstrap_schema(&conn).unwrap();
    assert_eq!(read_schema_version(&conn).unwrap(), SCHEMA_VERSION);
    // Re-running bootstrap leaves the stamp at the same value.
    bootstrap_schema(&conn).unwrap();
    assert_eq!(read_schema_version(&conn).unwrap(), SCHEMA_VERSION);
}
/// Bootstrap schema + ssh_keys round-trip on an in-memory DB.
/// Confirms the SQL strings parse and the column shapes match.
#[test]
fn ssh_keys_round_trip_in_memory() {
    let conn = Connection::open_in_memory().unwrap();
    conn.inner()
        .execute_batch("PRAGMA foreign_keys = ON")
        .unwrap();
    bootstrap_schema(&conn).unwrap();
    let row = ssh_keys::SshKeyRow {
        id: "k1".into(),
        label: "lap".into(),
        private_key: "PRIVATE".into(),
        public_key: "ssh-ed25519 AAAA".into(),
        key_type: "ssh-ed25519".into(),
        is_generated: true,
        created_at_ms: 1700000000000,
        credential_id: None,
        application_string: None,
        has_user_verification: false,
        agent_policy: ssh_keys::AgentPolicy::Ask,
        backend: ssh_keys::KeyBackend::Software,
        pkcs11_uri: None,
        pkcs11_module_path: None,
        pkcs11_token_serial: None,
        pkcs11_object_id: None,
        pkcs11_object_label: None,
        enclave_tag: None,
        hello_credential_name: None,
        tpm_blob: None,
        tpm_handle: None,
        tpm_provider: None,
        tpm_pin_required: false,
        cng_key_name: None,
        keystore_alias: None,
        keystore_strongbox: false,
        keystore_user_auth_required: false,
        keystore_platform: None,
        imported_as_stub: false,
    };
    ssh_keys::upsert(&conn, &row).unwrap();
    let got = ssh_keys::get(&conn, "k1").unwrap().unwrap();
    assert_eq!(got.label, "lap");
    assert!(got.is_generated);
    let all = ssh_keys::list_all(&conn).unwrap();
    assert_eq!(all.len(), 1);
    let n = ssh_keys::delete(&conn, "k1").unwrap();
    assert_eq!(n, 1);
    assert!(ssh_keys::get(&conn, "k1").unwrap().is_none());
}

/// Sessions ↔ folders FK behaves: deleting a folder NULLs the
/// folder_id on referencing sessions (ON DELETE SET NULL).
#[test]
fn sessions_folder_fk_set_null_on_delete() {
    let conn = Connection::open_in_memory().unwrap();
    conn.inner()
        .execute_batch("PRAGMA foreign_keys = ON")
        .unwrap();
    bootstrap_schema(&conn).unwrap();
    folders::upsert(
        &conn,
        &folders::FolderRow {
            id: "f1".into(),
            name: "Production".into(),
            parent_id: None,
            sort_order: 0,
            collapsed: false,
            created_at_ms: 1700000000000,
        },
    )
    .unwrap();
    sessions::upsert(
        &conn,
        &sessions::SessionRow {
            id: "s1".into(),
            label: "edge".into(),
            folder_id: Some("f1".into()),
            kind: sessions::SESSION_KIND_SSH.into(),
            host: "edge.example".into(),
            port: 22,
            user: "deploy".into(),
            auth_type: "password".into(),
            password: "".into(),
            key_path: "".into(),
            key_data: "".into(),
            key_id: None,
            passphrase: "".into(),
            sort_order: 0,
            notes: "".into(),
            last_connected_at_ms: None,
            extras: "{}".into(),
            via_session_id: None,
            via_host: None,
            via_port: None,
            via_user: None,
            created_at_ms: 1700000000000,
            updated_at_ms: 1700000000000,
        },
    )
    .unwrap();
    folders::delete(&conn, "f1").unwrap();
    let s = sessions::get(&conn, "s1").unwrap().unwrap();
    assert_eq!(s.folder_id, None);
}

// ── Tier transition tests ──────────────────────────────────────
// Each tier is represented by a fixed 32-byte key. The DB doesn't
// know about tiers — it only knows the key. Tier semantics are
// enforced outside this module (keychain, hardware, argon2id).

/// T1 key (keychain)
const KEY_T1: [u8; 32] = [0x11; 32];
/// T2 key (hardware)
const KEY_T2: [u8; 32] = [0x22; 32];
/// Paranoid key (argon2id)
const KEY_P: [u8; 32] = [0x33; 32];

/// Helper: seed a DB with a probe table and a known row.
fn seed_probe(db: &Db) {
    db.with_conn(|c| {
        c.inner()
            .execute_batch(
                "CREATE TABLE probe (id TEXT PRIMARY KEY, val TEXT);
                 INSERT INTO probe VALUES ('x', 'survived');",
            )
            .map_err(|e| Error::Db(format!("seed: {e}")))
    })
    .unwrap();
}

/// Helper: verify a row survives in a re-opened DB.
fn verify_data(path: &std::path::Path, key: &[u8], expected: &str) {
    let db = Db::open(path, key).expect("open rekeyed db");
    let val: String = db
        .with_conn(|c| {
            c.inner()
                .query_row("SELECT val FROM probe WHERE id = 'x'", [], |r| {
                    r.get::<_, String>(0)
                })
                .map_err(|e| Error::Db(format!("query: {e}")))
        })
        .unwrap();
    assert_eq!(val, expected);
}

/// Verify wrong key is rejected.
fn assert_wrong_key(path: &std::path::Path, wrong: &[u8]) {
    let bad = Db::open(path, wrong);
    assert!(
        bad.is_err(),
        "wrong key {:?} should be rejected",
        &wrong[..4]
    );
}

// ── T0 → T1 (plaintext → encrypted): ATTACH/export ────────────
#[test]
fn rekey_t0_to_t1() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("t0.db");
    let db = Db::open(&path, &[]).expect("open plaintext");
    seed_probe(&db);
    db.rekey(&KEY_T1).expect("rekey T0→T1");
    verify_data(&path, &KEY_T1, "survived");
    assert_wrong_key(&path, &[]);
}

#[test]
fn rekey_t0_to_t2() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("t0.db");
    let db = Db::open(&path, &[]).expect("open plaintext");
    seed_probe(&db);
    db.rekey(&KEY_T2).expect("rekey T0→T2");
    verify_data(&path, &KEY_T2, "survived");
    assert_wrong_key(&path, &[]);
}

#[test]
fn rekey_t0_to_paranoid() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("t0.db");
    let db = Db::open(&path, &[]).expect("open plaintext");
    seed_probe(&db);
    db.rekey(&KEY_P).expect("rekey T0→Paranoid");
    verify_data(&path, &KEY_P, "survived");
    assert_wrong_key(&path, &[]);
}

// ── T1 → T0 (encrypted → plaintext): export_plaintext_copy ────
#[test]
fn export_plaintext_t1_to_t0() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("t1.db");
    let plain = dir.path().join("t0.db");
    let db = Db::open(&path, &KEY_T1).expect("open T1");
    seed_probe(&db);
    db.export_plaintext_copy(&plain).expect("export plaintext");
    verify_data(&plain, &[], "survived");
}

#[test]
fn export_plaintext_t2_to_t0() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("t2.db");
    let plain = dir.path().join("t0.db");
    let db = Db::open(&path, &KEY_T2).expect("open T2");
    seed_probe(&db);
    db.export_plaintext_copy(&plain).expect("export plaintext");
    verify_data(&plain, &[], "survived");
}

#[test]
fn export_plaintext_paranoid_to_t0() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("p.db");
    let plain = dir.path().join("t0.db");
    let db = Db::open(&path, &KEY_P).expect("open paranoid");
    seed_probe(&db);
    db.export_plaintext_copy(&plain).expect("export plaintext");
    verify_data(&plain, &[], "survived");
}

// ── T1 → T2 (encrypted → encrypted): PRAGMA rekey ─────────────
#[test]
fn rekey_t1_to_t2() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("t1.db");
    let db = Db::open(&path, &KEY_T1).expect("open T1");
    seed_probe(&db);
    db.rekey(&KEY_T2).expect("rekey T1→T2");
    verify_data(&path, &KEY_T2, "survived");
    assert_wrong_key(&path, &KEY_T1);
}

// ── T1 → Paranoid ─────────────────────────────────────────────
#[test]
fn rekey_t1_to_paranoid() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("t1.db");
    let db = Db::open(&path, &KEY_T1).expect("open T1");
    seed_probe(&db);
    db.rekey(&KEY_P).expect("rekey T1→Paranoid");
    verify_data(&path, &KEY_P, "survived");
    assert_wrong_key(&path, &KEY_T1);
}

// ── T2 → T1 ───────────────────────────────────────────────────
#[test]
fn rekey_t2_to_t1() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("t2.db");
    let db = Db::open(&path, &KEY_T2).expect("open T2");
    seed_probe(&db);
    db.rekey(&KEY_T1).expect("rekey T2→T1");
    verify_data(&path, &KEY_T1, "survived");
    assert_wrong_key(&path, &KEY_T2);
}

// ── T2 → Paranoid ─────────────────────────────────────────────
#[test]
fn rekey_t2_to_paranoid() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("t2.db");
    let db = Db::open(&path, &KEY_T2).expect("open T2");
    seed_probe(&db);
    db.rekey(&KEY_P).expect("rekey T2→Paranoid");
    verify_data(&path, &KEY_P, "survived");
    assert_wrong_key(&path, &KEY_T2);
}

// ── Paranoid → T0 ─────────────────────────────────────────────
#[test]
fn export_plaintext_paranoid_to_t0_after_rekey() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("p.db");
    let plain = dir.path().join("t0.db");
    // Start as T1, rekey to Paranoid, then export plaintext.
    let db = Db::open(&path, &KEY_T1).expect("open T1");
    seed_probe(&db);
    db.rekey(&KEY_P).expect("rekey T1→Paranoid");
    db.export_plaintext_copy(&plain).expect("export plaintext");
    verify_data(&plain, &[], "survived");
}

// ── Paranoid → T1 ─────────────────────────────────────────────
#[test]
fn rekey_paranoid_to_t1() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("p.db");
    let db = Db::open(&path, &KEY_P).expect("open paranoid");
    seed_probe(&db);
    db.rekey(&KEY_T1).expect("rekey Paranoid→T1");
    verify_data(&path, &KEY_T1, "survived");
    assert_wrong_key(&path, &KEY_P);
}

// ── Paranoid → T2 ─────────────────────────────────────────────
#[test]
fn rekey_paranoid_to_t2() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("p.db");
    let db = Db::open(&path, &KEY_P).expect("open paranoid");
    seed_probe(&db);
    db.rekey(&KEY_T2).expect("rekey Paranoid→T2");
    verify_data(&path, &KEY_T2, "survived");
    assert_wrong_key(&path, &KEY_P);
}

// ── T2 → T0 via rekey + export ────────────────────────────────
#[test]
fn rekey_t2_to_t0_flow() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("t2.db");
    let plain = dir.path().join("t0.db");
    let db = Db::open(&path, &KEY_T2).expect("open T2");
    seed_probe(&db);
    db.export_plaintext_copy(&plain).expect("export plaintext");
    verify_data(&plain, &[], "survived");
}

// ── Full chain: T0→T1→T2→P→T1→T0 (multi-step regression) ─────
#[test]
fn full_tier_chain_preserves_data() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("chain.db");
    let plain = dir.path().join("plain.db");

    // T0: open plaintext, seed data
    let db = Db::open(&path, &[]).expect("T0 open");
    seed_probe(&db);

    // T0 → T1
    db.rekey(&KEY_T1).expect("T0→T1");
    verify_data(&path, &KEY_T1, "survived");

    // T1 → T2
    db.rekey(&KEY_T2).expect("T1→T2");
    verify_data(&path, &KEY_T2, "survived");

    // T2 → Paranoid
    db.rekey(&KEY_P).expect("T2→Paranoid");
    verify_data(&path, &KEY_P, "survived");

    // Paranoid → T1
    db.rekey(&KEY_T1).expect("Paranoid→T1");
    verify_data(&path, &KEY_T1, "survived");

    // T1 → T0 (export plaintext, swap file)
    db.export_plaintext_copy(&plain).expect("T1→T0 export");
    verify_data(&plain, &[], "survived");
    // Swap: move plain over original
    let _ = std::fs::remove_file(&path);
    std::fs::rename(&plain, &path).unwrap();

    // T0 again — data should still be there
    let db = Db::open(&path, &[]).expect("final T0 open");
    let val: String = db
        .with_conn(|c| {
            c.inner()
                .query_row("SELECT val FROM probe WHERE id = 'x'", [], |r| r.get(0))
                .map_err(|e| Error::Db(format!("query: {e}")))
        })
        .unwrap();
    assert_eq!(val, "survived");
}
