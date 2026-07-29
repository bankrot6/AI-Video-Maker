import 'package:flutter/material.dart';

import '../models/messenger_contact.dart';
import '../models/messenger_memory.dart';
import '../models/messenger_message.dart';
import '../models/messenger_thread.dart';
import '../models/friend_profile.dart';

class MessengerSeedData {
  final FriendProfile? friendProfile;

  const MessengerSeedData({this.friendProfile});

  List<MessengerThread> buildThreads() {
    final now = DateTime.now();
    final profile = friendProfile;

    final savedContact = MessengerContact(
      id: 'saved_messages',
      name: 'Избранное',
      status: 'личное',
      initials: 'И',
      avatarColor: const Color(0xFF607D8B),
    );
    final savedPersona = MessengerPersona(
      id: 'saved_messages',
      title: 'избранное',
      description: 'Сохраненные сообщения пользователя.',
      systemPrompt: '',
      autoReplies: const [],
    );
    final savedMessages = <MessengerMessage>[];
    final savedMemory = MessengerMemory(
      summary: 'Личные сохраненные сообщения.',
      updatedAt: now,
    );

    final friendThread = buildFriendThread(
      contactId: 'friend',
      profile: profile,
      now: now,
    );

    return [
      MessengerThread(
        contact: savedContact,
        persona: savedPersona,
        memory: savedMemory,
        messages: savedMessages,
        aiEnabled: false,
      ),
      friendThread,
    ];
  }

  String _id(DateTime now, String suffix) {
    return '${now.microsecondsSinceEpoch}-$suffix';
  }

  MessengerThread buildFriendThread({
    required String contactId,
    FriendProfile? profile,
    DateTime? now,
  }) {
    final createdAt = now ?? DateTime.now();
    final friendName = _resolveFriendName(profile);
    final friendInitials = _initials(friendName);
    final friendDetails =
        profile == null ? 'не указаны' : _buildFriendDetails(profile);
    final isRomantic = profile?.isRomantic ?? false;
    final friendRoleLabel =
        isRomantic ? 'ИИ-партнер пользователя' : 'ИИ-друг пользователя';
    final friendSystemPrompt = profile == null
        ? 'Ты Друг, близкий друг пользователя. Общайся дружелюбно, иногда с легким юмором. '
            'Говори коротко и по делу, поддерживай инициативу пользователя.'
        : 'Ты $friendName, $friendRoleLabel. '
            'Внешность и параметры: $friendDetails. '
            '${isRomantic ? 'Общайся чувственно, с легким флиртом и вниманием к желаниям пользователя.' : 'Общайся поддерживающе, с эмпатией и дружеской теплотой.'} '
            'Говори коротко и по делу, поддерживай инициативу пользователя.';
    final contact = MessengerContact(
      id: contactId,
      name: friendName,
      status: 'в сети',
      initials: friendInitials,
      avatarColor: _resolveFriendColor(contactId),
      avatarPath: profile?.avatarPath,
      isAvatarGenerating: profile?.isAvatarGenerating ?? false,
    );
    final persona = MessengerPersona(
      id: contactId,
      title: isRomantic ? 'отношения' : 'друг',
      description: profile == null
          ? 'Близкий друг, с которым легко общаться на "ты".'
          : isRomantic
              ? 'ИИ-партнер пользователя, романтичные отношения.'
              : 'ИИ-друг пользователя с заданными параметрами.',
      systemPrompt: friendSystemPrompt,
      autoReplies: const [
        'Бери воду и протеин, ок?',
        'Что у тебя нового?',
        'Как вообще настроение?',
      ],
      aiModel: _resolveAiModel(profile?.aiModel),
    );
    final friendMessages = [
      MessengerMessage(
        id: _id(createdAt, 'f1'),
        text: 'Привет, как дела?',
        time: createdAt.subtract(const Duration(minutes: 6)),
        isMine: false,
      ),
    ];
    final friendMemory = MessengerMemory(
      summary: 'Кто это: $friendName, $friendRoleLabel.',
      updatedAt: friendMessages.last.time,
    );
    return MessengerThread(
      contact: contact,
      persona: persona,
      memory: friendMemory,
      messages: friendMessages,
    );
  }

  String _resolveFriendName(FriendProfile? profile) {
    final name = profile?.name.trim() ?? '';
    return name.isEmpty ? 'Друг' : name;
  }

  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Д';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return _firstChar(parts.first).toUpperCase();
    }
    final first = _firstChar(parts.first).toUpperCase();
    final second = _firstChar(parts[1]).toUpperCase();
    return '$first$second';
  }

  String _firstChar(String value) {
    if (value.isEmpty) return '';
    return String.fromCharCode(value.runes.first);
  }

  MessengerAiModel _resolveAiModel(String? value) {
    return MessengerAiModel.chat;
  }

  Color _resolveFriendColor(String contactId) {
    if (contactId == 'friend') {
      return const Color(0xFF4C9AFF);
    }
    const palette = [
      Color(0xFF4C9AFF),
      Color(0xFF7E57C2),
      Color(0xFF26A69A),
      Color(0xFFFF7043),
      Color(0xFFEC407A),
      Color(0xFF5C6BC0),
      Color(0xFF8D6E63),
      Color(0xFF26C6DA),
    ];
    var hash = 0;
    for (final unit in contactId.codeUnits) {
      hash = (hash + unit) & 0x7fffffff;
    }
    return palette[hash % palette.length];
  }

  String _buildFriendDetails(FriendProfile? profile) {
    if (profile == null) return 'не указаны';
    final gender = profile.gender == 'female' ? 'женщина' : 'мужчина';
    final hair = _mapHair(profile.hairColor, profile.gender);
    final eyes = _mapEyes(profile.eyeColor);
    return 'пол: $gender, возраст: ${profile.age}, волосы: $hair, глаза: $eyes';
  }

  String _mapHair(String value, String gender) {
    switch (value) {
      case 'blonde':
        return gender == 'female' ? 'блондинка' : 'блондин';
      case 'brunette':
        return gender == 'female' ? 'брюнетка' : 'брюнет';
      case 'red':
        return gender == 'female' ? 'рыжая' : 'рыжий';
      default:
        return value;
    }
  }

  String _mapEyes(String value) {
    switch (value) {
      case 'blue':
        return 'голубые';
      case 'green':
        return 'зелёные';
      case 'brown':
        return 'карие';
      case 'gray':
        return 'серые';
      default:
        return value;
    }
  }
}
