import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/localization/app_localization_service.dart';
import '../../services/providers.dart' as services;
import '../../widgets/liquid_glass_card.dart';
import '../../widgets/bottom_content_blur.dart';

/// Экран добавления с опциями
class AddScreen extends ConsumerWidget {
  const AddScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          context.tr('add'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Фоновое изображение
          Positioned.fill(
            child: Image.asset(
              'assets/images/a-futuristic-digital-background-0.png',
              fit: BoxFit.cover,
              opacity: const AlwaysStoppedAnimation(0.8),
            ),
          ),
          // Контент с эффектом размытия снизу
          SafeArea(
            bottom: false,
            child: Stack(
              children: [
                BottomFadeMask(
                  fadeHeight: 100.0,
                  fadeStart: 0.70,
                  child: SingleChildScrollView(
                    padding:
                        const EdgeInsets.only(left: 20, right: 20, bottom: 100),
                    child: Column(
                      children: [
                        const SizedBox(height: 40),
                        LiquidGlassButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            final foodInputService = ref.read(
                              services.foodInputServiceProvider,
                            )(ref, context);
                            foodInputService.openWeightInput();
                          },
                          width: double.infinity,
                          color: const Color(0xFF5E7FE1),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.monitor_weight_rounded,
                                  size: 24),
                              const SizedBox(width: 12),
                              Text(context.tr('change_weight')),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        LiquidGlassButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            final foodInputService = ref.read(
                              services.foodInputServiceProvider,
                            )(ref, context);
                            foodInputService.openMeasurementsScreen();
                          },
                          width: double.infinity,
                          color: const Color(0xFF86A8FF),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.straighten_rounded, size: 24),
                              const SizedBox(width: 12),
                              Text(context.tr('body_measurements')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Размытие снизу (iOS 26 стиль)
                BottomContentBlur(
                  blurHeight: 100.0,
                  maxBlurIntensity: 6.0,
                  overlayColor: Colors.black,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
