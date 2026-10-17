import 'package:latlong2/latlong.dart';

enum ThreatType { drone, missile, airDefense }

class GeoPoint {
  final String key;
  final String name;
  final String regionGroup;
  final LatLng coords;
  final double radiusKm;

  const GeoPoint({
    required this.key,
    required this.name,
    required this.regionGroup,
    required this.coords,
    this.radiusKm = 18.0,
  });
}

class GeoDatabase {
  // Список регионов для выбора при первом запуске
  static const List<String> availableRegions = [
    'Москва и МО',
    'Белгородская область',
    'Курская область',
    'Брянская область',
    'Воронежская область',
    'Тульская область',
    'Калужская область',
    'Орловская область',
    'Рязанская область',
    'Липецкая область',
    'Ростовская область',
    'Краснодарский край',
    'Тверская и Ярославская обл.',
  ];

  // Подробный словарь городов и городских округов
  static const List<GeoPoint> locations = [
    // Москва и Подмосковье
    GeoPoint(key: 'одинцов', name: 'Одинцовский г.о.', regionGroup: 'Москва и МО', coords: LatLng(55.678, 36.768), radiusKm: 15),
    GeoPoint(key: 'наро-фоминск', name: 'Наро-Фоминский г.о.', regionGroup: 'Москва и МО', coords: LatLng(55.385, 36.734), radiusKm: 18),
    GeoPoint(key: 'нарофоминск', name: 'Наро-Фоминский г.о.', regionGroup: 'Москва и МО', coords: LatLng(55.385, 36.734), radiusKm: 18),
    GeoPoint(key: 'подольск', name: 'Подольск', regionGroup: 'Москва и МО', coords: LatLng(55.431, 37.545), radiusKm: 14),
    GeoPoint(key: 'домодедов', name: 'Домодедово', regionGroup: 'Москва и МО', coords: LatLng(55.443, 37.747), radiusKm: 15),
    GeoPoint(key: 'раменск', name: 'Раменский г.о.', regionGroup: 'Москва и МО', coords: LatLng(55.567, 38.225), radiusKm: 18),
    GeoPoint(key: 'люберц', name: 'Люберцы', regionGroup: 'Москва и МО', coords: LatLng(55.676, 37.893), radiusKm: 10),
    GeoPoint(key: 'балаших', name: 'Балашиха', regionGroup: 'Москва и МО', coords: LatLng(55.798, 37.958), radiusKm: 12),
    GeoPoint(key: 'красногорск', name: 'Красногорск', regionGroup: 'Москва и МО', coords: LatLng(55.820, 37.330), radiusKm: 12),
    GeoPoint(key: 'химк', name: 'Химки', regionGroup: 'Москва и МО', coords: LatLng(55.889, 37.444), radiusKm: 10),
    GeoPoint(key: 'мытищ', name: 'Мытищи', regionGroup: 'Москва и МО', coords: LatLng(55.911, 37.730), radiusKm: 12),
    GeoPoint(key: 'серпухов', name: 'Серпухов', regionGroup: 'Москва и МО', coords: LatLng(54.915, 37.412), radiusKm: 16),
    GeoPoint(key: 'чехов', name: 'Чехов', regionGroup: 'Москва и МО', coords: LatLng(55.148, 37.477), radiusKm: 15),
    GeoPoint(key: 'коломн', name: 'Коломна', regionGroup: 'Москва и МО', coords: LatLng(55.093, 38.778), radiusKm: 16),
    GeoPoint(key: 'ступин', name: 'Ступино', regionGroup: 'Москва и МО', coords: LatLng(54.887, 38.077), radiusKm: 16),
    GeoPoint(key: 'воскресенск', name: 'Воскресенск', regionGroup: 'Москва и МО', coords: LatLng(55.321, 38.683), radiusKm: 15),
    GeoPoint(key: 'истр', name: 'Истра', regionGroup: 'Москва и МО', coords: LatLng(55.918, 36.858), radiusKm: 16),
    GeoPoint(key: 'солнечногорск', name: 'Солнечногорск', regionGroup: 'Москва и МО', coords: LatLng(56.182, 36.976), radiusKm: 15),
    GeoPoint(key: 'дмитров', name: 'Дмитров', regionGroup: 'Москва и МО', coords: LatLng(56.344, 37.520), radiusKm: 18),
    GeoPoint(key: 'сергиев посад', name: 'Сергиев Посад', regionGroup: 'Москва и МО', coords: LatLng(56.315, 38.136), radiusKm: 18),
    GeoPoint(key: 'руз', name: 'Рузский г.о.', regionGroup: 'Москва и МО', coords: LatLng(55.698, 36.195), radiusKm: 18),
    GeoPoint(key: 'можайск', name: 'Можайский г.о.', regionGroup: 'Москва и МО', coords: LatLng(55.503, 36.029), radiusKm: 20),
    GeoPoint(key: 'зеленоград', name: 'Зеленоград', regionGroup: 'Москва и МО', coords: LatLng(55.987, 37.189), radiusKm: 10),
    GeoPoint(key: 'тинао', name: 'ТиНАО (Новая Москва)', regionGroup: 'Москва и МО', coords: LatLng(55.437, 37.155), radiusKm: 16),
    GeoPoint(key: 'троицк', name: 'Троицк (ТиНАО)', regionGroup: 'Москва и МО', coords: LatLng(55.485, 37.307), radiusKm: 12),
    GeoPoint(key: 'внуков', name: 'Район Внуково', regionGroup: 'Москва и МО', coords: LatLng(55.605, 37.286), radiusKm: 10),
    GeoPoint(key: 'жуковск', name: 'Жуковский', regionGroup: 'Москва и МО', coords: LatLng(55.597, 38.119), radiusKm: 10),
    GeoPoint(key: 'москв', name: 'Москва', regionGroup: 'Москва и МО', coords: LatLng(55.751, 37.618), radiusKm: 22),

    // Приграничные и центральные регионы
    GeoPoint(key: 'белгород', name: 'Белгород', regionGroup: 'Белгородская область', coords: LatLng(50.595, 36.587), radiusKm: 25),
    GeoPoint(key: 'шебекин', name: 'Шебекино', regionGroup: 'Белгородская область', coords: LatLng(50.409, 36.899), radiusKm: 18),
    GeoPoint(key: 'грайворон', name: 'Грайворон', regionGroup: 'Белгородская область', coords: LatLng(50.476, 35.676), radiusKm: 18),
    GeoPoint(key: 'валуйк', name: 'Валуйки', regionGroup: 'Белгородская область', coords: LatLng(50.212, 38.103), radiusKm: 18),
    GeoPoint(key: 'старый оскол', name: 'Старый Оскол', regionGroup: 'Белгородская область', coords: LatLng(51.296, 37.841), radiusKm: 20),

    GeoPoint(key: 'курск', name: 'Курск', regionGroup: 'Курская область', coords: LatLng(51.730, 36.192), radiusKm: 25),
    GeoPoint(key: 'курчат', name: 'Курчатов', regionGroup: 'Курская область', coords: LatLng(51.660, 35.660), radiusKm: 18),
    GeoPoint(key: 'рыльск', name: 'Рыльск', regionGroup: 'Курская область', coords: LatLng(51.568, 34.682), radiusKm: 18),
    GeoPoint(key: 'льгов', name: 'Льгов', regionGroup: 'Курская область', coords: LatLng(51.671, 35.266), radiusKm: 18),
    GeoPoint(key: 'судж', name: 'Суджа', regionGroup: 'Курская область', coords: LatLng(51.191, 35.271), radiusKm: 18),
    GeoPoint(key: 'железногорск', name: 'Железногорск', regionGroup: 'Курская область', coords: LatLng(52.339, 35.352), radiusKm: 18),

    GeoPoint(key: 'брянск', name: 'Брянск', regionGroup: 'Брянская область', coords: LatLng(53.243, 34.364), radiusKm: 25),
    GeoPoint(key: 'клинц', name: 'Клинцы', regionGroup: 'Брянская область', coords: LatLng(52.753, 32.238), radiusKm: 18),
    GeoPoint(key: 'севск', name: 'Севск', regionGroup: 'Брянская область', coords: LatLng(52.149, 34.492), radiusKm: 18),

    GeoPoint(key: 'воронеж', name: 'Воронеж', regionGroup: 'Воронежская область', coords: LatLng(51.672, 39.184), radiusKm: 25),
    GeoPoint(key: 'острогожск', name: 'Острогожск', regionGroup: 'Воронежская область', coords: LatLng(50.865, 39.073), radiusKm: 18),
    GeoPoint(key: 'борисоглебск', name: 'Борисоглебск', regionGroup: 'Воронежская область', coords: LatLng(51.368, 42.083), radiusKm: 18),

    GeoPoint(key: 'тул', name: 'Тула', regionGroup: 'Тульская область', coords: LatLng(54.193, 37.617), radiusKm: 25),
    GeoPoint(key: 'алексин', name: 'Алексин', regionGroup: 'Тульская область', coords: LatLng(54.502, 37.068), radiusKm: 18),
    GeoPoint(key: 'новомосковск', name: 'Новомосковск', regionGroup: 'Тульская область', coords: LatLng(54.011, 38.291), radiusKm: 18),

    GeoPoint(key: 'калуг', name: 'Калуга', regionGroup: 'Калужская область', coords: LatLng(54.513, 36.261), radiusKm: 25),
    GeoPoint(key: 'обнинск', name: 'Обнинск', regionGroup: 'Калужская область', coords: LatLng(55.096, 36.610), radiusKm: 16),

    GeoPoint(key: 'орёл', name: 'Орёл', regionGroup: 'Орловская область', coords: LatLng(52.968, 36.069), radiusKm: 25),
    GeoPoint(key: 'орел', name: 'Орёл', regionGroup: 'Орловская область', coords: LatLng(52.968, 36.069), radiusKm: 25),
    GeoPoint(key: 'орловск', name: 'Орловская обл.', regionGroup: 'Орловская область', coords: LatLng(52.968, 36.069), radiusKm: 25),

    GeoPoint(key: 'рязан', name: 'Рязань', regionGroup: 'Рязанская область', coords: LatLng(54.629, 39.734), radiusKm: 25),
    GeoPoint(key: 'липецк', name: 'Липецк', regionGroup: 'Липецкая область', coords: LatLng(52.610, 39.599), radiusKm: 25),
    GeoPoint(key: 'елец', name: 'Елец', regionGroup: 'Липецкая область', coords: LatLng(52.624, 38.504), radiusKm: 18),

    GeoPoint(key: 'ростов', name: 'Ростов-на-Дону', regionGroup: 'Ростовская область', coords: LatLng(47.222, 39.718), radiusKm: 25),
    GeoPoint(key: 'таганрог', name: 'Таганрог', regionGroup: 'Ростовская область', coords: LatLng(47.236, 38.896), radiusKm: 18),
    GeoPoint(key: 'каменск', name: 'Каменск-Шахтинский', regionGroup: 'Ростовская область', coords: LatLng(48.318, 40.260), radiusKm: 18),
    GeoPoint(key: 'морозовск', name: 'Морозовск', regionGroup: 'Ростовская область', coords: LatLng(48.352, 41.828), radiusKm: 18),

    GeoPoint(key: 'краснодар', name: 'Краснодар', regionGroup: 'Краснодарский край', coords: LatLng(45.035, 38.975), radiusKm: 25),
    GeoPoint(key: 'новороссийск', name: 'Новороссийск', regionGroup: 'Краснодарский край', coords: LatLng(44.723, 37.768), radiusKm: 18),
    GeoPoint(key: 'туапсе', name: 'Туапсе', regionGroup: 'Краснодарский край', coords: LatLng(44.105, 39.070), radiusKm: 18),
    GeoPoint(key: 'ейск', name: 'Ейск', regionGroup: 'Краснодарский край', coords: LatLng(46.711, 38.273), radiusKm: 18),

    GeoPoint(key: 'твер', name: 'Тверь', regionGroup: 'Тверская и Ярославская обл.', coords: LatLng(56.859, 35.911), radiusKm: 25),
    GeoPoint(key: 'ярослав', name: 'Ярославль', regionGroup: 'Тверская и Ярославская обл.', coords: LatLng(57.626, 39.884), radiusKm: 25),
  ];

  // Словарь угроз
  static const List<String> droneKeywords = [
    'бпла', 'дрон', 'беспилотник', 'птичк', 'фиксация', 'летит', 'летят',
    'курс на', 'в направлении', 'угроза', 'опасность', 'внимание', 'мопед',
  ];

  static const List<String> missileKeywords = [
    'ракетн', 'баллистик', 'сбитие', 'работает пво', 'пво', 'взрыв', 'хлопок', 'цель',
  ];

  static const List<String> cancelKeywords = [
    'отбой', 'чисто', 'снята', 'миновала', 'спокойно', 'без угроз',
  ];
}