class DeepSeekException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  DeepSeekException({
    required this.message,
    this.code,
    this.statusCode,
  });

  factory DeepSeekException.fromJson(Map<String, dynamic> json) {
    final error = json['error'] as Map<String, dynamic>?;

    return DeepSeekException(
      message: error?['message'] ?? 'Unknown DeepSeek error',
      code: error?['code'] as String?,
      statusCode: json['status_code'] as int?,
    );
  }

  @override
  String toString() {
    if (code != null) {
      return 'DeepSeekException (code: $code, status: $statusCode): $message';
    }
    return 'DeepSeekException: $message';
  }
}
