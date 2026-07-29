import 'dart:collection';
import 'package:openfoodfacts/openfoodfacts.dart';

class OpenFoodFactsProduct {
  final String name;
  final String? brand;
  final String? barcode;
  final String? imageUrl;
  final double kcalPer100g;
  final double proteinsPer100g;
  final double fatsPer100g;
  final double carbsPer100g;
  final double fiberPer100g;
  final double sugarPer100g;

  const OpenFoodFactsProduct({
    required this.name,
    this.brand,
    this.barcode,
    this.imageUrl,
    required this.kcalPer100g,
    required this.proteinsPer100g,
    required this.fatsPer100g,
    required this.carbsPer100g,
    required this.fiberPer100g,
    required this.sugarPer100g,
  });
}

class OpenFoodFactsService {
  final Map<String, OpenFoodFactsProduct> _barcodeCache = HashMap();

  OpenFoodFactsService() {
    OpenFoodAPIConfiguration.userAgent = UserAgent(
      name: 'AI Video Maker',
      version: '2.5.7',
      system: 'Flutter',
    );
    OpenFoodAPIConfiguration.globalLanguages = [OpenFoodFactsLanguage.RUSSIAN];
    OpenFoodAPIConfiguration.globalCountry = OpenFoodFactsCountry.RUSSIA;
  }

  Future<OpenFoodFactsProduct?> fetchByBarcode(String barcode) async {
    if (_barcodeCache.containsKey(barcode)) {
      return _barcodeCache[barcode];
    }

    final config = ProductQueryConfiguration(
      barcode,
      version: ProductQueryVersion.v3,
      fields: [
        ProductField.NUTRIMENTS,
        ProductField.NAME,
        ProductField.BRANDS,
        ProductField.BARCODE,
        ProductField.IMAGE_FRONT_URL,
      ],
    );

    final response = await OpenFoodAPIClient.getProductV3(config);
    final product = response.product;
    if (response.status != ProductResultV3.statusSuccess || product == null) {
      return null;
    }

    final nutr = product.nutriments;
    double v(Nutrient nutrient) {
      final value = nutr?.getValue(nutrient, PerSize.oneHundredGrams);
      return (value ?? 0).toDouble();
    }

    final kj = nutr?.getValue(Nutrient.energyKJ, PerSize.oneHundredGrams);
    final kcalFromKj = (kj ?? 0).toDouble() / 4.184;

    final result = OpenFoodFactsProduct(
      name: (product.productName?.isNotEmpty == true)
          ? product.productName!
          : (product.brands ?? 'Продукт'),
      brand: product.brands,
      barcode: product.barcode,
      imageUrl: product.imageFrontUrl,
      kcalPer100g: kcalFromKj,
      proteinsPer100g: v(Nutrient.proteins),
      fatsPer100g: v(Nutrient.fat),
      carbsPer100g: v(Nutrient.carbohydrates),
      fiberPer100g: v(Nutrient.fiber),
      sugarPer100g: v(Nutrient.sugars),
    );

    _barcodeCache[barcode] = result;
    return result;
  }

  Future<List<OpenFoodFactsProduct>> searchByName(String query,
      {int limit = 20}) async {
    if (query.trim().isEmpty) return [];

    final searchConfig = ProductSearchQueryConfiguration(
      version: ProductQueryVersion.v3,
      parametersList: <Parameter>[
        SearchTerms(terms: [query]),
        const PageNumber(page: 1),
        PageSize(size: limit),
        const SortBy(option: SortOption.POPULARITY),
      ],
      fields: [
        ProductField.NUTRIMENTS,
        ProductField.NAME,
        ProductField.BRANDS,
        ProductField.BARCODE,
        ProductField.IMAGE_FRONT_URL,
      ],
    );

    final result = await OpenFoodAPIClient.searchProducts(
      null,
      searchConfig,
    );
    final products = result.products ?? [];

    double v(Nutriments? nutr, Nutrient nutrient) {
      final value = nutr?.getValue(nutrient, PerSize.oneHundredGrams);
      return (value ?? 0).toDouble();
    }

    return products
        .map((p) {
          final nutr = p.nutriments;
          final kj = nutr?.getValue(Nutrient.energyKJ, PerSize.oneHundredGrams);
          final kcalFromKj = (kj ?? 0).toDouble() / 4.184;
          return OpenFoodFactsProduct(
            name: (p.productName?.isNotEmpty == true)
                ? p.productName!
                : (p.brands ?? 'Продукт'),
            brand: p.brands,
            barcode: p.barcode,
            imageUrl: p.imageFrontUrl,
            kcalPer100g: kcalFromKj,
            proteinsPer100g: v(nutr, Nutrient.proteins),
            fatsPer100g: v(nutr, Nutrient.fat),
            carbsPer100g: v(nutr, Nutrient.carbohydrates),
            fiberPer100g: v(nutr, Nutrient.fiber),
            sugarPer100g: v(nutr, Nutrient.sugars),
          );
        })
        .where((p) => p.kcalPer100g > 0)
        .toList();
  }

  Future<List<OpenFoodFactsProduct>> searchByNamePaged(
    String query, {
    required int page,
    int pageSize = 20,
  }) async {
    if (query.trim().isEmpty) return [];

    final searchConfig = ProductSearchQueryConfiguration(
      version: ProductQueryVersion.v3,
      parametersList: <Parameter>[
        SearchTerms(terms: [query]),
        PageNumber(page: page),
        PageSize(size: pageSize),
        const SortBy(option: SortOption.POPULARITY),
      ],
      fields: [
        ProductField.NUTRIMENTS,
        ProductField.NAME,
        ProductField.BRANDS,
        ProductField.BARCODE,
        ProductField.IMAGE_FRONT_URL,
      ],
    );

    final result = await OpenFoodAPIClient.searchProducts(
      null,
      searchConfig,
    );
    final products = result.products ?? [];

    double v(Nutriments? nutr, Nutrient nutrient) {
      final value = nutr?.getValue(nutrient, PerSize.oneHundredGrams);
      return (value ?? 0).toDouble();
    }

    return products
        .map((p) {
          final nutr = p.nutriments;
          final kj = nutr?.getValue(Nutrient.energyKJ, PerSize.oneHundredGrams);
          final kcalFromKj = (kj ?? 0).toDouble() / 4.184;
          return OpenFoodFactsProduct(
            name: (p.productName?.isNotEmpty == true)
                ? p.productName!
                : (p.brands ?? 'Продукт'),
            brand: p.brands,
            barcode: p.barcode,
            imageUrl: p.imageFrontUrl,
            kcalPer100g: kcalFromKj,
            proteinsPer100g: v(nutr, Nutrient.proteins),
            fatsPer100g: v(nutr, Nutrient.fat),
            carbsPer100g: v(nutr, Nutrient.carbohydrates),
            fiberPer100g: v(nutr, Nutrient.fiber),
            sugarPer100g: v(nutr, Nutrient.sugars),
          );
        })
        .where((p) => p.kcalPer100g > 0)
        .toList();
  }
}
