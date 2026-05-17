//! Multipart-upload orchestrator.
//!
//! Drives the AWS Initiate → UploadPart loop → Complete sequence
//! for object bodies larger than [`MULTIPART_THRESHOLD_BYTES`].
//! Smaller objects go through [`crate::s3::client::S3Client::put_object_single`]
//! — single-shot `PUT` is half the round-trips and matches the AWS
//! SDK default behaviour.
//!
//! ## Bounds
//!
//! AWS S3 enforces three numeric limits on multipart uploads:
//!
//! - Minimum part size: 5 MiB (every part except the last).
//! - Maximum part count: 10,000.
//! - Maximum object size: 5 TiB (5,000,000,000,000 bytes).
//!
//! [`PART_SIZE_BYTES`] = 8 MiB stays above the floor and lets a
//! single multipart upload cover 80 GiB before hitting the 10,000
//! part ceiling; the orchestrator surfaces a typed error
//! ([`crate::error::Error::S3`]) when the body would exceed the
//! ceiling rather than silently truncating.
//!
//! ## In-process resumability only
//!
//! The orchestrator does not persist `upload_id` / part state
//! across process restarts. A crash mid-upload leaves the staged
//! parts orphaned server-side; the next push restarts from scratch.
//! Cross-process resume is a follow-up — it needs a typed sidecar
//! file (or a DB row) and a recover-on-launch step that decides
//! whether to resume or abort, both of which lie outside the v1
//! cut.

use bytes::Bytes;
use futures_util::StreamExt;

use crate::error::Error;
use crate::s3::client::S3Client;
use crate::storage::ByteStream;

/// Above this body size the orchestrator falls back to multipart.
/// 8 MiB matches the AWS SDK default and keeps single-shot PUTs
/// inside one TCP segment burst on every reasonable link.
pub const MULTIPART_THRESHOLD_BYTES: u64 = 8 * 1024 * 1024;

/// Per-part chunk size for multipart uploads. AWS's minimum part
/// size is 5 MiB; 8 MiB sits above the floor + caps a 10,000-part
/// upload at 80 GiB before the per-call orchestrator needs a
/// rethink.
pub const PART_SIZE_BYTES: usize = 8 * 1024 * 1024;

/// AWS-enforced max part count per upload.
pub const MAX_PART_COUNT: u32 = 10_000;

/// Drive a multipart upload to completion.
///
/// Calls Initiate, walks `body` chunking into [`PART_SIZE_BYTES`]
/// blocks, uploads each part, and then Completes. Any error
/// short-circuits — the function calls Abort before returning the
/// underlying error so the staged-part state on the server is
/// released.
pub async fn upload_multipart(
    client: &S3Client,
    bucket: &str,
    key: &str,
    mut body: ByteStream,
) -> Result<(), Error> {
    let upload_id = client.create_multipart_upload(bucket, key).await?;
    let inner = async {
        let mut buf: Vec<u8> = Vec::with_capacity(PART_SIZE_BYTES);
        let mut part_number: i32 = 0;
        let mut parts: Vec<(i32, String)> = Vec::new();
        while let Some(chunk) = body.next().await {
            let chunk = chunk?;
            // Accumulate into `buf` until we have at least one
            // full part. The last partial buffer goes out below.
            buf.extend_from_slice(&chunk);
            while buf.len() >= PART_SIZE_BYTES {
                let part_bytes = buf.drain(..PART_SIZE_BYTES).collect::<Vec<u8>>();
                part_number = checked_increment(part_number)?;
                let etag = client
                    .upload_part(bucket, key, &upload_id, part_number, part_bytes)
                    .await?;
                parts.push((part_number, etag));
            }
        }
        if !buf.is_empty() {
            part_number = checked_increment(part_number)?;
            let final_part = std::mem::take(&mut buf);
            let etag = client
                .upload_part(bucket, key, &upload_id, part_number, final_part)
                .await?;
            parts.push((part_number, etag));
        }
        if parts.is_empty() {
            // Zero-byte body — multipart requires at least one
            // part. Upload an empty final part so Complete has
            // something to reference.
            part_number = checked_increment(part_number)?;
            let etag = client
                .upload_part(bucket, key, &upload_id, part_number, Vec::new())
                .await?;
            parts.push((part_number, etag));
        }
        client
            .complete_multipart_upload(bucket, key, &upload_id, &parts)
            .await
    }
    .await;
    if let Err(e) = inner {
        // Abort cleanup is best-effort — surface the original
        // error to the caller regardless of the abort outcome.
        let _ = client.abort_multipart_upload(bucket, key, &upload_id).await;
        return Err(e);
    }
    Ok(())
}

/// Pick the right upload path based on `len` hint. When `len` is
/// known and under [`MULTIPART_THRESHOLD_BYTES`] the body drains
/// into a single buffer and goes through single-shot `PUT`;
/// otherwise it streams through the multipart orchestrator.
pub async fn put_object_smart(
    client: &S3Client,
    bucket: &str,
    key: &str,
    body: ByteStream,
    len: Option<u64>,
) -> Result<(), Error> {
    match len {
        Some(n) if n < MULTIPART_THRESHOLD_BYTES => {
            // Drain into a single buffer for the single-shot PUT
            // path. Caller-supplied length doubles as a capacity
            // hint so the Vec doesn't grow geometrically.
            let mut buf = Vec::with_capacity(n as usize);
            let mut stream = body;
            while let Some(chunk) = stream.next().await {
                let bytes: Bytes = chunk?;
                buf.extend_from_slice(&bytes);
            }
            client.put_object_single(bucket, key, buf).await
        }
        _ => upload_multipart(client, bucket, key, body).await,
    }
}

fn checked_increment(part: i32) -> Result<i32, Error> {
    let next = part.saturating_add(1);
    if next > MAX_PART_COUNT as i32 {
        return Err(Error::S3(format!(
            "multipart: part count exceeds {MAX_PART_COUNT}"
        )));
    }
    Ok(next)
}

#[cfg(test)]
mod tests {
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
}
