import 'package:flutter/material.dart';

class MessengerContact {
  final String id;
  final String name;
  final String status;
  final String initials;
  final Color avatarColor;
  final String? avatarPath;
  final bool isAvatarGenerating;

  const MessengerContact({
    required this.id,
    required this.name,
    required this.status,
    required this.initials,
    required this.avatarColor,
    this.avatarPath,
    this.isAvatarGenerating = false,
  });

  MessengerContact copyWith({
    String? id,
    String? name,
    String? status,
    String? initials,
    Color? avatarColor,
    String? avatarPath,
    bool? isAvatarGenerating,
  }) {
    return MessengerContact(
      id: id ?? this.id,
      name: name ?? this.name,
      status: status ?? this.status,
      initials: initials ?? this.initials,
      avatarColor: avatarColor ?? this.avatarColor,
      avatarPath: avatarPath ?? this.avatarPath,
      isAvatarGenerating: isAvatarGenerating ?? this.isAvatarGenerating,
    );
  }
}
