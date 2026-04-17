import 'package:flutter/widgets.dart';

/// Helpers for handling secret-bearing [TextEditingController]s (master
/// password, SSH key passphrase, encryption setup) in a way that minimises
/// the residency time of the secret in the heap.
///
/// Dart `String`s are immutable, so the underlying buffer cannot be wiped
/// in place. The best we can do is overwrite the controller's `text`
/// property with same-length null-byte content and then clear it before
/// disposing. This (a) detaches the secret from the controller's
/// `valueListenable` listeners, (b) drops the only reference held by the
/// widget, (c) leaves only short-lived intermediate `String`s on the heap
/// for the GC to collect on the next cycle.
extension SecretController on TextEditingController {
  /// Overwrite [text] with same-length filler then clear the controller.
  /// Call this from [State.dispose] BEFORE [TextEditingController.dispose].
  ///
  /// Idempotent and safe to call on an already-empty controller.
  void wipeAndClear() {
    if (text.isNotEmpty) {
      // Two passes: replace with null bytes (so any listener observing the
      // change reads opaque content), then clear (so the listenable's
      // final state holds nothing).
      text = '\u0000' * text.length;
    }
    clear();
  }
}
