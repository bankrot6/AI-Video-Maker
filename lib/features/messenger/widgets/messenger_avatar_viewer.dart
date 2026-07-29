import 'dart:io';

import 'package:flutter/material.dart';
import 'package:loading_indicator/loading_indicator.dart';

import '../models/messenger_contact.dart';

String messengerAvatarHeroTag(MessengerContact contact) =>
    'messenger-avatar-${contact.id}';

class MessengerAvatarViewer extends StatelessWidget {
  final MessengerContact contact;

  const MessengerAvatarViewer({
    super.key,
    required this.contact,
  });

  ImageProvider? _resolveAvatarImage() {
    final path = contact.avatarPath;
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return FileImage(file);
  }

  List<Color> _loadingColors(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return [
      colors.primary.withOpacity(0.55),
      colors.secondary.withOpacity(0.45),
      colors.onSurface.withOpacity(0.3),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final avatarImage = _resolveAvatarImage();
    final indicatorSize = (MediaQuery.of(context).size.shortestSide * 0.35)
        .clamp(72.0, 160.0)
        .toDouble();
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.35),
        elevation: 0,
        title: Text(
          contact.name,
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close, color: Colors.white),
        ),
      ),
      body: Hero(
        tag: messengerAvatarHeroTag(contact),
        child: SizedBox.expand(
          child: avatarImage == null
              ? (contact.isAvatarGenerating
                  ? ColoredBox(
                      color: contact.avatarColor,
                      child: Center(
                        child: SizedBox(
                          width: indicatorSize,
                          height: indicatorSize,
                          child: LoadingIndicator(
                            indicatorType: Indicator.ballScaleMultiple,
                            colors: _loadingColors(context),
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      ),
                    )
                  : ColoredBox(
                      color: contact.avatarColor,
                      child: Center(
                        child: Text(
                          contact.initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 56,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ))
              : Image(
                  image: avatarImage,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                ),
        ),
      ),
    );
  }
}
