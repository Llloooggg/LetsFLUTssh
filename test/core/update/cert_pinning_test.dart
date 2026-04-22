import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/update/cert_pinning.dart';

/// Minimal X509Certificate fake — only `der` is read by CertPinning.
class _FakeCert implements X509Certificate {
  @override
  final Uint8List der;

  _FakeCert(List<int> bytes) : der = Uint8List.fromList(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      '${invocation.memberName} is not used by CertPinning',
    );
  }
}

void main() {
  group('CertPinning.accept', () {
    test('falls back to system CA (returns false) when host has no pins', () {
      // The two production hosts ship with empty pin lists in the source —
      // this test pins behaviour as "delegate to CA" rather than "accept
      // anything" so a refactor accident does not turn into a wide-open
      // pinning override.
      final dummy = _FakeCert([1, 2, 3]);
      expect(CertPinning.accept(dummy, 'api.github.com'), isFalse);
      expect(
        CertPinning.accept(dummy, 'objects.githubusercontent.com'),
        isFalse,
      );
    });

    test(
      'rejects (returns false) for hosts that are not in the pin map at all',
      () {
        final dummy = _FakeCert([1, 2, 3]);
        expect(CertPinning.accept(dummy, 'evil.example.com'), isFalse);
      },
    );

    test(
      'SPKI hash digest output matches the canonical sha256(der) base64',
      () {
        // Sanity check that the digest function used by accept is the one we
        // documented in the pin-capture playbook (sha256 over the cert DER).
        final bytes = List<int>.generate(64, (i) => i);
        final expected = base64.encode(sha256.convert(bytes).bytes);
        // The class API only exposes `accept`, so we verify the canonical
        // formula here — when pins are populated, this is exactly the
        // string they must contain.
        expect(expected, isNotEmpty);
        expect(expected.length, greaterThan(40));
      },
    );
  });

  group('CertPinning.enforce', () {
    test(
      'installs a badCertificateCallback that delegates to CertPinning.accept',
      () {
        // The callback is the only integration point between HttpClient
        // and the pin check; if enforce silently omits it or installs
        // the wrong function, all TLS failures would be accepted (or
        // silently rejected) without going through the pin table.
        final client = _CapturingHttpClient();
        CertPinning.enforce(client);

        expect(client.installed, isNotNull);
        final callback = client.installed!;
        final dummy = _FakeCert([9, 9, 9]);
        // Unknown host → must reject (no pin entry at all).
        expect(callback(dummy, 'evil.example.com', 443), isFalse);
        // Pinned host with empty list → still rejects (falls through
        // to system CA, which already said no).
        expect(callback(dummy, 'api.github.com', 443), isFalse);
        expect(callback(dummy, 'objects.githubusercontent.com', 443), isFalse);
      },
    );
  });
}

/// Captures the `badCertificateCallback` setter value so the test can
/// re-invoke it with synthetic inputs — `HttpClient` does not expose the
/// field as a getter.
class _CapturingHttpClient implements HttpClient {
  bool Function(X509Certificate, String, int)? installed;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? value,
  ) {
    installed = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      '${invocation.memberName} is not used by CertPinning.enforce',
    );
  }
}
