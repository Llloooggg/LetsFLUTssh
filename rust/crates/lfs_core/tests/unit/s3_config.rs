/// Unit tests extracted from s3/config.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

fn cfg(region: &str, endpoint: &str, path_style: bool) -> S3Config {
    S3Config {
        access_key_id: "AKID".into(),
        secret_access_key: Zeroizing::new("SK".into()),
        region: region.into(),
        endpoint: endpoint.into(),
        path_style,
        default_bucket: "".into(),
        default_prefix: "".into(),
        trusted_cert_pem: None,
        insecure_skip_verify: false,
    }
}

#[test]
fn resolve_endpoint_aws_default_uses_regional_shape() {
    let c = cfg("eu-west-2", "", false);
    assert_eq!(c.resolve_endpoint(), "https://s3.eu-west-2.amazonaws.com");
}

#[test]
fn resolve_endpoint_aws_default_us_east_1_when_region_empty() {
    // Empty region falls back to us-east-1, matching modern
    // AWS SDK default behaviour.
    let c = cfg("", "", false);
    assert_eq!(c.resolve_endpoint(), "https://s3.us-east-1.amazonaws.com");
}

#[test]
fn resolve_endpoint_uses_explicit_endpoint_when_set() {
    let c = cfg("auto", "https://minio.local:9000", true);
    assert_eq!(c.resolve_endpoint(), "https://minio.local:9000");
}

#[test]
fn resolve_bucket_base_path_style_appends_bucket_to_endpoint() {
    let c = cfg("auto", "https://minio.local:9000", true);
    assert_eq!(
        c.resolve_bucket_base("my-bucket").unwrap(),
        "https://minio.local:9000/my-bucket"
    );
}

#[test]
fn resolve_bucket_base_virtual_host_prepends_bucket_to_host() {
    let c = cfg("us-east-1", "", false);
    assert_eq!(
        c.resolve_bucket_base("logs").unwrap(),
        "https://logs.s3.us-east-1.amazonaws.com"
    );
}

#[test]
fn resolve_host_header_path_style_drops_bucket() {
    let c = cfg("auto", "https://minio.local:9000", true);
    assert_eq!(c.resolve_host_header("buc").unwrap(), "minio.local:9000");
}

#[test]
fn resolve_host_header_virtual_host_prepends_bucket() {
    let c = cfg("us-east-1", "", false);
    assert_eq!(
        c.resolve_host_header("buc").unwrap(),
        "buc.s3.us-east-1.amazonaws.com"
    );
}

#[test]
fn validate_bucket_name_accepts_aws_canonical_shapes() {
    assert!(validate_bucket_name("logs").is_ok());
    assert!(validate_bucket_name("my-bucket").is_ok());
    assert!(validate_bucket_name("123abc").is_ok());
    assert!(validate_bucket_name("a-b.c-d").is_ok());
    assert!(validate_bucket_name(&"a".repeat(63)).is_ok());
}

#[test]
fn validate_bucket_name_rejects_length_violations() {
    assert!(validate_bucket_name("").is_err());
    assert!(validate_bucket_name("ab").is_err());
    assert!(validate_bucket_name(&"a".repeat(64)).is_err());
}

#[test]
fn validate_bucket_name_rejects_invalid_characters() {
    assert!(validate_bucket_name("My-Bucket").is_err()); // uppercase
    assert!(validate_bucket_name("my_bucket").is_err()); // underscore
    assert!(validate_bucket_name("-bucket").is_err()); // leading hyphen
    assert!(validate_bucket_name("bucket-").is_err()); // trailing hyphen
    assert!(validate_bucket_name(".bucket").is_err()); // leading dot
    assert!(validate_bucket_name("bucket.").is_err()); // trailing dot
    assert!(validate_bucket_name("my..bucket").is_err()); // consecutive dots
    assert!(validate_bucket_name("my bucket").is_err()); // space
}

#[test]
fn validate_bucket_name_rejects_ipv4_format() {
    assert!(validate_bucket_name("192.168.1.1").is_err());
}

#[test]
fn resolve_bucket_base_rejects_invalid_bucket() {
    let c = cfg("us-east-1", "", false);
    assert!(c.resolve_bucket_base("My-Bucket").is_err());
    assert!(c.resolve_bucket_base("").is_err());
}
