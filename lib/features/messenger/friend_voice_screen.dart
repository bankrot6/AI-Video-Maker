import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/android_system_ui_controller.dart';
import 'messenger_providers.dart';
import 'models/friend_profile.dart';
import 'services/messenger_voice_service.dart';

class FriendVoiceScreen extends ConsumerStatefulWidget {
  final String contactId;
  final String contactName;

  const FriendVoiceScreen({
    super.key,
    required this.contactId,
    required this.contactName,
  });

  @override
  ConsumerState<FriendVoiceScreen> createState() => _FriendVoiceScreenState();
}

class _FriendVoiceScreenState extends ConsumerState<FriendVoiceScreen>
    with WidgetsBindingObserver {
  static const double _speedMin = 0.7;
  static const double _speedMax = 1.2;
  static const double _speedDefault = 1.0;
  static const double _stabilityDefault = 0.5;
  static const double _similarityDefault = 0.75;

  List<VoiceSelectionItem>? _voiceItems;
  bool _voiceLoading = false;
  String? _selectedVoiceId;
  late double _speed;
  late double _stability;
  late double _similarity;
  bool _isSaving = false;
  bool _isPreviewPlaying = false;
  final AudioPlayer _previewPlayer = AudioPlayer();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AndroidSystemUiController.showNavigationBar();
    _speed = _speedDefault;
    _stability = _stabilityDefault;
    _similarity = _similarityDefault;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AndroidSystemUiController.hideNavigationBar();
    _previewPlayer.dispose();
    super.dispose();
  }

  void _applyProfile(FriendProfile? profile) {
    if (profile == null || _initialized) return;
    _initialized = true;
    _selectedVoiceId = profile.voiceId;
    _speed = (profile.voiceSpeed ?? _speedDefault).clamp(_speedMin, _speedMax);
    _stability = (profile.voiceStability ?? _stabilityDefault).clamp(0.0, 1.0);
    _similarity =
        (profile.voiceSimilarityBoost ?? _similarityDefault).clamp(0.0, 1.0);
  }

  Future<void> _loadVoices(FriendProfile? profile) async {
    if (_voiceLoading || _voiceItems != null) return;
    setState(() => _voiceLoading = true);
    final voiceService = ref.read(messengerVoiceServiceProvider);
    final list = await voiceService.getVoicesForSelection(profile);
    if (!mounted) return;
    setState(() {
      _voiceItems = list;
      _voiceLoading = false;
      if (_selectedVoiceId == null && profile?.voiceId != null) {
        _selectedVoiceId = profile!.voiceId;
      }
      if (list.isNotEmpty && _selectedVoiceId == null) {
        _selectedVoiceId = list.first.voiceId;
      }
    });
  }

  Future<void> _playPreview() async {
    if (_isPreviewPlaying || _selectedVoiceId == null) return;
    final profile = ref.read(friendProfileRepositoryProvider).load(widget.contactId);
    final previewProfile = profile?.copyWith(
      voiceId: _selectedVoiceId,
      voiceSpeed: _speed,
      voiceStability: _stability,
      voiceSimilarityBoost: _similarity,
    );
    final voiceService = ref.read(messengerVoiceServiceProvider);
    setState(() => _isPreviewPlaying = true);
    try {
      final result = await voiceService.previewVoice(
        voiceId: _selectedVoiceId!,
        profile: previewProfile,
      );
      if (!mounted) return;
      if (result.audioPath != null) {
        await _previewPlayer.play(DeviceFileSource(result.audioPath!));
        await _previewPlayer.onPlayerComplete.first;
      } else if (result.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.errorMessage!)),
        );
      }
    } finally {
      if (mounted) setState(() => _isPreviewPlaying = false);
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final profileRepo = ref.read(friendProfileRepositoryProvider);
    final profile = profileRepo.load(widget.contactId);
    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль друга не найден.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final updated = profile.copyWith(
        voiceId: _selectedVoiceId,
        voiceSpeed: _speed,
        voiceStability: _stability,
        voiceSimilarityBoost: _similarity,
      );
      await profileRepo.save(widget.contactId, updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Настройки голоса сохранены.')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileRepo = ref.read(friendProfileRepositoryProvider);
    final profile = profileRepo.load(widget.contactId);
    _applyProfile(profile);
    if (profile != null &&
        _voiceItems == null &&
        !_voiceLoading &&
        mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadVoices(profile));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text('Голос ${widget.contactName}'),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Сохранить'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            _buildVoiceSection(profile),
            const SizedBox(height: 24),
            _buildSliderSection(
              title: 'Скорость речи',
              value: _speed,
              min: _speedMin,
              max: _speedMax,
              divisions: 5,
              label: _speed.toStringAsFixed(1),
              onChanged: (v) => setState(() => _speed = v),
            ),
            const SizedBox(height: 20),
            _buildSliderSection(
              title: 'Стабильность голоса',
              subtitle: 'Меньше — больше эмоций, больше — ровнее',
              value: _stability,
              min: 0,
              max: 1,
              divisions: 10,
              label: (_stability * 100).round().toString(),
              onChanged: (v) => setState(() => _stability = v),
            ),
            const SizedBox(height: 20),
            _buildSliderSection(
              title: 'Сходство с оригиналом',
              subtitle: 'Ясность и близость к эталону голоса',
              value: _similarity,
              min: 0,
              max: 1,
              divisions: 10,
              label: (_similarity * 100).round().toString(),
              onChanged: (v) => setState(() => _similarity = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceSection(FriendProfile? profile) {
    if (_voiceLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          height: 48,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    final items = _voiceItems ?? [];
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE1E1E6)),
        ),
        child: Text(
          'Голоса недоступны. Проверьте настройки ElevenLabs.',
          style: TextStyle(
            fontSize: 13,
            color: Colors.black.withOpacity(0.6),
          ),
        ),
      );
    }
    final currentValue = _selectedVoiceId != null &&
            items.any((e) => e.voiceId == _selectedVoiceId)
        ? _selectedVoiceId
        : items.first.voiceId;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E1E6)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: currentValue,
                isExpanded: true,
                hint: const Text('Выберите голос'),
                items: items
                    .map((v) => DropdownMenuItem<String>(
                          value: v.voiceId,
                          child: Text(
                            v.displayName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (id) {
                  if (id != null) setState(() => _selectedVoiceId = id);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isPreviewPlaying || _selectedVoiceId == null
                ? null
                : _playPreview,
            icon: _isPreviewPlaying
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.volume_up),
            tooltip: 'Прослушать',
          ),
        ],
      ),
    );
  }

  Widget _buildSliderSection({
    required String title,
    String? subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required ValueChanged<double> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E1E6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black.withOpacity(0.6),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.black.withOpacity(0.5),
              ),
            ),
          ],
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
