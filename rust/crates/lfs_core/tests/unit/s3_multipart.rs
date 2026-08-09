/// Unit tests extracted from s3/multipart.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn multipart_threshold_matches_part_size() {
    // The single-shot threshold and the per-part size both
    // settle on 8 MiB so a body just above the threshold splits
    // into exactly two parts (the full first part + a small
    // trailer). Drift in either constant flips that invariant.
    assert_eq!(MULTIPART_THRESHOLD_BYTES, PART_SIZE_BYTES as u64);
}

#[test]
fn checked_increment_rejects_over_aws_ceiling() {
    // Walks the part counter up to 10,000 cleanly, errors on
    // the 10,001-th increment.
    let mut part = 0;
    for _ in 0..MAX_PART_COUNT {
        part = checked_increment(part).unwrap();
    }
    assert_eq!(part, MAX_PART_COUNT as i32);
    let err = checked_increment(part).unwrap_err();
    assert!(matches!(err, Error::S3(_)));
}
