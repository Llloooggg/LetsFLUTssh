/// Unit tests extracted from db/known_hosts.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use crate::db::{bootstrap_schema, Connection};

fn fresh_conn() -> Connection {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    bootstrap_schema(&conn).expect("bootstrap schema");
    conn
}

#[test]
fn upsert_returns_stable_id_on_insert_and_update() {
    // First call inserts; second call hits the ON CONFLICT
    // arm and must return the same `id` so SFTP key-pin retries
    // converge on a single row.
    let conn = fresh_conn();
    let id_insert =
        upsert_by_host_port(&conn, "host.example", 22, "ssh-ed25519", "AAAA", 100).unwrap();
    let id_update =
        upsert_by_host_port(&conn, "host.example", 22, "ssh-ed25519", "BBBB", 200).unwrap();
    assert_eq!(
        id_insert, id_update,
        "RETURNING id must be stable across upsert"
    );

    let row = get_by_host_port(&conn, "host.example", 22)
        .unwrap()
        .unwrap();
    assert_eq!(row.id, id_insert);
    assert_eq!(
        row.key_base64, "BBBB",
        "second upsert overwrites key material"
    );
    assert_eq!(row.added_at_ms, 200, "second upsert overwrites timestamp");
}

#[test]
fn upsert_distinct_host_port_pairs_get_distinct_ids() {
    let conn = fresh_conn();
    let id_a = upsert_by_host_port(&conn, "host.example", 22, "ssh-ed25519", "A", 0).unwrap();
    let id_b = upsert_by_host_port(&conn, "other.example", 22, "ssh-ed25519", "B", 0).unwrap();
    let id_c = upsert_by_host_port(&conn, "host.example", 2222, "ssh-rsa", "C", 0).unwrap();
    assert_ne!(id_a, id_b);
    assert_ne!(id_a, id_c);
    assert_ne!(id_b, id_c);
}
