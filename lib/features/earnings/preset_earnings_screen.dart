import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/preset_earnings.dart';
import '../../models/photo_session_preset.dart';
import '../../services/preset_reward_service.dart';
import '../photosession/photosession_providers.dart';
import '../../widgets/preset_earnings_card.dart';

class PresetEarningsScreen extends ConsumerStatefulWidget {
  const PresetEarningsScreen({super.key});

  @override
  ConsumerState<PresetEarningsScreen> createState() =>
      _PresetEarningsScreenState();
}

class _PresetEarningsScreenState extends ConsumerState<PresetEarningsScreen> {
  bool _loading = true;
  bool _syncing = false;
  List<PresetEarnings> _earnings = [];
  Map<String, PhotoSessionPreset> _presets = {};
  Map<String, int> _stats = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);

    try {
      final rewardService = PresetRewardService();
      final earnings = await rewardService.getMyEarnings();
      final stats = await rewardService.getEarningsStats();

      final presetMap = <String, PhotoSessionPreset>{};
      if (earnings.isNotEmpty) {
        final repo = ref.read(showcaseRepositoryProvider);
        for (final earning in earnings) {
          final preset = await repo.getPresetById(earning.presetId);
          if (preset != null) {
            presetMap[earning.presetId] = preset;
          }
        }
      }

      if (mounted) {
        setState(() {
          _earnings = earnings;
          _presets = presetMap;
          _stats = stats;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('🔴 Ошибка загрузки данных о заработке: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _syncRewards() async {
    setState(() => _syncing = true);

    try {
      final newCredits = await PresetRewardService().syncEarnedCredits();

      if (mounted) {
        if (newCredits > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🎉 Начислено $newCredits кредитов за лайки!'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
          await _loadData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Нет новых кредитов для начисления'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка синхронизации: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои заработки'),
        actions: [
          IconButton(
            onPressed: _syncing ? null : _syncRewards,
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Синхронизировать',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _earnings.isEmpty
              ? _buildEmptyState(colors)
              : Column(
                  children: [
                    _buildStatsHeader(colors),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        itemCount: _earnings.length,
                        itemBuilder: (context, index) {
                          final earning = _earnings[index];
                          final preset = _presets[earning.presetId];
                          return PresetEarningsCard(
                            earnings: earning,
                            presetTitle: preset?.title,
                            presetImageUrl: preset?.thumbnailUrl ?? preset?.previewImageUrl,
                            onTap: () {
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildStatsHeader(ColorScheme colors) {
    final totalEarned = _stats['totalCreditsEarned'] ?? 0;
    final totalLikes = _stats['totalLikes'] ?? 0;
    final activePresets = _stats['activePresets'] ?? 0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.green.shade50,
            Colors.green.shade100,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.green.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.stars_rounded, color: Colors.amber.shade600, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Всего заработано',
                      style: TextStyle(
                        color: colors.onSurface.withOpacity(0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalEarned кредитов',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.favorite_rounded,
                  iconColor: Colors.pink.shade300,
                  label: 'Лайков',
                  value: '$totalLikes',
                  colors: colors,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.auto_awesome_rounded,
                  iconColor: Colors.purple.shade300,
                  label: 'Активных',
                  value: '$activePresets',
                  colors: colors,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required ColorScheme colors,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: colors.onSurface.withOpacity(0.6),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 80,
              color: colors.onSurfaceVariant.withOpacity(0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'Пока нет заработков',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Создайте публичный пресет и получайте\nкредиты за каждый лайк!\n\n1 лайк = 1 кредит\nМинимум 3 лайка для старта',
              style: TextStyle(
                fontSize: 14,
                color: colors.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Создать пресет'),
            ),
          ],
        ),
      ),
    );
  }
}
