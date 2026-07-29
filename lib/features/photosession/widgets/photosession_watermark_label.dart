import 'package:flutter/material.dart';

import '../theme/photosession_palette.dart';

double photosessionWatermarkStrokeWidth(double fontSize) =>
    (fontSize * 0.18).clamp(1.5, 4.0);

TextStyle photosessionWatermarkStrokeStyle({
  required double fontSize,
  double? strokeWidth,
}) {
  final width = strokeWidth ?? photosessionWatermarkStrokeWidth(fontSize);
  return TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
    foreground: Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = Colors.white,
  );
}

TextStyle photosessionWatermarkFillStyle({
  required double fontSize,
  required Color fillColor,
}) {
  return TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w700,
    color: fillColor,
  );
}

class PhotosessionWatermarkLabel extends StatelessWidget {
  const PhotosessionWatermarkLabel({
    super.key,
    required this.fontSize,
    this.fillColor,
    this.strokeWidth,
  });

  final double fontSize;
  final Color? fillColor;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final palette = PhotosessionPalette.of(context);
    final resolvedStrokeWidth =
        strokeWidth ?? photosessionWatermarkStrokeWidth(fontSize);
    final resolvedFillColor = fillColor ?? palette.textPrimary;

    return Stack(
      children: [
        Text(
          kPhotosessionWatermarkLabel,
          style: photosessionWatermarkStrokeStyle(
            fontSize: fontSize,
            strokeWidth: resolvedStrokeWidth,
          ),
        ),
        Text(
          kPhotosessionWatermarkLabel,
          style: photosessionWatermarkFillStyle(
            fontSize: fontSize,
            fillColor: resolvedFillColor,
          ),
        ),
      ],
    );
  }
}

Size measurePhotosessionWatermarkLabel({
  required double fontSize,
  double? strokeWidth,
}) {
  final resolvedStrokeWidth =
      strokeWidth ?? photosessionWatermarkStrokeWidth(fontSize);
  final painter = TextPainter(
    text: TextSpan(
      text: kPhotosessionWatermarkLabel,
      style: photosessionWatermarkStrokeStyle(
        fontSize: fontSize,
        strokeWidth: resolvedStrokeWidth,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.size;
}

void paintPhotosessionWatermarkLabel(
  Canvas canvas,
  Offset offset, {
  required double fontSize,
  Color fillColor = Colors.white,
  double? strokeWidth,
}) {
  final resolvedStrokeWidth =
      strokeWidth ?? photosessionWatermarkStrokeWidth(fontSize);
  for (final style in [
    photosessionWatermarkStrokeStyle(
      fontSize: fontSize,
      strokeWidth: resolvedStrokeWidth,
    ),
    photosessionWatermarkFillStyle(
      fontSize: fontSize,
      fillColor: fillColor,
    ),
  ]) {
    final painter = TextPainter(
      text: TextSpan(text: kPhotosessionWatermarkLabel, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }
}
