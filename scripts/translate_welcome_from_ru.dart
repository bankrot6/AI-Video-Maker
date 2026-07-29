import 'dart:io';
import 'package:translator/translator.dart';

/// Скрипт переводит приветственное сообщение чата (chat_welcome_message)
/// ИМЕННО из русской версии во все языки, сохраняя разметку и переносы строк.
///
/// Запуск:
///   dart run scripts/translate_welcome_from_ru.dart
///
Future<void> main() async {
  const localizationDir = 'lib/services/localization';
  const ruFileName = 'ru_strings.dart';

  final ruFile = File('$localizationDir/$ruFileName');
  if (!await ruFile.exists()) {
    stderr.writeln('❌ Не найден ru_strings.dart');
    exit(1);
  }

  final ruContent = await ruFile.readAsString();
  final ruMap = _extractTranslations(ruContent);
  String? ruWelcome;

  // 1) Пытаемся взять эталон ИЗ БЭКАПА (приоритетно, чтобы точно восстановить оригинальный длинный текст)
  final backupFile =
      File('lib/features/ai_chat/providers/chat_providers.dart.backup');
  if (await backupFile.exists()) {
    final backup = await backupFile.readAsString();
    final match = RegExp(r"'👋 Привет![\s\S]*?мои советы! 😊'", multiLine: true)
        .firstMatch(backup);
    if (match != null) {
      ruWelcome = match.group(0);
      if (ruWelcome != null && ruWelcome.startsWith("'")) {
        ruWelcome = ruWelcome.substring(1, ruWelcome.length - 1);
      }
    }
  }

  // 2) Если по какой-то причине не нашли в бэкапе — берём из текущего ru_strings.dart
  ruWelcome ??= ruMap['chat_welcome_message'];
  if (ruWelcome == null) {
    stderr.writeln('❌ В ru_strings.dart отсутствует ключ chat_welcome_message');
    exit(1);
  }

  // Нормализуем исходник (для записи в ru)
  final ruWelcomeOriginal = _normalizeWelcomeSource(ruWelcome);

  // Готовим версию ТОЛЬКО для перевода с плейсхолдерами (ru не меняем)
  String ruWelcomeForTranslation = ruWelcomeOriginal
      .replaceAll('**контекстного анализа**', '**__CONTEXT_ANALYSIS__**')
      .replaceAll('контекстного анализа', '__CONTEXT_ANALYSIS__')
      .replaceAll('БЖУ', '__MACROS__');

  final translator = GoogleTranslator();

  // Ручные литературные переводы для языков.
  // Если язык присутствует в словаре, он будет использован вместо автоперевода.
  final Map<String, String> manualWelcomeByLang = {
    'en':
        '👋 Hello! I\'m your personal AI dietitian with **contextual analysis**.\n\n🧠 **What I can do:**\n• 📊 I analyze your weekly nutrition data\n• 🎯 I evaluate your progress toward personal goals\n• ⚖️ I check the balance of macros in your diet\n• 💡 I give personalized recommendations\n• 📈 I track your weight trends\n\n🚀 **For a precise analysis**, use the buttons below or type "analysis", "progress", "recommendations".\n\nThe more data you add to the app, the more accurate my tips will be! 😊',
    'fr':
        '👋 Bonjour\u00a0! Je suis votre di\u00e9t\u00e9ticien IA personnel avec **analyse contextuelle**.\n\n🧠 **Ce que je peux faire\u00a0:**\n• 📊 Analyser vos donn\u00e9es alimentaires de la semaine\n• 🎯 \u00c9valuer vos progr\u00e8s par rapport \u00e0 vos objectifs personnels\n• ⚖️ V\u00e9rifier l\u2019\u00e9quilibre des macronutriments de votre alimentation\n• 💡 Donner des recommandations personnalis\u00e9es\n• 📈 Suivre l\u2019\u00e9volution de votre poids\n\n🚀 **Pour une analyse pr\u00e9cise**, utilisez les boutons ci\u2011dessous ou \u00e9crivez \u00ab\u00a0analyse\u00a0\u00bb, \u00ab\u00a0progr\u00e8s\u00a0\u00bb, \u00ab\u00a0recommandations\u00a0\u00bb.\n\nPlus vous ajoutez de donn\u00e9es dans l\'application, plus mes conseils seront pr\u00e9cis\u00a0! 😊',
    'frCA':
        '👋 Bonjour\u00a0! Je suis votre di\u00e9t\u00e9tiste IA personnel avec **analyse contextuelle**.\n\n🧠 **Ce que je peux faire\u00a0:**\n• 📊 Analyser vos donn\u00e9es alimentaires de la semaine\n• 🎯 \u00c9valuer vos progr\u00e8s par rapport \u00e0 vos objectifs personnels\n• ⚖️ V\u00e9rifier l\u2019\u00e9quilibre des macronutriments dans votre alimentation\n• 💡 Donner des recommandations personnalis\u00e9es\n• 📈 Suivre l\u2019\u00e9volution de votre poids\n\n🚀 **Pour une analyse pr\u00e9cise**, utilisez les boutons ci\u2011dessous ou \u00e9crivez \u00ab analyse \u00bb, \u00ab progr\u00e8s \u00bb, \u00ab recommandations \u00bb.\n\nPlus vous ajoutez de donn\u00e9es dans l\'app, plus mes conseils seront pr\u00e9cis\u00a0! 😊',
    'es':
        '👋 \u00a1Hola! Soy tu dietista con IA personal con **an\u00e1lisis contextual**.\n\n🧠 **Qu\u00e9 puedo hacer:**\n• 📊 Analizo tus datos de alimentaci\u00f3n de la semana\n• 🎯 Eval\u00faa el progreso hacia tus objetivos personales\n• ⚖️ Reviso el equilibrio de macronutrientes en tu dieta\n• 💡 Doy recomendaciones personalizadas\n• 📈 Sigo la evoluci\u00f3n de tu peso\n\n🚀 **Para un an\u00e1lisis preciso**, usa los botones de abajo o escribe \u00ab an\u00e1lisis \u00bb, \u00ab progreso \u00bb, \u00ab recomendaciones \u00bb.\n\n\u00a1Cuantos m\u00e1s datos a\u00f1adas a la app, m\u00e1s precisos ser\u00e1n mis consejos! 😊',
    'esMX':
        '👋 \u00a1Hola! Soy tu nutri\u00f3logo con IA personal con **an\u00e1lisis contextual**.\n\n🧠 **Qu\u00e9 puedo hacer:**\n• 📊 Analizo tus datos de alimentaci\u00f3n de la semana\n• 🎯 Eval\u00fao el avance hacia tus metas personales\n• ⚖️ Reviso el equilibrio de macronutrientes en tu dieta\n• 💡 Doy recomendaciones personalizadas\n• 📈 Doy seguimiento a la tendencia de tu peso\n\n🚀 **Para un an\u00e1lisis preciso**, usa los botones de abajo o escribe \u00ab an\u00e1lisis \u00bb, \u00ab progreso \u00bb, \u00ab recomendaciones \u00bb.\n\n\u00a1Entre m\u00e1s datos agregues a la app, m\u00e1s certeras ser\u00e1n mis sugerencias! 😊',
    'de':
        '👋 Hallo! Ich bin dein pers\u00f6nlicher KI\u2011Ern\u00e4hrungsberater mit **kontextueller Analyse**.\n\n🧠 **Was ich kann:**\n• 📊 Ich analysiere deine Ern\u00e4hrungsdaten der Woche\n• 🎯 Ich bewerte deinen Fortschritt zu deinen pers\u00f6nlichen Zielen\n• ⚖️ Ich pr\u00fcfe die Makron\u00e4hrstoff\u2011Balance in deiner Ern\u00e4hrung\n• 💡 Ich gebe personalisierte Empfehlungen\n• 📈 Ich verfolge deine Gewichtsentwicklung\n\n🚀 **F\u00fcr eine pr\u00e4zise Analyse** nutze die Buttons unten oder tippe \u00ab Analyse \u00bb, \u00ab Fortschritt \u00bb, \u00ab Empfehlungen \u00bb.\n\nJe mehr Daten du in der App erfasst, desto treffsicherer werden meine Tipps! 😊',
    'it':
        '👋 Ciao! Sono il tuo dietista IA personale con **analisi contestuale**.\n\n🧠 **Cosa posso fare:**\n• 📊 Analizzo i tuoi dati alimentari settimanali\n• 🎯 Valuto i progressi verso i tuoi obiettivi personali\n• ⚖️ Verifico l\u2019equilibrio dei macronutrienti nella tua dieta\n• 💡 Fornisco raccomandazioni personalizzate\n• 📈 Traccio l\u2019andamento del tuo peso\n\n🚀 **Per un\u2019analisi precisa**, usa i pulsanti qui sotto oppure scrivi \u00ab analisi \u00bb, \u00ab progresso \u00bb, \u00ab raccomandazioni \u00bb.\n\nPi\u00f9 dati aggiungi all\'app, pi\u00f9 precisi saranno i miei consigli! 😊',
    'pt':
        '👋 Ol\u00e1! Sou o seu nutricionista com IA com **an\u00e1lise contextual**.\n\n🧠 **O que eu fa\u00e7o:**\n• 📊 Analiso os seus dados de alimenta\u00e7\u00e3o da semana\n• 🎯 Avalio o progresso em rela\u00e7\u00e3o \u00e0s suas metas pessoais\n• ⚖️ Verifico o equil\u00edbrio de macronutrientes na sua dieta\n• 💡 Dou recomenda\u00e7\u00f5es personalizadas\n• 📈 Acompanho a evolu\u00e7\u00e3o do seu peso\n\n🚀 **Para uma an\u00e1lise precisa**, use os bot\u00f5es abaixo ou escreva \u00ab an\u00e1lise \u00bb, \u00ab progresso \u00bb, \u00ab recomenda\u00e7\u00f5es \u00bb.\n\nQuanto mais dados voc\u00ea adicionar ao app, mais precisas ser\u00e3o minhas dicas! 😊',
    'ptBR':
        '👋 Ol\u00e1! Sou o seu nutricionista com IA, com **an\u00e1lise contextual**.\n\n🧠 **O que posso fazer:**\n• 📊 Analiso seus dados de alimenta\u00e7\u00e3o da semana\n• 🎯 Avalio o progresso em rela\u00e7\u00e3o \u00e0s suas metas pessoais\n• ⚖️ Verifico o equil\u00edbrio de macronutrientes na sua dieta\n• 💡 Dou recomenda\u00e7\u00f5es personalizadas\n• 📈 Acompanho a tend\u00eancia do seu peso\n\n🚀 **Para uma an\u00e1lise precisa**, use os bot\u00f5es abaixo ou digite \u00ab an\u00e1lise \u00bb, \u00ab progresso \u00bb, \u00ab recomenda\u00e7\u00f5es \u00bb.\n\nQuanto mais dados voc\u00ea adicionar ao aplicativo, mais precisas ser\u00e3o as minhas dicas! 😊',
    'tr':
        '👋 Merhaba! **Ba\u011flamsal analiz** \u00f6zelli\u011fine sahip ki\u015fisel Yapay Zek\u00e2 diyetisyeninizim.\n\n🧠 **Neler yapar\u0131m:**\n• 📊 Haftal\u0131k beslenme verilerinizi analiz ederim\n• 🎯 Ki\u015fisel hedeflerinize ilerlemenizi de\u011ferlendiririm\n• ⚖️ Diyetinizdeki makrolar\u0131n dengesini kontrol ederim\n• 💡 Ki\u015fiselle\u015ftirilmi\u015f \u00f6neriler sunar\u0131m\n• 📈 Kilo trendinizi takip ederim\n\n🚀 **Daha isabetli bir analiz i\u00e7in** a\u015fa\u011f\u0131daki d\u00fc\u011fmeleri kullan\u0131n veya \u201canaliz\u201d, \u201cilerleme\u201d, \u201c\u00f6neriler\u201d yaz\u0131n.\n\nUygulamaya ne kadar \u00e7ok veri eklerseniz, \u00f6nerilerim o kadar isabetli olur! 😊',
    'uk':
        '👋 \u041f\u0440\u0438\u0432\u0456\u0442! \u042f \u0432\u0430\u0448 \u043f\u0435\u0440\u0441\u043e\u043d\u0430\u043b\u044c\u043d\u0438\u0439 \u0406\u0406\u2011\u0434\u0456\u0454\u0442\u043e\u043b\u043e\u0433 \u0456\u0437 \u0444\u0443\u043d\u043a\u0446\u0456\u0454\u044e **\u043a\u043e\u043d\u0442\u0435\u043a\u0441\u0442\u043d\u043e\u0433\u043e \u0430\u043d\u0430\u043b\u0456\u0437\u0443**.\n\n🧠 **\u0429\u043e \u044f \u0432\u043c\u0456\u044e:**\n• 📊 \u0410\u043d\u0430\u043b\u0456\u0437\u0443\u044e \u0432\u0430\u0448\u0456 \u0434\u0430\u043d\u0456 \u0445\u0430\u0440\u0447\u0443\u0432\u0430\u043d\u043d\u044f \u0437\u0430 \u0442\u0438\u0436\u0434\u0435\u043d\n• 🎯 \u041e\u0446\u0456\u043d\u044e\u044e \u043f\u0440\u043e\u0433\u0440\u0435\u0441 \u0449\u043e\u0434\u043e \u0432\u0430\u0448\u0438\u0445 \u043f\u0435\u0440\u0441\u043e\u043d\u0430\u043b\u044c\u043d\u0438\u0445 \u0446\u0456\u043b\u0435\u0439\n• ⚖️ \u041f\u0435\u0440\u0435\u0432\u0456\u0440\u044f\u044e \u0431\u0430\u043b\u0430\u043d\u0441 \u043c\u0430\u043a\u0440\u043e\u043d\u0443\u0442\u0440\u0456\u0454\u043d\u0442\u0456\u0432 \u0443 \u0440\u0430\u0446\u0456\u043e\u043d\u0456\n• 💡 \u0414\u0430\u044e \u043f\u0435\u0440\u0441\u043e\u043d\u0430\u043b\u0456\u0437\u043e\u0432\u0430\u043d\u0456 \u0440\u0435\u043a\u043e\u043c\u0435\u043d\u0434\u0430\u0446\u0456\u0457\n• 📈 \u0412\u0456\u0434\u0441\u0442\u0435\u0436\u0443\u044e \u0434\u0438\u043d\u0430\u043c\u0456\u043a\u0443 \u0432\u0430\u0433\u0438\n\n🚀 **\u0414\u043b\u044f \u0442\u043e\u0447\u043d\u043e\u0433\u043e \u0430\u043d\u0430\u043b\u0456\u0437\u0443** \u0441\u043a\u043e\u0440\u0438\u0441\u0442\u0430\u0439\u0442\u0435\u0441\u044c \u043a\u043d\u043e\u043f\u043a\u0430\u043c\u0438 \u043d\u0438\u0436\u0447\u0435 \u0430\u0431\u043e \u043d\u0430\u043f\u0438\u0448\u0456\u0442\u044c \u00ab\u0430\u043d\u0430\u043b\u0456\u0437\u00bb, \u00ab\u043f\u0440\u043e\u0433\u0440\u0435\u0441\u00bb, \u00ab\u0440\u0435\u043a\u043e\u043c\u0435\u043d\u0434\u0430\u0446\u0456\u0457\u00bb.\n\n\u0427\u0438\u043c \u0431\u0456\u043b\u044c\u0448\u0435 \u0434\u0430\u043d\u0438\u0445 \u0432\u0438 \u0434\u043e\u0434\u0430\u0441\u0442\u0435 \u0432 \u0437\u0430\u0441\u0442\u043e\u0441\u0443\u043d\u043e\u043a, \u0442\u0438\u043c \u0442\u043e\u0447\u043d\u0456\u0448\u0438\u043c\u0438 \u0431\u0443\u0434\u0443\u0442\u044c \u043c\u043e\u0457 \u043f\u043e\u0440\u0430\u0434\u0438! 😊',
    'pl':
        '👋 Cze\u015b\u0107! Jestem Twoim osobistym dietetykiem AI z **analiz\u0105 kontekstow\u0105**.\n\n🧠 **Co potrafi\u0119:**\n• 📊 Analizuj\u0119 Twoje tygodniowe dane \u017cywieniowe\n• 🎯 Oceniam post\u0119py w kierunku Twoich cel\u00f3w\n• ⚖️ Sprawdzam r\u00f3wnowag\u0119 makrosk\u0142adnik\u00f3w w diecie\n• 💡 Daj\u0119 spersonalizowane rekomendacje\n• 📈 \u015aledz\u0119 dynamik\u0119 masy cia\u0142a\n\n🚀 **Aby uzyska\u0107 precyzyjn\u0105 analiz\u0119**, u\u017cyj przycisk\u00f3w poni\u017cej lub wpisz \u00ab analiza \u00bb, \u00ab post\u0119p \u00bb, \u00ab rekomendacje \u00bb.\n\nIm wi\u0119cej danych dodasz do aplikacji, tym trafniejsze b\u0119d\u0105 moje wskaz\u00f3wki! 😊',
    'cs':
        '👋 Ahoj! Jsem tv\u016fj osobn\u00ed dietolog s AI s **kontextovou anal\u00fdzou**.\n\n🧠 **Co um\u00edm:**\n• 📊 Analyzuji tv\u00e1 data o stravov\u00e1n\u00ed za posledn\u00ed t\u00fdden\n• 🎯 Hodnot\u00edm pokrok vzhledem k tv\u00fdm c\u00edl\u016fm\n• ⚖️ Kontroluji rovnov\u00e1hu makro\u017eivin v j\u00eddeln\u00ed\u010dku\n• 💡 D\u00e1v\u00e1m personalizovan\u00e1 doporu\u010den\u00ed\n• 📈 Sleduji v\u00fdvoj hmotnosti\n\n🚀 **Pro p\u0159esnou anal\u00fdzu** pou\u017eij tla\u010d\u00edtka dole nebo napi\u0161 \u00ab anal\u00fdza \u00bb, \u00ab pokrok \u00bb, \u00ab doporu\u010den\u00ed \u00bb.\n\n\u010c\u00edm v\u00edce dat do aplikace p\u0159id\u00e1\u0161, t\u00edm p\u0159esn\u011bj\u0161\u00ed budou moje rady! 😊',
    'sk':
        '👋 Ahoj! Som tvoj osobn\u00fd AI di\u00e9tolog s **kontextovou anal\u00fdzou**.\n\n🧠 **\u010co viem:**\n• 📊 Analyzujem tvoje t\u00fd\u017ed\u0148ov\u00e9 stravovacie d\u00e1ta\n• 🎯 Hodnot\u00edm pokrok smerom k tvojim cie\u013eom\n• ⚖️ Kontrolujem rovnov\u00e1hu makro\u017eiv\u00edn v jed\u00e1lni\u010dku\n• 💡 D\u00e1vam personalizovan\u00e9 odpor\u00fa\u010dania\n• 📈 Sledujem v\u00fdvoj hmotnosti\n\n🚀 **Pre presn\u00fa anal\u00fdzu** pou\u017ei tla\u010didl\u00e1 ni\u017e\u0161ie alebo nap\u00ed\u0161 \u00ab anal\u00fdza \u00bb, \u00ab pokrok \u00bb, \u00ab odpor\u00fa\u010dania \u00bb.\n\n\u010c\u00edm viac d\u00e1t prid\u00e1\u0161 do aplik\u00e1cie, t\u00edm presnej\u0161ie bud\u00fa moje tipy! 😊',
    'ro':
        '👋 Salut! Sunt nutri\u021bionistul t\u0103u cu IA, cu **analiz\u0103 contextual\u0103**.\n\n🧠 **Ce pot face:**\n• 📊 Analizez datele tale alimentare pe ultima s\u0103pt\u0103m\u00e2n\u0103\n• 🎯 Evaluez progresul spre obiectivele tale personale\n• ⚖️ Verific echilibrul macronutrien\u021bilor din diet\u0103\n• 💡 Ofer recomand\u0103ri personalizate\n• 📈 Urm\u0103resc evolu\u021bia greut\u0103\u021bii\n\n🚀 **Pentru o analiz\u0103 precis\u0103**, folose\u0219te butoanele de mai jos sau scrie \u00ab analiz\u0103 \u00bb, \u00ab progres \u00bb, \u00ab recomand\u0103ri \u00bb.\n\nCu c\u00e2t adaugi mai multe date \u00een aplica\u021bie, cu at\u00e2t recomand\u0103rile mele vor fi mai precise! 😊',
    'hu':
        '👋 Szia! A szem\u00e9lyes MI\u2011dietetikusod vagyok **kontextu\u00e1lis elemz\u00e9ssel**.\n\n🧠 **Amit tudok:**\n• 📊 Elemzem a heti t\u00e1pl\u00e1lkoz\u00e1si adataidat\n• 🎯 \u00c9rt\u00e9kelem a szem\u00e9lyes c\u00e9ljaid fel\u00e9 tett el\u0151rel\u00e9p\u00e9st\n• ⚖️ Ellen\u0151rz\u00f6m a makrot\u00e1panyagok egyens\u00falyt az \u00e9trendben\n• 💡 Szem\u00e9lyre szabott aj\u00e1nlasokat adok\n• 📈 Nyomon k\u00f6vetem a tests\u00falyod alakul\u00e1s\u00e1t\n\n🚀 **A pontos elemz\u00e9shez** haszn\u00e1ld az al\u00e1bbi gombokat, vagy \u00edrd be: \u00ab elemz\u00e9s \u00bb, \u00ab halad\u00e1s \u00bb, \u00ab aj\u00e1nlasok \u00bb.\n\nMin\u00e9l t\u00f6bb adatot adsz a\u00b7applik\u00e1ci\u00f3hoz, ann\u00e1l pontosabbak lesznek a tan\u00e1csaim! 😊',
    'hr':
        '👋 Bok! Tvoj sam osobni AI dijeteti\u010dar s **kontekstualnom analizom**.\n\n🧠 **\u0160to mogu:**\n• 📊 Analiziram tvoje tjedne podatke o prehrani\n• 🎯 Procjenjujem napredak prema osobnim ciljevima\n• ⚖️ Provjeravam ravnote\u017eu makronutrijenata u prehrani\n• 💡 Dajem personalizirane preporuke\n• 📈 Pratim kretanje tvoje te\u017eine\n\n🚀 **Za preciznu analizu** koristi gumbe ispod ili upi\u0161i \u00ab analiza \u00bb, \u00ab napredak \u00bb, \u00ab preporuke \u00bb.\n\n\u0160to vi\u0161e podataka doda\u0161 u aplikaciju, to \u0107e moji savjeti biti precizniji! 😊',
    'nl':
        '👋 Hoi! Ik ben je persoonlijke AI\u2011di\u00ebtist met **contextuele analyse**.\n\n🧠 **Wat ik doe:**\n• 📊 Ik analyseer je voeding van de afgelopen week\n• 🎯 Ik beoordeel je voortgang richting je persoonlijke doelen\n• ⚖️ Ik controleer de balans van macronutri\u00ebnten in je dieet\n• 💡 Ik geef persoonlijke aanbevelingen\n• 📈 Ik volg je gewichtstrends\n\n🚀 **Voor een precieze analyse** gebruik je de knoppen hieronder of typ je \u201canalyse\u201d, \u201cprogressie\u201d, \u201caanbevelingen\u201d.\n\nHoe meer gegevens je toevoegt, hoe nauwkeuriger mijn tips worden! 😊',
    'da':
        '👋 Hej! Jeg er din personlige AI\u2011di\u00e6tist med **kontekstuel analyse**.\n\n🧠 **Hvad jeg kan:**\n• 📊 Jeg analyserer dine ugentlige kostdata\n• 🎯 Jeg vurderer fremskridt mod dine personlige m\u00e5l\n• ⚖️ Jeg tjekker balancen af makron\u00e6ringsstoffer i din kost\n• 💡 Jeg giver personlige anbefalinger\n• 📈 Jeg f\u00f8lger din v\u00e6gtudvikling\n\n🚀 **For en pr\u00e6cis analyse** skal du bruge knapperne nedenfor eller skrive \u201danalyse\u201d, \u201dfremskridt\u201d, \u201danbefalinger\u201d.\n\nJo flere data du tilf\u00f8jer i appen, desto mere pr\u00e6cise bliver mine r\u00e5d! 😊',
    'fi':
        '👋 Hei! Olen henkil\u00f6kohtainen teko\u00e4lyravitsemusterapeuttisi, jolla on **kontekstianalyysi**.\n\n🧠 **M\u00e4 k\u00e4rsin:**\n• 📊 Analysoin viikon ravintotietosi\n• 🎯 Arvioin edistymist\u00e4si kohti omia tavoitteitasi\n• ⚖️ Tarkistan ruokavaliosi makroravintoaineiden tasapainon\n• 💡 Annan yksil\u00f6llisi\u00e4 suosituksia\n• 📈 Seuraan painonkehityst\u00e4si\n\n🚀 **Tarkan analyysin saamiseksi** k\u00e4yt\u00e4 alla olevia painikkeita tai kirjoita \u201danalyysi\u201d, \u201cedistyminen\u201d, \u201dsuositukset\u201d.\n\nMitä enemmän lisäät dataa sovellukseen, sitä tarkempia vinkkini ovat! 😊',
    'no':
        '👋 Hei! Jeg er din personlige KI\u2011ern\u00e6ringsr\u00e5dgiver med **kontekstuell analyse**.\n\n🧠 **Hva jeg kan:**\n• 📊 Jeg analyserer ukens kostholdsdata\n• 🎯 Jeg vurderer fremdrift mot dine personlige m\u00e5l\n• ⚖️ Jeg sjekker balansen av makron\u00e6ringsstoffer i kostholdet ditt\n• 💡 Jeg gir personlige anbefalinger\n• 📈 Jeg f\u00f8lger vektutviklingen din\n\n🚀 **For en presis analyse** bruk knappene nedenfor eller skriv \u00ab analyse \u00bb, \u00ab fremdrift \u00bb, \u00ab anbefalinger \u00bb.\n\nJo mer data du legger inn i appen, jo mer treffsikre blir r\u00e5dene mine! 😊',
    'sv':
        '👋 Hej! Jag \u00e4r din personliga AI\u2011dietist med **kontextuell analys**.\n\n🧠 **Det h\u00e4r kan jag:**\n• 📊 Jag analyserar dina veckovisa kostdata\n• 🎯 Jag bed\u00f6mer dina framsteg mot personliga m\u00e5l\n• ⚖️ Jag kontrollerar balansen av makron\u00e4rings\u00e4mnen i din kost\n• 💡 Jag ger personliga rekommendationer\n• 📈 Jag f\u00f6ljer din viktutveckling\n\n🚀 **F\u00f6r en exakt analys** anv\u00e4nd knapparna nedan eller skriv \u201danalys\u201d, \u201dframsteg\u201d, \u201drekommendationer\u201d.\n\nJu mer data du l\u00e4gger in, desto mer tr\u00e4ffs\u00e4kra blir mina tips! 😊',
    'el':
        '👋 Γεια σου! Είμαι ο προσωπικός σου διαιτολόγος με ΤΝ με **ανάλυση συμφραζομένων**.\n\n🧠 **Τι μπορώ να κάνω:**\n• 📊 Αναλύω τα εβδομαδιαία διατροφικά σου δεδομένα\n• 🎯 Αξιολογώ την πρόοδο προς τους προσωπικούς σου στόχους\n• ⚖️ Ελέγχω την ισορροπία των μακροθρεπτικών συστατικών στη διατροφή σου\n• 💡 Δίνω εξατομικευμένες συστάσεις\n• 📈 Παρακολουθώ την πορεία του βάρους σου\n\n🚀 **Για ακριβή ανάλυση**, χρησιμοποίησε τα κουμπιά παρακάτω ή γράψε «ανάλυση», «πρόοδος», «συστάσεις».\n\nΌσο περισσότερα δεδομένα προσθέτεις στην εφαρμογή, τόσο πιο ακριβείς θα είναι οι συμβουλές μου! 😊',
    'ca':
        '👋 Hola! Soc el teu dietista amb IA personal amb **an\u00e0lisi contextual**.\n\n🧠 **Qu\u00e8 puc fer:**\n• 📊 Analitzo les teves dades d\'alimentaci\u00f3 de la setmana\n• 🎯 Avaluo el progr\u00e9s cap als teus objectius personals\n• ⚖️ Comprovo l\'equilibri de macronutrients a la teva dieta\n• 💡 Proporciono recomanacions personalitzades\n• 📈 Faig el seguiment de l\'evoluci\u00f3 del teu pes\n\n🚀 **Per a una an\u00e0lisi precisa**, fes servir els botons de sota o escriu \u00ab an\u00e0lisi \u00bb, \u00ab progr\u00e9s \u00bb, \u00ab recomanacions \u00bb.\n\nCom m\u00e9s dades afegeixis a l\'app, m\u00e9s precises seran les meves recomanacions! 😊',
    'he':
        '👋 שלום! אני הדיאטנית האישית שלך עם בינה מלאכותית ו**ניתוח הקשרי**.\n\n🧠 **מה אני יכולה לעשות:**\n• 📊 מנתחת את נתוני התזונה השבועיים שלך\n• 🎯 מעריכה את ההתקדמות לעבר היעדים האישיים שלך\n• ⚖️ בודקת את האיזון של המאקרונוטריאנטים בתזונה\n• 💡 נותנת המלצות מותאמות אישית\n• 📈 עוקבת אחרי מגמת המשקל שלך\n\n🚀 **לניתוח מדויק**, השתמש/י בכפתורים למטה או כתוב/כתבי "ניתוח", "התקדמות", "המלצות".\n\nככל שתוסיפ/י יותר נתונים לאפליקציה, כך העצות שלי יהיו מדויקות יותר! 😊',
    'ar':
        '👋 مرحبًا! أنا اختصاصي التغذية الشخصي بالذكاء الاصطناعي مع **تحليل سياقي**.\n\n🧠 **ماذا أستطيع أن أفعل:**\n• 📊 أحلل بيانات تغذيتك الأسبوعية\n• 🎯 أقيّم تقدمك نحو أهدافك الشخصية\n• ⚖️ أتحقق من توازن المغذيات الكبيرة في نظامك الغذائي\n• 💡 أقدم توصيات مخصصة\n• 📈 أتابع تغيّر وزنك مع الوقت\n\n🚀 **لتحليل أدق**، استخدم الأزرار أدناه أو اكتب "تحليل"، "تقدّم"، "توصيات".\n\nكلما أضفت بيانات أكثر إلى التطبيق، كانت نصائحي أدق! 😊',
    'id':
        '👋 Halo! Saya ahli gizi pribadi berbasis AI dengan **analisis kontekstual**.\n\n🧠 **Yang bisa saya lakukan:**\n• 📊 Menganalisis data nutrisi mingguan Anda\n• 🎯 Mengevaluasi kemajuan menuju tujuan pribadi Anda\n• ⚖️ Memeriksa keseimbangan makronutrien dalam diet Anda\n• 💡 Memberikan rekomendasi yang dipersonalisasi\n• 📈 Melacak tren berat badan Anda\n\n🚀 **Agar analisis lebih akurat**, gunakan tombol di bawah atau ketik "analisis", "progres", "rekomendasi".\n\nSemakin banyak data yang Anda tambahkan ke aplikasi, semakin tepat saran saya! 😊',
    'ms':
        '👋 Hai! Saya pakar diet peribadi berteraskan AI dengan **analisis kontekstual**.\n\n🧠 **Apa yang saya boleh lakukan:**\n• 📊 Menganalisis data pemakanan mingguan anda\n• 🎯 Menilai kemajuan terhadap matlamat peribadi anda\n• ⚖️ Menyemak keseimbangan makronutrien dalam diet anda\n• 💡 Memberi saran yang diperibadikan\n• 📈 Menjejak perubahan berat badan anda\n\n🚀 **Untuk analisis yang tepat**, gunakan butang di bawah atau taip "analisis", "kemajuan", "cadangan".\n\nLebih banyak data yang anda tambah ke aplikasi, lebih tepat cadangan saya! 😊',
    'vi':
        '👋 Xin ch\u00e0o! T\u00f4i l\u00e0 chuy\u00ean gia d\u01b0\u1ee1ng l\u01b0\u1ee3ng AI c\u00e1 nh\u00e2n v\u1edbi **ph\u00e2n t\u00edch ng\u1eef c\u1ea3nh**.\n\n🧠 **T\u00f4i c\u00f3 th\u1ec3:**\n• 📊 Ph\u00e2n t\u00edch d\u1eef li\u1ec7u dinh d\u01b0\u1ee1ng h\u00e0ng tu\u1ea7n c\u1ee7a b\u1ea1n\n• 🎯 \u0110\u00e1nh gi\u00e1 ti\u1ebfn \u0111\u1ed9 h\u01b0\u1edbng \u0111\u1ebfn m\u1ee5c ti\u00eau c\u00e1 nh\u00e2n\n• ⚖️ Ki\u1ec3m tra s\u1ef1 c\u00e2n b\u1eb1ng c\u00e1c ch\u1ea5t d\u01b0\u1ee1ng \u0111a l\u01b0\u1ee3ng trong ch\u1ebf \u0111\u1ed9\n• 💡 \u0110\u01b0a ra khuy\u00ean ngh\u1ecb c\u00e1 nh\u00e2n h\u00f3a\n• 📈 Theo d\u00f5i xu h\u01b0\u1edbng c\u00e2n n\u1eb7ng\n\n🚀 **\u0110\u1ec3 ph\u00e2n t\u00edch ch\u00ednh x\u00e1c**, h\u00e3y d\u00f9ng c\u00e1c n\u00fat b\u00ean d\u01b0\u1edbi ho\u1eb7c g\u00f5 "ph\u00e2n t\u00edch", "ti\u1ebfn \u0111\u1ed9", "khuy\u00ean ngh\u1ecb".\n\nC\u00e0ng th\u00eam nhi\u1ec1u d\u1eef li\u1ec7u v\u00e0o \u1ee9ng d\u1ee5ng, l\u1eddi khuy\u00ean c\u1ee7a t\u00f4i s\u1ebd c\u00e0ng ch\u00ednh x\u00e1c! 😊',
    'th':
        '👋 สวัสดี! ฉันคือนักโภชนาการส่วนตัวที่ขับเคลื่อนด้วย AI พร้อมความสามารถ **วิเคราะห์ตามบริบท**\n\n🧠 **ฉันทำอะไรได้บ้าง:**\n• 📊 วิเคราะห์ข้อมูลโภชนาการรายสัปดาห์ของคุณ\n• 🎯 ประเมินความก้าวหน้าตามเป้าหมายส่วนบุคคล\n• ⚖️ ตรวจสอบสมดุลของสารอาหารหลัก (macros) ในอาหารของคุณ\n• 💡 ให้คำแนะนำแบบเฉพาะบุคคล\n• 📈 ติดตามแนวโน้มน้ำหนักของคุณ\n\n🚀 **เพื่อการวิเคราะห์ที่แม่นยำ**, ใช้ปุ่มด้านล่างหรือพิมพ์ว่า "วิเคราะห์", "ความก้าวหน้า", "คำแนะนำ"\n\nยิ่งคุณเพิ่มข้อมูลในแอปมากเท่าไร คำแนะนำของฉันก็ยิ่งแม่นยำมากขึ้นเท่านั้น! 😊',
    'fil':
        '👋 Kumusta! Ako ang iyong personal na AI dietitian na may **contextual analysis**.\n\n🧠 **Ano ang kaya kong gawin:**\n• 📊 Sinusuri ko ang iyong lingguhang datos sa nutrisyon\n• 🎯 Tinatasa ko ang pag‑usad patungo sa iyong mga personal na layunin\n• ⚖️ Tinitingnan ko ang balanse ng mga macronutrient sa iyong diyeta\n• 💡 Nagbibigay ako ng personalisadong rekomendasyon\n• 📈 Tinutunton ko ang trend ng timbang mo\n\n🚀 **Para sa mas tumpak na pagsusuri**, gamitin ang mga button sa ibaba o i‑type ang “analysis”, “progress”, “recommendations”.\n\nKapag mas maraming datos ang idinadagdag mo sa app, mas eksakto ang aking mga payo! 😊',
    'ja':
        '👋 こんにちは！ **コンテキスト分析** を備えたあなたのパーソナルAI栄養士です。\n\n🧠 **できること：**\n• 📊 1週間の食事データを分析します\n• 🎯 あなたの個人目標への進捗を評価します\n• ⚖️ 食事中のマクロ栄養素のバランスを確認します\n• 💡 パーソナライズされたアドバイスを提供します\n• 📈 体重の推移を追跡します\n\n🚀 **正確な分析のために**、下のボタンを使うか「分析」「進捗」「おすすめ」と入力してください。\n\nアプリにデータを追加するほど、私の提案はより正確になります！ 😊',
    'ko':
        '👋 안녕하세요! **컨텍스트 분석** 기능을 갖춘 여러분의 개인 AI 영양사입니다.\n\n🧠 **제가 할 수 있는 일:**\n• 📊 일주일 식단 데이터를 분석해요\n• 🎯 개인 목표 달성 진행도를 평가해요\n• ⚖️ 식단의 거대영양소(매크로) 균형을 점검해요\n• 💡 개인 맞춤형 추천을 드려요\n• 📈 체중 추이를 추적해요\n\n🚀 **정확한 분석을 위해** 아래 버튼을 사용하거나 "분석", "진행 상황", "추천"을 입력하세요.\n\n앱에 데이터를 더 많이 추가할수록 제 조언은 더 정확해집니다! 😊',
    'zh':
        '👋 你好！我是你的个人AI营养师，具备**上下文分析**能力。\n\n🧠 **我可以为你做：**\n• 📊 分析你一周的饮食数据\n• 🎯 评估你在个人目标上的进展\n• ⚖️ 检查饮食中的常量营养素（宏量营养素）平衡\n• 💡 提供个性化建议\n• 📈 跟踪你的体重变化趋势\n\n🚀 **为了更精准的分析**，请使用下方按钮或输入“分析”、“进展”、“建议”。\n\n你在应用中添加的数据越多，我的建议就会越准确！ 😊',
    'zhTW':
        '👋 你好！我是你的個人AI營養師，具備**情境分析**能力。\n\n🧠 **我可以為你做：**\n• 📊 分析你一週的飲食資料\n• 🎯 評估你在個人目標上的進展\n• ⚖️ 檢查飲食中的巨量營養素平衡\n• 💡 提供個人化建議\n• 📈 追蹤你的體重變化趨勢\n\n🚀 **為了更精準的分析**，請使用下方按鈕或輸入「分析」、「進展」、「建議」。\n\n你在App中新增的資料越多，我的建議就會越精準！ 😊',
    'hi':
        '👋 नमस्ते! मैं आपका निजी एआई डाइटीशियन हूँ, **प्रसंगगत विश्लेषण** के साथ।\n\n🧠 **मैं क्या कर सकता/सकती हूँ:**\n• 📊 आपके साप्ताहिक भोजन/पोषण डेटा का विश्लेषण करता/करती हूँ\n• 🎯 आपके व्यक्तिगत लक्ष्यों की ओर प्रगति का आकलन करता/करती हूँ\n• ⚖️ आपके आहार में मैक्रोन्यूट्रिएंट्स का संतुलन जाँचता/जाँचती हूँ\n• 💡 व्यक्तिगत सिफारिशें देता/देती हूँ\n• 📈 आपके वज़न के रुझानों को ट्रैक करता/करती हूँ\n\n🚀 **सटीक विश्लेषण के लिए**, नीचे दिए गए बटन इस्तेमाल करें या “analysis”, “progress”, “recommendations” लिखें।\n\nजितना ज़्यादा डेटा आप ऐप में जोड़ेंगे, मेरी सलाह उतनी ही सटीक होगी! 😊',
  };

  // Обходим все языковые файлы в каталоге
  final dir = Directory(localizationDir);
  final files = await dir
      .list()
      .where((e) => e is File && e.path.endsWith('_strings.dart'))
      .cast<File>()
      .toList();

  for (final file in files) {
    final lang = _langFromFileName(file.path);
    if (lang == null) continue;
    if (lang == 'ru') {
      // Для русского языка пишем исходный нормализованный текст БЕЗ плейсхолдеров
      await _upsertKeyInFile(file, 'chat_welcome_message', ruWelcomeOriginal);
      stdout.writeln('  • ru: обновлено из нормализованного источника');
      continue;
    }

    final targetCode = _langCodeFor(lang);
    if (targetCode == null) {
      stdout.writeln('  • $lang: пропущен (нет кода перевода)');
      continue;
    }

    // Если есть ручной перевод — используем его и минуем автоперевод
    final manual = manualWelcomeByLang[lang];
    String translated = manual ??
        await _translatePreservingFormatting(
          translator: translator,
          sourceText: ruWelcomeForTranslation,
          from: 'ru',
          to: targetCode,
        );

    // Восстанавливаем термины по словарю для языка
    if (manual == null) {
      final restored = _restorePlaceholders(translated, lang);
      translated = restored;
    }

    // Всегда санитизируем перед записью, чтобы экранировать кавычки/бэкслеши
    translated = _sanitizeForDart(translated);

    await _upsertKeyInFile(file, 'chat_welcome_message', translated);
    stdout.writeln('  ✅ $lang: приветствие обновлено');
  }

  stdout.writeln(
      '\n🎉 Готово: приветственное сообщение обновлено для всех языков.');
}

