import 'package:flutter/foundation.dart';

import '../data/showcase_repository.dart';
import '../models/preset_tag.dart';
import 'image_prompt_service.dart';

class PresetTagService {
  PresetTagService({
    required ShowcaseRepository repository,
    required PromptTagExtractor tagExtractor,
  })  : _repository = repository,
        _tagExtractor = tagExtractor;

  final ShowcaseRepository _repository;
  final PromptTagExtractor _tagExtractor;

  Future<void> updateTagsForPublicPreset(String presetId, [String? prompt]) async {
    try {
      String promptToAnalyze = prompt ?? '';

      if (promptToAnalyze.isEmpty) {
        debugPrint('PresetTagService: промпт не передан, загружаем из БД...');
        final preset = await _repository.getPresetById(presetId);
        if (preset == null) {
          throw Exception('Пресет не найден в БД');
        }
        promptToAnalyze = preset.prompt;
      }

      if (promptToAnalyze.isEmpty) {
        throw Exception('Промпт пуст');
      }

      debugPrint(
        'PresetTagService: анализируем промпт (${promptToAnalyze.length} символов)',
      );
      final extractedTags = await _tagExtractor.extractTags(promptToAnalyze);

      final allTags = [PresetTag.idCustom, ...extractedTags];

      await _repository.updateTags(presetId, allTags);

      debugPrint(
        'PresetTagService: теги обновлены для $presetId: ${allTags.join(", ")}',
      );
    } catch (e) {
      debugPrint('PresetTagService: ошибка обновления тегов: $e');
      rethrow;
    }
  }
}
