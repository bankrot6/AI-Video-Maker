import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import '../utils/navigation.dart';
import '../features/subscription/subscription_providers.dart';
import '../services/localization/app_localization_service.dart';
import 'banner_limit_provider.dart';

/// Виджет для отображения баннера бесплатного периода на главном экране
class PremiumTrialBanner extends ConsumerStatefulWidget {
  /// Основной цвет баннера
  final Color primaryColor;

  /// Скругление углов баннера
  final double borderRadius;

  const PremiumTrialBanner({
    super.key,
    this.primaryColor =
        const Color(0xFF655BBB), // Фиолетовый цвет из приложения
    this.borderRadius = 12.0,
  });

  @override
  ConsumerState<PremiumTrialBanner> createState() => _PremiumTrialBannerState();
}

class _PremiumTrialBannerState extends ConsumerState<PremiumTrialBanner> {
  bool _didInitialize = false;
  String _displayedText = '';
  bool _isTyping = false;
  Timer? _typingTimer;
  Timer? _delayTimer;
  int _currentCharIndex = 0;
  String _targetText = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInitialize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(subscriptionProvider.notifier).refreshSubscription();
        debugPrint('🔄 PremiumTrialBanner: Обновление статуса подписки');

        // Инициализируем начальный текст
        _displayedText = context.tr('premium_banner_short');
        _targetText = _displayedText;
      });
      _didInitialize = true;
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _delayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Слушаем изменения состояния лимита
    ref.listen<BannerLimitState>(
      bannerLimitProvider,
      (previous, next) {
        debugPrint(
            '🎯 BANNER_LIMIT: Изменение состояния - showingLimit=${next.showingLimit}, count=${next.remainingCount}');
        if (next.showingLimit && !(previous?.showingLimit ?? false)) {
          debugPrint(
              '🎯 BANNER_LIMIT: Условие выполнено, вызываем _showLimitText');
          // Показываем текст лимита
          _showLimitText(next.remainingCount);
        }
      },
    );

    return _buildBanner(context);
  }

  /// Показывает текст о лимите с эффектом печатанья
  void _showLimitText(int remainingCount) {
    debugPrint(
        '🎯 BANNER_LIMIT: _showLimitText вызван с remainingCount=$remainingCount');
    if (_isTyping) {
      debugPrint('🎯 BANNER_LIMIT: Уже печатается, пропускаем');
      return;
    }

    final limitText = _buildLimitTextString(remainingCount);
    final originalText = context.tr('premium_banner_short');

    debugPrint('🎯 BANNER_LIMIT: limitText="$limitText"');
    debugPrint('🎯 BANNER_LIMIT: originalText="$originalText"');

    // Останавливаем текущие таймеры
    _typingTimer?.cancel();
    _delayTimer?.cancel();

    // Печатаем текст лимита
    _typeText(limitText, () {
      // После печати ждем 3 секунды
      _delayTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          // Возвращаемся к основному тексту
          _typeText(originalText, () {
            if (mounted) {
              ref.read(bannerLimitProvider.notifier).hideLimit();
            }
          });
        }
      });
    });
  }

  /// Создает текст о лимите в зависимости от количества
  String _buildLimitTextString(int count) {
    if (count == 0) {
      return context.tr('no_free_requests_left');
    } else if (count == 1) {
      return context.tr('one_free_request_left');
    } else if (count >= 2 && count <= 4) {
      return context.trParams('few_free_requests_left', [count.toString()]);
    } else {
      return context.trParams('many_free_requests_left', [count.toString()]);
    }
  }

  /// Печатает текст с эффектом печатной машинки
  void _typeText(String targetText, VoidCallback onComplete) {
    if (!mounted) return;

    setState(() {
      _isTyping = true;
      _targetText = targetText;
      _currentCharIndex = 0;
      _displayedText = '';
    });

    const typingSpeed = Duration(milliseconds: 30);

    _typingTimer = Timer.periodic(typingSpeed, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_currentCharIndex < _targetText.length) {
        setState(() {
          _currentCharIndex++;
          _displayedText = _targetText.substring(0, _currentCharIndex);
        });
      } else {
        timer.cancel();
        setState(() {
          _isTyping = false;
        });
        onComplete();
      }
    });
  }

  /// Построение UI баннера
  Widget _buildBanner(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.showPaywall(),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            color: widget.primaryColor.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: widget.primaryColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.workspace_premium_rounded,
                color: widget.primaryColor,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _displayedText.isEmpty
                        ? context.tr('premium_banner_short')
                        : _displayedText,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: widget.primaryColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