String _normalizeWelcomeSource(String value) {
  String v = value;
  // Склеиваем фрагменты вида: '...\n'\n  '...\n'\n  '...'
  // Удаляем границы сегментов между одинарными кавычками по переводам строк
  v = v.replaceAll(RegExp(r"'\s*\n\s*'", multiLine: true), '');
  // Снимаем крайние кавычки, если остались
  if (v.startsWith("'")) v = v.substring(1);
  if (v.endsWith("'")) v = v.substring(0, v.length - 1);
  // Приводим кастомные плейсхолдеры к ** и \n
  v = v
      .replaceAll(
          RegExp(r'__\s*ai\s*_\s*bold\s*__', caseSensitive: false), '**')
      .replaceAll(RegExp(r'\\\s*[nN]'), '\\n')
      .replaceAll(RegExp(r'\s+\\n\s+'), '\\n')
      .replaceAll('\\ N', '\\n')
      .replaceAll('\\ n', '\\n');

  return v;
}

Future<String> _translatePreservingFormatting({
  required GoogleTranslator translator,
  required String sourceText,
  required String from,
  required String to,
}) async {
  // Защищаем разметку и переносы строк от искажения
  const bold = '__AI_BOLD__';
  const nl2 = '__AI_NL2__';
  const nl1 = '__AI_NL__';

  String protected = sourceText
      .replaceAll('**', bold)
      .replaceAll('\\n\\n', nl2)
      .replaceAll('\\n', nl1);

  String translated =
      (await translator.translate(protected, from: from, to: to)).text;

  // Восстанавливаем токены и чистим возможные пробелы вокруг них
  translated = translated
      // Базовая замена точных токенов
      .replaceAll(RegExp(r'\s*' + nl2 + r'\s*', caseSensitive: false), '\\n\\n')
      .replaceAll(RegExp(r'\s*' + nl1 + r'\s*', caseSensitive: false), '\\n')
      .replaceAll(RegExp(r'\s*' + bold + r'\s*', caseSensitive: false), '**')
      // Расширенные варианты: допускаем пробелы внутри __AI_...__
      .replaceAll(
          RegExp(r'__\s*AI\s*[_-]?\s*NL2\s*__', caseSensitive: false), '\\n\\n')
      .replaceAll(
          RegExp(r'__\s*AI\s*[_-]?\s*NL\s*__', caseSensitive: false), '\\n')
      .replaceAll(
          RegExp(r'__\s*AI\s*[_-]?\s*BOLD\s*__', caseSensitive: false), '**');

  // Нормализуем возможные разрывы "\\ n" -> "\\n"
  translated = translated.replaceAll('\\ n', '\\n').replaceAll('\\ N', '\\n');

  // Удаляем двойные/тройные пробелы, возникшие из-за токенов
  translated = translated.replaceAll(RegExp(r'\s{2,}'), ' ');

  return _sanitizeForDart(translated);
}

