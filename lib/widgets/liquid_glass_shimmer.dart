import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class LiquidGlassShimmer extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const LiquidGlassShimmer({
    super.key,
    this.width = double.infinity,
    this.height = 78,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.black.withOpacity(0.12),
      highlightColor: Colors.black.withOpacity(0.04),
      period: const Duration(milliseconds: 1100),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.12),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

/// Шиммер для заголовка дня (меньшая высота)
class LiquidGlassShimmerTitle extends StatelessWidget {
  final double width;
  final double height;

  const LiquidGlassShimmerTitle({
    super.key,
    this.width = double.infinity,
    this.height = 24,
  });

  @override
  Widget build(BuildContext context) {
    return LiquidGlassShimmer(
      width: width,
      height: height,
      borderRadius: 8,
    );
  }
}

/// Простой шиммер без BackdropFilter (для списков, где много элементов)
/// Более производительный вариант
class LiquidGlassShimmerLight extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const LiquidGlassShimmerLight({
    super.key,
    this.width = double.infinity,
    this.height = 78,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.black.withOpacity(0.10),
      highlightColor: Colors.black.withOpacity(0.04),
      period: const Duration(milliseconds: 1500),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.10),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: Colors.black.withOpacity(0.12),
            width: 0.5,
          ),
        ),
      ),
    );
  }
}
