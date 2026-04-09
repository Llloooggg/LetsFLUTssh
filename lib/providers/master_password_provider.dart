import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/master_password.dart';

/// Master password manager — singleton.
final masterPasswordProvider = Provider<MasterPasswordManager>((ref) {
  return MasterPasswordManager();
});