// Простая вставка/замена значения ключа в карте переводов файла
Future<void> _upsertKeyInFile(File file, String key, String value) async {
  String content = await file.readAsString();
  // Паттерн, который покрывает как одиночную строку, так и несколько смежных литералов
  // вида: 'key': '...\n'\n '...\n'\n '...',
  final pattern = RegExp(
      "'" + RegExp.escape(key) + r"'\s*:\s*(?:'(?:\\'|[^']*)'\s*)+,\s*",
      multiLine: true);
  // Очень широкий страховочный паттерн: удаляем блок от ключа до следующего ключа или конца карты
  final widePattern = RegExp(
      "'" + RegExp.escape(key) + r"'\s*:\s*[\s\S]*?(?=(^\s*'[^']+'\s*:)|\};)",
      multiLine: true);

  final entry = "  '$key': '$value',";

  // Полностью удаляем все старые вхождения ключа во всём файле
  while (pattern.hasMatch(content) || widePattern.hasMatch(content)) {
    content = content.replaceAll(pattern, '');
    content = content.replaceAll(widePattern, '');
  }

  // Пробуем вставить строго после ключа 'please_try_later_or_check_internet'
  final anchor = RegExp(
      r"'please_try_later_or_check_internet'\s*:\s*'(?:\\'|[^']*)',",
      multiLine: true);
  final match = anchor.firstMatch(content);
  if (match != null) {
    final pos = match.end;
    content = "${content.substring(0, pos)}\n$entry${content.substring(pos)}";
  } else {
    // Фолбэк: вставляем перед закрывающей скобкой };
    final insertPos = content.lastIndexOf('};');
    if (insertPos != -1) {
      content =
          '${content.substring(0, insertPos)}$entry\n${content.substring(insertPos)}';
    }
  }
  await file.writeAsString(content);
}

