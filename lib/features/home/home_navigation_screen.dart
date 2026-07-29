import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../photosession/photosession_showcase_screen.dart';
import '../photosession/theme/photosession_theme_scope.dart';

class HomeNavigationScreen extends ConsumerStatefulWidget {
  const HomeNavigationScreen({super.key});

  @override
  ConsumerState<HomeNavigationScreen> createState() =>
      _HomeNavigationScreenState();
}

class _HomeNavigationScreenState extends ConsumerState<HomeNavigationScreen> {
  // Startup paywall отключён - показываем paywall после первой генерации
  // для лучшей конверсии (пользователь сначала видит результат)
  
  @override
  void initState() {
    super.initState();
    // Больше не показываем paywall при старте
  }

  @override
  Widget build(BuildContext context) {
    return const PhotosessionThemeScope(child: PhotosessionShowcaseScreen());
  }
}
