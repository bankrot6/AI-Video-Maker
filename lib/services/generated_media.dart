import 'dart:typed_data';

/// Результат генерации сохраняется в одном поле (`resultImageUrl`) и для видео,
/// и для изображений, поэтому тип медиа приходится определять по самому файлу.
///
/// Расширение — основной признак, но оно выживает не всегда: ссылка Appwrite
/// заканчивается на `/view`, а Firebase кодирует путь в query. Поэтому имя
/// файла ищется по всем сегментам пути, а для загруженных байтов есть проверка
/// по сигнатуре контейнера.
abstract final class GeneratedMedia {
  static const String videoExtension = '.mp4';

  static const Set<String> _videoExtensions = {'.mp4', '.mov', '.webm', '.m4v'};

  static bool isVideo(String? url) {
    final value = url?.trim();
    if (value == null || value.isEmpty) return false;

    final decoded = Uri.decodeFull(value).toLowerCase();
    final withoutQuery = decoded.split('?').first;
    return withoutQuery
        .split('/')
        .any((segment) => _videoExtensions.any(segment.endsWith));
  }

  /// Определяет видео по сигнатуре контейнера: MP4/MOV/M4V содержат бокс `ftyp`
  /// с пятого байта, WebM начинается с EBML-заголовка Matroska.
  static bool looksLikeVideoBytes(Uint8List bytes) {
    if (bytes.length >= 12) {
      final hasFtypBox = bytes[4] == 0x66 &&
          bytes[5] == 0x74 &&
          bytes[6] == 0x79 &&
          bytes[7] == 0x70;
      if (hasFtypBox) return true;
    }
    if (bytes.length >= 4) {
      final isMatroska = bytes[0] == 0x1A &&
          bytes[1] == 0x45 &&
          bytes[2] == 0xDF &&
          bytes[3] == 0xA3;
      if (isMatroska) return true;
    }
    return false;
  }

  /// Расширение для файла, который сохраняется из уже полученных байтов.
  static String extensionForBytes(Uint8List bytes) =>
      looksLikeVideoBytes(bytes) ? videoExtension : '.jpg';
}
