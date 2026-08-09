/// Unit tests extracted from webdav/auth.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn basic_header_matches_b64_user_colon_pass() {
    let creds = Credentials {
        method: AuthMethod::Basic,
        username: Some("Aladdin".into()),
        password_or_token: Zeroizing::new("open sesame".into()),
    };
    // RFC 7617 reference value.
    assert_eq!(
        header_value_basic_or_bearer(&creds).unwrap(),
        "Basic QWxhZGRpbjpvcGVuIHNlc2FtZQ=="
    );
}

#[test]
fn basic_header_empty_username_renders_colon_pass() {
    let creds = Credentials {
        method: AuthMethod::Basic,
        username: None,
        password_or_token: Zeroizing::new("t0p".into()),
    };
    // base64(":t0p")
    assert_eq!(
        header_value_basic_or_bearer(&creds).unwrap(),
        "Basic OnQwcA=="
    );
}

#[test]
fn bearer_header_pass_through_token() {
    let creds = Credentials {
        method: AuthMethod::Bearer,
        username: None,
        password_or_token: Zeroizing::new("opaque-token-xyz".into()),
    };
    assert_eq!(
        header_value_basic_or_bearer(&creds).unwrap(),
        "Bearer opaque-token-xyz"
    );
}

#[test]
fn digest_method_rejects_basic_helper() {
    let creds = Credentials {
        method: AuthMethod::Digest,
        username: Some("u".into()),
        password_or_token: Zeroizing::new("p".into()),
    };
    assert!(header_value_basic_or_bearer(&creds).is_err());
}

#[test]
fn parse_challenge_rejects_non_digest_scheme() {
    assert!(DigestChallenge::parse("Basic realm=\"x\"").is_none());
    assert!(DigestChallenge::parse("Bearer token=\"x\"").is_none());
}

#[test]
fn parse_challenge_extracts_quoted_and_token_fields() {
    let ch = DigestChallenge::parse(
        "Digest realm=\"testrealm@host.com\", \
         qop=\"auth,auth-int\", \
         nonce=\"dcd98b7102dd2f0e8b11d0f600bfb0c093\", \
         opaque=\"5ccc069c403ebaf9f0171e9517f40e41\", \
         algorithm=MD5, stale=false",
    )
    .unwrap();
    assert_eq!(ch.realm, "testrealm@host.com");
    assert_eq!(ch.qop.as_deref(), Some("auth,auth-int"));
    assert_eq!(ch.nonce, "dcd98b7102dd2f0e8b11d0f600bfb0c093");
    assert_eq!(
        ch.opaque.as_deref(),
        Some("5ccc069c403ebaf9f0171e9517f40e41")
    );
    assert_eq!(ch.algorithm, "MD5");
    assert!(!ch.stale);
}

#[test]
fn parse_challenge_picks_up_stale_true() {
    let ch = DigestChallenge::parse("Digest realm=\"r\", nonce=\"n\", stale=true").unwrap();
    assert!(ch.stale);
}

#[test]
fn digest_response_matches_rfc7616_known_vector() {
    // RFC 7616 §3.9.1 worked example, MD5 algorithm + qop=auth.
    // Username "Mufasa", password "Circle of Life", realm
    // "http-auth@example.org", nonce "7ypf/xlj9XXwfDPEoM4URrv/xwf...",
    // cnonce "f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ",
    // method GET, uri /dir/index.html, qop=auth, nc=00000001.
    //
    // Expected response = 8ca523f5e9506fed4657c9700eebdbec
    let state = DigestState::new();
    state.set_challenge(DigestChallenge {
        realm: "http-auth@example.org".into(),
        nonce: "7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v".into(),
        qop: Some("auth".into()),
        opaque: Some("FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS".into()),
        algorithm: "MD5".into(),
        stale: false,
    });
    let creds = Credentials {
        method: AuthMethod::Digest,
        username: Some("Mufasa".into()),
        password_or_token: Zeroizing::new("Circle of Life".into()),
    };
    let header = state
        .build_response(
            &creds,
            "GET",
            "/dir/index.html",
            "f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ",
        )
        .unwrap();
    assert!(
        header.contains("response=\"8ca523f5e9506fed4657c9700eebdbec\""),
        "header did not contain expected MD5 response: {header}"
    );
    assert!(header.contains("nc=00000001"));
}

#[test]
fn digest_response_without_qop_falls_back_to_legacy_format() {
    // RFC 2069 fall-through path — qop absent.
    let state = DigestState::new();
    state.set_challenge(DigestChallenge {
        realm: "realm".into(),
        nonce: "abc".into(),
        qop: None,
        opaque: None,
        algorithm: "MD5".into(),
        stale: false,
    });
    let creds = Credentials {
        method: AuthMethod::Digest,
        username: Some("u".into()),
        password_or_token: Zeroizing::new("p".into()),
    };
    let header = state
        .build_response(&creds, "GET", "/x", "ignored-without-qop")
        .unwrap();
    // No qop / nc / cnonce parameters when challenge omitted qop.
    assert!(!header.contains("qop="));
    assert!(!header.contains("nc="));
    assert!(header.contains("response="));
}

#[test]
fn digest_response_rejects_unsupported_algorithm() {
    let state = DigestState::new();
    state.set_challenge(DigestChallenge {
        realm: "r".into(),
        nonce: "n".into(),
        qop: None,
        opaque: None,
        algorithm: "SHA-256".into(),
        stale: false,
    });
    let creds = Credentials {
        method: AuthMethod::Digest,
        username: Some("u".into()),
        password_or_token: Zeroizing::new("p".into()),
    };
    let err = state.build_response(&creds, "GET", "/", "c").unwrap_err();
    assert!(err.to_string().contains("unsupported digest algorithm"));
}

#[test]
fn digest_response_errors_when_no_challenge_seen() {
    let state = DigestState::new();
    let creds = Credentials {
        method: AuthMethod::Digest,
        username: Some("u".into()),
        password_or_token: Zeroizing::new("p".into()),
    };
    let err = state.build_response(&creds, "GET", "/", "c").unwrap_err();
    assert!(err.to_string().contains("digest challenge"));
}
