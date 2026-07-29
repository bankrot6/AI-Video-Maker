import 'dart:io';

/// Быстрый скрипт для обновления коротких переводов для проблемных ключей.
/// Специально для решения проблемы с слишком короткими переводами для кнопок выбора пола
/// и кнопки "Изменить" на экране Анализ еды.
///
/// Запуск:
/// ```bash
/// dart run scripts/fix_short_translations.dart
/// ```
void main() async {
  const localizationDir = 'lib/services/localization';

  // Список языков для обновления
  final languages = [
    'ru',
    'en',
    'es',
    'esMX',
    'fr',
    'frCA',
    'de',
    'it',
    'pt',
    'ptBR',
    'zh',
    'zhTW',
    'ja',
    'ko',
    'ar',
    'hi',
    'th',
    'uk',
    'vi',
    'tr',
    'pl',
    'cs',
    'sk',
    'hr',
    'ro',
    'hu',
    'da',
    'he',
    'id',
    'ca',
    'ms',
    'nl',
    'no',
    'fi',
    'sv',
    'el',
    'fil'
  ];

  stdout.writeln(
      '🔧 Обновление слишком коротких переводов для проблемных ключей...\n');

  int updatedFiles = 0;
  int totalUpdates = 0;

  for (final lang in languages) {
    final fileName = '${lang}_strings.dart';
    final file = File('$localizationDir/$fileName');

    if (!await file.exists()) {
      stdout.writeln('⚠️  Файл $fileName не найден, пропускаем.');
      continue;
    }

    final content = await file.readAsString();
    final translations = _extractTranslations(content);
    final betterTranslations = _getBetterTranslations(lang);

    bool fileUpdated = false;

    for (final entry in betterTranslations.entries) {
      final key = entry.key;
      final betterValue = entry.value;

      if (translations.containsKey(key)) {
        final currentValue = translations[key]!;

        // Новые правила:
        // - Обновляем, если текущий перевод слишком короткий (≤2 символов);
        // - Или если предложенный синоним вписывается в 8 символов
        //   и он длиннее и читабельнее текущего (избавляемся от агрессивных сокращений 3-4 симв.).
        final bool tooShort = currentValue.length <= 2;
        final bool betterCompact = betterValue.length <= 8 &&
            currentValue.isNotEmpty &&
            currentValue.length < betterValue.length &&
            currentValue.length <= 4;
        final shouldUpdate = tooShort || betterCompact;

        if (shouldUpdate) {
          stdout
              .writeln('  🔄 $lang: "$key": "$currentValue" → "$betterValue"');
          translations[key] = betterValue;
          fileUpdated = true;
          totalUpdates++;
        }
      }
    }

    // Добавляем недостающий ключ баннера, если его нет
    const bannerKey = 'premium_banner_short';
    if (!translations.containsKey(bannerKey)) {
      final bannerText = _getBannerText(lang);
      if (bannerText != null) {
        translations[bannerKey] = bannerText;
        fileUpdated = true;
        totalUpdates++;
        stdout.writeln('  ➕ $lang: добавлен "$bannerKey"');
      }
    }

    if (fileUpdated) {
      await _writeTranslationsFile(file, translations, lang);
      updatedFiles++;
      stdout.writeln('  ✅ $lang: файл обновлен');
    } else {
      stdout.writeln('  ℹ️  $lang: обновления не требуются');
    }
  }

  stdout.writeln('\n🎉 Завершено!');
  stdout.writeln('📊 Обновлено файлов: $updatedFiles');
  stdout.writeln('📊 Всего замен: $totalUpdates');

  if (totalUpdates > 0) {
    stdout.writeln('\n💡 Рекомендации:');
    stdout.writeln(
        '  • Проверьте UI на корректность отображения обновленных переводов');
    stdout.writeln(
        '  • Убедитесь, что кнопки правильно отображаются на разных устройствах');
    stdout.writeln(
        '  • При необходимости настройте стили кнопок под новые тексты');
  }
}

/// Извлекает пары `key -> value` из содержимого файла переводов
Map<String, String> _extractTranslations(String content) {
  final Map<String, String> result = {};
  final regExp = RegExp(r"'([^']+)':\s*'((?:\\'|[^'])*?)'", multiLine: true);
  for (final match in regExp.allMatches(content)) {
    final key = match.group(1)!;
    final rawValue = match.group(2)!;
    final value = rawValue.replaceAll("\\'", "'");
    result[key] = value;
  }
  return result;
}

/// Записывает обновленные переводы в файл
Future<void> _writeTranslationsFile(
    File file, Map<String, String> translations, String lang) async {
  final buffer = StringBuffer();
  buffer.writeln('final Map<String, String> ${lang}Strings = {');

  for (final entry in translations.entries) {
    final key = entry.key;
    final value = _sanitizeForDart(entry.value);
    buffer.writeln("  '$key': '$value',");
  }

  buffer.writeln('};');
  await file.writeAsString(buffer.toString());
}

