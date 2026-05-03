/// Pure helpers for the recordings browser. Extracted so the
/// session-id → display-label fallback (live label → display name →
/// truncated id sentinel for orphaned recordings) has a clear test
/// target.
library;

import '../../core/session/session.dart';

/// Resolve the human label for a recording's session id. Walks the
/// supplied list once; returns the first match's `label` (or
/// `displayName` when label is empty). Recordings outlive their
/// sessions — when no match exists we surface a `<deleted>` prefix
/// + the first 8 chars of the id so the user can at least find and
/// delete the orphaned file.
///
/// `<deleted>` prefix is intentional English: not localised because
/// the suffix is the raw id and a localised label would mix scripts
/// inside the same row visual.
String resolveRecordingSessionLabel(String sessionId, List<Session> sessions) {
  for (final s in sessions) {
    if (s.id == sessionId) {
      return s.label.isNotEmpty ? s.label : s.displayName;
    }
  }
  return '<deleted> ${sessionId.substring(0, 8)}';
}
