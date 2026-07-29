import 'dart:io';

abstract class PhotosessionRemoteStorage {
  Future<String?> uploadUserPhoto(File file);

  Future<String?> uploadPresetPreview(File file);

  Future<String?> uploadResultImage(File file);

  Future<bool> isAvailable();
}
