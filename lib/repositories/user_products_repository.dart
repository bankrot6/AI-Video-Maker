import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/openfoodfacts/openfoodfacts_service.dart';

class UserProduct {
  final String id;
  final String name;
  final String? imagePath; // может быть локальный file-путь или http
  final double kcalPer100g;
  final double proteinsPer100g;
  final double fatsPer100g;
  final double carbsPer100g;
  final bool isFavorite;

  const UserProduct({
    required this.id,
    required this.name,
    required this.imagePath,
    required this.kcalPer100g,
    required this.proteinsPer100g,
    required this.fatsPer100g,
    required this.carbsPer100g,
    this.isFavorite = false,
  });

  factory UserProduct.create({
    required String name,
    String? imagePath,
    required double kcalPer100g,
    required double proteinsPer100g,
    required double fatsPer100g,
    required double carbsPer100g,
    bool isFavorite = false,
  }) {
    return UserProduct(
      id: const Uuid().v4(),
      name: name,
      imagePath: imagePath,
      kcalPer100g: kcalPer100g,
      proteinsPer100g: proteinsPer100g,
      fatsPer100g: fatsPer100g,
      carbsPer100g: carbsPer100g,
      isFavorite: isFavorite,
    );
  }

  UserProduct copyWith({
    String? id,
    String? name,
    String? imagePath,
    double? kcalPer100g,
    double? proteinsPer100g,
    double? fatsPer100g,
    double? carbsPer100g,
    bool? isFavorite,
  }) {
    return UserProduct(
      id: id ?? this.id,
      name: name ?? this.name,
      imagePath: imagePath ?? this.imagePath,
      kcalPer100g: kcalPer100g ?? this.kcalPer100g,
      proteinsPer100g: proteinsPer100g ?? this.proteinsPer100g,
      fatsPer100g: fatsPer100g ?? this.fatsPer100g,
      carbsPer100g: carbsPer100g ?? this.carbsPer100g,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imagePath': imagePath,
        'kcalPer100g': kcalPer100g,
        'proteinsPer100g': proteinsPer100g,
        'fatsPer100g': fatsPer100g,
        'carbsPer100g': carbsPer100g,
        'isFavorite': isFavorite,
      };

  factory UserProduct.fromJson(Map<String, dynamic> json) => UserProduct(
        id: json['id'] as String,
        name: json['name'] as String,
        imagePath: json['imagePath'] as String?,
        kcalPer100g: (json['kcalPer100g'] as num).toDouble(),
        proteinsPer100g: (json['proteinsPer100g'] as num).toDouble(),
        fatsPer100g: (json['fatsPer100g'] as num).toDouble(),
        carbsPer100g: (json['carbsPer100g'] as num).toDouble(),
        isFavorite: (json['isFavorite'] as bool?) ?? false,
      );

  OpenFoodFactsProduct toOpenFoodFactsProduct() => OpenFoodFactsProduct(
        name: name,
        brand: 'Мой продукт',
        barcode: null,
        imageUrl: imagePath,
        kcalPer100g: kcalPer100g,
        proteinsPer100g: proteinsPer100g,
        fatsPer100g: fatsPer100g,
        carbsPer100g: carbsPer100g,
        fiberPer100g: 0,
        sugarPer100g: 0,
      );
}

class UserProductsRepository {
  static const String _key = 'user_products_v1';

  Future<List<UserProduct>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (json.decode(raw) as List<dynamic>)
          .map((e) => UserProduct.fromJson(e as Map<String, dynamic>))
          .toList();
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<UserProduct> items) async {
    final prefs = await SharedPreferences.getInstance();
    final data = json.encode(items.map((e) => e.toJson()).toList());
    await prefs.setString(_key, data);
  }

  Future<void> add(UserProduct product) async {
    final all = await getAll();
    all.insert(0, product);
    await _saveAll(all);
  }

  Future<void> remove(String id) async {
    final all = await getAll();
    all.removeWhere((p) => p.id == id);
    await _saveAll(all);
  }

  Future<void> update(UserProduct product) async {
    final all = await getAll();
    final index = all.indexWhere((p) => p.id == product.id);
    if (index >= 0) {
      all[index] = product;
      await _saveAll(all);
    } else {
      // если нет — добавим как новый
      all.insert(0, product);
      await _saveAll(all);
    }
  }

  Future<List<UserProduct>> searchByName(String query) async {
    final all = await getAll();
    if (query.trim().isEmpty) return all;
    final q = query.toLowerCase();
    return all.where((p) => p.name.toLowerCase().contains(q)).toList();
  }

  Future<void> setFavorite(String id, bool value) async {
    final all = await getAll();
    final index = all.indexWhere((p) => p.id == id);
    if (index >= 0) {
      all[index] = all[index].copyWith(isFavorite: value);
      await _saveAll(all);
    }
  }

  Future<void> toggleFavorite(String id) async {
    final all = await getAll();
    final index = all.indexWhere((p) => p.id == id);
    if (index >= 0) {
      final current = all[index];
      all[index] = current.copyWith(isFavorite: !current.isFavorite);
      await _saveAll(all);
    }
  }

  Future<bool> isFavorite(String id) async {
    final all = await getAll();
    final item = all.firstWhere((p) => p.id == id,
        orElse: () => const UserProduct(
            id: '',
            name: '',
            imagePath: null,
            kcalPer100g: 0,
            proteinsPer100g: 0,
            fatsPer100g: 0,
            carbsPer100g: 0));
    return item.id.isNotEmpty && item.isFavorite;
  }

  Future<List<UserProduct>> getFavorites() async {
    final all = await getAll();
    return all.where((p) => p.isFavorite).toList();
  }
}
