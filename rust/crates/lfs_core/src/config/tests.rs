use super::*;

#[test]
fn terminal_validate_accepts_defaults() {
    assert!(TerminalConfig::default().validate().is_none());
}

#[test]
fn terminal_validate_rejects_oversize_font() {
    let t = TerminalConfig {
        font_size: 200.0,
        ..TerminalConfig::default()
    };
    assert!(t.validate().is_some());
}

#[test]
fn ssh_validate_rejects_zero_port() {
    let s = SshDefaults {
        default_port: 0,
        ..SshDefaults::default()
    };
    assert!(s.validate().is_some());
}

#[test]
fn ui_validate_rejects_extreme_scale() {
    let u = UiConfig {
        ui_scale: 10.0,
        ..UiConfig::default()
    };
    assert!(u.validate().is_some());
}

#[test]
fn app_config_validate_walks_sub_structs() {
    // Bad font size in TerminalConfig surfaces as the first
    // error from the AppConfig walk.
    let cfg = AppConfig {
        terminal: TerminalConfig {
            font_size: 1.0,
            ..TerminalConfig::default()
        },
        ..AppConfig::default()
    };
    let err = cfg.validate().unwrap();
    assert!(err.contains("Font size"));
}

#[test]
fn app_config_validate_catches_negative_max_history() {
    let cfg = AppConfig {
        max_history: -1,
        ..AppConfig::default()
    };
    let err = cfg.validate().unwrap();
    assert!(err.contains("Max history"));
}

#[test]
fn terminal_defaults_match_dart() {
    let d = TerminalConfig::default();
    assert_eq!(d.font_size, 14.0);
    assert_eq!(d.theme, "system");
    assert_eq!(d.scrollback, 5000);
}

#[test]
fn terminal_sanitized_clamps_font_size() {
    let t = TerminalConfig {
        font_size: 1000.0,
        theme: "system".into(),
        scrollback: 5000,
    }
    .sanitized();
    assert_eq!(t.font_size, 72.0);
}

#[test]
fn terminal_sanitized_replaces_unknown_theme() {
    let t = TerminalConfig {
        font_size: 14.0,
        theme: "neon".into(),
        scrollback: 5000,
    }
    .sanitized();
    assert_eq!(t.theme, "system");
}

#[test]
fn terminal_round_trip_preserves_fields() {
    let t = TerminalConfig {
        font_size: 16.0,
        theme: "dark".into(),
        scrollback: 10_000,
    };
    let json = t.to_json_object();
    let parsed = TerminalConfig::from_json_object(&json);
    assert_eq!(parsed, t);
}

#[test]
fn ssh_defaults_clamp_invalid_port() {
    let s = SshDefaults {
        keepalive_sec: 30,
        default_port: 999_999,
        ssh_timeout_sec: 10,
    }
    .sanitized();
    assert_eq!(s.default_port, 22);
}

#[test]
fn ui_clamps_window_size() {
    let u = UiConfig {
        toast_duration_ms: 4000,
        window_width: 100.0,
        window_height: 100.0,
        ui_scale: 1.0,
        show_folder_sizes: false,
    }
    .sanitized();
    assert_eq!(u.window_width, 1100.0);
    assert_eq!(u.window_height, 650.0);
}

#[test]
fn ui_clamps_ui_scale_outside_range() {
    let u = UiConfig {
        toast_duration_ms: 4000,
        window_width: 1100.0,
        window_height: 650.0,
        ui_scale: 5.0,
        show_folder_sizes: false,
    }
    .sanitized();
    assert_eq!(u.ui_scale, 2.0);
}

#[test]
fn behavior_log_level_omitted_when_none() {
    let b = BehaviorConfig::default();
    let json = b.to_json_object();
    assert!(!json.contains_key("log_level"));
}

#[test]
fn behavior_log_level_round_trips() {
    for level in [LogLevel::Info, LogLevel::Warn, LogLevel::Error] {
        let b = BehaviorConfig {
            log_level: Some(level),
            check_updates_on_start: true,
            skipped_version: None,
            fido2_prefer_direct_hid: false,
        };
        let json = b.to_json_object();
        let parsed = BehaviorConfig::from_json_object(&json);
        assert_eq!(parsed.log_level, Some(level));
    }
}

