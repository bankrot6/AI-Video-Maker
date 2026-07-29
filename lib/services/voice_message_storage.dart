import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/file_utils.dart';

/// Хранилище аудиофайлов голосовых сообщений
class VoiceMessageStorage {
  static const String _folderName = 'voice_messages';

  /// Возвращает путь к каталогу хранения голосовых сообщений
  static Future<String> _ensureFolder() async {
    final Directory baseDir = await getApplicationDocumentsDirectory();
    final String folderPath = p.join(baseDir.path, _folderName);
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return folderPath;
  }

  /// Перемещает временный аудиофайл в каталог приложения и возвращает новый путь
  static Future<String> saveFromTemp(String tempPath) async {
    try {
      final String folder = await _ensureFolder();
      final String fileName = FileUtils.generateFileName(
        prefix: 'AI Video Maker',
        suffix: 'voice',
        extension: 'wav',
      );
      final String targetPath = p.join(folder, fileName);

      final File src = File(tempPath);
      if (!await src.exists()) {
        throw Exception('Файл не найден: $tempPath');
      }

      try {
        // Пытаемся переименовать (переместить) — быстро и без копирования
        final moved = await src.rename(targetPath);
        await _ensurePlayableWav(moved.path);
        return moved.path;
      } catch (_) {
        // Если не удалось (например, разные файловые системы) — копируем и удаляем источник
        await src.copy(targetPath);
        try {
          await src.delete();
        } catch (_) {}
        await _ensurePlayableWav(targetPath);
        return targetPath;
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎧 VoiceStorage: ошибка перемещения файла: $e');
      }
      rethrow;
    }
  }

  /// Удаляет аудиофайл, если он существует
  static Future<void> deleteIfExists(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      if (kDebugMode) {
        print('🎧 VoiceStorage: ошибка удаления файла $path: $e');
      }
    }
  }

  static Future<void> _ensurePlayableWav(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      if (bytes.length < 12) return;
      if (_hasWavHeader(bytes)) return;
      final wrapped = _wrapPcmAsWav(
        pcmData: bytes,
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
      );
      await file.writeAsBytes(wrapped, flush: true);
    } catch (e) {
      if (kDebugMode) {
        print('🎧 VoiceStorage: ошибка подготовки WAV: $e');
      }
    }
  }

  static bool _hasWavHeader(Uint8List bytes) {
    if (bytes.length < 12) return false;
    return bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x41 &&
        bytes[10] == 0x56 &&
        bytes[11] == 0x45;
  }

  static Uint8List _wrapPcmAsWav({
    required Uint8List pcmData,
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
  }) {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;
    final header = BytesBuilder(copy: false);
    header.add(const [0x52, 0x49, 0x46, 0x46]);
    header.add(_uint32le(fileSize));
    header.add(const [0x57, 0x41, 0x56, 0x45]);
    header.add(const [0x66, 0x6D, 0x74, 0x20]);
    header.add(_uint32le(16));
    header.add(_uint16le(1));
    header.add(_uint16le(channels));
    header.add(_uint32le(sampleRate));
    header.add(_uint32le(byteRate));
    header.add(_uint16le(blockAlign));
    header.add(_uint16le(bitsPerSample));
    header.add(const [0x64, 0x61, 0x74, 0x61]);
    header.add(_uint32le(dataSize));
    header.add(pcmData);
    return header.toBytes();
  }

  static Uint8List _uint16le(int value) {
    final data = ByteData(2);
    data.setUint16(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  static Uint8List _uint32le(int value) {
    final data = ByteData(4);
    data.setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }
}
