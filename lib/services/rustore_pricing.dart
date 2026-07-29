class RuStorePricing {
  // Валюта RuStore
  static const String currencySymbol = '₽';
  static const String currencyCode = 'RUB';

  // Единые цены в рублях
  static const double weekly = 99.0;
  static const double monthly = 299.0;
  static const double yearly = 999.0;

  // Форматирование
  static String format(double value) => '$currencySymbol${value.round()}';

  static String get formattedWeekly => format(weekly);
  static String get formattedMonthly => format(monthly);
  static String get formattedYearly => format(yearly);
}
