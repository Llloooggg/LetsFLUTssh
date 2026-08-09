/// Unit tests extracted from update/http.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[tokio::test]
async fn untrusted_host_rejected_for_fetch_text() {
    let err = fetch_text("https://evil.com/foo").await.unwrap_err();
    assert!(err.to_string().contains("untrusted"));
}

#[tokio::test]
async fn untrusted_host_rejected_for_download() {
    let path = std::env::temp_dir().join("lfs_update_http_test.bin");
    let err = download_to_file("https://evil.com/foo", &path, |_, _| {})
        .await
        .unwrap_err();
    assert!(err.to_string().contains("untrusted"));
    // No file created on rejection.
    assert!(!path.exists());
}

#[tokio::test]
async fn http_scheme_rejected() {
    let err = fetch_text("http://github.com/x").await.unwrap_err();
    assert!(err.to_string().contains("untrusted"));
}
