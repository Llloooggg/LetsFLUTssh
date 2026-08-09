/// Unit tests extracted from webdav/client.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

use crate::webdav::auth::{AuthMethod, Credentials};
use wiremock::matchers::{header, method as match_method, path as match_path};
use wiremock::{Mock, MockServer, ResponseTemplate};
use zeroize::Zeroizing;

fn basic_creds(user: &str, pass: &str) -> Credentials {
    Credentials {
        method: AuthMethod::Basic,
        username: Some(user.into()),
        password_or_token: Zeroizing::new(pass.into()),
    }
}

fn make_client(base: &str) -> WebDavClient {
    WebDavClient::new(base, basic_creds("alice", "p"), None, false).unwrap()
}

/// Sample self-signed certificate — generated once for the test
/// suite via `openssl req -x509 -newkey rsa:2048 -nodes -days 1
/// -subj /CN=test.local`. The actual subject / validity does
/// not matter for the parser test; only the PEM shape matters.
const SELF_SIGNED_PEM: &str = "-----BEGIN CERTIFICATE-----\nMIIDazCCAlOgAwIBAgIUFNJyP1HJ9HShdsZRfO4Pg6XnUmwwDQYJKoZIhvcNAQEL\nBQAwRTELMAkGA1UEBhMCVUExDjAMBgNVBAgMBVRlc3RTMQ4wDAYDVQQHDAVUZXN0\nQzEWMBQGA1UEAwwNbG9jYWxob3N0LXRlc3QwHhcNMjUwMTAxMDAwMDAwWhcNMjYw\nMTAxMDAwMDAwWjBFMQswCQYDVQQGEwJVQTEOMAwGA1UECAwFVGVzdFMxDjAMBgNV\nBAcMBVRlc3RDMRYwFAYDVQQDDA1sb2NhbGhvc3QtdGVzdDCCASIwDQYJKoZIhvcN\nAQEBBQADggEPADCCAQoCggEBAMK4tD9PdOmYnVqGRGiyMUuTfbHQpvVNeUkKXY8x\nF8gqK1ZQbS5OZ19o/SH4OQfTRkSqGZ+wMPRdEFm5OETIz1xPgxTbJyfDH8AdvjGM\nxZ6+8ngS+y6m+5+r9rg2nC4q3SNZw4cWQk0Eo2k1NWB+iqsKEXBSeqcuq8/N5UVS\nLpFFszLPB+xa7Ahw4OhQa+H8d0jWpQiAJl7ks7e2OqLAcyHkkpY9XxqA5OFOq5oT\nMfPmYO8xDywPwT5oOZBgyB69+W8Z5kIKxiB7e6/qY/4xBMVAOWMjmnUL76YYg1lh\nL7iSEnq8N9aLb1aMS3KuM4OG+IBhVCC8tRZWvHK0gPvT60UCAwEAAaNTMFEwHQYD\nVR0OBBYEFCKchpljkbAdNJW39CKPjqlf2wmYMB8GA1UdIwQYMBaAFCKchpljkbAd\nNJW39CKPjqlf2wmYMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEB\nADV3VlqLZmqHpoBohOY6BdUVnPK7Q4QwI4OQM0pHy5LRdHqIaR0xRY+M3HQRkWcz\nVCw+aMP0zpEIJl9eq2KbjxhJgWxHwlSEPxLE7zX8m1xLM4Tk+1qSc+H6f4WiTwT/\n6w0wTPmTBYsdjF5sZ6vSXP9NxC1pNYykqHo3qq84MlS5KIaa4ZxIVqj/UWB8tnRA\n4iEW8sHbeUXjVprlrG/+/aMM6q9bbDfHmRVl+IpAi1ku3xkXrLb6/EOIUtxc9QmI\n3p8jW9oA4n82BlSdQH8oS6OnRJ81Mg2QmTpC5gLxr8aHEZ2K9D6XHQfdYySFvuRr\nWXFcUUSGOEhcg2Tf2EOAt7s=\n-----END CERTIFICATE-----\n";

#[test]
fn join_resolves_same_origin_paths() {
    let client = make_client("https://dav.example.com/dav/");
    // Relative + server-absolute + same-origin-absolute all resolve.
    assert_eq!(
        client.join("file.txt").unwrap().as_str(),
        "https://dav.example.com/dav/file.txt"
    );
    assert_eq!(
        client.join("/dav/other.txt").unwrap().as_str(),
        "https://dav.example.com/dav/other.txt"
    );
    assert_eq!(
        client
            .join("https://dav.example.com/dav/abs.txt")
            .unwrap()
            .as_str(),
        "https://dav.example.com/dav/abs.txt"
    );
}

