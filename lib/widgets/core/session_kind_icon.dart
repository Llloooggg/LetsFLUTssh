import 'package:flutter/material.dart';

import '../../core/session/session.dart';

/// Canonical icon mapping for [SessionKind] values across the UI.
///
/// Lives in `widgets/` because the mapping produces an [IconData]
/// — a Flutter symbol that `lib/core/` deliberately can't depend
/// on (the core layer must stay framework-free). The symmetric
/// transport-capability matrix on the same enum lives on
/// `SessionKindCapabilities` in `core/session/session.dart`; that
/// one is data-only and can stay framework-free.
///
/// Adding a new [SessionKind] variant → drop the row in here and
/// every consumer (session-list sidebar, panel tab strip, drag
/// feedback chip) picks up the new glyph at once. The earlier
/// shape was a private `_iconForKind` switch in the sidebar plus
/// a hard-coded `kind == TabKind.terminal ? terminal : folder`
/// ternary in the tab bar — the two surfaces drifted and the tab
/// strip collapsed every non-terminal kind onto a generic folder
/// glyph regardless of whether the underlying session was WebDAV,
/// S3, or SFTP-over-SSH.
extension SessionKindIcon on SessionKind {
  /// Outline-weight icon representing this session kind. SSH gets
  /// the terminal glyph (the kind always leads into a shell, the
  /// SFTP browser rides alongside); WebDAV gets the outlined
  /// cloud to signal an HTTP-backed file store; S3 gets the
  /// outlined inventory glyph to read as a bucket / object store.
  IconData get icon => switch (this) {
    SessionKind.ssh => Icons.terminal,
    SessionKind.webdav => Icons.cloud_outlined,
    SessionKind.s3 => Icons.inventory_2_outlined,
  };
}
