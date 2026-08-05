import '../config/credit_config.dart';

/// Модели генерации видео, доступные через ApiBost.
///
/// Клип выходит со звуковой дорожкой, длительностью до 8 секунд (предел Veo).
/// Пропорции и длительность задаются директивами в тексте промпта (`[9:16]`,
/// `[8s]`) — JSON-поля `aspect_ratio` и `duration` релей игнорирует, несмотря
/// на то, что объявляет их в документации.
///
/// Тиры различаются качеством генерации, а не форматом кадра: доступный набор
/// пропорций (16:9, 9:16, 1:1, 21:9) одинаков для всех моделей.
enum PhotosessionProvider {
  veoLite,
  veoFast,
  veoPro,
  veoFastPreview,
  veoPro4k,
}

extension PhotosessionProviderExt on PhotosessionProvider {
  String get label {
    switch (this) {
      case PhotosessionProvider.veoLite:
        return 'Veo 3.1 Lite';
      case PhotosessionProvider.veoFast:
        return 'Veo 3.1 Fast';
      case PhotosessionProvider.veoPro:
        return 'Veo 3.1 Pro';
      case PhotosessionProvider.veoFastPreview:
        return 'Veo 3.1 Fast Preview';
      case PhotosessionProvider.veoPro4k:
        return 'Veo 3.1 Pro 4K';
    }
  }

  String get fullLabel => label;

  String get subtitle {
    switch (this) {
      case PhotosessionProvider.veoLite:
        return 'veo3.1-lite';
      case PhotosessionProvider.veoFast:
        return 'veo3.1-fast';
      case PhotosessionProvider.veoPro:
        return 'veo3.1-pro';
      case PhotosessionProvider.veoFastPreview:
        return 'veo-3.1-fast-generate-preview';
      case PhotosessionProvider.veoPro4k:
        return 'veo3.1-pro-4k';
    }
  }

  /// Идентификатор модели в ApiBost.
  String get apiBostModel => subtitle;

  bool get isApiBost => true;

  String? get sourceBadge => null;

  String get price => creditCostLabel;

  String get description {
    switch (this) {
      case PhotosessionProvider.veoLite:
        return 'Самая доступная модель. Клип до 8 секунд со звуком — '
            'подходит, чтобы проверить идею перед финальным вариантом.';
      case PhotosessionProvider.veoFast:
        return 'Оптимальный баланс качества и расхода кредитов. '
            'Универсальный выбор для большинства сюжетов.';
      case PhotosessionProvider.veoPro:
        return 'Флагманская модель: плавное движение, стабильная геометрия '
            'и лучшая проработка деталей в кадре.';
      case PhotosessionProvider.veoFastPreview:
        return 'Официальная ветка Google Veo 3.1 Fast с повышенной '
            'детализацией движения.';
      case PhotosessionProvider.veoPro4k:
        return 'Максимальное качество в 4K. Для финальных работ, '
            'где важна каждая деталь.';
    }
  }

  /// Premium и ultra остаются выключенными до проверки на реальном трафике:
  /// официальные preview-эндпоинты ApiBost отвечали HTTP 524 (timeout).
  bool get isAvailable {
    switch (this) {
      case PhotosessionProvider.veoLite:
      case PhotosessionProvider.veoFast:
      case PhotosessionProvider.veoPro:
        return true;
      case PhotosessionProvider.veoFastPreview:
      case PhotosessionProvider.veoPro4k:
        return false;
    }
  }

  /// Veo принимает входные кадры через `inlineData`: одно фото анимируется,
  /// два задают переход между первым и последним кадром.
  bool get supportsImageEditing => true;

  AiModelTier get creditTier {
    switch (this) {
      case PhotosessionProvider.veoLite:
        return AiModelTier.economy;
      case PhotosessionProvider.veoFast:
        return AiModelTier.standard;
      case PhotosessionProvider.veoPro:
        return AiModelTier.advanced;
      case PhotosessionProvider.veoFastPreview:
        return AiModelTier.premium;
      case PhotosessionProvider.veoPro4k:
        return AiModelTier.ultra;
    }
  }

  int get creditCost => CreditCost.forGeneration(creditTier);

  String get creditCostLabel => '$creditCost кредитов';
}