#[test]
fn join_rejects_cross_origin_href() {
    // A hostile PROPFIND href pointing at another host/scheme/port
    // must be refused so `apply_auth` never stamps the user's
    // credential onto an attacker-controlled origin.
    let client = make_client("https://dav.example.com/dav/");
    for hostile in [
        "http://attacker.example/x",
        "https://attacker.example/x",
        "https://dav.example.com:8443/x", // different port
        "http://dav.example.com/x",       // different scheme
    ] {
        let err = client.join(hostile).unwrap_err();
        assert!(
            err.to_string().contains("cross-origin"),
            "expected cross-origin refusal for {hostile}, got {err}"
        );
    }
}

#[test]
fn parse_pem_certs_handles_empty_blob() {
    assert_eq!(parse_pem_certs("").unwrap().len(), 0);
    assert_eq!(parse_pem_certs("   \n\t  ").unwrap().len(), 0);
}

#[test]
fn parse_pem_certs_returns_one_cert_for_single_block() {
    let parsed = parse_pem_certs(SELF_SIGNED_PEM).unwrap();
    assert_eq!(parsed.len(), 1);
}

#[test]
fn parse_pem_certs_returns_multiple_certs_for_chain_blob() {
    let doubled = format!("{SELF_SIGNED_PEM}{SELF_SIGNED_PEM}");
    let parsed = parse_pem_certs(&doubled).unwrap();
    assert_eq!(parsed.len(), 2);
}

#[test]
fn parse_pem_certs_rejects_unterminated_block() {
    let truncated = "-----BEGIN CERTIFICATE-----\nMIIB...";
    let err = parse_pem_certs(truncated).unwrap_err();
    assert!(format!("{err}").contains("unterminated"));
}

#[test]
fn webdav_client_insecure_skip_verify_builds() {
    let client = WebDavClient::new(
        "https://example.invalid/dav/",
        basic_creds("u", "p"),
        None,
        true,
    );
    assert!(client.is_ok());
}

#[tokio::test]
async fn propfind_depth1_happy_path_parses_entries() {
    let server = MockServer::start().await;
    let body = include_str!("../fixtures/webdav/nextcloud_depth1.xml");
    Mock::given(match_method("PROPFIND"))
        .and(match_path("/dav/files/alice/"))
        .and(header("depth", "1"))
        .respond_with(
            ResponseTemplate::new(207)
                .insert_header("Content-Type", "application/xml")
                .set_body_string(body),
        )
        .expect(1)
        .mount(&server)
        .await;
    let base = format!("{}/dav/files/alice/", server.uri());
    let client = make_client(&base);
    let entries = client.propfind("", 1).await.unwrap();
    assert!(!entries.is_empty());
}

#[tokio::test]
async fn propfind_depth_infinity_rejected_without_network() {
    let client = make_client("https://example.invalid/dav/");
    let err = client.propfind("foo", 2).await.unwrap_err();
    assert!(err.to_string().contains("depth"));
}

#[tokio::test]
async fn propfind_with_per_resource_404_returns_only_2xx_entries() {
    let server = MockServer::start().await;
    let body = include_str!("../fixtures/webdav/partial_404.xml");
    Mock::given(match_method("PROPFIND"))
        .respond_with(ResponseTemplate::new(207).set_body_string(body))
        .mount(&server)
        .await;
    let base = format!("{}/dav/", server.uri());
    let client = make_client(&base);
    let entries = client.propfind("", 1).await.unwrap();
    assert_eq!(entries.len(), 1);
}

#[tokio::test]
async fn put_with_if_match_412_maps_to_etag_mismatch() {
    let server = MockServer::start().await;
    Mock::given(match_method("PUT"))
        .and(match_path("/dav/notes.txt"))
        .and(header("if-match", "\"stale\""))
        .respond_with(ResponseTemplate::new(412))
        .mount(&server)
        .await;
    let base = format!("{}/dav/", server.uri());
    let client = make_client(&base);
    let err = client
        .put("notes.txt", Bytes::from_static(b"hello"), Some("stale"))
        .await
        .unwrap_err();
    assert!(err.to_string().contains("etag mismatch"));
}

