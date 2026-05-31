import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/session.dart';
import 'package:letsflutssh/core/ssh/ssh_config.dart';
import 'package:letsflutssh/features/session_manager/session_details_rows.dart';
import 'package:letsflutssh/l10n/app_localizations.dart';
import 'package:letsflutssh/src/rust/api/db.dart';

/// `sessionDetailRows` is the pure presentation slice behind the
/// sidebar properties panel: given a session and (for WebDAV / S3) the
/// async-fetched transport tuple, it returns the ordered
/// `(label, value)` rows the panel renders. The spec these tests pin:
///   * SSH carries host / login / port on the in-memory row and always
///     shows the full tuple.
///   * WebDAV / S3 show the name + protocol tag always, plus whichever
///     transport fields are present once the details arrive; empty
///     fields are dropped so a fresh session never shows a blank row;
///     `null` details (fetch in flight) collapse to name + protocol.
void main() {
  late S l10n;

  setUpAll(() async {
    l10n = await S.delegate.load(const Locale('en'));
  });

  Session ssh({String label = 'web1'}) => Session(
    id: 's',
    label: label,
    server: const ServerAddress(host: '10.0.0.1', port: 2222, user: 'root'),
  );

  Session webdav({String label = 'dav'}) => Session(
    id: 'w',
    label: label,
    kind: SessionKind.webdav,
    server: const ServerAddress(host: '', user: ''),
  );

  Session s3({String label = 'store'}) => Session(
    id: 'o',
    label: label,
    kind: SessionKind.s3,
    server: const ServerAddress(host: '', user: ''),
  );

  DbWebDavSessionDetails webdavDetails({
    String baseUrl = 'https://dav.example.com/remote.php/dav',
    String username = 'alice',
  }) => DbWebDavSessionDetails(
    sessionId: 'w',
    baseUrl: baseUrl,
    username: username,
    authMethod: 'basic',
    insecureSkipVerify: false,
  );

  DbS3SessionDetails s3Details({
    String region = 'us-east-1',
    String endpoint = 'https://minio.local',
    String bucket = 'backups',
    String prefix = 'db/',
  }) => DbS3SessionDetails(
    sessionId: 'o',
    accessKeyId: 'AKIA',
    region: region,
    endpoint: endpoint,
    pathStyle: true,
    defaultBucket: bucket,
    defaultPrefix: prefix,
    insecureSkipVerify: false,
  );

  group('SSH', () {
    test('shows the full host / login / port tuple', () {
      final rows = sessionDetailRows(session: ssh(), l10n: l10n);
      expect(rows, [
        (l10n.name, 'web1'),
        (l10n.host, '10.0.0.1'),
        (l10n.login, 'root'),
        (l10n.protocol, 'SSH'),
        (l10n.port, '2222'),
      ]);
    });

    test('ignores any passed WebDAV / S3 details', () {
      final rows = sessionDetailRows(
        session: ssh(),
        l10n: l10n,
        webdav: webdavDetails(),
        s3: s3Details(),
      );
      expect(rows.map((r) => r.$1), isNot(contains(l10n.bucket)));
      expect(rows.length, 5);
    });
  });

  group('WebDAV', () {
    test('null details collapse to name + protocol only', () {
      final rows = sessionDetailRows(session: webdav(), l10n: l10n);
      expect(rows, [(l10n.name, 'dav'), (l10n.protocol, 'WebDAV')]);
    });

    test('details add base URL and login between name and protocol', () {
      final rows = sessionDetailRows(
        session: webdav(),
        l10n: l10n,
        webdav: webdavDetails(),
      );
      expect(rows, [
        (l10n.name, 'dav'),
        (l10n.webDavBaseUrl, 'https://dav.example.com/remote.php/dav'),
        (l10n.login, 'alice'),
        (l10n.protocol, 'WebDAV'),
      ]);
    });

    test('empty base URL / username rows are dropped', () {
      final rows = sessionDetailRows(
        session: webdav(),
        l10n: l10n,
        webdav: webdavDetails(baseUrl: '', username: ''),
      );
      expect(rows, [(l10n.name, 'dav'), (l10n.protocol, 'WebDAV')]);
    });
  });

  group('S3', () {
    test('null details collapse to name + protocol only', () {
      final rows = sessionDetailRows(session: s3(), l10n: l10n);
      expect(rows, [(l10n.name, 'store'), (l10n.protocol, 'S3')]);
    });

    test('details add endpoint / region / bucket / prefix in order', () {
      final rows = sessionDetailRows(
        session: s3(),
        l10n: l10n,
        s3: s3Details(),
      );
      expect(rows, [
        (l10n.name, 'store'),
        (l10n.s3Endpoint, 'https://minio.local'),
        (l10n.s3Region, 'us-east-1'),
        (l10n.bucket, 'backups'),
        (l10n.prefix, 'db/'),
        (l10n.protocol, 'S3'),
      ]);
    });

    test('empty endpoint (AWS default) drops only the endpoint row', () {
      final rows = sessionDetailRows(
        session: s3(),
        l10n: l10n,
        s3: s3Details(endpoint: ''),
      );
      expect(rows, [
        (l10n.name, 'store'),
        (l10n.s3Region, 'us-east-1'),
        (l10n.bucket, 'backups'),
        (l10n.prefix, 'db/'),
        (l10n.protocol, 'S3'),
      ]);
    });

    test('all-empty optional fields collapse to name + protocol', () {
      final rows = sessionDetailRows(
        session: s3(),
        l10n: l10n,
        s3: s3Details(region: '', endpoint: '', bucket: '', prefix: ''),
      );
      expect(rows, [(l10n.name, 'store'), (l10n.protocol, 'S3')]);
    });
  });

  test('blank label falls back to the derived display name', () {
    final rows = sessionDetailRows(
      session: ssh(label: ''),
      l10n: l10n,
    );
    final name = rows.first;
    expect(name.$1, l10n.name);
    expect(name.$2, isNotEmpty);
    expect(name.$2, isNot('web1'));
  });
}
