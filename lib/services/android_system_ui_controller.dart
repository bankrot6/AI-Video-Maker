import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AndroidSystemUiController {
  static int _navigationBarClients = 0;

  static void showNavigationBar() {
    if (!_isAndroid) return;
    _navigationBarClients += 1;
    _applyNavigationBarVisible();
  }

  static void hideNavigationBar() {
    if (!_isAndroid) return;
    if (_navigationBarClients > 0) {
      _navigationBarClients -= 1;
    }
    if (_navigationBarClients == 0) {
      _applyNavigationBarHidden();
    }
  }

  static void refresh() {
    if (!_isAndroid) return;
    if (_navigationBarClients > 0) {
      _applyNavigationBarVisible();
    } else {
      _applyNavigationBarHidden();
    }
  }

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void _applyNavigationBarVisible() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
      ),
    );
  }

  static void _applyNavigationBarHidden() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
    );
  }
}
