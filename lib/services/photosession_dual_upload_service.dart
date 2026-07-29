import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/photosession_backend.dart';
import 'appwrite_storage_service.dart';
import 'firebase_storage_service.dart';

class DualSideImageUrls {
  const DualSideImageUrls({this.appwriteUrl, this.firebaseUrl});

  final String? appwriteUrl;
  final String? firebaseUrl;

  String? primaryForCurrentBackend() =>
      useAppwriteBackend() ? appwriteUrl : firebaseUrl;

  String? mirrorForCurrentBackend() =>
      useAppwriteBackend() ? firebaseUrl : appwriteUrl;

  static bool _isHttpUrl(String? s) {
    if (s == null || s.isEmpty) return false;
    final t = s.trim();
    return t.startsWith('http://') || t.startsWith('https://');
  }

  String? firstHttpPrimaryOrMirror() {
    final p = primaryForCurrentBackend()?.trim();
    if (_isHttpUrl(p)) return p;
    final m = mirrorForCurrentBackend()?.trim();
    if (_isHttpUrl(m)) return m;
    return null;
  }

  String? pairedHttpRelativeTo(String chosen) {
    final c = chosen.trim();
    final p = primaryForCurrentBackend()?.trim();
    final m = mirrorForCurrentBackend()?.trim();
    if (p == c) return _isHttpUrl(m) ? m : null;
    if (m == c) return _isHttpUrl(p) ? p : null;
    return null;
  }
}

class PhotosessionDualUploadService {
  PhotosessionDualUploadService({
    required AppwriteStorageService appwrite,
    required FirebaseStorageService firebase,
  })  : _appwrite = appwrite,
        _firebase = firebase;

  final AppwriteStorageService _appwrite;
  final FirebaseStorageService _firebase;

  Future<DualSideImageUrls> uploadResultImage(File file) async {
    debugPrint(
      'PhotosessionDualUploadService: uploadResultImage — параллельно Appwrite+Firebase',
    );
    try {
      final results = await Future.wait([
        _appwrite.uploadResultImage(file),
        _firebase.uploadResultImage(file),
      ]);
      debugPrint(
        'PhotosessionDualUploadService: uploadResultImage готово '
        'appwrite=${results[0] != null} firebase=${results[1] != null}',
      );
      return DualSideImageUrls(
        appwriteUrl: results[0],
        firebaseUrl: results[1],
      );
    } catch (e, st) {
      debugPrint('PhotosessionDualUploadService: uploadResultImage $e');
      debugPrint('$st');
      return const DualSideImageUrls();
    }
  }

  Future<DualSideImageUrls> uploadPresetPreview(File file) async {
    debugPrint(
      'PhotosessionDualUploadService: uploadPresetPreview — параллельно Appwrite+Firebase',
    );
    try {
      final results = await Future.wait([
        _appwrite.uploadPresetPreview(file),
        _firebase.uploadPresetPreview(file),
      ]);
      debugPrint(
        'PhotosessionDualUploadService: uploadPresetPreview готово '
        'appwrite=${results[0] != null} firebase=${results[1] != null}',
      );
      return DualSideImageUrls(
        appwriteUrl: results[0],
        firebaseUrl: results[1],
      );
    } catch (e, st) {
      debugPrint('PhotosessionDualUploadService: uploadPresetPreview $e');
      debugPrint('$st');
      return const DualSideImageUrls();
    }
  }
}
