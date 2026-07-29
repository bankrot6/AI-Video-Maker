import 'package:flutter/material.dart';

class FriendPersonaSectionTitle extends StatelessWidget {
  final String text;

  const FriendPersonaSectionTitle({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class FriendPersonaSingleLineField extends StatelessWidget {
  final String hintText;
  final TextEditingController controller;
  final TextInputAction textInputAction;

  const FriendPersonaSingleLineField({
    super.key,
    required this.hintText,
    required this.controller,
    this.textInputAction = TextInputAction.next,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E1E6)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: TextField(
        controller: controller,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: textInputAction,
        decoration: InputDecoration(
          hintText: hintText,
          border: InputBorder.none,
          hintStyle: TextStyle(
            color: Colors.black.withOpacity(0.35),
          ),
        ),
      ),
    );
  }
}

class FriendPersonaMultiLineField extends StatelessWidget {
  final String hintText;
  final TextEditingController controller;
  final int minLines;
  final int maxLines;

  const FriendPersonaMultiLineField({
    super.key,
    required this.hintText,
    required this.controller,
    this.minLines = 2,
    this.maxLines = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E1E6)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: hintText,
          border: InputBorder.none,
          hintStyle: TextStyle(
            color: Colors.black.withOpacity(0.35),
          ),
        ),
      ),
    );
  }
}
