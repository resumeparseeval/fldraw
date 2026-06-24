import 'package:flutter/widgets.dart';

/// Central monotone design tokens for FlowDraw's *chrome* — the floating
/// tool island, the menu bar, popovers, the canvas-control cluster and the
/// contextual selection toolbar.
///
/// The philosophy is deliberately narrow: one near-black neutral surface,
/// a graphite hairline, three tiers of foreground text, and a *single*
/// restrained accent used only to mark the active tool, the current
/// selection and primary actions. Nothing else is allowed to carry colour,
/// which is what keeps the interface calm and clutter-free.
///
/// Every chrome widget reads its colours from [FlowDrawSkin.of] rather than
/// hard-coding values, so the whole surface stays coherent and is trivial to
/// retheme from one place.
@immutable
class FlowDrawTokens {
  const FlowDrawTokens({
    required this.surface,
    required this.surfaceHover,
    required this.surfaceActive,
    required this.border,
    required this.foreground,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accentForeground,
    required this.accentSoft,
    required this.danger,
    required this.scrim,
    required this.shadow,
    this.radius = 13,
    this.itemRadius = 9,
  });

  /// Base card background for floating chrome (toolbar, menu, popovers).
  final Color surface;

  /// Background of a hovered, non-active control.
  final Color surfaceHover;

  /// Background of a pressed / momentarily-active control (non-accent).
  final Color surfaceActive;

  /// Hairline borders + dividers.
  final Color border;

  /// Primary icon / text colour.
  final Color foreground;

  /// Secondary text (labels, shortcut hints).
  final Color muted;

  /// Tertiary / disabled.
  final Color faint;

  /// The one restrained accent — active tool, selection, primary action.
  final Color accent;

  /// Foreground used on top of [accent].
  final Color accentForeground;

  /// Translucent accent for soft selection tints and rails.
  final Color accentSoft;

  /// Destructive action colour.
  final Color danger;

  /// Full-screen scrim behind modal overlays.
  final Color scrim;

  /// Elevation shadow for floating cards.
  final List<BoxShadow> shadow;

  /// Outer card corner radius.
  final double radius;

  /// Inner control corner radius.
  final double itemRadius;

  /// Refined dark monotone — matches the canvas's light-ink-on-dark surface.
  static const FlowDrawTokens dark = FlowDrawTokens(
    surface: Color(0xFF161618),
    surfaceHover: Color(0x12FFFFFF),
    surfaceActive: Color(0x1FFFFFFF),
    border: Color(0xFF2B2B30),
    foreground: Color(0xFFECECEE),
    muted: Color(0xFF9A9AA1),
    faint: Color(0xFF5C5C63),
    accent: Color(0xFF3B6FE0),
    accentForeground: Color(0xFFFFFFFF),
    accentSoft: Color(0x303B6FE0),
    danger: Color(0xFFE5565B),
    scrim: Color(0x99000000),
    shadow: [
      BoxShadow(color: Color(0x5C000000), blurRadius: 28, offset: Offset(0, 10)),
      BoxShadow(color: Color(0x33000000), blurRadius: 3, offset: Offset(0, 1)),
    ],
  );
}

/// Inherited carrier for [FlowDrawTokens]. Provided once near the top of the
/// app (in `FlowDraw`) so every chrome widget can do `FlowDrawSkin.of(context)`.
class FlowDrawSkin extends InheritedWidget {
  const FlowDrawSkin({
    super.key,
    this.tokens = FlowDrawTokens.dark,
    required super.child,
  });

  final FlowDrawTokens tokens;

  /// The nearest tokens, falling back to [FlowDrawTokens.dark] so chrome can
  /// be dropped anywhere without crashing if a provider is missing.
  static FlowDrawTokens of(BuildContext context) {
    final skin = context.dependOnInheritedWidgetOfExactType<FlowDrawSkin>();
    return skin?.tokens ?? FlowDrawTokens.dark;
  }

  @override
  bool updateShouldNotify(FlowDrawSkin oldWidget) =>
      !identical(oldWidget.tokens, tokens);
}
