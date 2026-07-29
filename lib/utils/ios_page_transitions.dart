import 'package:flutter/material.dart';

/// iOS-подобные переходы между страницами
class IOSPageTransitions {
  /// Стандартный iOS push переход (слайд справа налево)
  static PageRoute createRoute(Widget destination) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => destination,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;

        var tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );

        var offsetAnimation = animation.drive(tween);

        return SlideTransition(
          position: offsetAnimation,
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 350),
    );
  }

  /// iOS модальный переход (слайд снизу вверх)
  static PageRoute createModalRoute(Widget destination) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => destination,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;

        var tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );

        var offsetAnimation = animation.drive(tween);

        return SlideTransition(
          position: offsetAnimation,
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 300),
    );
  }

  /// Fade переход для tab navigation
  static PageRoute createFadeRoute(Widget destination) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => destination,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 250),
    );
  }

  /// Комбинированный переход (fade + slide) для tab navigation
  static PageRoute createTabRoute(Widget destination, {bool isForward = true}) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => destination,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final begin = Offset(isForward ? 0.15 : -0.15, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;

        var slideTween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );

        var fadeTween = Tween(begin: 0.0, end: 1.0).chain(
          CurveTween(curve: curve),
        );

        return SlideTransition(
          position: animation.drive(slideTween),
          child: FadeTransition(
            opacity: animation.drive(fadeTween),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 350),
    );
  }

  /// Переход с масштабированием (для модальных окон)
  static PageRoute createScaleRoute(Widget destination) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => destination,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const curve = Curves.easeInOut;

        var scaleTween = Tween(begin: 0.85, end: 1.0).chain(
          CurveTween(curve: curve),
        );

        var fadeTween = Tween(begin: 0.0, end: 1.0).chain(
          CurveTween(curve: curve),
        );

        return ScaleTransition(
          scale: animation.drive(scaleTween),
          child: FadeTransition(
            opacity: animation.drive(fadeTween),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
      opaque: false,
      barrierColor: Colors.black54,
    );
  }
}

/// Extension для удобного использования
extension NavigatorIOSExtension on NavigatorState {
  /// Push с iOS переходом
  Future<T?> pushIOS<T extends Object?>(Widget destination) {
    return push<T>(IOSPageTransitions.createRoute(destination) as Route<T>);
  }

  /// Push modal с iOS переходом
  Future<T?> pushIOSModal<T extends Object?>(Widget destination) {
    return push<T>(
        IOSPageTransitions.createModalRoute(destination) as Route<T>);
  }

  /// Replace с iOS переходом
  Future<T?> pushReplacementIOS<T extends Object?, TO extends Object?>(
      Widget destination) {
    return pushReplacement<T, TO>(
        IOSPageTransitions.createRoute(destination) as Route<T>);
  }

  /// Replace с fade переходом для tabs
  Future<T?> pushReplacementFade<T extends Object?, TO extends Object?>(
      Widget destination) {
    return pushReplacement<T, TO>(
        IOSPageTransitions.createFadeRoute(destination) as Route<T>);
  }
}
