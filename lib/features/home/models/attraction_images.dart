import 'dart:io';

enum ImageCategory {
  exterior('Внешний вид', 'exterior facade building'),
  interior('Интерьер', 'interior inside'),
  historical('Историческое фото', 'historical vintage old archive'),
  night('Вечерний вид', 'night evening illumination'),
  aerial('Вид сверху', 'aerial drone view'),
  details('Детали', 'architecture details close-up');

  final String label;
  final String searchSuffix;

  const ImageCategory(this.label, this.searchSuffix);
}

class AttractionImage {
  final File file;
  final ImageCategory category;
  final String? sourceUrl;

  const AttractionImage({
    required this.file,
    required this.category,
    this.sourceUrl,
  });
}

class AttractionImages {
  final String attractionName;
  final List<AttractionImage> images;
  final DateTime loadedAt;

  const AttractionImages({
    required this.attractionName,
    required this.images,
    required this.loadedAt,
  });

  bool get isEmpty => images.isEmpty;
  bool get isNotEmpty => images.isNotEmpty;
  int get count => images.length;

  List<File> get files => images.map((e) => e.file).toList();

  AttractionImage? getByCategory(ImageCategory category) {
    try {
      return images.firstWhere((img) => img.category == category);
    } catch (_) {
      return null;
    }
  }

  AttractionImages copyWith({
    String? attractionName,
    List<AttractionImage>? images,
    DateTime? loadedAt,
  }) {
    return AttractionImages(
      attractionName: attractionName ?? this.attractionName,
      images: images ?? this.images,
      loadedAt: loadedAt ?? this.loadedAt,
    );
  }

  static AttractionImages empty(String name) {
    return AttractionImages(
      attractionName: name,
      images: const [],
      loadedAt: DateTime.now(),
    );
  }
}



















