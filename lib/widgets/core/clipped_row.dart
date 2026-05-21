import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A horizontal [Flex] that clips overflowing children **and** suppresses
/// Flutter's debug overflow indicator (yellow-and-black stripes).
///
/// The built-in `Flex.clipBehavior: Clip.hardEdge` clips the children painting
/// but the debug indicator is still painted unconditionally by `RenderFlex`.
/// This widget uses a custom [RenderFlex] subclass that overrides `paint()` to
/// skip the indicator entirely — the overflow is silently clipped.
///
/// Use this in any row whose parent can be resized (sidebar, split panes,
/// column-header rows, status bars) to guarantee no overflow indicators.
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
  }) : super(direction: Axis.horizontal, clipBehavior: Clip.hardEdge);

  @override
  RenderFlex createRenderObject(BuildContext context) {
    return _ClippedRenderFlex(
      direction: Axis.horizontal,
      mainAxisAlignment: mainAxisAlignment,
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: crossAxisAlignment,
      textDirection: getEffectiveTextDirection(context),
      verticalDirection: verticalDirection,
      textBaseline: textBaseline,
      clipBehavior: Clip.hardEdge,
      spacing: spacing,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderFlex renderObject,
  ) {
    renderObject
      ..direction = Axis.horizontal
      ..mainAxisAlignment = mainAxisAlignment
      ..mainAxisSize = mainAxisSize
      ..crossAxisAlignment = crossAxisAlignment
      ..textDirection = getEffectiveTextDirection(context)
      ..verticalDirection = verticalDirection
      ..textBaseline = textBaseline
      ..clipBehavior = Clip.hardEdge
      ..spacing = spacing;
  }
}

/// [RenderFlex] subclass that clips overflow silently — no debug stripes,
/// no error messages in the console.
class _ClippedRenderFlex extends RenderFlex {
  _ClippedRenderFlex({
    required super.direction,
    required super.mainAxisAlignment,
    required super.mainAxisSize,
    required super.crossAxisAlignment,
    required super.textDirection,
    required super.verticalDirection,
    super.textBaseline,
    required super.clipBehavior,
    required super.spacing,
  });

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;

    // Always clip — skip the debug overflow indicator entirely.
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      defaultPaint,
      clipBehavior: Clip.hardEdge,
    );
  }
}
