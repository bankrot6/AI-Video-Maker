import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

abstract class ReferenceFaceMaskService {
  Future<File> suppressFaceIdentity(File imageFile);
}

class MlKitReferenceFaceMaskService implements ReferenceFaceMaskService {
  MlKitReferenceFaceMaskService({
    ReferenceFaceMaskService? fallback,
  }) : _fallback = fallback ?? HeuristicReferenceFaceMaskService();

  final ReferenceFaceMaskService _fallback;

  @override
  Future<File> suppressFaceIdentity(File imageFile) async {
    if (!imageFile.existsSync()) {
      return imageFile;
    }

    final detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableClassification: false,
        enableContours: false,
        enableLandmarks: false,
        enableTracking: false,
        minFaceSize: 0.12,
      ),
    );

    try {
      final inputImage = InputImage.fromFile(imageFile);
      final faces = await detector.processImage(inputImage);
      if (faces.isEmpty) {
        return _fallback.suppressFaceIdentity(imageFile);
      }

      final bytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return _fallback.suppressFaceIdentity(imageFile);
      }

      final masked = decoded.clone();
      final region = _primaryFaceRegion(
        faces: faces,
        imageWidth: masked.width,
        imageHeight: masked.height,
      );
      if (region == null) {
        return _fallback.suppressFaceIdentity(imageFile);
      }

      final average = _computeAverageColor(masked, region);
      _applyEllipseMask(masked, region, average);
      return _writeMaskedImage(masked);
    } catch (e) {
      debugPrint('MlKitReferenceFaceMaskService: $e');
      return _fallback.suppressFaceIdentity(imageFile);
    } finally {
      await detector.close();
    }
  }
}

class HeuristicReferenceFaceMaskService implements ReferenceFaceMaskService {
  @override
  Future<File> suppressFaceIdentity(File imageFile) async {
    if (!imageFile.existsSync()) {
      return imageFile;
    }

    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        return imageFile;
      }

      if (!_shouldMask(image)) {
        return imageFile;
      }

      final masked = image.clone();
      final region = _estimateHeuristicFaceRegion(masked.width, masked.height);
      final average = _computeAverageColor(masked, region);
      _applyEllipseMask(masked, region, average);
      return _writeMaskedImage(masked);
    } catch (e) {
      debugPrint('ReferenceFaceMaskService: $e');
      return imageFile;
    }
  }

  bool _shouldMask(img.Image image) {
    if (image.width < 384 || image.height < 384) {
      return false;
    }

    final aspectRatio = image.width / image.height;
    return aspectRatio <= 1.2;
  }
}

_MaskRegion _estimateHeuristicFaceRegion(int width, int height) {
  final regionWidth = (width * 0.38).round().clamp(120, width).toInt();
  final regionHeight = (height * 0.30).round().clamp(120, height).toInt();
  final centerX = width ~/ 2;
  final centerY = (height * 0.24).round();
  final left = (centerX - regionWidth ~/ 2).clamp(0, width - 1).toInt();
  final top = (centerY - regionHeight ~/ 2).clamp(0, height - 1).toInt();
  final right = (left + regionWidth).clamp(1, width).toInt();
  final bottom = (top + regionHeight).clamp(1, height).toInt();
  return _MaskRegion(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
  );
}

_MaskRegion? _primaryFaceRegion({
  required List<Face> faces,
  required int imageWidth,
  required int imageHeight,
}) {
  if (faces.isEmpty) {
    return null;
  }

  Face primary = faces.first;
  var maxArea = 0.0;
  for (final face in faces) {
    final rect = face.boundingBox;
    final area = rect.width * rect.height;
    if (area > maxArea) {
      primary = face;
      maxArea = area;
    }
  }

  final rect = primary.boundingBox;
  if (rect.width <= 0 || rect.height <= 0) {
    return null;
  }

  final padX = rect.width * 0.28;
  final padTop = rect.height * 0.32;
  final padBottom = rect.height * 0.22;

  final left = (rect.left - padX).floor().clamp(0, imageWidth - 1).toInt();
  final top = (rect.top - padTop).floor().clamp(0, imageHeight - 1).toInt();
  final right =
      (rect.right + padX).ceil().clamp(1, imageWidth).toInt();
  final bottom =
      (rect.bottom + padBottom).ceil().clamp(1, imageHeight).toInt();

  if (right <= left || bottom <= top) {
    return null;
  }

  return _MaskRegion(
    left: left,
    top: top,
    right: right,
    bottom: bottom,
  );
}

_RgbColor _computeAverageColor(img.Image image, _MaskRegion region) {
  var totalR = 0.0;
  var totalG = 0.0;
  var totalB = 0.0;
  var samples = 0;

  for (var y = region.top; y < region.bottom; y++) {
    for (var x = region.left; x < region.right; x++) {
      final pixel = image.getPixel(x, y);
      totalR += pixel.r;
      totalG += pixel.g;
      totalB += pixel.b;
      samples++;
    }
  }

  if (samples == 0) {
    return const _RgbColor(140, 140, 140);
  }

  return _RgbColor(
    (totalR / samples).round(),
    (totalG / samples).round(),
    (totalB / samples).round(),
  );
}

void _applyEllipseMask(
  img.Image image,
  _MaskRegion region,
  _RgbColor average,
) {
  final centerX = (region.left + region.right) / 2.0;
  final centerY = (region.top + region.bottom) / 2.0;
  final radiusX = (region.right - region.left) / 2.0;
  final radiusY = (region.bottom - region.top) / 2.0;

  for (var y = region.top; y < region.bottom; y++) {
    for (var x = region.left; x < region.right; x++) {
      final dx = (x - centerX) / radiusX;
      final dy = (y - centerY) / radiusY;
      final distance = (dx * dx) + (dy * dy);
      if (distance > 1.0) {
        continue;
      }

      final pixel = image.getPixel(x, y);
      final strength = 0.40 + ((1.0 - distance) * 0.55);
      final alpha = strength.clamp(0.0, 0.95).toDouble();
      final blendedR = _blendChannel(pixel.r.round(), average.r, alpha);
      final blendedG = _blendChannel(pixel.g.round(), average.g, alpha);
      final blendedB = _blendChannel(pixel.b.round(), average.b, alpha);
      image.setPixelRgba(x, y, blendedR, blendedG, blendedB, pixel.a.round());
    }
  }
}

Future<File> _writeMaskedImage(img.Image image) async {
  final tempDir = await getTemporaryDirectory();
  final outputPath = path.join(
    tempDir.path,
    'photosession_ref_masked_${DateTime.now().microsecondsSinceEpoch}.jpg',
  );
  final file = File(outputPath);
  await file.writeAsBytes(
    img.encodeJpg(image, quality: 88),
    flush: true,
  );
  return file;
}

int _blendChannel(int base, int overlay, double alpha) {
  final value = (base * (1 - alpha)) + (overlay * alpha);
  return value.round().clamp(0, 255).toInt();
}

class _MaskRegion {
  const _MaskRegion({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final int left;
  final int top;
  final int right;
  final int bottom;
}

class _RgbColor {
  const _RgbColor(this.r, this.g, this.b);

  final int r;
  final int g;
  final int b;
}
