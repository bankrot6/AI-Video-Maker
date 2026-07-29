import 'package:flutter/material.dart';
import '../../services/localization/app_localization_service.dart';
import '../rtl_wrapper.dart';

class FullScreenTextEditorScreen extends StatefulWidget {
  const FullScreenTextEditorScreen({
    super.key,
    required this.title,
    required this.initialText,
    this.hintText = '',
    this.keyboardType = TextInputType.multiline,
    this.maxLines,
    this.trimOnSave = true,
  });

  final String title;
  final String initialText;
  final String hintText;
  final TextInputType keyboardType;
  final int? maxLines;
  final bool trimOnSave;

  static Future<String?> open(
    BuildContext context, {
    required String title,
    required String initialText,
    String hintText = '',
    TextInputType keyboardType = TextInputType.multiline,
    int? maxLines,
    bool trimOnSave = true,
  }) {
    return Navigator.of(context).push<String?>(
      MaterialPageRoute<String?>(
        fullscreenDialog: true,
        builder: (context) => FullScreenTextEditorScreen(
          title: title,
          initialText: initialText,
          hintText: hintText,
          keyboardType: keyboardType,
          maxLines: maxLines,
          trimOnSave: trimOnSave,
        ),
      ),
    );
  }

  @override
  State<FullScreenTextEditorScreen> createState() =>
      _FullScreenTextEditorScreenState();
}

class _FullScreenTextEditorScreenState extends State<FullScreenTextEditorScreen> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  bool get _multiline =>
      widget.maxLines == null || (widget.maxLines != null && widget.maxLines! > 1);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _save() {
    final raw = _controller.text;
    final text = widget.trimOnSave ? raw.trim() : raw;
    Navigator.of(context).pop(text);
  }

  InputDecoration _decoration(BuildContext context, ColorScheme colors) {
    final borderRadius = BorderRadius.circular(12);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      hintText: widget.hintText.isEmpty ? null : widget.hintText,
      filled: true,
      fillColor: colors.surfaceContainerHighest.withValues(
        alpha: isDark ? 0.35 : 0.65,
      ),
      border: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: colors.outline.withValues(alpha: 0.25)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: colors.outline.withValues(alpha: 0.25)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: colors.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.all(16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final fieldStyle = TextStyle(
      fontSize: 16,
      height: 1.45,
      color: colors.onSurface,
    );

    final textField = TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      textInputAction:
          _multiline ? TextInputAction.newline : TextInputAction.done,
      onSubmitted: _multiline ? null : (_) => _save(),
      maxLines: _multiline ? null : 1,
      minLines: _multiline ? null : 1,
      expands: _multiline,
      textAlignVertical: TextAlignVertical.top,
      textDirection: context.textDirection,
      textAlign: context.isRTL ? TextAlign.right : TextAlign.left,
      style: fieldStyle,
      decoration: _decoration(context, colors),
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        ),
        title: LayoutBuilder(
          builder: (context, constraints) {
            final titleStyle = theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ) ??
                TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                );
            final maxW = constraints.maxWidth;
            if (!maxW.isFinite || maxW <= 0) {
              return Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              );
            }
            return Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(
                width: maxW,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    softWrap: false,
                    style: titleStyle,
                  ),
                ),
              ),
            );
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonal(
              onPressed: _save,
              child: Text(context.tr('text_editing_save')),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: _multiline
              ? SizedBox.expand(child: textField)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [textField],
                ),
        ),
      ),
    );
  }
}