Map<String, String> _extractTranslations(String content) {
  final Map<String, String> result = {};
  final regExp = RegExp(r"'([^']+)'\s*:\s*'((?:\\'|[^'])*?)'", multiLine: true);
  for (final m in regExp.allMatches(content)) {
    final key = m.group(1)!;
    final rawValue = m.group(2)!;
    result[key] = rawValue.replaceAll("\\'", "'");
  }
  return result;
}

String? _langFromFileName(String path) {
  final name = path.split('/').last; // xx_strings.dart
  final idx = name.indexOf('_strings.dart');
  if (idx <= 0) return null;
  return name.substring(0, idx);
}

String? _langCodeFor(String lang) {
  switch (lang) {
    case 'ru':
      return 'ru';
    case 'en':
      return 'en';
    case 'es':
    case 'esMX':
      return 'es';
    case 'ar':
      return 'ar';
    case 'fr':
    case 'frCA':
      return 'fr';
    case 'fil':
      return 'tl';
    case 'ja':
      return 'ja';
    case 'it':
      return 'it';
    case 'ko':
      return 'ko';
    case 'pt':
    case 'ptBR':
      return 'pt';
    case 'zh':
      return 'zh-cn';
    case 'zhTW':
      return 'zh-tw';
    case 'uk':
      return 'uk';
    case 'th':
      return 'th';
    case 'el':
      return 'el';
    case 'tr':
      return 'tr';
    case 'vi':
      return 'vi';
    case 'hi':
      return 'hi';
    case 'de':
      return 'de';
    case 'hu':
      return 'hu';
    case 'da':
      return 'da';
    case 'he':
      return 'iw';
    case 'id':
      return 'id';
    case 'ca':
      return 'ca';
    case 'ms':
      return 'ms';
    case 'nl':
      return 'nl';
    case 'no':
      return 'no';
    case 'pl':
      return 'pl';
    case 'ro':
      return 'ro';
    case 'sk':
      return 'sk';
    case 'fi':
      return 'fi';
    case 'hr':
      return 'hr';
    case 'cs':
      return 'cs';
    case 'sv':
      return 'sv';
    default:
      return null;
  }
}

