import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../analysis/food_analysis_screen.dart';
import '../../widgets/loading/loading_manager.dart';
import '../../services/localization/app_localization_service.dart';
import '../analysis/analysis_providers.dart' as analysis;
import '../../utils/file_utils.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  final bool _isRearCameraSelected = true;
  // Визуальное состояние вспышки не используется в текущем UX
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Немедленно открываем системную камеру, не дожидаясь построения интерфейса
    _getImageFromCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    // Скрываем экран загрузки при уничтожении экрана, если он был показан
    try {
      LoadingManager().hideLoadingScreen();
    } catch (e) {
      debugPrint('❌ Ошибка при скрытии экрана загрузки в dispose: $e');
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    // убрали локальный флаг загрузки — используем экран загрузки

    // Показываем экран загрузки
    try {
      LoadingManager().showLoadingScreen(
        context,
        text: context.tr('initializing_camera'),
        animationPath: 'assets/animations/road.json',
        animationHeight: MediaQuery.of(context).size.height * 0.4,
        backgroundColor: Colors.white,
        processingStepText: context.tr('preparing_image'),
        progressValue: 0.1,
      );
    } catch (e) {
      debugPrint('❌ Ошибка при показе экрана загрузки: $e');
    }

    try {
      _cameras = await availableCameras();

      if (_cameras != null && _cameras!.isNotEmpty) {
        final camera = _isRearCameraSelected
            ? _cameras!.firstWhere(
                (camera) => camera.lensDirection == CameraLensDirection.back,
                orElse: () => _cameras!.first,
              )
            : _cameras!.firstWhere(
                (camera) => camera.lensDirection == CameraLensDirection.front,
                orElse: () => _cameras!.first,
              );

        // Обновление текста без отдельной задержки
        if (mounted) {
          try {
            LoadingManager().updateProcessingInfo(
              context,
              newText: context.tr('setting_camera_params'),
              newProcessingStep: context.tr('recognizing_objects'),
              newProgressValue: 0.3,
              animationPath: 'assets/animations/road.json',
              animationHeight: MediaQuery.of(context).size.height * 0.4,
            );
          } catch (e) {
            debugPrint('❌ Ошибка при обновлении экрана загрузки: $e');
          }
        }

        _cameraController = CameraController(
          camera,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );

        await _cameraController!.initialize();

        if (mounted) {
          // камера инициализирована

          // Скрываем экран загрузки
          try {
            LoadingManager().hideLoadingScreen();
          } catch (e) {
            debugPrint('❌ Ошибка при скрытии экрана загрузки: $e');
          }
        }
      } else {
        if (mounted) {
          // завершили попытку инициализации

          // Скрываем экран загрузки
          try {
            LoadingManager().hideLoadingScreen();
          } catch (e) {
            debugPrint('❌ Ошибка при скрытии экрана загрузки: $e');
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('camera_not_available'))),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        // завершили попытку инициализации с ошибкой

        // Скрываем экран загрузки
        try {
          LoadingManager().hideLoadingScreen();
        } catch (error) {
          debugPrint('❌ Ошибка при скрытии экрана загрузки: $error');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context.trParams('camera_init_error', ['$e']))),
        );
      }
    }
  }

  Future<void> _getImageFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (image != null) {
        // Сохраняем копию изображения в папке приложения
        final directory = await getApplicationDocumentsDirectory();
        final fileName = FileUtils.generateFoodImageFileName(source: 'camera');
        final savedImage = File(path.join(directory.path, fileName));

        await File(image.path).copy(savedImage.path);
        if (!mounted) return;

        // Устанавливаем провайдеры и сразу переходим на экран анализа
        ref.read(analysis.nutritionAnalysisStateProvider.notifier).state =
            const AsyncValue.loading();
        ref.read(analysis.lastAnalysisResultsProvider.notifier).state = null;
        ref.read(analysis.selectedImageProvider.notifier).state = savedImage;

        // локальная загрузка не используется

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const FoodAnalysisScreen(),
          ),
        );
      } else if (mounted) {
        // Пользователь отменил выбор - возвращаемся на предыдущий экран
        Navigator.of(context).pop();
      }
    } catch (e) {
      // Показываем экран загрузки только при ошибке
      LoadingManager().showLoadingScreen(
        context,
        text: context.tr('camera_error'),
        animationPath: 'assets/animations/road.json',
        animationHeight: MediaQuery.of(context).size.height * 0.4,
        backgroundColor: Colors.white,
        processingStepText: context.tr('camera_error_step'),
        progressValue: 1.0,
      );

      // Задержка для отображения сообщения об ошибке
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        // Скрываем экран загрузки
        try {
          LoadingManager().hideLoadingScreen();
        } catch (e) {
          debugPrint(
              '❌ Ошибка при скрытии экрана загрузки в обработке ошибки getImageFromCamera: $e');
        }

        // Стандартное сообщение об ошибке в том же формате
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.trParams('camera_photo_error', ['$e']),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );

        Navigator.of(context)
            .pushNamedAndRemoveUntil('/home', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}

class GuidelinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Рисуем круг в центре
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.4;
    canvas.drawCircle(center, radius, paint);

    // Рисуем прямоугольную рамку
    final rect = Rect.fromCenter(
      center: center,
      width: size.width * 0.8,
      height: size.width * 0.8,
    );
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
