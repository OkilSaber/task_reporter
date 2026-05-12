import 'dart:ui';
import 'package:flutter/material.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final bool isHighlighted;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 15,
    this.opacity = 0.15,
    this.borderRadius,
    this.padding,
    this.color,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final br = borderRadius ?? BorderRadius.circular(24);
    return Container(
      decoration: BoxDecoration(
        borderRadius: br,
        boxShadow: [
          BoxShadow(
            color: isHighlighted 
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.1),
            blurRadius: isHighlighted ? 40 : 30,
            spreadRadius: isHighlighted ? 2 : 0,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: (color ?? Colors.white).withValues(alpha: isHighlighted ? opacity + 0.1 : opacity),
              borderRadius: br,
              border: Border.all(
                color: Colors.white.withValues(alpha: isHighlighted ? 0.6 : 0.3),
                width: isHighlighted ? 2.5 : 1.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
