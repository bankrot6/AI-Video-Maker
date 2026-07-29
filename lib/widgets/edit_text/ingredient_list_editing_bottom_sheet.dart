import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/ingredient.dart';
import '../../services/localization/app_localization_service.dart';
import '../rtl_wrapper.dart';

/// Bottom sheet для пакетного редактирования ингредиентов
class IngredientListEditingBottomSheet extends StatefulWidget {
  final List<Ingredient> initialIngredients;

  const IngredientListEditingBottomSheet({
    super.key,
    required this.initialIngredients,
  });

  static Future<List<Ingredient>?> show({
    required BuildContext context,
    required List<Ingredient> ingredients,
  }) {
    return showModalBottomSheet<List<Ingredient>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: IngredientListEditingBottomSheet(
            initialIngredients: ingredients,
          ),
        );
      },
    );
  }

  @override
  State<IngredientListEditingBottomSheet> createState() =>
      _IngredientListEditingBottomSheetState();
}

class _IngredientListEditingBottomSheetState
    extends State<IngredientListEditingBottomSheet> {
  late List<_IngredientRow> _rows;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _rows = widget.initialIngredients
        .map((i) => _IngredientRow(
              nameController: TextEditingController(text: i.name),
              weightController:
                  TextEditingController(text: i.weight.toStringAsFixed(1)),
            ))
        .toList();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.nameController.dispose();
      r.weightController.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() {
      _rows.add(_IngredientRow(
        nameController: TextEditingController(),
        weightController: TextEditingController(text: '0'),
        nameFocus: FocusNode(),
      ));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      if (_rows.isNotEmpty) {
        _rows.last.nameFocus?.requestFocus();
      }
    });
  }

  void _removeRow(int index) {
    setState(() {
      _rows.removeAt(index);
    });
  }

  void _onCancel() {
    Navigator.of(context).pop();
  }

  void _onDone() {
    final List<Ingredient> result = [];
    for (final r in _rows) {
      final name = r.nameController.text.trim();
      if (name.isEmpty) continue;
      final weightRaw = r.weightController.text.trim().replaceAll(',', '.');
      final double? weight = double.tryParse(weightRaw);
      if (weight == null) continue;
      result.add(Ingredient(name: name, weight: weight, verified: true));
    }
    Navigator.of(context).pop(result);
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
                    context.tr('recognized_ingredients'),
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
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                controller: _scrollController,
                shrinkWrap: true,
                itemCount: _rows.length,
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: TextField(
                            controller: row.nameController,
                            focusNode: row.nameFocus,
                            textDirection: context.textDirection,
                            textAlign: context.isRTL
                                ? TextAlign.right
                                : TextAlign.left,
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
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 4,
                          child: TextField(
                            controller: row.weightController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]')),
                            ],
                            decoration: InputDecoration(
                              hintText: context.tr('weight'),
                              suffixText: context.tr('grams_suffix'),
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
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: () => _removeRow(index),
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          tooltip: context.tr('delete'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('add_ingredient')),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _onCancel,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: Theme.of(context).primaryColor,
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
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
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

class _IngredientRow {
  final TextEditingController nameController;
  final TextEditingController weightController;
  final FocusNode? nameFocus;

  _IngredientRow({
    required this.nameController,
    required this.weightController,
    this.nameFocus,
  });
}
