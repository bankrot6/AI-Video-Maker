import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/localization/app_localization_service.dart';
import '../rtl_wrapper.dart';

/// Результат редактирования ингредиента
class IngredientEditResult {
  final String? newName;
  final double? newWeight;
  final bool deleted;

  const IngredientEditResult({
    this.newName,
    this.newWeight,
    this.deleted = false,
  });
}

/// Bottom sheet для редактирования ингредиента (имя/вес) или удаления
class IngredientEditingBottomSheet extends StatefulWidget {
  final String initialName;
  final double initialWeight;

  const IngredientEditingBottomSheet({
    super.key,
    required this.initialName,
    required this.initialWeight,
  });

  static Future<IngredientEditResult?> show({
    required BuildContext context,
    required String name,
    required double weight,
  }) {
    return showModalBottomSheet<IngredientEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: IngredientEditingBottomSheet(
            initialName: name,
            initialWeight: weight,
          ),
        );
      },
    );
  }

  @override
  State<IngredientEditingBottomSheet> createState() =>
      _IngredientEditingBottomSheetState();
}

class _IngredientEditingBottomSheetState
    extends State<IngredientEditingBottomSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _weightController;
  final FocusNode _nameFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _weightController = TextEditingController(
      text: widget.initialWeight.toStringAsFixed(1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _nameFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _weightController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _onDelete() {
    Navigator.of(context).pop(const IngredientEditResult(deleted: true));
  }

  void _onDone() {
    final String name = _nameController.text.trim();
    final String weightRaw = _weightController.text.trim().replaceAll(',', '.');
    if (name.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    double? weight;
    try {
      weight = double.parse(weightRaw);
    } catch (_) {
      // Если парсинг не удался, просто не сохраняем
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(
      IngredientEditResult(newName: name, newWeight: weight),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 0,
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.initialName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Имя ингредиента
            TextField(
              controller: _nameController,
              focusNode: _nameFocus,
              textDirection: context.textDirection,
              textAlign: context.isRTL ? TextAlign.right : TextAlign.left,
              decoration: InputDecoration(
                hintText: context.tr('enter_food_name'),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            // Вес ингредиента
            TextField(
              controller: _weightController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                hintText: context.tr('weight'),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(12),
                suffixText: context.tr('grams_suffix'),
              ),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            // Удаление ингредиента
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _onDelete,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: Text(
                  context.tr('delete'),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(context.tr('cancel')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _onDone,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(context.tr('done')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
