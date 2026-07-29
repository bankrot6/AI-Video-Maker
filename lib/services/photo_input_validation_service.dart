import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

enum PhotoValidationSeverity {
  valid,
  warning,
  error,
}

class PhotoInputValidationResult {
  const PhotoInputValidationResult._({
    required this.severity,
    required this.title,
    required this.message,
  });

  const PhotoInputValidationResult.valid({
    required String title,
    required String message,
  }) : this._(
         severity: PhotoValidationSeverity.valid,
         title: title,
         message: message,
       );

  const PhotoInputValidationResult.warning({
    required String title,
    required String message,
  }) : this._(
         severity: PhotoValidationSeverity.warning,
         title: title,
         message: message,
       );

  const PhotoInputValidationResult.error({
    required String title,
    required String message,
  }) : this._(
         severity: PhotoValidationSeverity.error,
         title: title,
         message: message,
       );

  final PhotoValidationSeverity severity;
  final String title;
  final String message;

  bool get isBlocking => severity == PhotoValidationSeverity.error;
}

abstract class PhotoInputValidationService {
  Future<PhotoInputValidationResult> validate(File imageFile);
}

class MlKitPhotoInputValidationService implements PhotoInputValidationService {
  @override
  Future<PhotoInputValidationResult> validate(File imageFile) async {
    if (!imageFile.existsSync()) {
      return const PhotoInputValidationResult.error(
        title: 'Фото недоступно',
        message: 'Не удалось прочитать выбранный файл. Попробуйте выбрать фото заново.',
      );
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
        return const PhotoInputValidationResult.error(
          title: 'Лицо не найдено',
          message: 'Выберите фото, где одно лицо хорошо видно без сильных теней и перекрытий.',
        );
      }

      if (faces.length > 1) {
        return const PhotoInputValidationResult.error(
          title: 'На фото несколько лиц',
          message: 'Для точной генерации лучше загрузить фото только с одним человеком в кадре.',
        );
      }

      final bytes = await imageFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
        return const PhotoInputValidationResult.error(
          title: 'Не удалось проверить фото',
          message: 'Файл изображения повреждён или имеет неподдерживаемый формат.',
        );
      }

      final face = faces.first;
      final rect = face.boundingBox;
      final imageWidth = decoded.width.toDouble();
      final imageHeight = decoded.height.toDouble();
      final widthRatio = rect.width / imageWidth;
      final heightRatio = rect.height / imageHeight;
      final areaRatio = (rect.width * rect.height) / (imageWidth * imageHeight);
      final leftMargin = rect.left / imageWidth;
      final topMargin = rect.top / imageHeight;
      final rightMargin = (imageWidth - rect.right) / imageWidth;
      final bottomMargin = (imageHeight - rect.bottom) / imageHeight;
      final minMargin = [
        leftMargin,
        topMargin,
        rightMargin,
        bottomMargin,
      ].reduce((a, b) => a < b ? a : b);
      final yaw = face.headEulerAngleY?.abs() ?? 0.0;
      final roll = face.headEulerAngleZ?.abs() ?? 0.0;

      if (widthRatio < 0.18 || heightRatio < 0.18 || areaRatio < 0.04) {
        return const PhotoInputValidationResult.error(
          title: 'Лицо слишком далеко',
          message: 'Лучше выбрать портрет крупнее: лицо должно занимать заметную часть кадра.',
        );
      }

      if (minMargin < 0.015) {
        return const PhotoInputValidationResult.error(
          title: 'Лицо обрезано',
          message: 'Лицо слишком близко к краю кадра. Нужен снимок с небольшим запасом вокруг головы.',
        );
      }

      if (widthRatio < 0.26 || heightRatio < 0.26 || areaRatio < 0.08) {
        return const PhotoInputValidationResult.warning(
          title: 'Лицо можно взять крупнее',
          message: 'Фото подходит, но при более крупном портрете лицо обычно переносится точнее.',
        );
      }

      if (minMargin < 0.05) {
        return const PhotoInputValidationResult.warning(
          title: 'Лицо близко к краю',
          message: 'Фото подходит, но лучше оставить немного свободного пространства вокруг головы.',
        );
      }

      if (yaw > 20 || roll > 12) {
        return const PhotoInputValidationResult.warning(
          title: 'Голова заметно повернута',
          message: 'Фото можно использовать, но анфас или почти анфас обычно даёт более точное лицо.',
        );
      }

      return const PhotoInputValidationResult.valid(
        title: 'Фото подходит',
        message: 'Лицо хорошо читается, можно генерировать.',
      );
    } catch (e) {
      debugPrint('PhotoInputValidationService: $e');
      return const PhotoInputValidationResult.error(
        title: 'Проверка не удалась',
        message: 'Не удалось проанализировать фото. Попробуйте выбрать другое изображение.',
      );
    } finally {
      await detector.close();
    }
  }
}
