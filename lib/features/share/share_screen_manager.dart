import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/providers.dart';
import '../../services/screenshot/screenshot_service.dart';
import '../../services/localization/app_localization_service.dart';

/// Перечисление типов экранов для создания скриншотов
enum ScreenshotType { home, analytics, history }

/// Менеджер для управления скриншотами экранов
/// Следуя принципу SOLID (Single Responsibility), класс отвечает только за создание и шаринг скриншотов
class ShareScreenManager {
  final Ref ref;
  final ScreenshotServiceInterface _screenshotService;

  /// Отдельные ключи для домашнего экрана: хедер и контент «Ваш прогресс сегодня»
  final GlobalKey homeHeaderKey = GlobalKey();
  final GlobalKey homeContentKey = GlobalKey();

  /// Ключи для виджетов, скриншоты которых нужно сделать
  final Map<ScreenshotType, GlobalKey> _screenshotKeys = {
    ScreenshotType.home: GlobalKey(),
    ScreenshotType.analytics: GlobalKey(),
    ScreenshotType.history: GlobalKey(),
  };

  ShareScreenManager(this.ref)
      : _screenshotService = ref.read(screenshotServiceProvider);

  /// Получить ключ для виджета
  GlobalKey getKeyForType(ScreenshotType type) {
    return _screenshotKeys[type]!;
  }

  /// Сделать скриншот экрана определенного типа
  Future<Uint8List?> takeScreenshot(ScreenshotType type) async {
    final key = _screenshotKeys[type];
    if (key == null) {
      debugPrint('❌ Ключ для типа $type не найден');
      return null;
    }

    return await _screenshotService.captureWidget(key);
  }

  /// Поделиться скриншотом
  Future<void> shareScreenshot(ScreenshotType type) async {
    Uint8List? screenshotBytes;
    if (type != ScreenshotType.home) {
      screenshotBytes = await takeScreenshot(type);
      if (screenshotBytes == null) {
        debugPrint('❌ Не удалось создать скриншот');
        return;
      }
    }

    String subject;
    final l10n = ref.read(appLocalizationServiceProvider);
    switch (type) {
      case ScreenshotType.home:
        subject = l10n.translate('share_subject_home');
        break;
      case ScreenshotType.analytics:
        subject = l10n.translate('share_subject_analytics');
        break;
      case ScreenshotType.history:
        subject = l10n.translate('share_subject_history');
        break;
    }

    // Пытаемся вычислить позицию исходного виджета для корректного отображения меню шаринга на iPad/Android
    ui.Rect? origin;
    RenderBox? originBox;
    if (type == ScreenshotType.home) {
      originBox =
          homeHeaderKey.currentContext?.findRenderObject() as RenderBox?;
    } else {
      final key = _screenshotKeys[type];
      originBox = key?.currentContext?.findRenderObject() as RenderBox?;
    }
    if (originBox != null) {
      final offset = originBox.localToGlobal(Offset.zero);
      final size = originBox.size;
      origin = ui.Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
    }

    if (type == ScreenshotType.home) {
      // Захватываем хедер и контент отдельно и объединяем
      final headerBytes = await _screenshotService.captureWidget(homeHeaderKey);
      final contentBytes =
          await _screenshotService.captureWidget(homeContentKey);
      final parts = [headerBytes, contentBytes].whereType<Uint8List>().toList();
      if (parts.isEmpty) {
        debugPrint('❌ Не удалось создать части скриншота для главного экрана');
        return;
      }
      if (parts.length == 1) {
        await _screenshotService.shareScreenshot(parts.first, subject,
            sharePositionOrigin: origin);
      } else {
        await _screenshotService.shareCombinedScreenshots(parts, subject,
            sharePositionOrigin: origin);
      }
      return;
    }

    // Для остальных экранов делимся одним скриншотом
    await _screenshotService.shareScreenshot(
      screenshotBytes!,
      subject,
      sharePositionOrigin: origin,
    );
  }

  /// Поделиться скриншотом, используя переданный ключ виджета
  /// Используется для локальных ключей на экранах, чтобы избежать конфликтов GlobalKey
  Future<void> shareScreenshotWithKey(
    ScreenshotType type,
    GlobalKey boundaryKey,
  ) async {
    // Захватываем изображение по переданному ключу
    final screenshotBytes = await _screenshotService.captureWidget(boundaryKey);
    if (screenshotBytes == null) {
      debugPrint('❌ Не удалось создать скриншот');
      return;
    }

    // Тема и заголовок
    String subject;
    final l10n = ref.read(appLocalizationServiceProvider);
    switch (type) {
      case ScreenshotType.home:
        subject = l10n.translate('share_subject_home');
        break;
      case ScreenshotType.analytics:
        subject = l10n.translate('share_subject_analytics');
        break;
      case ScreenshotType.history:
        subject = l10n.translate('share_subject_history');
        break;
    }

    // Пытаемся вычислить позицию исходного виджета для корректного отображения меню шаринга
    ui.Rect? origin;
    final originBox =
        boundaryKey.currentContext?.findRenderObject() as RenderBox?;
    if (originBox != null) {
      final offset = originBox.localToGlobal(Offset.zero);
      final size = originBox.size;
      origin = ui.Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
    }

    await _screenshotService.shareScreenshot(
      screenshotBytes,
      subject,
      sharePositionOrigin: origin,
    );
  }

  /// Поделиться главной страницей, передав локальные ключи хедера и контента
  Future<void> shareHomeWithKeys(
    GlobalKey headerKey,
    GlobalKey contentKey,
  ) async {
    // Тема и заголовок
    final l10n = ref.read(appLocalizationServiceProvider);
    final subject = l10n.translate('share_subject_home');

    // Пытаемся вычислить позицию исходного виджета (по хедеру)
    ui.Rect? origin;
    final originBox =
        headerKey.currentContext?.findRenderObject() as RenderBox?;
    if (originBox != null) {
      final offset = originBox.localToGlobal(Offset.zero);
      final size = originBox.size;
      origin = ui.Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);
    }

    // Захватываем части скриншота
    final headerBytes = await _screenshotService.captureWidget(headerKey);
    final contentBytes = await _screenshotService.captureWidget(contentKey);

    final parts = [headerBytes, contentBytes].whereType<Uint8List>().toList();
    if (parts.isEmpty) {
      debugPrint('❌ Не удалось создать части скриншота для главного экрана');
      return;
    }

    if (parts.length == 1) {
      await _screenshotService.shareScreenshot(
        parts.first,
        subject,
        sharePositionOrigin: origin,
      );
      return;
    }

    await _screenshotService.shareCombinedScreenshots(
      parts,
      subject,
      sharePositionOrigin: origin,
    );
  }
}
