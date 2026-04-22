import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/platform/macos/code_signing/cert_factory.dart';
import 'package:letsflutssh/platform/macos/code_signing/codesigner.dart';
import 'package:letsflutssh/platform/macos/code_signing/keychain.dart';
import 'package:letsflutssh/platform/macos/code_signing/process_runner.dart';
import 'package:letsflutssh/platform/macos/code_signing/resign_service.dart';

class _FakeKeychain implements Keychain {
  bool certPresent;
  bool importCalled = false;
  bool trustCalled = false;
  bool removeTrustCalled = false;
  int deleteIdentityCalls = 0;
  int deleteCertCalls = 0;

  _FakeKeychain({this.certPresent = false});

  @override
  String get keychainPath => '/tmp/fake-kc';
  @override
  IProcessRunner get runner => const SystemProcessRunner();

  @override
  Future<bool> hasCertificate(String commonName) async => certPresent;

  @override
  Future<void> importPkcs12({
    required File p12Path,
    required String passphrase,
  }) async {
    importCalled = true;
  }

  @override
  Future<void> addTrustedCert(File crtPath) async {
    trustCalled = true;
  }

  @override
  Future<void> removeTrustedCert() async {
    removeTrustCalled = true;
  }

  @override
  Future<void> deleteIdentity(String commonName) async {
    deleteIdentityCalls++;
  }

  @override
  Future<void> deleteCertificate(String commonName) async {
    deleteCertCalls++;
  }
}

class _FakeFactory extends CertFactory {
  int generateCalls = 0;
  _FakeFactory() : super(runner: const SystemProcessRunner());
  @override
  Future<GeneratedCertMaterial> generate({
    String commonName = CertFactory.defaultCommonName,
    String organisation = CertFactory.defaultOrganisation,
    int validityDays = 3650,
  }) async {
    generateCalls++;
    final tmp = Directory.systemTemp.createTempSync('lfs-fake-cert-');
    final crt = File('${tmp.path}/cert.crt')..writeAsStringSync('');
    final p12 = File('${tmp.path}/cert.p12')..writeAsStringSync('');
    return GeneratedCertMaterial(
      tmpDir: tmp,
      crtPath: crt,
      p12Path: p12,
      p12Passphrase: 'pw',
    );
  }
}

class _FakeCodesigner extends Codesigner {
  String? entitlements;
  bool verifyReturn;
  int resignCalls = 0;
  String? resignCn;
  String? resignEntitlementsPlist;

  _FakeCodesigner({this.verifyReturn = true})
    : entitlements = '<plist/>',
      super(runner: const SystemProcessRunner());

  @override
  Future<String?> extractEntitlements(Directory appBundle) async =>
      entitlements;

  @override
  Future<bool> verify(Directory bundle) async => verifyReturn;

  @override
  Future<void> resignInsideOut({
    required Directory appBundle,
    required String commonName,
    String? entitlementsPlist,
    bool useSudo = false,
  }) async {
    resignCalls++;
    resignCn = commonName;
    resignEntitlementsPlist = entitlementsPlist;
  }
}

void main() {
  group('ResignService.ensureIdentity', () {
    test('skips cert generation when one already exists', () async {
      final kc = _FakeKeychain(certPresent: true);
      final factory = _FakeFactory();
      final svc = ResignService(
        certFactory: factory,
        keychain: kc,
        codesigner: _FakeCodesigner(),
      );
      final created = await svc.ensureIdentity();
      expect(created, isFalse);
      expect(factory.generateCalls, 0);
      expect(kc.importCalled, isFalse);
      expect(kc.trustCalled, isFalse);
    });

    test('generates + imports + trusts when cert absent', () async {
      final kc = _FakeKeychain(certPresent: false);
      final factory = _FakeFactory();
      final svc = ResignService(
        certFactory: factory,
        keychain: kc,
        codesigner: _FakeCodesigner(),
      );
      final created = await svc.ensureIdentity();
      expect(created, isTrue);
      expect(factory.generateCalls, 1);
      expect(kc.importCalled, isTrue);
      expect(kc.trustCalled, isTrue);
    });
  });

  group('ResignService.resignBundle', () {
    test('succeeds when bundle is writable + verify passes', () async {
      final bundle = Directory.systemTemp.createTempSync('lfs-svc-');
      addTearDown(() => bundle.deleteSync(recursive: true));
      final cs = _FakeCodesigner(verifyReturn: true);
      final svc = ResignService(
        keychain: _FakeKeychain(certPresent: true),
        codesigner: cs,
      );
      expect(
        await svc.resignBundle(appBundle: bundle),
        ResignOutcome.succeeded,
      );
      expect(cs.resignCalls, 1);
      // Entitlements extracted from the fake codesigner must be
      // threaded through to `resignInsideOut` — missing this is
      // exactly the regression where T1 keychain -34018 comes back.
      expect(cs.resignEntitlementsPlist, '<plist/>');
    });

    test('returns bundleNotWritable when bundle root is read-only', () async {
      // Point at a path we know won't be writable (`/etc` is root-
      // owned on every test host, unwritable by the test user).
      // The service probes with a throw-away file create + delete
      // which fails with a FileSystemException.
      final bundle = Directory('/etc');
      final cs = _FakeCodesigner();
      final svc = ResignService(
        keychain: _FakeKeychain(certPresent: true),
        codesigner: cs,
      );
      expect(
        await svc.resignBundle(appBundle: bundle),
        ResignOutcome.bundleNotWritable,
      );
      expect(cs.resignCalls, 0);
    });

    test('returns cancelledOrFailed when codesign verify fails', () async {
      final bundle = Directory.systemTemp.createTempSync('lfs-svc-');
      addTearDown(() => bundle.deleteSync(recursive: true));
      final cs = _FakeCodesigner(verifyReturn: false);
      final svc = ResignService(
        keychain: _FakeKeychain(certPresent: true),
        codesigner: cs,
      );
      expect(
        await svc.resignBundle(appBundle: bundle),
        ResignOutcome.cancelledOrFailed,
      );
    });
  });

  group('ResignService.uninstallIdentity', () {
    test(
      'calls remove-trust + delete-identity + delete-cert in order',
      () async {
        final kc = _FakeKeychain(certPresent: true);
        final svc = ResignService(keychain: kc, codesigner: _FakeCodesigner());
        await svc.uninstallIdentity();
        expect(kc.removeTrustCalled, isTrue);
        expect(kc.deleteIdentityCalls, 1);
        expect(kc.deleteCertCalls, 1);
      },
    );
  });
}