#[tokio::test]
async fn put_plain_201_returns_server_etag() {
    let server = MockServer::start().await;
    Mock::given(match_method("PUT"))
        .and(match_path("/dav/notes.txt"))
        .respond_with(ResponseTemplate::new(201).insert_header("ETag", "\"new-tag\""))
        .mount(&server)
        .await;
    let base = format!("{}/dav/", server.uri());
    let client = make_client(&base);
    let outcome = client
        .put("notes.txt", Bytes::from_static(b"hello"), None)
        .await
        .unwrap();
    assert_eq!(outcome.etag.as_deref(), Some("new-tag"));
}

#[tokio::test]
async fn get_range_206_returns_partial_body() {
    let server = MockServer::start().await;
    Mock::given(match_method("GET"))
        .and(match_path("/dav/data.bin"))
        .and(header("range", "bytes=10-19"))
        .respond_with(ResponseTemplate::new(206).set_body_bytes(b"0123456789".to_vec()))
        .mount(&server)
        .await;
    let base = format!("{}/dav/", server.uri());
    let client = make_client(&base);
    let response = client.get("data.bin", Some((10, 19)), None).await.unwrap();
    let bytes = response.bytes().await.unwrap();
    assert_eq!(&bytes[..], b"0123456789");
}

#[tokio::test]
async fn get_with_if_none_match_304_returns_response_without_error() {
    let server = MockServer::start().await;
    Mock::given(match_method("GET"))
        .and(match_path("/dav/file.lfs"))
        .and(wiremock::matchers::header_exists("if-none-match"))
        .respond_with(ResponseTemplate::new(304))
        .mount(&server)
        .await;
    let base = format!("{}/dav/", server.uri());
    let client = make_client(&base);
    let response = client
        .get("file.lfs", None, Some("\"e1\", \"e2\""))
        .await
        .expect("304 is not an error");
    assert_eq!(response.status().as_u16(), 304);
}

#[tokio::test]
async fn get_without_if_none_match_omits_the_header() {
    let server = MockServer::start().await;
    Mock::given(match_method("GET"))
        .and(match_path("/dav/file"))
        .and(wiremock::matchers::header_exists("authorization"))
        .respond_with(ResponseTemplate::new(200).set_body_bytes(b"ok".to_vec()))
        .mount(&server)
        .await;
    let base = format!("{}/dav/", server.uri());
    let client = make_client(&base);
    let response = client.get("file", None, None).await.unwrap();
    assert!(response.headers().get("if-none-match").is_none());
    let body = response.bytes().await.unwrap();
    assert_eq!(&body[..], b"ok");
}

#[tokio::test]
async fn unauthenticated_digest_path_retries_after_401_challenge() {
    let server = MockServer::start().await;
    // First call: no `Authorization` header → 401 with challenge.
    Mock::given(match_method("GET"))
        .and(match_path("/dav/file"))
        .respond_with(ResponseTemplate::new(401).insert_header(
            "WWW-Authenticate",
            "Digest realm=\"r\", nonce=\"n1\", qop=\"auth\", algorithm=MD5",
        ))
        .up_to_n_times(1)
        .mount(&server)
        .await;
    // Second call: any `Authorization` starting with `Digest` → 200.
    Mock::given(match_method("GET"))
        .and(match_path("/dav/file"))
        .respond_with(ResponseTemplate::new(200).set_body_bytes(b"ok".to_vec()))
        .mount(&server)
        .await;
    let creds = Credentials {
        method: AuthMethod::Digest,
        username: Some("u".into()),
        password_or_token: Zeroizing::new("p".into()),
    };
    let base = format!("{}/dav/", server.uri());
    let client = WebDavClient::new(&base, creds, None, false).unwrap();
    let response = client.get("file", None, None).await.unwrap();
    let body = response.bytes().await.unwrap();
    assert_eq!(&body[..], b"ok");
}

#[tokio::test]
async fn mkcol_on_existing_collection_maps_to_method_not_allowed() {
    let server = MockServer::start().await;
    Mock::given(match_method("MKCOL"))
        .respond_with(ResponseTemplate::new(405))
        .mount(&server)
        .await;
    let base = format!("{}/dav/", server.uri());
    let client = make_client(&base);
    let err = client.mkcol("existing/").await.unwrap_err();
    assert!(err.to_string().contains("method not allowed"));
}

