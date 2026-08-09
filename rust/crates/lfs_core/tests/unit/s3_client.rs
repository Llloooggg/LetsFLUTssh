/// Unit tests extracted from s3/client.rs
/// Declared via `#[path] mod tests;` in the source file.
use super::*;

#[test]
fn unix_to_components_round_trips_known_epoch() {
    // 2024-01-02T03:04:05Z — pinned by Linux `date -u
    // --date=@1704164645`.
    assert_eq!(unix_to_components(1_704_164_645), (2024, 1, 2, 3, 4, 5));
}

#[test]
fn format_amz_timestamp_uses_compact_iso_shape() {
    // SigV4 mandates `YYYYMMDDTHHMMSSZ` — no dashes, no colons.
    assert_eq!(format_amz_timestamp(1_704_067_200), "20240101T000000Z");
}

#[test]
fn parse_iso8601_ms_round_trips_with_milliseconds() {
    assert_eq!(
        parse_iso8601_ms("2024-01-01T00:00:00.000Z"),
        Some(1_704_067_200_000)
    );
}

#[test]
fn parse_iso8601_ms_handles_no_fractional_seconds() {
    // Some S3 vendors omit the `.fff` portion entirely; the
    // parser must still produce a valid timestamp.
    assert_eq!(
        parse_iso8601_ms("2024-01-01T00:00:00Z"),
        Some(1_704_067_200_000)
    );
}

#[test]
fn parse_iso8601_ms_returns_none_on_malformed() {
    // Reject inputs missing the `Z` suffix — different tz
    // offsets are not what S3 emits.
    assert_eq!(parse_iso8601_ms("2024-01-01T00:00:00+02:00"), None);
    assert_eq!(parse_iso8601_ms(""), None);
}

#[test]
fn extract_tag_returns_inner_text() {
    assert_eq!(
        extract_tag("<a><Code>NoSuchBucket</Code></a>", "Code"),
        Some("NoSuchBucket".into())
    );
}

#[test]
fn extract_tag_returns_none_when_missing() {
    assert_eq!(extract_tag("<a/>", "Code"), None);
}

#[test]
fn extract_tag_decodes_xml_entities() {
    assert_eq!(
        extract_tag(
            "<Error><Message>Bucket &quot;x&quot; not found</Message></Error>",
            "Message"
        ),
        Some("Bucket \"x\" not found".into())
    );
}

#[test]
fn extract_tag_handles_cdata() {
    assert_eq!(
        extract_tag("<Error><Code><![CDATA[NoSuchKey]]></Code></Error>", "Code"),
        Some("NoSuchKey".into())
    );
}

#[test]
fn extract_tag_ignores_namespace_prefix() {
    assert_eq!(
        extract_tag(
            "<aws:Error xmlns:aws=\"x\"><aws:Code>SignatureDoesNotMatch</aws:Code></aws:Error>",
            "Code"
        ),
        Some("SignatureDoesNotMatch".into())
    );
}

#[test]
fn extract_tag_returns_none_on_unparseable_body() {
    assert_eq!(extract_tag("<<<not xml", "Code"), None);
}

#[test]
fn parse_initiate_multipart_upload_id_extracts_value() {
    let xml = r#"<?xml version="1.0"?>
        <InitiateMultipartUploadResult>
          <Bucket>b</Bucket>
          <Key>k</Key>
          <UploadId>VXBsb2FkSWQ=</UploadId>
        </InitiateMultipartUploadResult>"#;
    assert_eq!(
        parse_initiate_multipart_upload_id(xml).unwrap(),
        "VXBsb2FkSWQ="
    );
}

#[test]
fn parse_initiate_multipart_upload_id_errors_on_missing_id() {
    let xml = "<InitiateMultipartUploadResult/>";
    assert!(parse_initiate_multipart_upload_id(xml).is_err());
}

