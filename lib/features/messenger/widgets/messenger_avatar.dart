import 'package:flutter/material.dart';
import 'package:loading_indicator/loading_indicator.dart';

class MessengerAvatar extends StatelessWidget {
  final double size;
  final ImageProvider? image;
  final Color backgroundColor;
  final String initials;
  final TextStyle? initialsStyle;
  final Alignment imageAlignment;
  final bool isLoading;

  const MessengerAvatar({
    super.key,
    required this.size,
    required this.backgroundColor,
    required this.initials,
    this.image,
    this.initialsStyle,
    this.imageAlignment = const Alignment(0, -0.65),
    this.isLoading = false,
  });

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
    final style = initialsStyle ??
        TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.38,
        );
    final indicatorSize = size * 0.6;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: isLoading
            ? ColoredBox(
                color: backgroundColor,
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
            : image == null
                ? ColoredBox(
                    color: backgroundColor,
                    child: Center(
                      child: Text(
                        initials,
                        style: style,
                      ),
                    ),
                  )
                : ColoredBox(
                    color: backgroundColor,
                    child: Image(
                      image: image!,
                      fit: BoxFit.cover,
                      alignment: imageAlignment,
                    ),
                  ),
      ),
    );
  }
}
