import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';

BoxDecoration raisedDeco(SoftPalette p,
    {double radius = 20, Color? color, bool circle = false}) {
  return BoxDecoration(
    color: color ?? p.bg,
    shape: circle ? BoxShape.circle : BoxShape.rectangle,
    borderRadius: circle ? null : BorderRadius.circular(radius),
    border: Border.all(color: p.ring, width: 1),
    boxShadow: [
      BoxShadow(color: p.shadow, blurRadius: 3, offset: const Offset(0, 2)),
    ],
  );
}

BoxDecoration pressedDeco(SoftPalette p,
    {double radius = 20, bool circle = false}) {
  return BoxDecoration(
    color: p.pressed,
    shape: circle ? BoxShape.circle : BoxShape.rectangle,
    borderRadius: circle ? null : BorderRadius.circular(radius),
    border: Border.all(color: p.ring, width: 1),
  );
}

TextStyle ts(BuildContext context, double size,
    {FontWeight weight = FontWeight.w400,
    Color? color,
    double? height,
    double? letterSpacing}) {
  return TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color ?? context.soft.text,
    height: height,
    letterSpacing: letterSpacing,
  );
}

class SoftTap extends StatelessWidget {
  final VoidCallback? onTap;
  final String? label;
  final Widget child;

  const SoftTap({super.key, required this.child, this.onTap, this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }
}

class SoftIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String label;
  final double size;
  final double iconSize;
  final Color? color;

  const SoftIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.size = 44,
    this.iconSize = 20,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final enabled = onTap != null;
    return SoftTap(
      onTap: onTap,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: raisedDeco(p, circle: true),
          child: Icon(icon, size: iconSize, color: color ?? p.text),
        ),
      ),
    );
  }
}

class SoftPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final double height;
  final IconData? icon;
  final bool expand;

  const SoftPill({
    super.key,
    required this.label,
    this.onTap,
    this.color,
    this.height = 52,
    this.icon,
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final c = color ?? p.accent;
    final enabled = onTap != null;
    return SoftTap(
      onTap: onTap,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          alignment: Alignment.center,
          decoration: raisedDeco(p, radius: height / 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: c),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(context, 16, weight: FontWeight.w500, color: c),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SoftChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const SoftChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    return SoftTap(
      onTap: onTap,
      label: label,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration:
            selected ? pressedDeco(p, radius: 18) : raisedDeco(p, radius: 18),
        child: Text(
          label,
          style: ts(context, 13,
              weight: FontWeight.w500, color: selected ? p.accent : p.muted),
        ),
      ),
    );
  }
}

/// A pressed-in slot with an accent fill.
class SoftSlot extends StatelessWidget {
  final double value;
  final double height;

  const SoftSlot({super.key, required this.value, this.height = 8});

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final double v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();
    return Container(
      height: height,
      decoration: pressedDeco(p, radius: height / 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: v,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: p.accent,
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
        ),
      ),
    );
  }
}

class SoftScaffold extends StatelessWidget {
  final Widget child;

  const SoftScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final p = context.soft;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final style = (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
        .copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: p.bg,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      child: Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(child: child),
      ),
    );
  }
}

void showSoftSnack(BuildContext context, String message,
    {String? actionLabel, VoidCallback? onAction}) {
  final p = context.soft;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: p.pressed,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: p.ring),
      ),
      content: Text(message, style: ts(context, 14)),
      action: actionLabel == null
          ? null
          : SnackBarAction(
              label: actionLabel,
              textColor: p.accent,
              onPressed: onAction ?? () {},
            ),
    ),
  );
}
