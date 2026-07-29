import '../models/weight_entry_model.dart';

/// Репозиторий для работы с историей веса пользователя
abstract class WeightRepository {
  /// Добавляет новую запись веса
  Future<void> addWeightEntry(WeightEntryModel entry);

  /// Возвращает все записи веса (отсортированы по дате по возрастанию)
  Future<List<WeightEntryModel>> getAllEntries();

  /// Возвращает последнюю запись веса или null, если записей нет
  Future<WeightEntryModel?> getLatestEntry();
}

/// Простая мок-реализация репозитория для разработки
class MockWeightRepository implements WeightRepository {
  final List<WeightEntryModel> _entries = [];

  @override
  Future<void> addWeightEntry(WeightEntryModel entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<WeightEntryModel>> getAllEntries() async {
    // Возвращаем копию, чтобы предотвратить внешнюю мутацию
    _entries.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return List<WeightEntryModel>.from(_entries);
  }

  @override
  Future<WeightEntryModel?> getLatestEntry() async {
    if (_entries.isEmpty) return null;
    _entries.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return _entries.first;
  }
}
