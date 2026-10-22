import 'package:flutter/material.dart';

import 'scale_down_text.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;
  final Color? color;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double borderRadius;
  final bool isOutlined;
  final bool outlined;

  const CustomButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = true,
    this.color,
    this.backgroundColor,
    this.foregroundColor,
    this.borderRadius = 12.0,
    this.isOutlined = false,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    final effectiveBackgroundColor = color ?? backgroundColor ?? scheme.primary;
    final effectiveIsOutlined = isOutlined || outlined;
    final onPrimaryColor = foregroundColor ?? (effectiveIsOutlined ? effectiveBackgroundColor : Colors.white);

    Widget content = Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(onPrimaryColor),
            ),
          )
        else ...[
          if (icon != null) ...[
            Icon(icon, size: 20, color: onPrimaryColor),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: ScaleDownText(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: onPrimaryColor,
                fontFamily: 'Tajawal',
              ),
            ),
          ),
        ],
      ],
    );

    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: 56,
      child: effectiveIsOutlined
          ? OutlinedButton(
              onPressed: isLoading ? null : onPressed,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: effectiveBackgroundColor, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
                padding: const EdgeInsets.symmetric(horizontal: 24),
              ),
              child: content,
            )
          : FilledButton(
              onPressed: isLoading ? null : onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: effectiveBackgroundColor,
                foregroundColor: onPrimaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius)),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                elevation: 0,
              ),
              child: content,
            ),
    );
  }
}