#[test]
fn build_complete_multipart_body_sorts_and_emits_quoted_etag() {
    // Parts come in out-of-order to verify the defensive resort.
    let parts = vec![
        (2, "etag2".to_string()),
        (1, "etag1".to_string()),
        (3, "\"etag3\"".to_string()),
    ];
    let body = build_complete_multipart_body(&parts);
    // Part 1 comes first, part 3 last; etag is quoted exactly
    // once (already-quoted input is normalised).
    let p1 = body.find("<PartNumber>1</PartNumber>").unwrap();
    let p2 = body.find("<PartNumber>2</PartNumber>").unwrap();
    let p3 = body.find("<PartNumber>3</PartNumber>").unwrap();
    assert!(p1 < p2 && p2 < p3);
    assert!(body.contains(r#"<ETag>"etag1"</ETag>"#));
    assert!(body.contains(r#"<ETag>"etag3"</ETag>"#));
}

#[test]
fn parse_list_objects_v2_resolves_entities_in_key() {
    // quick-xml splits entity references out of the text run, so a key
    // with `&` and surrounding spaces must reassemble exactly — no
    // dropped spaces, no truncation at the entity.
    let xml = r#"<?xml version="1.0"?>
        <ListBucketResult>
          <Contents>
            <Key>My &amp; Files/q &#38; a.txt</Key>
            <Size>7</Size>
          </Contents>
        </ListBucketResult>"#;
    let page = parse_list_objects_v2(xml).unwrap();
    assert_eq!(page.objects.len(), 1);
    assert_eq!(page.objects[0].key, "My & Files/q & a.txt");
    assert_eq!(page.objects[0].size, 7);
}

#[test]
fn parse_list_objects_v2_extracts_objects_and_common_prefixes() {
    let xml = r#"<?xml version="1.0"?>
        <ListBucketResult>
          <Name>b</Name>
          <Contents>
            <Key>a.txt</Key>
            <LastModified>2024-01-01T00:00:00.000Z</LastModified>
            <ETag>"abc"</ETag>
            <Size>42</Size>
          </Contents>
          <CommonPrefixes>
            <Prefix>logs/</Prefix>
          </CommonPrefixes>
          <NextContinuationToken>NEXT</NextContinuationToken>
        </ListBucketResult>"#;
    let page = parse_list_objects_v2(xml).unwrap();
    assert_eq!(page.objects.len(), 2);
    let file = &page.objects[0];
    assert_eq!(file.key, "a.txt");
    assert_eq!(file.size, 42);
    assert_eq!(file.etag, "abc");
    assert!(!file.is_dir);
    let dir = &page.objects[1];
    assert_eq!(dir.key, "logs/");
    assert!(dir.is_dir);
    assert_eq!(page.next_continuation_token.as_deref(), Some("NEXT"));
}

#[test]
fn map_xml_error_categorises_auth_404_5xx() {
    let err = map_xml_error(
        StatusCode::FORBIDDEN,
        "<Error><Code>AccessDenied</Code></Error>",
    );
    assert!(matches!(err, Error::S3(ref s) if s.contains("auth")));
    let err = map_xml_error(
        StatusCode::NOT_FOUND,
        "<Error><Code>NoSuchKey</Code></Error>",
    );
    assert!(matches!(err, Error::S3(ref s) if s.contains("not found")));
    let err = map_xml_error(
        StatusCode::INTERNAL_SERVER_ERROR,
        "<Error><Code>InternalError</Code></Error>",
    );
    assert!(matches!(err, Error::S3(ref s) if s.contains("server error")));
}

#[test]
fn parse_iso8601_ms_round_trips_unix_to_components() {
    // The two helpers form a round-trip pair via the shared
    // civil-from-days helper; a regression in either surfaces.
    let unix_ms = 1_704_164_645_000_i64;
    let parsed = parse_iso8601_ms("2024-01-02T03:04:05.000Z").expect("valid iso8601");
    assert_eq!(parsed, unix_ms);
    let (y, m, d, h, mi, s) = unix_to_components(1_704_164_645);
    assert_eq!((y, m, d, h, mi, s), (2024, 1, 2, 3, 4, 5));
}
