import 'package:flutter/material.dart';

/// A horizontal [Flex] that clips overflowing children instead of showing
/// Flutter's yellow-and-black debug stripes.
///
/// Use this in any row whose parent can be resized (sidebar, split panes,
/// column-header rows, status bars) to guarantee no overflow indicators.
///
/// Equivalent to:
/// ```dart
/// Flex(
///   direction: Axis.horizontal,
///   clipBehavior: Clip.hardEdge,
///   children: [...],
/// )
/// ```
class ClippedRow extends Flex {
  const ClippedRow({
    super.key,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
    super.textBaseline,
    super.spacing,
    super.children,
  }) : super(
          direction: Axis.horizontal,
          clipBehavior: Clip.hardEdge,
        );
}