#[tokio::test]
async fn delete_204_returns_ok() {
    let server = MockServer::start().await;
    Mock::given(match_method("DELETE"))
        .and(match_path("/dav/gone.txt"))
        .respond_with(ResponseTemplate::new(204))
        .mount(&server)
        .await;
    let base = format!("{}/dav/", server.uri());
    let client = make_client(&base);
    client.delete("gone.txt").await.unwrap();
}

#[tokio::test]
async fn move_resource_stamps_destination_header() {
    let server = MockServer::start().await;
    let dest_match = format!("{}/dav/to.txt", server.uri());
    Mock::given(match_method("MOVE"))
        .and(match_path("/dav/from.txt"))
        .and(header("destination", dest_match.as_str()))
        .and(header("overwrite", "T"))
        .respond_with(ResponseTemplate::new(201))
        .mount(&server)
        .await;
    let base = format!("{}/dav/", server.uri());
    let client = make_client(&base);
    client
        .move_resource("from.txt", "to.txt", true)
        .await
        .unwrap();
}

#[tokio::test]
async fn base_url_without_trailing_slash_is_normalised() {
    let server = MockServer::start().await;
    Mock::given(match_method("DELETE"))
        .and(match_path("/dav/a.txt"))
        .respond_with(ResponseTemplate::new(204))
        .mount(&server)
        .await;
    // Constructor must add the trailing slash so `join("a.txt")`
    // resolves to `/dav/a.txt` instead of `/a.txt`.
    let base = format!("{}/dav", server.uri());
    let client = make_client(&base);
    client.delete("a.txt").await.unwrap();
}

/// Regression: every Dart caller (file pane navigation, the
/// drag-drop `enqueueUpload` path, the right-click delete) hands
/// `WebDavClient` a **server-absolute** path (`/dav/probe.txt`)
/// because that's the shape PROPFIND returns in `href` fields
/// and the shape `WebDavFileSystem.initialDir()` now emits. The
/// earlier `trim_start_matches('/')` in `join` collapsed the
/// absolute reference to relative, doubling the base path
/// component (`http://h/dav/dav/probe.txt`) and 404-ing every
/// write verb — surfaced as the user-reported "delete failed:
/// HTTP 404: not found" and silent drag-drop landing.
#[tokio::test]
async fn delete_with_server_absolute_path_hits_base_relative_target() {
    let server = MockServer::start().await;
    Mock::given(match_method("DELETE"))
        .and(match_path("/dav/probe.txt"))
        .respond_with(ResponseTemplate::new(204))
        .mount(&server)
        .await;
    let base = format!("{}/dav/", server.uri());
    let client = make_client(&base);
    client.delete("/dav/probe.txt").await.unwrap();
}

#[tokio::test]
async fn put_with_server_absolute_path_lands_under_base_path() {
    // Same regression class on the write side — `put` must
    // also reach `/dav/<key>`, not `/dav/dav/<key>`.
    let server = MockServer::start().await;
    Mock::given(match_method("PUT"))
        .and(match_path("/dav/uploaded.bin"))
        .respond_with(ResponseTemplate::new(201))
        .mount(&server)
        .await;
    let base = format!("{}/dav/", server.uri());
    let client = make_client(&base);
    client
        .put("/dav/uploaded.bin", bytes::Bytes::from_static(b"x"), None)
        .await
        .unwrap();
}

#[tokio::test]
async fn propfind_with_relative_path_still_works_for_legacy_callers() {
    // Defensive: a caller that still passes a relative path
    // (`""`, `"sub/"`) must keep resolving against the base.
    // The fix dropped the leading-slash trim but kept relative
    // resolution unchanged — `Url::join` handles both shapes.
    let server = MockServer::start().await;
    Mock::given(match_method("PROPFIND"))
        .and(match_path("/dav/sub/"))
        .respond_with(ResponseTemplate::new(207).set_body_string(
            "<?xml version=\"1.0\"?><D:multistatus xmlns:D=\"DAV:\">\
                   <D:response><D:href>/dav/sub/</D:href></D:response>\
                 </D:multistatus>",
        ))
        .mount(&server)
        .await;
    let base = format!("{}/dav/", server.uri());
    let client = make_client(&base);
    client.propfind("sub/", 1).await.unwrap();
}
