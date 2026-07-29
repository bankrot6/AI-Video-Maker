import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum AppStoreDownloadVisualState {
  notDownloaded,
  downloading,
  downloaded,
  error,
}

class AppStoreDownloadButton extends StatelessWidget {
  final AppStoreDownloadVisualState state;
  final double progress; // 0..1
  final VoidCallback onTap;
  final VoidCallback? onCancel;
  final double size;

  const AppStoreDownloadButton({
    super.key,
    required this.state,
    required this.progress,
    required this.onTap,
    this.onCancel,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    final bg = Colors.black.withOpacity(0.06);
    final ring = const Color(0xFF007AFF);

    Widget icon;
    switch (state) {
      case AppStoreDownloadVisualState.notDownloaded:
        icon = const Icon(CupertinoIcons.cloud_download,
            size: 16, color: Color(0xFF007AFF));
        break;
      case AppStoreDownloadVisualState.downloading:
        icon = const Icon(CupertinoIcons.stop_fill,
            size: 12, color: Color(0xFF007AFF));
        break;
      case AppStoreDownloadVisualState.downloaded:
        icon = const Icon(CupertinoIcons.check_mark,
            size: 16, color: Color(0xFF007AFF));
        break;
      case AppStoreDownloadVisualState.error:
        icon = const Icon(CupertinoIcons.exclamationmark_triangle,
            size: 14, color: Color(0xFF007AFF));
        break;
    }

    final targetOnTap =
        state == AppStoreDownloadVisualState.downloading ? onCancel : onTap;

    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: targetOnTap,
        radius: size,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                ),
              ),
              if (state == AppStoreDownloadVisualState.downloading)
                SizedBox(
                  width: size,
                  height: size,
                  child: CircularProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    strokeWidth: 2.6,
                    backgroundColor: Colors.black.withOpacity(0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(ring),
                  ),
                )
              else if (state == AppStoreDownloadVisualState.downloaded ||
                  state == AppStoreDownloadVisualState.error)
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ring.withOpacity(0.85),
                      width: 2.2,
                    ),
                  ),
                ),
              icon,
            ],
          ),
        ),
      ),
    );
  }
}











