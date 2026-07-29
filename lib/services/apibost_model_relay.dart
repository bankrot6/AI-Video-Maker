class ApiBostHttpException implements Exception {
  ApiBostHttpException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class ApiBostGenerateResult {
  const ApiBostGenerateResult({
    required this.data,
    required this.actualModel,
    required this.requestedModel,
  });

  final Map<String, dynamic> data;
  final String actualModel;
  final String requestedModel;
}

abstract final class ApiBostModelRelay {
  static const String flash25Model = 'gemini-2.5-flash-image';

  static bool is31FlashImage(String model) {
    return model.toLowerCase().contains('3.1-flash-image');
  }

  static bool shouldFallbackTo25({
    required String model,
    int? httpStatus,
    String? errorMessage,
  }) {
    if (!is31FlashImage(model)) return false;

    if (httpStatus != null) {
      if (httpStatus == 400 || httpStatus == 404 || httpStatus == 503) {
        return true;
      }
      if (httpStatus >= 500) return true;
    }

    final msg = (errorMessage ?? '').toLowerCase();
    if (msg.contains('not been priced') ||
        msg.contains('价格尚未') ||
        msg.contains('no available channel') ||
        msg.contains('openai_error')) {
      return true;
    }
    return false;
  }

  static const _actualModelHeader = 'x-apibost-actual-model';

  static String resolveActualModel({
    required String requestedModel,
    Map<String, String>? responseHeaders,
  }) {
    final fromRelay = responseHeaders?[_actualModelHeader]?.trim();
    if (fromRelay != null && fromRelay.isNotEmpty) return fromRelay;
    return requestedModel;
  }
}
