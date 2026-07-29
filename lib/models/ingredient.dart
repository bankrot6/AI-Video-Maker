import 'package:equatable/equatable.dart';

class Ingredient extends Equatable {
  final String name;
  final double weight; // вес в граммах
  final bool verified; // подтвержден ли ингредиент

  const Ingredient({
    required this.name,
    required this.weight,
    this.verified = true,
  });

  @override
  List<Object?> get props => [name, weight, verified];

  // Фабричный метод для создания из JSON
  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      name: json['name'] as String,
      weight: (json['weight'] as num).toDouble(),
      verified: json['verified'] as bool? ?? true,
    );
  }

  // Метод для сериализации в JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'weight': weight,
      'verified': verified,
    };
  }
}
