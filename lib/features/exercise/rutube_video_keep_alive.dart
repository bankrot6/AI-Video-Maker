import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class RutubeVideoKeepAlive extends StatefulWidget {
  final String videoId;
  final bool isActive;
  const RutubeVideoKeepAlive(
      {super.key, required this.videoId, required this.isActive});

  @override
  State<RutubeVideoKeepAlive> createState() => _RutubeVideoKeepAliveState();
}

class _RutubeVideoKeepAliveState extends State<RutubeVideoKeepAlive> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    // iOS: включаем inline-проигрывание и разрешаем воспроизведение без жестов
    final PlatformWebViewControllerCreationParams params =
        WebKitWebViewControllerCreationParams(
      allowsInlineMediaPlayback: true,
      mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
    );

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..loadRequest(Uri.parse(
          'https://rutube.ru/play/embed/${widget.videoId}?autoplay=0'));
  }

  @override
  void didUpdateWidget(covariant RutubeVideoKeepAlive oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Если слайд стал неактивным — ставим плеер на паузу внутри WebView
    if (oldWidget.isActive && !widget.isActive) {
      _pauseInsideWebView();
    }
    // Держим WebView живым; не пересоздаём и не перезагружаем при переключениях
  }

  @override
  void dispose() {
    // На всякий случай пытаемся поставить на паузу перед уничтожением
    _pauseInsideWebView();
    super.dispose();
  }

  void _pauseInsideWebView() {
    try {
      _controller.runJavaScript(
          "document.querySelectorAll('video').forEach(v=>{try{v.pause();}catch(e){}});");
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Offstage(
      offstage: !widget.isActive,
      child: WebViewWidget(
        key: ValueKey('rutube_${widget.videoId}'),
        controller: _controller,
      ),
    );
  }
}