String _sanitizeForDart(String value) {
  String v = value;
  // Экранируем обратные слэши и одинарные кавычки
  v = v.replaceAll('\\', r'\\').replaceAll("'", r"\'");
  // Переводим реальные переводы строк в текстовый токен \n
  v = v.replaceAll('\r\n', r'\n').replaceAll('\n', r'\n');
  return v;
}

// Восстановление плейсхолдеров с языковым словарём
String _restorePlaceholders(String text, String lang) {
  final macros = <String, String>{
    'en': 'macros',
    'fr': 'macronutriments',
    'frCA': 'macronutriments',
    'es': 'macronutrientes',
    'esMX': 'macronutrientes',
    'de': 'Makronährstoffe',
    'it': 'macronutrienti',
    'pt': 'macronutrientes',
    'ptBR': 'macronutrientes',
    'tr': 'makrolar',
    'uk': 'макронутрієнти',
    'pl': 'makroskładniki',
    'cs': 'makroživiny',
    'sk': 'makroživiny',
    'sv': 'makronäringsämnen',
    'da': 'makronæringsstoffer',
    'fi': 'makroravintoaineet',
    'no': 'makronæringsstoffer',
    'nl': 'macronutriënten',
    'he': 'מאקרונוטריאנטים',
    'ar': 'المغذيات الكبيرة',
    'ja': 'マクロ栄養素',
    'ko': '다량 영양소',
    'zh': '常量营养素',
    'zhTW': '巨量營養素',
    'id': 'makronutrien',
    'ms': 'makronutrien',
    'vi': 'chất dinh dưỡng đa lượng',
    'th': 'สารอาหารหลัก',
    'fil': 'macronutrients',
    'hr': 'makronutrijenti',
    'hu': 'makrotápanyagok',
    'ro': 'macronutrienți',
    'el': 'μακροθρεπτικά συστατικά',
    'hi': 'मैक्रोन्यूट्रिएंट्स',
    'ca': 'macronutrients',
  };

  final contextAnalysis = <String, String>{
    'en': 'contextual analysis',
    'fr': 'analyse contextuelle',
    'frCA': 'analyse contextuelle',
    'es': 'análisis contextual',
    'esMX': 'análisis contextual',
    'de': 'kontextuelle Analyse',
    'it': 'analisi contestuale',
    'pt': 'análise contextual',
    'ptBR': 'análise contextual',
    'tr': 'bağlamsal analiz',
    'uk': 'контекстний аналіз',
    'pl': 'analiza kontekstowa',
    'cs': 'kontextová analýza',
    'sk': 'kontextová analýza',
    'sv': 'kontextuell analys',
    'da': 'kontekstuel analyse',
    'fi': 'kontekstianalyysi',
    'no': 'kontekstuell analyse',
    'nl': 'contextuele analyse',
    'he': 'ניתוח הקשרי',
    'ar': 'تحليل سياقي',
    'ja': 'コンテキスト分析',
    'ko': '컨텍스트 분석',
    'zh': '上下文分析',
    'zhTW': '情境分析',
    'id': 'analisis kontekstual',
    'ms': 'analisis kontekstual',
    'vi': 'phân tích ngữ cảnh',
    'th': 'การวิเคราะห์ตามบริบท',
    'fil': 'pagsusuri ng konteksto',
    'hr': 'kontekstualna analiza',
    'hu': 'kontextuális elemzés',
    'ro': 'analiză contextuală',
    'el': 'ανάλυση συμφραζομένων',
    'hi': 'प्रसंगगत विश्लेषण',
    'ca': 'anàlisi contextual',
  };

  final langKey = lang; // уже язык файла
  final m = macros[langKey] ?? macros['en']!;
  final c = contextAnalysis[langKey] ?? contextAnalysis['en']!;

  return text
      .replaceAll(RegExp(r'__\s*MACROS\s*__', caseSensitive: false), m)
      .replaceAll(
          RegExp(r'__\s*CONTEXT\s*ANALYSIS\s*__', caseSensitive: false), c)
      .replaceAll('__macros__', m)
      .replaceAll('__context_analysis__', c)
      .replaceAll('__MACROS__', m)
      .replaceAll('__CONTEXT_ANALYSIS__', c);
}
