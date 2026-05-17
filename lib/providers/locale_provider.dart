import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show Intl;

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

/// Mirror of [localeProvider] into `package:intl`'s
/// [Intl.defaultLocale] static. Pulled separately because
/// [Intl.defaultLocale] is a top-level mutable global — every
/// `NumberFormat` / `DateFormat` constructor that doesn't pass a
/// locale arg reads it. Keeping it in lockstep with the user's
/// chosen locale means utilities like `formatSize` (and any future
/// locale-blind helper that picks up `Intl.defaultLocale`) match
/// the rest of the UI without a per-callsite locale plumb.
///
/// Watch this provider once from `main_app` (kept in scope for the
/// app's lifetime); the side-effect runs on every locale flip.
final intlDefaultLocaleSyncProvider = Provider<void>((ref) {
  final locale = ref.watch(localeProvider);
  Intl.defaultLocale = locale?.toLanguageTag();
});
