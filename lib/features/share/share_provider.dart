import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'share_screen_manager.dart';

/// Провайдер для менеджера скриншотов (единый экземпляр на все дерево)
final shareScreenManagerProvider = Provider<ShareScreenManager>(
  (ref) => ShareScreenManager(ref),
);