/// Экранирует строку для использования в Dart
String _sanitizeForDart(String value) {
  return value
      .replaceAll('\\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll("\r", '')
      .replaceAll("\n", r"\n");
}

/// Возвращает карту улучшенных переводов для каждого языка (3-7 символов для пола)
Map<String, String> _getBetterTranslations(String lang) {
  switch (lang) {
    case 'ru':
      return {
        'gender_male': 'Мужчина',
        'gender_female': 'Женщина',
        'text_editing_cancel': 'Правка',
      };
    case 'en':
      return {
        'gender_male': 'Male',
        'gender_female': 'Female',
        'text_editing_cancel': 'Edit',
      };
    case 'es':
    case 'esMX':
      return {
        'gender_male': 'Hombre',
        'gender_female': 'Mujer',
        'text_editing_cancel': 'Editar',
      };
    case 'fr':
    case 'frCA':
      return {
        'gender_male': 'Homme',
        'gender_female': 'Femme',
        'text_editing_cancel': 'Éditer',
      };
    case 'de':
      return {
        'gender_male': 'Mann',
        'gender_female': 'Frau',
        'text_editing_cancel': 'Ändern',
      };
    case 'it':
      return {
        'gender_male': 'Uomo',
        'gender_female': 'Donna',
        'text_editing_cancel': 'Cambia',
      };
    case 'pt':
    case 'ptBR':
      return {
        'gender_male': 'Homem',
        'gender_female': 'Mulher',
        'text_editing_cancel': 'Editar',
      };
    case 'zh':
      return {
        'gender_male': '男性',
        'gender_female': '女性',
        'text_editing_cancel': '编辑',
      };
    case 'zhTW':
      return {
        'gender_male': '男性',
        'gender_female': '女性',
        'text_editing_cancel': '編輯',
      };
    case 'ja':
      return {
        'gender_male': '男性',
        'gender_female': '女性',
        'text_editing_cancel': '編集',
      };
    case 'ko':
      return {
        'gender_male': '남성',
        'gender_female': '여성',
        'text_editing_cancel': '편집',
      };
    case 'ar':
      return {
        'gender_male': 'ذكر',
        'gender_female': 'أنثى',
        'text_editing_cancel': 'تعديل',
      };
    case 'hi':
      return {
        'gender_male': 'पुरुष',
        'gender_female': 'महिला',
        'text_editing_cancel': 'संपादन',
      };
    case 'th':
      return {
        'gender_male': 'ชาย',
        'gender_female': 'หญิง',
        'text_editing_cancel': 'แก้ไข',
      };
    case 'uk':
      return {
        'gender_male': 'Чоловік',
        'gender_female': 'Жінка',
        'text_editing_cancel': 'Правка',
      };
    case 'vi':
      return {
        'gender_male': 'Nam',
        'gender_female': 'Nữ',
        'text_editing_cancel': 'Sửa',
      };
    case 'tr':
      return {
        'gender_male': 'Erkek',
        'gender_female': 'Kadın',
        'text_editing_cancel': 'Düzenle',
      };
    case 'pl':
      return {
        'gender_male': 'Mężczyzna',
        'gender_female': 'Kobieta',
        'text_editing_cancel': 'Zmień',
      };
    case 'cs':
      return {
        'gender_male': 'Muž',
        'gender_female': 'Žena',
        'text_editing_cancel': 'Upravit',
      };
    case 'sk':
      return {
        'gender_male': 'Muž',
        'gender_female': 'Žena',
        'text_editing_cancel': 'Upraviť',
      };
    case 'hr':
      return {
        'gender_male': 'Muškarac',
        'gender_female': 'Žena',
        'text_editing_cancel': 'Uredi',
      };
    case 'ro':
      return {
        'gender_male': 'Bărbat',
        'gender_female': 'Femeie',
        'text_editing_cancel': 'Editează',
      };
    case 'hu':
      return {
        'gender_male': 'Férfi',
        'gender_female': 'Nő',
        'text_editing_cancel': 'Módosít',
      };
    case 'da':
      return {
        'gender_male': 'Mand',
        'gender_female': 'Kvinde',
        'text_editing_cancel': 'Rediger',
      };
    case 'he':
      return {
        'gender_male': 'זכר',
        'gender_female': 'נקבה',
        'text_editing_cancel': 'עריכה',
      };
    case 'id':
      return {
        'gender_male': 'Pria',
        'gender_female': 'Wanita',
        'text_editing_cancel': 'Edit',
      };
    case 'ca':
      return {
        'gender_male': 'Home',
        'gender_female': 'Dona',
        'text_editing_cancel': 'Editar',
      };
    case 'ms':
      return {
        'gender_male': 'Lelaki',
        'gender_female': 'Perempuan',
        'text_editing_cancel': 'Edit',
      };
    case 'nl':
      return {
        'gender_male': 'Man',
        'gender_female': 'Vrouw',
        'text_editing_cancel': 'Wijzig',
      };
    case 'no':
      return {
        'gender_male': 'Mann',
        'gender_female': 'Kvinne',
        'text_editing_cancel': 'Endre',
      };
    case 'fi':
      return {
        'gender_male': 'Mies',
        'gender_female': 'Nainen',
        'text_editing_cancel': 'Muuta',
      };
    case 'sv':
      return {
        'gender_male': 'Man',
        'gender_female': 'Kvinna',
        'text_editing_cancel': 'Ändra',
      };
    case 'el':
      return {
        'gender_male': 'Άντρας',
        'gender_female': 'Γυναίκα',
        'text_editing_cancel': 'Αλλαγή',
      };
    case 'fil':
      return {
        'gender_male': 'Lalaki',
        'gender_female': 'Babae',
        'text_editing_cancel': 'Ayusin',
      };
    default:
      return {};
  }
}

/// Тексты для баннера по языкам
String? _getBannerText(String lang) {
  switch (lang) {
    case 'ru':
      return 'У вас бесплатная версия. Попробуйте полную версию.';
    case 'en':
      return 'You are on the free version. Try the full version.';
    case 'es':
    case 'esMX':
      return 'Tienes la versión gratuita. Prueba la versión completa.';
    case 'fr':
    case 'frCA':
      return 'Vous utilisez la version gratuite. Essayez la version complète.';
    case 'de':
      return 'Sie nutzen die kostenlose Version. Probieren Sie die Vollversion aus.';
    case 'it':
      return 'Stai usando la versione gratuita. Prova la versione completa.';
    case 'pt':
    case 'ptBR':
      return 'Você está na versão gratuita. Experimente a versão completa.';
    case 'zh':
      return '您正在使用免费版。试试完整版。';
    case 'zhTW':
      return '您正在使用免費版。試試完整版。';
    case 'ja':
      return '無料版をご利用中です。フルバージョンをお試しください。';
    case 'ko':
      return '무료 버전을 사용 중입니다. 전체 버전을 사용해 보세요.';
    case 'ar':
      return 'أنت تستخدم النسخة المجانية. جرّب النسخة الكاملة.';
    case 'hi':
      return 'आप मुफ्त संस्करण पर हैं। पूर्ण संस्करण आज़माएं।';
    case 'th':
      return 'คุณกำลังใช้เวอร์ชันฟรี ลองเวอร์ชันเต็มดูสิ';
    case 'uk':
      return 'У вас безкоштовна версія. Спробуйте повну версію.';
    case 'vi':
      return 'Bạn đang dùng bản miễn phí. Hãy thử bản đầy đủ.';
    case 'tr':
      return 'Ücretsiz sürümü kullanıyorsunuz. Tam sürümü deneyin.';
    case 'pl':
      return 'Korzystasz z wersji bezpłatnej. Wypróbuj pełną wersję.';
    case 'cs':
      return 'Používáte bezplatnou verzi. Vyzkoušejte plnou verzi.';
    case 'sk':
      return 'Používate bezplatnú verziu. Vyskúšajte plnú verziu.';
    case 'hr':
      return 'Koristite besplatnu verziju. Isprobajte punu verziju.';
    case 'ro':
      return 'Folosiți versiunea gratuită. Încercați versiunea completă.';
    case 'hu':
      return 'Ingyenes verziót használ. Próbálja ki a teljes verziót.';
    case 'da':
      return 'Du bruger gratisversionen. Prøv fuld version.';
    case 'he':
      return 'אתה משתמש בגרסה החינמית. נסה את הגרסה המלאה.';
    case 'id':
      return 'Anda menggunakan versi gratis. Coba versi lengkap.';
    case 'ca':
      return 'Esteu a la versió gratuïta. Proveu la versió completa.';
    case 'ms':
      return 'Anda menggunakan versi percuma. Cuba versi penuh.';
    case 'nl':
      return 'Je gebruikt de gratis versie. Probeer de volledige versie.';
    case 'no':
      return 'Du bruker gratisversjonen. Prøv fullversjonen.';
    case 'fi':
      return 'Käytät ilmaista versiota. Kokeile täysversiota.';
    case 'sv':
      return 'Du använder gratisversionen. Prova fullversionen.';
    case 'el':
      return 'Χρησιμοποιείτε τη δωρεάν έκδοση. Δοκιμάστε την πλήρη έκδοση.';
    case 'fil':
      return 'Libre ang bersyon mo. Subukan ang buong bersyon.';
    default:
      return null;
  }
}
