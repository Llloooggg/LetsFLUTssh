import 'package:flutter/widgets.dart';
import '../theme/app_theme.dart';

/// Bordered container that enforces consistent rounded corners.
///
/// Wraps its child in a [DecoratedBox] with [Border.all] and
/// [AppTheme.radiusSm] by default. Use this instead of manually
/// constructing [BoxDecoration] with [Border.all] to guarantee
/// the design system's border radius is always applied.
class AppBorderedBox extends StatelessWidget {
  const AppBorderedBox({
    super.key,
    required this.child,
    this.borderColor,
    this.color,
    this.borderRadius,
    this.borderWidth = 1,
    this.padding,
    this.height,
    this.width,
    this.constraints,
    this.alignment,
  });

  final Widget child;
  final Color? borderColor;
  final Color? color;
  final BorderRadius? borderRadius;
  final double borderWidth;
  final EdgeInsetsGeometry? padding;
  final double? height;
  final double? width;
  final BoxConstraints? constraints;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      padding: padding,
      alignment: alignment,
      constraints: constraints,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(
          color: borderColor ?? AppTheme.borderLight,
          width: borderWidth,
        ),
        borderRadius: borderRadius ?? AppTheme.radiusSm,
      ),
      child: child,
    );
  }
}
