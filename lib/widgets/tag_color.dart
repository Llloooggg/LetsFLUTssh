import 'package:flutter/material.dart';

import '../core/tags/tag.dart';

/// UI-side helper for resolving a [Tag]'s stored hex string into
/// a Flutter [Color]. Lives in `lib/widgets/` so `core/tags/` can
/// stay Flutter-package-free — the audit flagged
/// `core/tags/tag.dart` as one of the 15 `core/` files importing
/// `package:flutter/*`.
extension TagColorX on Tag {
  /// Parse the stored hex color (`#RRGGBB`) to a Flutter [Color].
  /// Returns `null` when no color is set or the stored string is
  /// malformed. The fallback at every call site is `AppTheme.fgDim`,
  /// so a failed parse renders as the disabled-foreground tone
  /// rather than throwing.
  Color? get colorValue {
    final c = color;
    if (c == null || c.isEmpty) return null;
    try {
      final hex = c.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return null;
    }
  }
}
