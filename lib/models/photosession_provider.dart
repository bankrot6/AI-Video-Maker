import '../config/credit_config.dart';

enum PhotosessionProvider {
  piapi,
  googleFlash,
  flash,
  qwen,
  gptImage15,
  gptImage2,
  grokImage,
  apibostPro,
  apibostStandard,
  apibostFlash,
}

extension PhotosessionProviderExt on PhotosessionProvider {
  String get label {
    switch (this) {
      case PhotosessionProvider.piapi:
        return 'Nano Banana Pro';
      case PhotosessionProvider.googleFlash:
        return 'Nano Banana 3.1';
      case PhotosessionProvider.flash:
        return 'Nano Banana 2.5';
      case PhotosessionProvider.qwen:
        return 'Qwen';
      case PhotosessionProvider.gptImage15:
        return 'GPT Image 1.5';
      case PhotosessionProvider.gptImage2:
        return 'GPT Image 2';
      case PhotosessionProvider.grokImage:
        return 'Grok 3 Image';
      case PhotosessionProvider.apibostPro:
        return 'Api Bost PRO';
      case PhotosessionProvider.apibostStandard:
        return 'Api Bost 2';
      case PhotosessionProvider.apibostFlash:
        return 'Api Bost';
    }
  }

  String get fullLabel {
    switch (this) {
      case PhotosessionProvider.piapi:
        return 'Nano Banana Pro';
      case PhotosessionProvider.googleFlash:
        return 'Nano Banana 3.1';
      case PhotosessionProvider.flash:
        return 'Nano Banana 2.5';
      case PhotosessionProvider.qwen:
        return 'Qwen Image Edit';
      case PhotosessionProvider.gptImage15:
        return 'GPT Image 1.5';
      case PhotosessionProvider.gptImage2:
        return 'GPT Image 2';
      case PhotosessionProvider.grokImage:
        return 'Grok 3 Image';
      case PhotosessionProvider.apibostPro:
        return 'Api Bost PRO';
      case PhotosessionProvider.apibostStandard:
        return 'Api Bost 2';
      case PhotosessionProvider.apibostFlash:
        return 'Api Bost';
    }
  }

  String get subtitle {
    switch (this) {
      case PhotosessionProvider.piapi:
        return 'gemini-3-pro-image-preview';
      case PhotosessionProvider.googleFlash:
        return 'gemini-3.1-flash-image-preview';
      case PhotosessionProvider.flash:
        return 'gemini-2.5-flash-image';
      case PhotosessionProvider.qwen:
        return 'Qwen Image Edit';
      case PhotosessionProvider.gptImage15:
        return 'gpt-image-1.5';
      case PhotosessionProvider.gptImage2:
        return 'gpt-image-2';
      case PhotosessionProvider.grokImage:
        return 'grok-3-image';
      case PhotosessionProvider.apibostPro:
        return 'Gemini 3 Pro Image via Api Bost';
      case PhotosessionProvider.apibostStandard:
        return 'Gemini 3.1 Flash Image via Api Bost';
      case PhotosessionProvider.apibostFlash:
        return 'Gemini 2.5 Flash Image via Api Bost';
    }
  }

  bool get isApiBost {
    switch (this) {
      case PhotosessionProvider.apibostPro:
      case PhotosessionProvider.apibostStandard:
      case PhotosessionProvider.apibostFlash:
        return true;
      default:
        return false;
    }
  }

  /// Бейдж источника — null у основных моделей, так как они уже через Api Bost
  String? get sourceBadge => null;

  String get price {
    return creditCostLabel;
  }

  String get description {
    switch (this) {
      case PhotosessionProvider.piapi:
        return 'Максимальное качество и детализация. '
            'Используйте для сложных сцен, печати и работ, '
            'где важна каждая деталь.';
      case PhotosessionProvider.googleFlash:
        return 'Хорошее качество с оптимальным расходом кредитов. '
            'Универсальный выбор для большинства изображений.';
      case PhotosessionProvider.flash:
        return 'Быстрая генерация с минимальным расходом кредитов. '
            'Подходит, чтобы проверить идею перед финальным вариантом.';
      case PhotosessionProvider.qwen:
        return 'Самая доступная модель. Хороша для экспериментов '
            'и массовых генераций.';
      case PhotosessionProvider.gptImage15:
        return 'Модель OpenAI с точным следованием промпту и аккуратным '
            'текстом на изображении.';
      case PhotosessionProvider.gptImage2:
        return 'Новое поколение OpenAI: максимальная детализация и лучшая '
            'работа со сложными сценами.';
      case PhotosessionProvider.grokImage:
        return 'Быстрая генерация по описанию от xAI. '
            'Работает только с текстом — без вашего фото.';
      case PhotosessionProvider.apibostPro:
        return 'Максимальное качество через Api Bost.';
      case PhotosessionProvider.apibostStandard:
        return 'Хорошее качество через Api Bost.';
      case PhotosessionProvider.apibostFlash:
        return 'Быстрая генерация через Api Bost.';
    }
  }

  bool get isAvailable {
    switch (this) {
      case PhotosessionProvider.piapi:
      case PhotosessionProvider.googleFlash:
      case PhotosessionProvider.flash:
      case PhotosessionProvider.gptImage15:
      case PhotosessionProvider.gptImage2:
        return true;
      // ApiBost отдаёт для grok-3-image "No available channel" на обоих
      // контурах — включаем модель, когда канал появится.
      case PhotosessionProvider.grokImage:
      case PhotosessionProvider.qwen:
      case PhotosessionProvider.apibostPro:
      case PhotosessionProvider.apibostStandard:
      case PhotosessionProvider.apibostFlash:
        return false;
    }
  }

  bool get supportsImageEditing {
    switch (this) {
      case PhotosessionProvider.piapi:
      case PhotosessionProvider.googleFlash:
      case PhotosessionProvider.flash:
      case PhotosessionProvider.apibostPro:
      case PhotosessionProvider.apibostStandard:
      case PhotosessionProvider.apibostFlash:
      case PhotosessionProvider.gptImage15:
      case PhotosessionProvider.gptImage2:
        return true;
      case PhotosessionProvider.qwen:
      case PhotosessionProvider.grokImage:
        return false;
    }
  }


  AiModelTier get creditTier {
    switch (this) {
      case PhotosessionProvider.piapi:
      case PhotosessionProvider.apibostPro:
        return AiModelTier.premium;
      case PhotosessionProvider.gptImage15:
      case PhotosessionProvider.gptImage2:
        return AiModelTier.ultra;
      case PhotosessionProvider.grokImage:
        return AiModelTier.advanced;
      case PhotosessionProvider.googleFlash:
      case PhotosessionProvider.apibostStandard:
        return AiModelTier.standard;
      case PhotosessionProvider.flash:
      case PhotosessionProvider.qwen:
      case PhotosessionProvider.apibostFlash:
        return AiModelTier.economy;
    }
  }

  int get creditCost => CreditCost.forGeneration(creditTier);

  String get creditCostLabel => '$creditCost кредитов';
}
