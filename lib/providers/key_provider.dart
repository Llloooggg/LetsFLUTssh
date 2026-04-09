import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/key_store.dart';

/// Key store — singleton (encrypted SSH key storage).
final keyStoreProvider = Provider<KeyStore>((ref) {
  return KeyStore();
});

/// Reactive list of all stored SSH keys.
///
/// Loads keys on first access; [invalidate] to reload after mutations.
final sshKeysProvider = FutureProvider<List<SshKeyEntry>>((ref) async {
  final store = ref.watch(keyStoreProvider);
  final keys = await store.loadAllSafe();
  return keys.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
});
