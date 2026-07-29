import 'dart:io';
import 'package:flutter/material.dart';
import '../../repositories/user_products_repository.dart';
import '../create/product_create_screen.dart';
import '../../services/localization/app_localization_service.dart';

class UserProductsScreen extends StatefulWidget {
  const UserProductsScreen({super.key});

  @override
  State<UserProductsScreen> createState() => _UserProductsScreenState();
}

class _UserProductsScreenState extends State<UserProductsScreen> {
  final _repo = UserProductsRepository();
  List<UserProduct> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await _repo.getAll();
    if (!mounted) return;
    setState(() {
      _items = all;
      _loading = false;
    });
  }

  Future<void> _delete(String id) async {
    await _repo.remove(id);
    await _load();
  }

  // диалог редактирования больше не используется: редактирование через ProductCreateScreen

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('my_products')), actions: [
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: context.tr('create_product'),
          onPressed: () async {
            await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProductCreateScreen()));
            await _load();
          },
        )
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(child: Text('Список пуст'))
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (ctx, i) {
                    final p = _items[i];
                    return Dismissible(
                      key: ValueKey(p.id),
                      background: Container(
                        color: Colors.red,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(context
                                .tr('confirm_delete_user_product_title')),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: Text(context.tr('cancel'))),
                              TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: Text(context.tr('delete'))),
                            ],
                          ),
                        );
                        return ok == true;
                      },
                      onDismissed: (_) => _delete(p.id),
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
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
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ProductCreateScreen(initialProduct: p),
                                ),
                              );
                              await _load();
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: _buildImage(p.imagePath),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                            IconButton(
                                              onPressed: () async {
                                                await _repo
                                                    .toggleFavorite(p.id);
                                                await _load();
                                              },
                                              icon: Icon(
                                                p.isFavorite
                                                    ? Icons.star
                                                    : Icons.star_border,
                                                color: Colors.white,
                                              ),
                                              tooltip: p.isFavorite
                                                  ? context.tr(
                                                      'remove_from_favorites')
                                                  : context
                                                      .tr('add_to_favorites'),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.local_fire_department,
                                              size: 16,
                                              color: Theme.of(context)
                                                  .primaryColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${p.kcalPer100g.toStringAsFixed(0)} ккал / 100 г',
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Theme.of(context)
                                                    .primaryColor,
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
                                            _buildNutrientBadge(
                                                'Ж',
                                                p.fatsPer100g.round(),
                                                Colors.red),
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
                      ),
                    );
                  },
                ),
    );
  }
}

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
  if (isNetwork) {
    return Image.network(url, width: 70, height: 70, fit: BoxFit.cover);
  }
  if (isFileUri) {
    return Image.file(File.fromUri(Uri.parse(url)),
        width: 70, height: 70, fit: BoxFit.cover);
  }
  return Image.file(File(url), width: 70, height: 70, fit: BoxFit.cover);
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
