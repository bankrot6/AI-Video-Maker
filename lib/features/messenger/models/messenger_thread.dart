import 'messenger_contact.dart';
import 'messenger_memory.dart';
import 'messenger_message.dart';

enum MessengerAiModel {
  chat,
  reasoner,
}

enum MessengerChatMode {
  text,
  image,
}

class MessengerPersona {
  final String id;
  final String title;
  final String description;
  final String systemPrompt;
  final List<String> autoReplies;
  final MessengerAiModel aiModel;
  final MessengerChatMode chatMode;

  const MessengerPersona({
    required this.id,
    required this.title,
    required this.description,
    required this.systemPrompt,
    required this.autoReplies,
    this.aiModel = MessengerAiModel.chat,
    this.chatMode = MessengerChatMode.text,
  });
}

class MessengerThread {
  final MessengerContact contact;
  final MessengerPersona persona;
  final MessengerMemory memory;
  final List<MessengerMessage> messages;
  final bool aiEnabled;

  MessengerThread({
    required this.contact,
    required this.persona,
    required this.memory,
    List<MessengerMessage>? messages,
    this.aiEnabled = true,
  }) : messages = messages ?? [];

  MessengerThread copyWith({
    MessengerContact? contact,
    MessengerPersona? persona,
    MessengerMemory? memory,
    List<MessengerMessage>? messages,
    bool? aiEnabled,
  }) {
    return MessengerThread(
      contact: contact ?? this.contact,
      persona: persona ?? this.persona,
      memory: memory ?? this.memory,
      messages: messages ?? this.messages,
      aiEnabled: aiEnabled ?? this.aiEnabled,
    );
  }

  DateTime get lastUpdated {
    if (messages.isNotEmpty) {
      return messages.last.time;
    }
    return memory.updatedAt;
  }
}
