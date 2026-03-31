import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config_provider.dart';

/// Current ThemeMode derived from config.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final config = ref.watch(configProvider);
  switch (config.theme) {
    case 'light':
      return ThemeMode.light;
    case 'system':
      return ThemeMode.system;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
});
