/// Перечисление типов уведомлений
///
/// Используется для определения важности и внешнего вида уведомления
enum NotificationType {
  /// Информационное уведомление (низкий приоритет)
  info,

  /// Напоминание (средний приоритет)
  reminder,

  /// Предупреждение (высокий приоритет)
  warning,

  /// Критическое уведомление (максимальный приоритет)
  critical,
}

/// Интерфейс сервиса уведомлений
///
/// Определяет контракт для различных реализаций сервисов уведомлений
/// (локальные уведомления, Firebase уведомления и т.д.)
abstract class NotificationServiceInterface {
  /// Инициализирует сервис уведомлений
  ///
  /// Должен быть вызван перед использованием других методов
  Future<void> initialize();

  /// Запрашивает у пользователя разрешения на отправку уведомлений
  ///
  /// Возвращает флаг, указывающий, были ли предоставлены разрешения
  Future<bool> requestPermissions();

  /// Проверяет, включены ли уведомления
  ///
  /// Возвращает флаг, указывающий, включены ли уведомления для приложения
  Future<bool> areNotificationsEnabled();

  /// Регистрирует устройство для получения уведомлений
  ///
  /// Используется для пуш-уведомлений, для локальных не требуется
  Future<void> registerDevice();

  /// Показывает локальное уведомление немедленно
  ///
  /// [id] - уникальный идентификатор уведомления
  /// [title] - заголовок уведомления
  /// [body] - текст уведомления
  /// [payload] - дополнительные данные, передаваемые с уведомлением
  /// [type] - тип уведомления (влияет на приоритет и внешний вид)
  Future<void> showLocalNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    NotificationType type,
  });

  /// Планирует отправку уведомления на указанное время
  ///
  /// [id] - уникальный идентификатор уведомления
  /// [title] - заголовок уведомления
  /// [body] - текст уведомления
  /// [scheduledDate] - дата и время отправки уведомления
  /// [payload] - дополнительные данные, передаваемые с уведомлением
  /// [type] - тип уведомления (влияет на приоритет и внешний вид)
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
    NotificationType type,
  });

  /// Настраивает периодическое уведомление
  ///
  /// [id] - уникальный идентификатор уведомления
  /// [title] - заголовок уведомления
  /// [body] - текст уведомления
  /// [interval] - интервал между повторениями уведомления
  /// [payload] - дополнительные данные, передаваемые с уведомлением
  /// [type] - тип уведомления (влияет на приоритет и внешний вид)
  /// [initialDateTime] - начальное время для первого показа уведомления (если null, начинается сразу)
  Future<void> periodicallyShowNotification({
    required int id,
    required String title,
    required String body,
    required Duration interval,
    String? payload,
    NotificationType type,
    DateTime? initialDateTime,
  });

  /// Отменяет уведомление с указанным идентификатором
  ///
  /// [id] - идентификатор уведомления для отмены
  Future<void> cancelNotification(int id);

  /// Отменяет все запланированные уведомления
  Future<void> cancelAllNotifications();

  /// Устанавливает обработчик для события получения уведомления
  ///
  /// [onNotificationReceived] - функция обратного вызова,
  /// которая будет вызвана при получении уведомления
  void setOnNotificationReceived(
      void Function(String? payload) onNotificationReceived);

  /// Устанавливает обработчик для события открытия уведомления
  ///
  /// [onNotificationTapped] - функция обратного вызова,
  /// которая будет вызвана при открытии уведомления пользователем
  void setOnNotificationTapped(
      void Function(String? payload) onNotificationTapped);

  /// Обрабатывает данные, полученные с уведомлением
  ///
  /// [payload] - дополнительные данные, переданные с уведомлением
  Future<void> handleNotificationPayload(String? payload);
}
