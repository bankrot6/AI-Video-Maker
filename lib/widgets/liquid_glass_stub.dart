import 'package:flutter/widgets.dart';

class LiquidGlassSettings {
  final double thickness;
  final Color glassColor;
  final double lightIntensity;
  final double ambientStrength;
  final double saturation;

  const LiquidGlassSettings({
    this.thickness = 0,
    this.glassColor = const Color(0x00000000),
    this.lightIntensity = 0,
    this.ambientStrength = 0,
    this.saturation = 1,
  });
}

class LiquidRoundedSuperellipse {
  final Radius borderRadius;

  const LiquidRoundedSuperellipse({required this.borderRadius});
}

class FakeGlass extends StatelessWidget {
  final LiquidRoundedSuperellipse? shape;
  final LiquidGlassSettings? settings;
  final Widget child;

  const FakeGlass({
    super.key,
    required this.child,
    this.shape,
    this.settings,
  });

  @override
  Widget build(BuildContext context) => child;
}

class LiquidGlass extends StatelessWidget {
  final LiquidRoundedSuperellipse? shape;
  final LiquidGlassSettings? settings;
  final Widget child;

  const LiquidGlass({
    super.key,
    required this.child,
    this.shape,
    this.settings,
  });

  @override
  Widget build(BuildContext context) => child;
}