#[test]
fn behavior_fido2_prefer_direct_hid_round_trips() {
    let b = BehaviorConfig {
        log_level: None,
        check_updates_on_start: true,
        skipped_version: None,
        fido2_prefer_direct_hid: true,
    };
    let json = b.to_json_object();
    assert_eq!(
        json.get("fido2_prefer_direct_hid")
            .and_then(|v| v.as_bool()),
        Some(true),
    );
    let parsed = BehaviorConfig::from_json_object(&json);
    assert!(parsed.fido2_prefer_direct_hid);
}

#[test]
fn behavior_fido2_prefer_direct_hid_defaults_off_when_missing() {
    let json = serde_json::Map::new();
    let parsed = BehaviorConfig::from_json_object(&json);
    assert!(!parsed.fido2_prefer_direct_hid);
}

#[test]
fn app_config_default_round_trip() {
    let cfg = AppConfig::default();
    let json = cfg.to_json_value();
    let parsed = AppConfig::from_json_value(&json);
    assert_eq!(parsed, cfg);
}

#[test]
fn app_config_emits_flat_top_level_keys() {
    let cfg = AppConfig::default();
    let v = cfg.to_json_value();
    let obj = v.as_object().unwrap();
    // Sub-struct fields land at the top level — mirrors Dart
    // `AppConfig.toJson` which spreads `...subStruct.toJson()`.
    assert!(obj.contains_key("font_size"));
    assert!(obj.contains_key("default_port"));
    assert!(obj.contains_key("toast_duration_ms"));
    assert!(obj.contains_key("check_updates_on_start"));
}

#[test]
fn app_config_security_omitted_until_wizard_runs() {
    let cfg = AppConfig::default();
    let v = cfg.to_json_value();
    let obj = v.as_object().unwrap();
    assert!(!obj.contains_key("security_tier"));
    assert!(!obj.contains_key("security_modifiers"));
}

#[test]
fn to_json_value_stamps_config_schema_version() {
    let v = AppConfig::default().to_json_value();
    let stamped = v
        .as_object()
        .and_then(|o| o.get("config_schema_version"))
        .and_then(|n| n.as_i64());
    assert_eq!(
        stamped,
        Some(crate::migration::SchemaVersions::CONFIG as i64),
    );
}

#[test]
fn from_json_then_to_json_preserves_current_schema_version_even_if_input_was_stale() {
    // Simulates a `Store::set_json` round-trip: caller hands JSON
    // produced by an older build that wrote an outdated version;
    // the canonicaliser must re-stamp the current `SchemaVersions::CONFIG`
    // on the way out so the on-disk file always reflects the live
    // build's target version.
    let stale = json!({"font_size": 14.0, "config_schema_version": 0});
    let cfg = AppConfig::from_json_value(&stale);
    let out = cfg.to_json_value();
    assert_eq!(
        out.as_object()
            .and_then(|o| o.get("config_schema_version"))
            .and_then(|n| n.as_i64()),
        Some(crate::migration::SchemaVersions::CONFIG as i64),
    );
}

#[test]
fn app_config_security_round_trips_when_set() {
    let cfg = AppConfig {
        security: Some(SecurityConfig {
            tier: SecurityTier::Hardware,
            modifiers: crate::security::SecurityTierModifiers::default(),
        }),
        ..AppConfig::default()
    };
    let v = cfg.to_json_value();
    let obj = v.as_object().unwrap();
    assert_eq!(
        obj.get("security_tier").and_then(|v| v.as_str()),
        Some("hardware"),
    );
    let parsed = AppConfig::from_json_value(&v);
    assert_eq!(parsed.security.unwrap().tier, SecurityTier::Hardware);
}

#[test]
fn app_config_unknown_tier_string_collapses_to_none() {
    let v = json!({"security_tier": "L99"});
    let parsed = AppConfig::from_json_value(&v);
    assert!(parsed.security.is_none());
}

#[test]
fn app_config_locale_unknown_falls_through() {
    let v = json!({"locale": "klingon"});
    let parsed = AppConfig::from_json_value(&v);
    assert!(parsed.locale.is_none());
}

#[test]
fn app_config_locale_known_round_trips() {
    let v = json!({"locale": "ru"});
    let parsed = AppConfig::from_json_value(&v);
    assert_eq!(parsed.locale.as_deref(), Some("ru"));
}

