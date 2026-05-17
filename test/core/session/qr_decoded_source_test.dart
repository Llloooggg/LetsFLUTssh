/// Coverage for [QrDecodedSource] + [tryDecodeQrPayloadViaRust].
///
/// The class is a thin wrapper that adapts the Rust
/// `DbImportOpenResult` to the `LfsPreview` surface the UI consumes.
/// The decoder swallows every FRB / decode failure into `null` so a
/// junk paste-link does not crash the deep-link pump.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:letsflutssh/core/session/qr_decoded_source.dart';

import '../../helpers/frb_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(requireFrbLoaded);

  group('tryDecodeQrPayloadViaRust', () {
    test('returns null for an obviously bogus payload', () async {
      // Random ASCII — cannot possibly parse as the base64url-encoded
      // archive envelope the Rust decoder expects. The catch wraps
      // every error path (FRB transport, decode, AnyhowException);
      // the contract is "best-effort decode, null on any failure".
      expect(await tryDecodeQrPayloadViaRust('not-a-real-payload'), isNull);
    });

    test('returns null for an empty string', () async {
      expect(await tryDecodeQrPayloadViaRust(''), isNull);
    });

    test('returns null for a malformed letsflutssh:// URI', () async {
      // The Rust call accepts both the full URI and the raw
      // base64url payload — both shapes decode through the same
      // pipeline, both fail the same way on garbage input.
      expect(
        await tryDecodeQrPayloadViaRust('letsflutssh://import?d=xxx'),
        isNull,
      );
    });

    test('returns null for a base64url-shaped but undecodable blob', () async {
      // Looks like a base64url payload (length / charset OK) but
      // does not decrypt under any password — the envelope decoder
      // raises and the catch wraps to null.
      const fake =
          'AAAA-BBBB_CCCC-DDDD_EEEE-FFFF_GGGG-HHHH_IIII-JJJJ_KKKK-LLLL';
      expect(await tryDecodeQrPayloadViaRust(fake), isNull);
    });
  });
}
