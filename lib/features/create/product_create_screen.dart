import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/ingredient.dart';
import '../../widgets/edit_text/ingredient_list_editing_bottom_sheet.dart';
import '../../repositories/user_products_repository.dart';
import '../../services/localization/app_localization_service.dart';
import '../../models/favorite_meal_model.dart';
import '../../models/meal_model.dart';
import '../favorites/favorites_providers.dart';

// Поля нутриентов для редактирования
enum _CreateNutrientField { calories, proteins, fats, carbs }

class ProductCreateScreen extends StatefulWidget {
  final UserProduct? initialProduct;
  const ProductCreateScreen({super.key, this.initialProduct});

  @override
  State<ProductCreateScreen> createState() => _ProductCreateScreenState();
}

class _ProductCreateScreenState extends State<ProductCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _kcalCtrl = TextEditingController();
  final _pCtrl = TextEditingController();
  final _fCtrl = TextEditingController();
  final _cCtrl = TextEditingController();
  final List<Ingredient> _ingredients = <Ingredient>[];
  File? _image;
  String? _initialImagePath; // используется, если редактируем и фото не меняли
  bool _isFavorite = false;
  String? _createdProductId; // id черновика, если создали при нажатии звезды

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
        source: source, maxWidth: 1200, maxHeight: 1200, imageQuality: 85);
    if (x == null) return;
    setState(() => _image = File(x.path));
    _initialImagePath = null;
  }

  @override
  void initState() {
    super.initState();
    final p = widget.initialProduct;
    if (p != null) {
      _nameCtrl.text = p.name;
      _kcalCtrl.text = p.kcalPer100g.toStringAsFixed(0);
      _pCtrl.text = p.proteinsPer100g.toString();
      _fCtrl.text = p.fatsPer100g.toString();
      _cCtrl.text = p.carbsPer100g.toString();
      _initialImagePath = p.imagePath;
      _isFavorite = p.isFavorite;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // Валидация КБЖУ
    final String kcalRaw = _kcalCtrl.text.trim().replaceAll(',', '.');
    final String pRaw = _pCtrl.text.trim().replaceAll(',', '.');
    final String fRaw = _fCtrl.text.trim().replaceAll(',', '.');
    final String cRaw = _cCtrl.text.trim().replaceAll(',', '.');
    final double? kcal = double.tryParse(kcalRaw);
    final double proteins = double.tryParse(pRaw) ?? 0;
    final double fats = double.tryParse(fRaw) ?? 0;
    final double carbs = double.tryParse(cRaw) ?? 0;
    if (kcal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите калории')),
      );
      return;
    }

    String? localImagePath;
    if (_image != null) {
      final dir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(path.join(dir.path, 'user_products'));
      if (!imagesDir.existsSync()) imagesDir.createSync(recursive: true);
      final filePath = path.join(imagesDir.path, '${const Uuid().v4()}.jpg');
      await _image!.copy(filePath);
      localImagePath = filePath;
    } else if (_initialImagePath != null) {
      localImagePath = _initialImagePath;
    }

    final result = {
      'name': _nameCtrl.text.trim(),
      'kcalPer100g': kcal,
      'proteinsPer100g': proteins,
      'fatsPer100g': fats,
      'carbsPer100g': carbs,
      'imagePath': localImagePath,
      // Для обратной совместимости возвращаем строку с ингредиентами
      'ingredients': _ingredients.map((e) => e.name).join(', '),
      // И структурированный список (на будущее)
      'ingredientsList': _ingredients.map((e) => e.toJson()).toList(),
    };

    // Сохраняем продукт в локальный справочник пользовательских продуктов
    try {
      final repo = UserProductsRepository();
      if (widget.initialProduct != null) {
        final updated = UserProduct(
          id: widget.initialProduct!.id,
          name: _nameCtrl.text.trim(),
          imagePath: localImagePath,
          kcalPer100g: kcal,
          proteinsPer100g: proteins,
          fatsPer100g: fats,
          carbsPer100g: carbs,
          isFavorite: _isFavorite,
        );
        await repo.update(updated);
      } else if (_createdProductId != null) {
        // Обновляем ранее созданный черновик, чтобы избежать дублей
        final updated = UserProduct(
          id: _createdProductId!,
          name: _nameCtrl.text.trim(),
          imagePath: localImagePath,
          kcalPer100g: kcal,
          proteinsPer100g: proteins,
          fatsPer100g: fats,
          carbsPer100g: carbs,
          isFavorite: _isFavorite,
        );
        await repo.update(updated);
      } else {
        final product = UserProduct.create(
          name: _nameCtrl.text.trim(),
          imagePath: localImagePath,
          kcalPer100g: kcal,
          proteinsPer100g: proteins,
          fatsPer100g: fats,
          carbsPer100g: carbs,
          isFavorite: _isFavorite,
        );
        await repo.add(product);
        _createdProductId = product.id;
      }
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  void _unfocus() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  bool get _canSave {
    final nameOk = _nameCtrl.text.trim().isNotEmpty;
    final kcal = double.tryParse(_kcalCtrl.text.trim().replaceAll(',', '.'));
    return nameOk && kcal != null;
  }

  Future<void> _confirmAndDelete() async {
    if (widget.initialProduct == null) return;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить продукт?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await UserProductsRepository().remove(widget.initialProduct!.id);
      if (!mounted) return;
      Navigator.of(context).pop({'deleted': true});
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить продукт')),
      );
    }
  }

  Future<String?> _showNumberInputSheet({
    required String title,
    required String hintText,
    required String initialText,
    required bool allowDecimal,
  }) async {
    final controller = TextEditingController(text: initialText);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: allowDecimal
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      hintText: hintText,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Отмена'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.of(ctx).pop(controller.text),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Готово'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _editNutrient(_CreateNutrientField field) async {
    _unfocus();
    String title = '';
    String initial = '';
    switch (field) {
      case _CreateNutrientField.calories:
        title = context.tr('calories');
        initial = _kcalCtrl.text;
        break;
      case _CreateNutrientField.proteins:
        title = context.tr('proteins');
        initial = _pCtrl.text;
        break;
      case _CreateNutrientField.fats:
        title = context.tr('fats');
        initial = _fCtrl.text;
        break;
      case _CreateNutrientField.carbs:
        title = context.tr('carbs');
        initial = _cCtrl.text;
        break;
    }

    final text = await _showNumberInputSheet(
      title: title,
      hintText: field == _CreateNutrientField.calories
          ? 'Например: 250 ккал'
          : 'Например: 12.5 г',
      initialText: initial,
      allowDecimal: field != _CreateNutrientField.calories,
    );
    if (text == null) return;
    final normalized = text.replaceAll(',', '.');
    setState(() {
      switch (field) {
        case _CreateNutrientField.calories:
          _kcalCtrl.text =
              double.tryParse(normalized)?.floor().toString() ?? '';
          break;
        case _CreateNutrientField.proteins:
          _pCtrl.text = double.tryParse(normalized)?.toString() ?? '';
          break;
        case _CreateNutrientField.fats:
          _fCtrl.text = double.tryParse(normalized)?.toString() ?? '';
          break;
        case _CreateNutrientField.carbs:
          _cCtrl.text = double.tryParse(normalized)?.toString() ?? '';
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(0),
        child: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      ),
      body: Stack(
        children: [
          // Тап по пустому месту снимает фокус с поля названия
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _unfocus,
              child: const SizedBox.shrink(),
            ),
          ),
          Column(
            children: [
              // Верхняя секция как в Анализ еды: изображение + кнопки камеры/галереи
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(22),
                  bottomRight: Radius.circular(22),
                ),
                child: SizedBox(
                  height: 260,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _image != null
                          ? Image.file(_image!, fit: BoxFit.cover)
                          : (_initialImagePath == null
                              ? Container(color: Colors.grey[200])
                              : _buildInitialImage(_initialImagePath!)),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 110,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00000000), Color(0x55000000)],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 12,
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _pickImage(ImageSource.camera),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Colors.black.withOpacity(0.45),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.camera_alt),
                                label: Text(context.tr('take_photo')),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _pickImage(ImageSource.gallery),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Colors.black.withOpacity(0.45),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(Icons.photo_library),
                                label: Text(context.tr('select_from_gallery')),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _nameCtrl,
                          decoration:
                              InputDecoration(labelText: context.tr('name')),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Укажите название'
                              : null,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        // Карточка КБЖУ как на экране анализа: круглые виджеты
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.2),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _buildNutrientItem(
                                    context.tr('calories'),
                                    '${(_kcalCtrl.text.isEmpty ? '0.0' : (double.tryParse(_kcalCtrl.text.replaceAll(',', '.'))?.toStringAsFixed(1) ?? '0.0'))} ккал',
                                    Colors.red,
                                    onTap: () => _editNutrient(
                                        _CreateNutrientField.calories),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.center,
                                  child: _buildNutrientItem(
                                    context.tr('proteins'),
                                    '${(_pCtrl.text.isEmpty ? '0.0' : (double.tryParse(_pCtrl.text.replaceAll(',', '.'))?.toStringAsFixed(1) ?? '0.0'))} г',
                                    Colors.green,
                                    onTap: () => _editNutrient(
                                        _CreateNutrientField.proteins),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.center,
                                  child: _buildNutrientItem(
                                    context.tr('fats'),
                                    '${(_fCtrl.text.isEmpty ? '0.0' : (double.tryParse(_fCtrl.text.replaceAll(',', '.'))?.toStringAsFixed(1) ?? '0.0'))} г',
                                    Colors.yellow.shade800,
                                    onTap: () => _editNutrient(
                                        _CreateNutrientField.fats),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: _buildNutrientItem(
                                    context.tr('carbs'),
                                    '${(_cCtrl.text.isEmpty ? '0.0' : (double.tryParse(_cCtrl.text.replaceAll(',', '.'))?.toStringAsFixed(1) ?? '0.0'))} г',
                                    Colors.purple,
                                    onTap: () => _editNutrient(
                                        _CreateNutrientField.carbs),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Ингредиенты
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.2),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Распознанные ингредиенты',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 24, minHeight: 24),
                                    icon: const Icon(Icons.edit, size: 20),
                                    tooltip: 'Редактировать',
                                    onPressed: () async {
                                      _unfocus();
                                      final updated =
                                          await IngredientListEditingBottomSheet
                                              .show(
                                        context: context,
                                        ingredients: _ingredients,
                                      );
                                      if (updated == null) return;
                                      setState(() {
                                        _ingredients
                                          ..clear()
                                          ..addAll(updated);
                                      });
                                    },
                                  ),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                        minWidth: 24, minHeight: 24),
                                    icon: const Icon(Icons.add_circle_outline,
                                        size: 20),
                                    tooltip: 'Добавить ингредиент',
                                    onPressed: () async {
                                      _unfocus();
                                      final updated =
                                          await IngredientListEditingBottomSheet
                                              .show(
                                        context: context,
                                        ingredients: _ingredients,
                                      );
                                      if (updated == null) return;
                                      setState(() {
                                        _ingredients
                                          ..clear()
                                          ..addAll(updated);
                                      });
                                    },
                                  ),
                                ],
                              ),
                              if (_ingredients.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4.0),
                                  child: Text(
                                    'Добавьте ингредиенты',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              else
                                ListView.builder(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _ingredients.length,
                                  itemBuilder: (context, index) {
                                    final i = _ingredients[index];
                                    return _buildIngredientRow(
                                        i.name, i.weight, 'г');
                                  },
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
              // Нижняя панель действий как на экране анализа
              Container(
                padding: const EdgeInsets.only(
                  left: 16.0,
                  right: 16.0,
                  top: 12.0,
                  bottom: 20.0,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, -1),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    if (widget.initialProduct != null) ...[
                      Expanded(
                        flex: 1,
                        child: ElevatedButton.icon(
                          onPressed: _confirmAndDelete,
                          icon: const Icon(Icons.delete, color: Colors.white),
                          label: const Text('Удалить',
                              style:
                                  TextStyle(fontSize: 16, color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _canSave ? _save : null,
                        icon: const Icon(Icons.save, color: Colors.white),
                        label: Text(
                          _canSave ? 'Сохранить' : 'Заполните данные',
                          style: const TextStyle(
                              fontSize: 16, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isFavorite ? Icons.star : Icons.star_border,
                      color: Colors.white,
                    ),
                    tooltip: _isFavorite
                        ? context.tr('remove_from_favorites')
                        : context.tr('add_to_favorites'),
                    onPressed: () async {
                      setState(() => _isFavorite = !_isFavorite);
                      final productsRepo = UserProductsRepository();
                      String? targetId =
                          widget.initialProduct?.id ?? _createdProductId;

                      // Если создаём — обеспечить наличие id (черновик)
                      if (targetId == null) {
                        final String name = _nameCtrl.text.trim();
                        final double? kcal = double.tryParse(
                            _kcalCtrl.text.trim().replaceAll(',', '.'));
                        if (name.isNotEmpty && kcal != null) {
                          try {
                            String? localImagePath = _initialImagePath;
                            if (_image != null) {
                              final dir =
                                  await getApplicationDocumentsDirectory();
                              final imagesDir = Directory(
                                  path.join(dir.path, 'user_products'));
                              if (!imagesDir.existsSync()) {
                                imagesDir.createSync(recursive: true);
                              }
                              final filePath = path.join(
                                  imagesDir.path, '${const Uuid().v4()}.jpg');
                              await _image!.copy(filePath);
                              localImagePath = filePath;
                            }
                            final product = UserProduct.create(
                              name: name,
                              imagePath: localImagePath,
                              kcalPer100g: kcal,
                              proteinsPer100g: double.tryParse(_pCtrl.text
                                      .trim()
                                      .replaceAll(',', '.')) ??
                                  0,
                              fatsPer100g: double.tryParse(_fCtrl.text
                                      .trim()
                                      .replaceAll(',', '.')) ??
                                  0,
                              carbsPer100g: double.tryParse(_cCtrl.text
                                      .trim()
                                      .replaceAll(',', '.')) ??
                                  0,
                              isFavorite: _isFavorite,
                            );
                            await productsRepo.add(product);
                            _createdProductId = product.id;
                            targetId = product.id;
                          } catch (_) {}
                        }
                      } else {
                        // если редактируем или уже есть черновик — обновим флаг
                        try {
                          await productsRepo.setFavorite(targetId, _isFavorite);
                        } catch (_) {}
                      }

                      // Синхронизируем с FavoritesRepository (экран "Избранное")
                      if (targetId != null) {
                        try {
                          // Сконструируем FavoriteMealModel из текущих полей
                          final String name = _nameCtrl.text.trim();
                          final double? kcal = double.tryParse(
                              _kcalCtrl.text.trim().replaceAll(',', '.'));
                          final double proteins = double.tryParse(
                                  _pCtrl.text.trim().replaceAll(',', '.')) ??
                              0;
                          final double fats = double.tryParse(
                                  _fCtrl.text.trim().replaceAll(',', '.')) ??
                              0;
                          final double carbs = double.tryParse(
                                  _cCtrl.text.trim().replaceAll(',', '.')) ??
                              0;

                          String? localImagePath = _initialImagePath;
                          if (_image != null) {
                            final dir =
                                await getApplicationDocumentsDirectory();
                            final imagesDir =
                                Directory(path.join(dir.path, 'user_products'));
                            if (!imagesDir.existsSync()) {
                              imagesDir.createSync(recursive: true);
                            }
                            final filePath = path.join(
                                imagesDir.path, '${const Uuid().v4()}.jpg');
                            await _image!.copy(filePath);
                            localImagePath = filePath;
                          }

                          final fav = FavoriteMealModel(
                            id: targetId,
                            name: name,
                            imagePath: localImagePath,
                            ingredients: _ingredients
                                .map((e) => IngredientModel(
                                      name: e.name,
                                      quantity: e.weight,
                                    ))
                                .toList(),
                            nutrients: MealNutrientsModel(
                              calories: (kcal ?? 0).round(),
                              proteins: proteins,
                              fats: fats,
                              carbs: carbs,
                            ),
                            healthiness: 0,
                          );

                          // Через Riverpod провайдер, как на экране анализа
                          // ignore: use_build_context_synchronously
                          final container = ProviderScope.containerOf(context);
                          final favNotifier =
                              container.read(favoritesProvider.notifier);
                          if (_isFavorite) {
                            await favNotifier.add(fav);
                          } else {
                            await favNotifier.removeById(targetId);
                          }
                        } catch (_) {}
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutrientItem(String label, String value, Color color,
      {VoidCallback? onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(50),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.pie_chart,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIngredientRow(String name, double weight, String unitSuffix) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "${weight.toStringAsFixed(1)} $unitSuffix",
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // Отрисовка исходного изображения при редактировании
  Widget _buildInitialImage(String path) {
    final isNetwork = path.startsWith('http');
    final isFileUri = path.startsWith('file://');
    if (isNetwork) {
      return Image.network(path, fit: BoxFit.cover);
    }
    if (isFileUri) {
      return Image.file(File.fromUri(Uri.parse(path)), fit: BoxFit.cover);
    }
    return Image.file(File(path), fit: BoxFit.cover);
  }
}
