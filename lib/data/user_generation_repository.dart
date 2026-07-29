import '../models/user_generation.dart';

abstract class UserGenerationRepository {
  Future<List<UserGeneration>> getGenerationsByPreset(
    String presetId, {
    required String deviceId,
  });
  Future<UserGeneration?> createGeneration({
    required String presetId,
    required String userImageUrl,
    required String resultImageUrl,
    required String deviceId,
    String? referenceImageUrl,
    String? clientAssignedDocumentId,
    String? pairedUserImageUrl,
    String? pairedResultImageUrl,
    String? pairedReferenceImageUrl,
  });

  Stream<Set<String>> watchUsedPresetIds(String deviceId);

  Future<bool> deleteGeneration(
    String generationId, {
    required String deviceId,
    required String presetId,
  });
}
