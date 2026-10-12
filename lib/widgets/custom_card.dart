import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class CustomCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double? borderRadius;
  final VoidCallback? onTap;
  final BorderSide? border;
  final List<BoxShadow>? boxShadow;
  final bool gloss;
  final bool enableHover;

  const CustomCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.borderRadius,
    this.onTap,
    this.border,
    this.boxShadow,
    this.gloss = false,
    this.enableHover = true,
  });

  @override
  State<CustomCard> createState() => _CustomCardState();
}

class _CustomCardState extends State<CustomCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(widget.borderRadius ?? 16);
    final base = widget.color ?? scheme.surface;
    final isDark = scheme.brightness == Brightness.dark;
    final hoverT = _isHovered ? 1.0 : 0.0;
    final lift = (_isPressed ? -1.0 : -4.0) * hoverT;

    Widget card = TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: hoverT),
      builder: (context, t, _) {
        final animatedLift = lift * t;
        final animatedScale = _isPressed ? 0.99 : (1.0 + 0.01 * t);
        final showBorder = widget.border != null;
        final borderColor = showBorder
            ? widget.border!.color
            : Colors.transparent;
        final borderWidth = showBorder
            ? widget.border!.width
            : 0.0;
        final shadowAlpha = (isDark ? 0.20 : 0.08) + 0.05 * t;

        return Transform.translate(
          offset: Offset(0, animatedLift),
          child: Transform.scale(
            scale: animatedScale,
            child: Material(
              color: Colors.transparent,
              borderRadius: radius,
              child: Ink(
                decoration: BoxDecoration(
                  color: base,
                  borderRadius: radius,
                  border: showBorder
                      ? Border.all(color: borderColor, width: borderWidth)
                      : null,
                  boxShadow: widget.boxShadow ??
                      [
                        BoxShadow(
                          color: scheme.shadow.withValues(alpha: shadowAlpha),
                          blurRadius: isDark ? 12 + 8 * t : 14 + 10 * t,
                          spreadRadius: 0,
                          offset: Offset(0, 8 + 2 * t),
                        ),
                      ],
                ),
                child: InkWell(
                  onTap: widget.onTap,
                  onHighlightChanged: (v) {
                    setState(() => _isPressed = v);
                  },
                  borderRadius: radius,
                  child: ClipRRect(
                    borderRadius: radius,
                    child: Stack(
                      children: [
                        if (widget.gloss && (kIsWeb || hoverT > 0))
                          Positioned.fill(
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: radius,
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.center,
                                    colors: [
                                      Colors.white.withValues(
                                        alpha: (isDark ? 0.05 : 0.10) +
                                            (0.05 * t),
                                      ),
                                      Colors.transparent,
                                    ],
                                    stops: const [0.0, 0.55],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Padding(
                          padding: widget.padding ?? const EdgeInsets.all(16),
                          child: widget.child,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (widget.enableHover) {
      card = MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: card,
      );
    }

    return Container(margin: widget.margin, child: card);
  }
}
