import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirebaseAnonymousAuthService {
  FirebaseAnonymousAuthService._();
  static final FirebaseAnonymousAuthService instance = FirebaseAnonymousAuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _currentUser;

  User? get currentUser => _currentUser ?? _auth.currentUser;
  String? get uid => currentUser?.uid;
  bool get isSignedIn => currentUser != null;

  Future<User?> signInAnonymously() async {
    try {
      if (_currentUser != null) {
        debugPrint('FirebaseAnonymousAuth: пользователь уже авторизован, uid=${_currentUser!.uid}');
        return _currentUser;
      }

      final existingUser = _auth.currentUser;
      if (existingUser != null) {
        debugPrint('FirebaseAnonymousAuth: найден существующий пользователь, uid=${existingUser.uid}');
        _currentUser = existingUser;
        return existingUser;
      }

      debugPrint('FirebaseAnonymousAuth: создание анонимного пользователя...');
      final userCredential = await _auth.signInAnonymously();
      _currentUser = userCredential.user;
      
      debugPrint('FirebaseAnonymousAuth: успешно авторизован, uid=${_currentUser?.uid}');
      return _currentUser;
    } catch (e, st) {
      debugPrint('FirebaseAnonymousAuth: ошибка авторизации: $e');
      debugPrint('FirebaseAnonymousAuth: стек: $st');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
      _currentUser = null;
      debugPrint('FirebaseAnonymousAuth: пользователь вышел');
    } catch (e) {
      debugPrint('FirebaseAnonymousAuth: ошибка выхода: $e');
    }
  }

  Future<void> ensureSignedIn() async {
    if (!isSignedIn) {
      await signInAnonymously();
    }
  }
}
