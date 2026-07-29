class MealActionResult {
  final bool deleted;
  final DateTime? movedTo;

  const MealActionResult._({this.deleted = false, this.movedTo});

  factory MealActionResult.deleted() => const MealActionResult._(deleted: true);

  factory MealActionResult.moved(DateTime to) =>
      MealActionResult._(deleted: false, movedTo: to);
}
