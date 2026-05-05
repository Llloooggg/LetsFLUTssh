/// Pure helpers extracted from `_QrExportTile._showQrExport` so the
/// payload-build / deeplink-wrap / credentials-flag decisions can be
/// unit-tested without booting FRB or showing the
/// `UnifiedExportDialog`.
///
/// The dispatcher in `_QrExportTile` reads providers + shows dialogs;
/// once those have produced an [ExportOptions] + a list of selected
/// session ids + an optional `AppConfig`, every remaining shape
/// decision is pure — what fields land in [rust_archive.DbQrExportInput],
/// how the deflated payload becomes a `letsflutssh://import?d=...`
/// deeplink, and which combination of toggles count as
/// "credential-bearing" for the QR display screen's safety pill.
library;

import 'dart:convert';

import '../../core/config/app_config.dart';
import '../../core/session/qr_codec.dart';
import '../../src/rust/api/archive.dart' as rust_archive;

/// Wrap a Rust-side QR payload string in the canonical deeplink
/// scheme. The Dart receiver — see `extract_payload_from_uri` in
/// `lfs_core::qr_codec_decode` — strips the `letsflutssh://import?d=`
/// prefix back off; both ends must agree on the scheme + parameter
/// name verbatim, so the wrap stays in one place.
String qrPayloadDeepLink(String payload) => 'letsflutssh://import?d=$payload';

/// True when the [options] turn on at least one credential-bearing
/// toggle. Drives the "this code carries credentials" warning pill on
/// the QR display screen — see `_QrExportTile._showQrExport`. The QR
/// mode default is `includePasswords: true`, so a blanket "no
/// credentials" reassurance would be misleading; this helper makes the
/// check explicit and testable.
bool qrPayloadHasCredentials(ExportOptions options) {
  return options.includePasswords ||
      options.includeEmbeddedKeys ||
      options.hasManagerKeys;
}

/// Build the FRB-side input struct for `dbExportQrPayload` from the
/// dialog's resolved selections. Mirrors the
/// `_QrExportTile._showQrExport` body, peeled out so the shape mapping
/// can be exercised against every options-toggle combination directly.
///
/// `cfg` is the live `AppConfig` snapshot the caller resolved from
/// `configProvider` when [options.includeConfig] was true; the helper
/// drops the config payload entirely (sets `configJson: null`) when
/// `cfg` is null, mirroring the `_QrExportTile` `if-includeConfig`
/// short-circuit.
rust_archive.DbQrExportInput buildDbQrExportInput({
  required ExportOptions options,
  required List<String> selectedSessionIds,
  required List<String> selectedEmptyFolders,
  required AppConfig? cfg,
}) {
  return rust_archive.DbQrExportInput(
    options: rust_archive.DbQrExportOptions(
      includeSessions: options.includeSessions,
      // Belt-and-braces: even with includeConfig=true on the options,
      // a null cfg means the caller didn't actually resolve the
      // provider snapshot in time; flip the Rust flag off so the
      // composer doesn't ship a `c` block with no payload.
      includeConfig: options.includeConfig && cfg != null,
      includeKnownHosts: options.includeKnownHosts,
      includePasswords: options.includePasswords,
      includeEmbeddedKeys: options.includeEmbeddedKeys,
      includeManagerKeys: options.includeManagerKeys,
      includeAllManagerKeys: options.includeAllManagerKeys,
      includeTags: options.includeTags,
      includeSnippets: options.includeSnippets,
    ),
    selectedSessionIds: selectedSessionIds,
    selectedEmptyFolders: selectedEmptyFolders,
    // Skip the JSON encode entirely when the caller said "no config"
    // even if they happened to hand in a non-null cfg snapshot — saves
    // an FRB round-trip and keeps the helper self-defensive (the only
    // current caller already nulls cfg when includeConfig is off, but
    // an opt-in test or a future caller shouldn't have to know that).
    configJson: (options.includeConfig && cfg != null)
        ? jsonEncode(cfg.toJson())
        : null,
  );
}
