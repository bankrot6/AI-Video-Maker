class FriendConversationContext {
  final String mood;
  final String energy;
  final String responseLength;
  final String relationshipStyle;
  final String? lifeUpdate;

  const FriendConversationContext({
    required this.mood,
    required this.energy,
    required this.responseLength,
    required this.relationshipStyle,
    this.lifeUpdate,
  });
}
