import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/openfoodfacts/openfoodfacts_service.dart';
import '../../repositories/user_products_repository.dart';
import 'user_products_screen.dart';
import '../../widgets/portion_input_sheet.dart';
import '../create/product_create_screen.dart';
import '../../services/localization/app_localization_service.dart';

class ProductSearchScreen extends ConsumerStatefulWidget {
  final void Function(OpenFoodFactsProduct product, double grams) onPicked;
  const ProductSearchScreen({super.key, required this.onPicked});

  @override
  ConsumerState<ProductSearchScreen> createState() =>
      _ProductSearchScreenState();
}

class _ProductSearchScreenState extends ConsumerState<ProductSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final _service = OpenFoodFactsService();
  List<OpenFoodFactsProduct> _results = const [];
  bool _loading = false;
  int _currentPage = 1;
  String _lastQuery = '';
  bool _isPaging = false;
  final bool _showOnlyUser = false;
  final _userRepo = UserProductsRepository();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_focusNode);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final trimmed = query.trim();
    _lastQuery = trimmed;
    _currentPage = 1;
    if (trimmed.length < 2) {
      setState(() {
        _loading = false;
        _results = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _results = const [];
    });
    try {
      // Пользовательские продукты только по поисковому запросу
      final user = await _userRepo.searchByName(trimmed);
      final userResults = user.map((e) => e.toOpenFoodFactsProduct()).toList();

      // Онлайн поиск
      final first =
          await _service.searchByNamePaged(trimmed, page: 1, pageSize: 20);
      if (!mounted) return;
      setState(() {
        _results = [...userResults, ...first];
      });

      // Догрузка второй страницы
      _isPaging = true;
      final second =
          await _service.searchByNamePaged(trimmed, page: 2, pageSize: 20);
      if (!mounted || _lastQuery != trimmed) return;
      setState(() {
        _results = [..._results, ...second];
      });
    } finally {
      if (mounted)
        setState(() {
          _loading = false;
          _isPaging = false;
        });
    }
  }

  Future<void> _pickPortion(OpenFoodFactsProduct product) async {
    final grams = await PortionInputSheet.show(
      context: context,
      title: product.name,
      imageUrl: product.imageUrl,
      initialGrams: 100,
    );
    if (grams == null) return;
    widget.onPicked(product, grams);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('search_products')),
        actions: [
          // Кнопка списка пользовательских продуктов
          IconButton(
            tooltip: context.tr('my_products'),
            icon: const Icon(Icons.list_alt),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UserProductsScreen()),
              );
              // после возврата перезагрузим текущий поиск
              if (mounted) {
                await _search(_controller.text);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: context.tr('create_product'),
            onPressed: () async {
              final data =
                  await Navigator.of(context).push<Map<String, dynamic>>(
                MaterialPageRoute(builder: (_) => const ProductCreateScreen()),
              );
              if (data == null) return;
              // Преобразуем введённый продукт в структуру поиска и сразу открываем порцию
              final custom = OpenFoodFactsProduct(
                name: data['name'] as String,
                brand: null,
                barcode: null,
                imageUrl: data['imagePath'] as String?,
                kcalPer100g: (data['kcalPer100g'] as num).toDouble(),
                proteinsPer100g: (data['proteinsPer100g'] as num).toDouble(),
                fatsPer100g: (data['fatsPer100g'] as num).toDouble(),
                carbsPer100g: (data['carbsPer100g'] as num).toDouble(),
                fiberPer100g: 0,
                sugarPer100g: 0,
              );
              await _pickPortion(custom);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textInputAction: TextInputAction.search,
              autofocus: true,
              onChanged: (v) async {
                if (v.trim().length < 2) {
                  setState(() => _results = const []);
                  return;
                }
                await _search(v);
              },
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: context.tr('enter_product_name'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: (_controller.text.isNotEmpty)
                    ? IconButton(
                        onPressed: () {
                          _controller.clear();
                          setState(() => _results = const []);
                          _focusNode.requestFocus();
                        },
                        icon: const Icon(Icons.clear))
                    : null,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (_showOnlyUser) return false; // пейджинг для моих не нужен
                if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200 &&
                    !_isPaging &&
                    !_loading &&
                    _lastQuery.trim().length >= 2) {
                  _isPaging = true;
                  _currentPage += 1;
                  _service
                      .searchByNamePaged(_lastQuery,
                          page: _currentPage, pageSize: 20)
                      .then((more) {
                    if (!mounted || _lastQuery.isEmpty) return;
                    setState(() {
                      _results = [..._results, ...more];
                      _isPaging = false;
                    });
                  }).catchError((_) {
                    if (mounted) _isPaging = false;
                  });
                }
                return false;
              },
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final p = _results[i];
                  return Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _pickPortion(p),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: _buildImage(p.imageUrl),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            p.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.local_fire_department,
                                          size: 16,
                                          color: Theme.of(context).primaryColor,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${p.kcalPer100g.toStringAsFixed(0)} ккал / 100 г',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color:
                                                Theme.of(context).primaryColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        _buildNutrientBadge(
                                            'Б',
                                            p.proteinsPer100g.round(),
                                            Colors.blue),
                                        const SizedBox(width: 8),
                                        _buildNutrientBadge('Ж',
                                            p.fatsPer100g.round(), Colors.red),
                                        const SizedBox(width: 8),
                                        _buildNutrientBadge(
                                            'У',
                                            p.carbsPer100g.round(),
                                            Colors.green),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Subtitle не используется после перехода на карточки из истории

  Widget _buildImage(String? url) {
    if (url == null || url.isEmpty) {
      return Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.fastfood, color: Colors.grey),
      );
    }
    final isNetwork = url.startsWith('http://') || url.startsWith('https://');
    final isFileUri = url.startsWith('file://');
    final imageWidget = isNetwork
        ? Image.network(url, width: 70, height: 70, fit: BoxFit.cover)
        : (isFileUri
            ? Image.file(File.fromUri(Uri.parse(url)),
                width: 70, height: 70, fit: BoxFit.cover)
            : Image.file(File(url), width: 70, height: 70, fit: BoxFit.cover));
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: imageWidget,
    );
  }

  Widget _buildNutrientBadge(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: color,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
