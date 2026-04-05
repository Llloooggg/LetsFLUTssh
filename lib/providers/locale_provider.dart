import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config_provider.dart';

/// Current locale derived from config.
///
/// Returns `null` when the user chose "System Default" — Flutter will
/// auto-resolve from the OS locale against [S.supportedLocales].
final localeProvider = Provider<Locale?>((ref) {
  final locale = ref.watch(configProvider.select((c) => c.locale));
  if (locale == null) return null;
  return Locale(locale);
});