#[test]
fn strip_for_export_removes_per_host_fields() {
    let cfg = AppConfig {
        security: Some(SecurityConfig {
            tier: SecurityTier::Hardware,
            modifiers: crate::security::SecurityTierModifiers::default(),
        }),
        ..AppConfig::default()
    };
    let mut v = cfg.to_json_value();
    // `to_json_value` always stamps `config_schema_version`;
    // `strip_for_export` is responsible for removing it before
    // the blob lands inside an `.lfs` archive.
    assert_eq!(
        v.as_object()
            .and_then(|o| o.get("config_schema_version"))
            .and_then(|n| n.as_i64()),
        Some(crate::migration::SchemaVersions::CONFIG as i64),
    );
    strip_for_export(&mut v);
    let obj = v.as_object().unwrap();
    assert!(!obj.contains_key("security_tier"));
    assert!(!obj.contains_key("security_modifiers"));
    assert!(!obj.contains_key("security_probe_cache"));
    assert!(!obj.contains_key("config_schema_version"));
    // Non-security fields survive.
    assert!(obj.contains_key("font_size"));
}

#[test]
fn transfer_workers_clamped_to_minimum_one() {
    let cfg = AppConfig {
        transfer_workers: 0,
        ..AppConfig::default()
    }
    .sanitized();
    assert_eq!(cfg.transfer_workers, 2);
}

#[test]
fn max_history_clamped_to_non_negative() {
    let cfg = AppConfig {
        max_history: -5,
        ..AppConfig::default()
    }
    .sanitized();
    assert_eq!(cfg.max_history, 500);
}

#[test]
fn recordings_storage_cap_default_is_500_mib() {
    let cfg = AppConfig::default();
    assert_eq!(
        cfg.recordings_storage_cap_bytes,
        DEFAULT_RECORDINGS_STORAGE_CAP_BYTES,
    );
    assert_eq!(cfg.recordings_storage_cap_bytes, 500 * 1024 * 1024);
}

#[test]
fn recordings_storage_cap_round_trips_through_json() {
    let cfg = AppConfig {
        recordings_storage_cap_bytes: 750 * 1024 * 1024,
        ..AppConfig::default()
    };
    let v = cfg.to_json_value();
    let parsed = AppConfig::from_json_value(&v);
    assert_eq!(parsed.recordings_storage_cap_bytes, 750 * 1024 * 1024);
}

#[test]
fn recordings_storage_cap_zero_collapses_to_default() {
    // Zero means "evict every file every sweep" — that is never
    // what the user wants; sanitiser maps it to the default.
    let cfg = AppConfig {
        recordings_storage_cap_bytes: 0,
        ..AppConfig::default()
    }
    .sanitized();
    assert_eq!(
        cfg.recordings_storage_cap_bytes,
        DEFAULT_RECORDINGS_STORAGE_CAP_BYTES,
    );
}

#[test]
fn recordings_storage_cap_absurd_value_collapses_to_default() {
    let cfg = AppConfig {
        recordings_storage_cap_bytes: u64::MAX,
        ..AppConfig::default()
    }
    .sanitized();
    assert_eq!(
        cfg.recordings_storage_cap_bytes,
        DEFAULT_RECORDINGS_STORAGE_CAP_BYTES,
    );
}

#[test]
fn sync_config_defaults_are_disabled_with_canonical_secret_ids() {
    let s = SyncConfig::default();
    assert!(!s.enabled);
    assert!(s.webdav_url.is_empty());
    assert_eq!(s.webdav_password_ref, SYNC_PASSWORD_SECRET_ID);
    assert_eq!(s.passphrase_ref, SYNC_PASSPHRASE_SECRET_ID);
    assert_eq!(s.remote_path, SYNC_DEFAULT_REMOTE_PATH);
    assert_eq!(s.webdav_auth_method, "basic");
    assert_eq!(s.last_pushed_at_ms, 0);
    assert_eq!(s.last_pulled_at_ms, 0);
    assert!(s.last_pushed_sha256.is_empty());
    assert!(s.last_pushed_etag.is_empty());
    assert!(s.last_pulled_etag.is_empty());
    assert!(s.last_pulled_sha256.is_empty());
}

#[test]
fn sync_config_round_trips_through_json_object() {
    let s = SyncConfig {
        enabled: true,
        webdav_url: "https://dav.example.com/remote.php/dav/files/user/".into(),
        webdav_username: "alice".into(),
        webdav_password_ref: SYNC_PASSWORD_SECRET_ID.into(),
        webdav_auth_method: "digest".into(),
        passphrase_ref: SYNC_PASSPHRASE_SECRET_ID.into(),
        remote_path: "lfssh/sync.lfs".into(),
        last_pushed_at_ms: 1_700_000_000_000,
        last_pulled_at_ms: 1_700_000_001_000,
        last_pushed_sha256: "abc123".into(),
        last_pushed_etag: "etag-1".into(),
        last_pulled_etag: "etag-pulled".into(),
        last_pulled_sha256: "deadbeef-pulled".into(),
    };
    let obj = s.to_json_object();
    let parsed = SyncConfig::from_json_object(&obj);
    assert_eq!(parsed, s);
}

