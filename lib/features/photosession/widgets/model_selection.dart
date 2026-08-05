import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/credit_config.dart';
import '../../../models/photosession_provider.dart';
import '../../subscription/subscription_providers.dart';
import '../theme/photosession_palette.dart';

/// Иконка модели генерации: одна на всё приложение, чтобы список моделей и
/// кнопка выбора не расходились.
IconData photosessionProviderIcon(PhotosessionProvider provider) {
  switch (provider) {
    case PhotosessionProvider.veoLite:
      return Icons.flash_on_rounded;
    case PhotosessionProvider.veoFast:
      return Icons.bolt_rounded;
    case PhotosessionProvider.veoPro:
      return Icons.rocket_launch_rounded;
    case PhotosessionProvider.veoFastPreview:
      return Icons.auto_awesome_rounded;
    case PhotosessionProvider.veoPro4k:
      return Icons.diamond_rounded;
  }
}

/// Кнопка с текущей моделью, открывающая список выбора.
class ModelSelectorButton extends StatelessWidget {
  const ModelSelectorButton({
    super.key,
    required this.selected,
    required this.onPressed,
  });

  final PhotosessionProvider selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = PhotosessionPalette.of(context);
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 54),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        backgroundColor: palette.surfaceHigh.withValues(alpha: 0.45),
        foregroundColor: palette.accent,
        disabledForegroundColor: palette.textSecondary,
        side: BorderSide(color: palette.accentMuted, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            photosessionProviderIcon(selected),
            size: 22,
            color: palette.accent,
          ),
          const SizedBox(width: 10),
          Text(
            selected.label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            color: palette.textSecondary,
            size: 20,
          ),
        ],
      ),
    );
  }
}

/// Показывает список доступных моделей и возвращает выбранную.
///
/// `null` означает, что пользователь закрыл лист без выбора.
Future<PhotosessionProvider?> showModelSelectionSheet({
  required BuildContext context,
  required PhotosessionProvider selected,
}) {
  final colors = Theme.of(context).colorScheme;
  return showModalBottomSheet<PhotosessionProvider>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SafeArea(
          child: _ModelSelectionList(selected: selected),
        ),
      ),
    ),
  );
}

class _ModelSelectionList extends ConsumerWidget {
  const _ModelSelectionList({required this.selected});

  final PhotosessionProvider selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final hasPaidSubscription =
        ref.watch(subscriptionProvider).valueOrNull?.isPaidUser ?? false;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 4),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: colors.onSurface.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Icon(
                Icons.auto_awesome_mosaic_rounded,
                color: colors.primary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Text(
                'Выберите модель генерации',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: PhotosessionProvider.values
                  .where((provider) => provider.isAvailable)
                  .map(
                    (provider) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ModelTile(
                        provider: provider,
                        isSelected: provider == selected,
                        isLocked: !CreditCost.isTierAccessible(
                          provider.creditTier,
                          hasPaidSubscription: hasPaidSubscription,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.provider,
    required this.isSelected,
    required this.isLocked,
  });

  final PhotosessionProvider provider;
  final bool isSelected;
  final bool isLocked;

  void _onTap(BuildContext context) {
    if (isLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Модель доступна только подписчикам'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    Navigator.pop(context, provider);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = PhotosessionPalette.of(context);
    final highlighted = isSelected && !isLocked;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onTap(context),
        borderRadius: BorderRadius.circular(16),
        child: Opacity(
          opacity: isLocked ? 0.5 : 1.0,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: highlighted
                    ? colors.primary
                    : colors.outline.withValues(alpha: 0.2),
                width: highlighted ? 2.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color:
                        colors.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isLocked
                        ? Icons.lock_rounded
                        : photosessionProviderIcon(provider),
                    size: 24,
                    color: highlighted
                        ? colors.primary
                        : colors.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              provider.label,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (provider.sourceBadge != null) ...[
                            _Badge(
                              text: provider.sourceBadge!,
                              background:
                                  palette.accent.withValues(alpha: 0.16),
                              foreground: palette.accent,
                            ),
                            const SizedBox(width: 6),
                          ],
                          _Badge(
                            text: isLocked ? 'PRO' : provider.price,
                            background: isLocked
                                ? colors.outline.withValues(alpha: 0.1)
                                : colors.primary.withValues(alpha: 0.12),
                            foreground:
                                isLocked ? colors.outline : colors.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isLocked
                            ? 'Доступна с подпиской PRO'
                            : provider.description,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: colors.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
                if (highlighted)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: colors.primary,
                      size: 24,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}
