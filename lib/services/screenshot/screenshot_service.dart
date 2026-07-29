import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../../utils/file_utils.dart';

/// Интерфейс для сервиса скриншота
/// Следуя принципу SOLID (Interface Segregation), создаем интерфейс
abstract class ScreenshotServiceInterface {
  /// Создает скриншот виджета
  Future<Uint8List?> captureWidget(GlobalKey key);

  /// Открывает диалог для поделиться скриншотом
  Future<void> shareScreenshot(Uint8List screenshotBytes, String subject,
      {ui.Rect? sharePositionOrigin});

  /// Объединяет несколько PNG по вертикали и шарит как один PNG
  Future<void> shareCombinedScreenshots(
      List<Uint8List> screenshots, String subject,
      {ui.Rect? sharePositionOrigin});
}

/// Реализация сервиса скриншота с использованием библиотеки screenshot
class ScreenshotService implements ScreenshotServiceInterface {
  final Ref? _ref;

  // Цвет фона для скриншотов
  Color get _backgroundColor =>
      _ref?.read(screenshotThemeProvider).backgroundColor ?? Colors.white;

  // Конструктор может принимать Ref для доступа к провайдерам
  ScreenshotService([this._ref]);

  @override
  Future<Uint8List?> captureWidget(GlobalKey key) async {
    try {
      // Надежно находим RenderRepaintBoundary по ключу с несколькими попытками
      RenderRepaintBoundary? boundary;
      int attempts = 0;
      while (boundary == null && attempts < 10) {
        final renderObject = key.currentContext?.findRenderObject();
        if (renderObject is RenderRepaintBoundary) {
          boundary = renderObject;
          break;
        }
        // Ждем следующий кадр, если не нашли
        await WidgetsBinding.instance.endOfFrame;
        attempts++;
      }

      if (boundary == null) {
        debugPrint('❌ Не удалось найти RenderRepaintBoundary');
        return null;
      }

      // Дожидаемся, пока виджет будет отрисован хотя бы один кадр,
      // иначе toImage может падать с '!debugNeedsPaint'
      await WidgetsBinding.instance.endOfFrame;

      // В debug-режиме дополнительно ждём до 5 кадров, пока boundary перестанет нуждаться в отрисовке
      int retries = 0;
      bool needsPaint = false;
      assert(() {
        needsPaint = boundary?.debugNeedsPaint ?? false;
        return true;
      }());
      while (needsPaint && retries < 5) {
        await Future.delayed(const Duration(milliseconds: 16));
        assert(() {
          needsPaint = boundary?.debugNeedsPaint ?? false;
          return true;
        }());
        retries++;
      }

      // Создаем изображение из виджета
      // Увеличиваем pixelRatio для лучшего качества изображения
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);

      // Создаем холст и рисуем на нем белый фон и затем изображение виджета
      // Это гарантирует, что все прозрачные области будут белыми
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final Paint paint = Paint()..color = _backgroundColor;

      // Рисуем белый фон на холсте
      canvas.drawRect(
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          paint);

      // Рисуем изображение виджета поверх белого фона
      canvas.drawImage(image, Offset.zero, Paint());

      // Создаем финальное изображение из холста
      final ui.Picture picture = recorder.endRecording();
      final ui.Image finalImage =
          await picture.toImage(image.width, image.height);

      // Получаем данные изображения в формате PNG
      final ByteData? byteData =
          await finalImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        debugPrint('❌ Не удалось получить данные изображения');
        return null;
      }

      return byteData.buffer.asUint8List();
    } catch (e) {
      debugPrint('❌ Ошибка при создании скриншота: $e');
      return null;
    }
  }

  @override
  Future<void> shareScreenshot(Uint8List screenshotBytes, String subject,
      {ui.Rect? sharePositionOrigin}) async {
    File? tempFile;
    try {
      final Directory tempDir = await getTemporaryDirectory();
      final String fileName = FileUtils.generateScreenshotFileName();
      tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(screenshotBytes);

      await Share.shareXFiles(
        [XFile(tempFile.path, mimeType: 'image/png', name: fileName)],
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      );

      _scheduleFileDeletion(tempFile);
    } catch (e) {
      debugPrint('❌ Ошибка при попытке поделиться скриншотом: $e');
      if (tempFile != null) _scheduleFileDeletion(tempFile);
    }
  }

  void _scheduleFileDeletion(File file) {
    Future.delayed(const Duration(seconds: 30), () async {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    });
  }

  @override
  Future<void> shareCombinedScreenshots(
      List<Uint8List> screenshots, String subject,
      {ui.Rect? sharePositionOrigin}) async {
    try {
      // Декодируем все изображения
      final decoded = <ui.Image>[];
      for (final bytes in screenshots) {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        decoded.add(frame.image);
      }

      // Рассчитываем итоговые размеры (ширина = макс ширина, высота = сумма)
      int targetWidth = 0;
      int totalHeight = 0;
      for (final img in decoded) {
        targetWidth = targetWidth < img.width ? img.width : targetWidth;
        totalHeight += img.height;
      }

      // Рисуем в единый холст с белым фоном
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..color = Colors.white;
      canvas.drawRect(
          Rect.fromLTWH(0, 0, targetWidth.toDouble(), totalHeight.toDouble()),
          paint);

      int dy = 0;
      for (final img in decoded) {
        canvas.drawImage(img, Offset(0, dy.toDouble()), Paint());
        dy += img.height;
      }

      final picture = recorder.endRecording();
      final merged = await picture.toImage(targetWidth, totalHeight);
      final byteData = await merged.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        debugPrint('❌ Не удалось собрать объединённое изображение');
        return;
      }
      final mergedBytes = byteData.buffer.asUint8List();

      await shareScreenshot(mergedBytes, subject,
          sharePositionOrigin: sharePositionOrigin);
    } catch (e) {
      debugPrint('❌ Ошибка при объединении скриншотов: $e');
    }
  }
}