#[test]
fn sync_config_unknown_auth_method_collapses_to_basic() {
    let s = SyncConfig {
        webdav_auth_method: "oauth2".into(),
        ..SyncConfig::default()
    }
    .sanitized();
    assert_eq!(s.webdav_auth_method, "basic");
}

#[test]
fn sync_config_empty_remote_path_falls_back_to_default() {
    let s = SyncConfig {
        remote_path: String::new(),
        ..SyncConfig::default()
    }
    .sanitized();
    assert_eq!(s.remote_path, SYNC_DEFAULT_REMOTE_PATH);
}

#[test]
fn sync_config_negative_timestamps_clamp_to_zero() {
    let s = SyncConfig {
        last_pushed_at_ms: -42,
        last_pulled_at_ms: -1,
        ..SyncConfig::default()
    }
    .sanitized();
    assert_eq!(s.last_pushed_at_ms, 0);
    assert_eq!(s.last_pulled_at_ms, 0);
}

#[test]
fn app_config_sync_round_trips_through_full_envelope() {
    let cfg = AppConfig {
        sync: SyncConfig {
            enabled: true,
            webdav_url: "https://dav.example.com/dav/".into(),
            webdav_username: "alice".into(),
            webdav_password_ref: SYNC_PASSWORD_SECRET_ID.into(),
            webdav_auth_method: "basic".into(),
            passphrase_ref: SYNC_PASSPHRASE_SECRET_ID.into(),
            remote_path: "letsflutssh.lfs".into(),
            last_pushed_at_ms: 1_700_000_000_000,
            last_pulled_at_ms: 0,
            last_pushed_sha256: "deadbeef".into(),
            last_pushed_etag: "etag-7".into(),
            last_pulled_etag: "etag-pulled-7".into(),
            last_pulled_sha256: "deadbeef-pulled-7".into(),
        },
        ..AppConfig::default()
    };
    let v = cfg.to_json_value();
    let parsed = AppConfig::from_json_value(&v);
    assert_eq!(parsed.sync, cfg.sync);
}

#[test]
fn strip_for_export_drops_sync_state() {
    // Sync settings describe the current install's relationship
    // with a remote — never portable. The export pipeline must
    // remove them before the JSON lands inside an `.lfs` archive,
    // otherwise an importer on a different machine would adopt
    // the exporter's WebDAV endpoint.
    let cfg = AppConfig {
        sync: SyncConfig {
            enabled: true,
            webdav_url: "https://dav.example.com/dav/".into(),
            last_pushed_sha256: "deadbeef".into(),
            ..SyncConfig::default()
        },
        ..AppConfig::default()
    };
    let mut v = cfg.to_json_value();
    strip_for_export(&mut v);
    let obj = v.as_object().unwrap();
    assert!(!obj.contains_key("sync_enabled"));
    assert!(!obj.contains_key("sync_webdav_url"));
    assert!(!obj.contains_key("sync_webdav_username"));
    assert!(!obj.contains_key("sync_webdav_password_ref"));
    assert!(!obj.contains_key("sync_webdav_auth_method"));
    assert!(!obj.contains_key("sync_passphrase_ref"));
    assert!(!obj.contains_key("sync_remote_path"));
    assert!(!obj.contains_key("sync_last_pushed_at_ms"));
    assert!(!obj.contains_key("sync_last_pulled_at_ms"));
    assert!(!obj.contains_key("sync_last_pushed_sha256"));
    assert!(!obj.contains_key("sync_last_pushed_etag"));
    assert!(!obj.contains_key("sync_last_pulled_etag"));
    assert!(!obj.contains_key("sync_last_pulled_sha256"));
}

#[test]
fn recordings_storage_cap_field_in_json_envelope() {
    // The cap is part of the persisted shape — it must show up
    // at the top level so a hand-edit / out-of-band tool can
    // round-trip the field.
    let v = AppConfig::default().to_json_value();
    let obj = v.as_object().unwrap();
    assert!(obj.contains_key("recordings_storage_cap_bytes"));
}
