/// Unit tests extracted from storage/s3.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn parse_path_accepts_explicit_s3_uri() {
    let (bucket, key) = parse_path("s3://my-bucket/logs/app.log", "", "").unwrap();
    assert_eq!(bucket, "my-bucket");
    assert_eq!(key, "logs/app.log");
}

#[test]
fn parse_path_rejects_s3_uri_without_bucket() {
    // `s3:///key` is invalid — bucket name is required for
    // wire correctness.
    assert!(parse_path("s3:///key", "", "").is_err());
}

#[test]
fn parse_path_uses_default_bucket_when_no_scheme() {
    let (bucket, key) = parse_path("a.txt", "default", "").unwrap();
    assert_eq!(bucket, "default");
    assert_eq!(key, "a.txt");
}

#[test]
fn parse_path_prepends_default_prefix_with_separator() {
    let (bucket, key) = parse_path("file.bin", "b", "logs/").unwrap();
    assert_eq!(bucket, "b");
    assert_eq!(key, "logs/file.bin");
}

#[test]
fn parse_path_prepends_default_prefix_inserts_separator_when_missing() {
    // Prefix without trailing slash + relative path without
    // leading slash should still produce `prefix/path`.
    let (_, key) = parse_path("file.bin", "b", "logs").unwrap();
    assert_eq!(key, "logs/file.bin");
}

#[test]
fn parse_path_errors_when_no_bucket_default_and_no_scheme() {
    assert!(parse_path("a.txt", "", "").is_err());
}

#[test]
fn display_name_strips_parent_prefix() {
    assert_eq!(display_name("logs/2024/", "logs/"), "2024");
    assert_eq!(display_name("logs/app.log", "logs/"), "app.log");
}

#[test]
fn display_name_falls_back_to_key_when_strip_empties_it() {
    // The listed prefix itself echoes back with key == prefix;
    // stripping leaves an empty string which would render as a
    // blank row. Fall back to the raw key for that case.
    assert_eq!(display_name("logs/", "logs/"), "logs/");
}
