import 'package:flutter/material.dart';

/// Soft UI palette. Depth comes only from a 1px ring plus a tiny, crisp shadow.
/// No blur, no gradients, no translucent overlays.
class SoftPalette {
  final Color bg;
  final Color ring;
  final Color shadow;
  final Color pressed;
  final Color text;
  final Color muted;
  final Color accent;
  final Color keep;
  final Color remove;

  const SoftPalette({
    required this.bg,
    required this.ring,
    required this.shadow,
    required this.pressed,
    required this.text,
    required this.muted,
    required this.accent,
    required this.keep,
    required this.remove,
  });
}

const SoftPalette darkPalette = SoftPalette(
  bg: Color(0xFF23262E),
  ring: Color(0xFF2C3039),
  shadow: Color(0x4D000000),
  pressed: Color(0xFF1D1F25),
  text: Color(0xFFE6E8EE),
  muted: Color(0xFFA3A9B8),
  accent: Color(0xFF8FA2FF),
  keep: Color(0xFF7DE3B1),
  remove: Color(0xFFFF9AA5),
);

const SoftPalette lightPalette = SoftPalette(
  bg: Color(0xFFE6EAF0),
  ring: Color(0xFFD3D8E0),
  shadow: Color(0x38465064),
  pressed: Color(0xFFDCE0E7),
  text: Color(0xFF2B3040),
  muted: Color(0xFF5E6577),
  accent: Color(0xFF3B4FC4),
  keep: Color(0xFF17714A),
  remove: Color(0xFFB02A3E),
);

class SoftExt extends ThemeExtension<SoftExt> {
  final SoftPalette p;

  const SoftExt(this.p);

  @override
  SoftExt copyWith({SoftPalette? p}) => SoftExt(p ?? this.p);

  @override
  SoftExt lerp(ThemeExtension<SoftExt>? other, double t) {
    if (other is SoftExt && t >= 0.5) return other;
    return this;
  }
}

extension SoftContext on BuildContext {
  SoftPalette get soft => Theme.of(this).extension<SoftExt>()!.p;
}

ThemeData buildTheme(SoftPalette p, Brightness b) {
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    colorScheme: ColorScheme(
      brightness: b,
      primary: p.accent,
      onPrimary: p.bg,
      secondary: p.accent,
      onSecondary: p.bg,
      error: p.remove,
      onError: p.bg,
      surface: p.bg,
      onSurface: p.text,
    ),
    fontFamily: 'Roboto',
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    extensions: [SoftExt(p)],
  );
}
