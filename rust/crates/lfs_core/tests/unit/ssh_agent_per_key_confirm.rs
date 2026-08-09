/// Unit tests extracted from ssh_agent/per_key_confirm.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[tokio::test]
async fn enqueue_then_respond_resolves_receiver() {
    let (prompt, rx) = enqueue_with_receiver("k1", "Lab key", Some("git".into()));
    assert_eq!(prompt.key_id, "k1");
    respond_to_request(&prompt.request_id, Decision::AuthorizeOnce).unwrap();
    let decision = rx.await.unwrap();
    assert_eq!(decision, Decision::AuthorizeOnce);
}

#[tokio::test]
async fn cancel_drops_pending_entry() {
    let prompt = enqueue("k2", "Lab key", None);
    assert!(pending_count() >= 1);
    cancel_request(&prompt.request_id);
    // Re-responding now fails — entry is gone.
    let res = respond_to_request(&prompt.request_id, Decision::AuthorizeOnce);
    assert!(res.is_err());
}

#[tokio::test]
async fn dropping_receiver_makes_respond_fail() {
    let (prompt, rx) = enqueue_with_receiver("k3", "Lab key", None);
    drop(rx);
    let res = respond_to_request(&prompt.request_id, Decision::AuthorizeOnce);
    assert!(res.is_err());
}

#[test]
fn respond_unknown_id_fails() {
    let res = respond_to_request("not-a-real-uuid", Decision::Deny);
    assert!(res.is_err());
}
