import 'deepseek_models.dart';

class DeepSeekConfig {
  static const String defaultModel = DeepSeekModels.flash;

  final String apiKey;
  final String baseUrl;
  final String model;
  final double temperature;
  final int maxTokens;
  final bool fastMode;
  final bool enableFunctionCalling;
  final bool enableJsonOutput;
  // Токен защиты nginx-прокси (NL_PROXY_TOKEN); null — прямой запрос к DeepSeek.
  final String? proxyToken;

  DeepSeekConfig({
    required this.apiKey,
    this.baseUrl = 'https://api.deepseek.com',
    this.model = defaultModel,
    this.temperature = 0.3,
    this.maxTokens = 8000,
    this.fastMode = false,
    this.enableFunctionCalling = false,
    this.enableJsonOutput = false,
    this.proxyToken,
  });

  // Принудительно используем flash-модель: legacy-идентификаторы и pro
  // приводятся к flash для снижения затрат на DeepSeek API.
  static String normalizeModel(String? rawModel) {
    final value = rawModel?.trim();
    if (value == null || value.isEmpty) {
      return defaultModel;
    }
    if (value == 'deepseek-chat' ||
        value == 'deepseek-reasoner' ||
        value == DeepSeekModels.pro) {
      return defaultModel;
    }
    return value;
  }

  factory DeepSeekConfig.fromEnvironment(String apiKey,
      {bool fastMode = false,
      bool enableFunctionCalling = false,
      bool enableJsonOutput = true,
      String? model}) {
    return DeepSeekConfig(
      apiKey: apiKey,
      model: normalizeModel(model),
      fastMode: fastMode,
      // Стабильные параметры
      maxTokens:
          fastMode ? 3000 : 8000, // Достаточно для полных экскурсионных текстов
      temperature: fastMode ? 0.1 : 0.3,
      enableFunctionCalling: enableFunctionCalling,
      enableJsonOutput: enableJsonOutput,
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'model': model,
      'temperature': temperature,
      'max_tokens': maxTokens,
    };

    if (model.startsWith('deepseek-v4-')) {
      json['thinking'] = {'type': 'disabled'};
    }

    // JSON Output пока отключен для стабильности
    // if (enableJsonOutput) {
    //   json['response_format'] = {'type': 'json_object'};
    // }

    // Function calling будет добавлен позже при необходимости
    // if (enableFunctionCalling && tools != null) {
    //   json['tools'] = tools;
    // }

    return json;
  }
}
