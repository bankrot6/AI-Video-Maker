import 'package:flutter/material.dart';
import 'full_screen_text_editor_screen.dart';

export 'full_screen_text_editor_screen.dart' show FullScreenTextEditorScreen;

class TextEditingBottomSheet {
  static Future<void> show({
    required BuildContext context,
    required String initialText,
    required String title,
    required String hintText,
    required void Function(String) onSave,
    TextInputType keyboardType = TextInputType.text,
    int? maxLines = 1,
  }) async {
    final result = await FullScreenTextEditorScreen.open(
      context,
      title: title,
      initialText: initialText,
      hintText: hintText,
      keyboardType: keyboardType,
      maxLines: maxLines,
    );
    if (result != null) {
      onSave(result);
    }
  }
}
