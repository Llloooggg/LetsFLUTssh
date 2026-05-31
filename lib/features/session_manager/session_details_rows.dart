import '../../core/session/session.dart';
import '../../l10n/app_localizations.dart';
import '../../src/rust/api/db.dart';

/// Pick the label/value rows the session details panel renders for
/// [session].
///
/// SSH carries the host / login / port tuple on the in-memory
/// [Session] row, so its rows are built straight from [session].
/// WebDAV and S3 keep their transport tuple on the matching join
/// table (`webdav_session_details` / `s3_session_details`); the panel
/// fetches it async via FRB and hands the result here through
/// [webdav] / [s3]. Either is `null` while that fetch is in flight (or
/// for a kind that has no detail row) — in which case only the name
/// and protocol tag render, never a stale empty row. Empty optional
/// fields are skipped so a freshly created session shows just what it
/// actually has.
///
/// Pure presentation: choosing which localized label pairs with which
/// field is rendering, not core data logic, so it lives Dart-side and
/// is unit-tested directly without a widget pump.
List<(String, String)> sessionDetailRows({
  required Session session,
  required S l10n,
  DbWebDavSessionDetails? webdav,
  DbS3SessionDetails? s3,
}) {
  final name = session.label.isNotEmpty ? session.label : session.displayName;
  switch (session.kind) {
    case SessionKind.ssh:
      return [
        (l10n.name, name),
        (l10n.host, session.host),
        (l10n.login, session.user),
        (l10n.protocol, 'SSH'),
        (l10n.port, session.port.toString()),
      ];
    case SessionKind.webdav:
      return _webdavRows(name, l10n, webdav);
    case SessionKind.s3:
      return _s3Rows(name, l10n, s3);
  }
}

List<(String, String)> _webdavRows(
  String name,
  S l10n,
  DbWebDavSessionDetails? d,
) {
  final rows = <(String, String)>[(l10n.name, name)];
  if (d != null) {
    if (d.baseUrl.isNotEmpty) rows.add((l10n.webDavBaseUrl, d.baseUrl));
    if (d.username.isNotEmpty) rows.add((l10n.login, d.username));
  }
  rows.add((l10n.protocol, 'WebDAV'));
  return rows;
}

List<(String, String)> _s3Rows(String name, S l10n, DbS3SessionDetails? d) {
  final rows = <(String, String)>[(l10n.name, name)];
  if (d != null) {
    // Empty endpoint means the AWS default endpoints derived from the
    // region — the region / bucket rows below already identify the
    // session, so the row is dropped rather than shown blank.
    if (d.endpoint.isNotEmpty) rows.add((l10n.s3Endpoint, d.endpoint));
    if (d.region.isNotEmpty) rows.add((l10n.s3Region, d.region));
    if (d.defaultBucket.isNotEmpty) rows.add((l10n.bucket, d.defaultBucket));
    if (d.defaultPrefix.isNotEmpty) rows.add((l10n.prefix, d.defaultPrefix));
  }
  rows.add((l10n.protocol, 'S3'));
  return rows;
}
