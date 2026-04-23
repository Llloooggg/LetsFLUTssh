import 'dart:io';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
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
      'extractSpki returns identical bytes for two certs sharing a keypair',
      () {
        // Pin invariant: a cert renewal that keeps the same keypair must
        // produce the same SPKI bytes (and therefore the same pin). This
        // is the whole point of SPKI pinning over full-cert pinning —
        // without it, every routine leaf rotation would break the
        // updater. Two minimal X.509 structures with identical SPKI
        // payloads but different serial numbers / subjects must hash
        // equal.
        final spki = _fakeSpki([0xAA, 0xBB, 0xCC]);
        final certA = _buildMinimalX509Cert(
          spki: spki,
          serial: 1,
          subjectCommonName: 'original',
        );
        final certB = _buildMinimalX509Cert(
          spki: spki,
          serial: 2,
          subjectCommonName: 'renewed',
        );
        expect(CertPinning.extractSpki(certA), CertPinning.extractSpki(certB));
      },
    );

    test('extractSpki returns different bytes for different keypairs', () {
      // Flip side of the pinning contract: a genuine key rotation must
      // break the pin so the updater refuses to talk to the new host
      // until someone deliberately rolls the pin forward.
      final certA = _buildMinimalX509Cert(
        spki: _fakeSpki([0xAA, 0xBB]),
        serial: 1,
        subjectCommonName: 'hostA',
      );
      final certB = _buildMinimalX509Cert(
        spki: _fakeSpki([0xDD, 0xEE]),
        serial: 2,
        subjectCommonName: 'hostA',
      );
      expect(
        CertPinning.extractSpki(certA),
        isNot(equals(CertPinning.extractSpki(certB))),
      );
    });

    test('extractSpki returns null on torn / non-ASN.1 input', () {
      expect(CertPinning.extractSpki(Uint8List.fromList([0])), isNull);
      expect(CertPinning.extractSpki(Uint8List.fromList([1, 2, 3])), isNull);
    });
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

/// Build a minimal X.509-shaped ASN.1 structure with a caller-supplied
/// SubjectPublicKeyInfo subtree. Not a signature-valid cert — the
/// [CertPinning.extractSpki] logic only walks the outer SEQUENCE /
/// tbsCertificate / SPKI path, so sibling elements need only exist
/// with any valid ASN.1 shape.
Uint8List _buildMinimalX509Cert({
  required Uint8List spki,
  required int serial,
  required String subjectCommonName,
}) {
  // Decode the caller's SPKI bytes into an ASN1Object so the outer
  // TBS sequence can re-encode it verbatim through `.encodedBytes`.
  final spkiObj = ASN1Parser(spki).nextObject();
  // Minimal issuer / subject — a single RDN with a dummy OID. The
  // SPKI-extraction path does not read these, but asn1lib's encoder
  // refuses empty structural nodes in some versions.
  ASN1Object name(String cn) {
    final rdn = ASN1Set()
      ..add(
        ASN1Sequence()
          ..add(ASN1ObjectIdentifier.fromComponentString('2.5.4.3'))
          ..add(ASN1PrintableString(cn)),
      );
    return ASN1Sequence()..add(rdn);
  }

  final validity = ASN1Sequence()
    ..add(ASN1UtcTime(DateTime.utc(2020, 1, 1)))
    ..add(ASN1UtcTime(DateTime.utc(2099, 12, 31)));
  final sigAlg = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromComponentString('1.2.840.113549.1.1.11'))
    ..add(ASN1Null());

  // [0] EXPLICIT version wrapper — tag 0xA0 with the contained
  // INTEGER as content. Encode an INTEGER then prepend the explicit
  // wrapper bytes.
  final inner = ASN1Integer(BigInt.from(2)); // v3
  final innerBytes = inner.encodedBytes;
  final versionExplicit = ASN1Object.fromBytes(
    Uint8List.fromList([0xA0, innerBytes.length, ...innerBytes]),
  );

  final tbs = ASN1Sequence()
    ..add(versionExplicit)
    ..add(ASN1Integer(BigInt.from(serial)))
    ..add(sigAlg)
    ..add(name('issuer'))
    ..add(validity)
    ..add(name(subjectCommonName))
    ..add(spkiObj);

  final cert = ASN1Sequence()
    ..add(tbs)
    ..add(sigAlg)
    ..add(ASN1BitString(Uint8List.fromList([0])));

  return cert.encodedBytes;
}

/// Build a SubjectPublicKeyInfo node with a caller-chosen key payload.
/// Shape: `SEQUENCE { AlgorithmIdentifier, BIT STRING }` per RFC 5280.
Uint8List _fakeSpki(List<int> keyBytes) {
  final algo = ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromComponentString('1.2.840.113549.1.1.1'))
    ..add(ASN1Null());
  final seq = ASN1Sequence()
    ..add(algo)
    ..add(ASN1BitString(Uint8List.fromList(keyBytes)));
  return seq.encodedBytes;
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
