import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'geo_data.dart';
import 'tg_scraper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF090C10),
    ),
  );
  runApp(const SkyRadarApp());
}

class SkyRadarApp extends StatelessWidget {
  const SkyRadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SkyRadar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090C10),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(
            fontFamily: 'sans-serif',
            letterSpacing: -0.2,
          ),
        ),
      ),
      home: const RootFlowController(),
    );
  }
}

/// УПРАВЛЕНИЕ ЭКРАНАМИ:
/// 1. Красивая анимация загрузки (Splash)
/// 2. Полноэкранный выбор региона (только при первом входе или по клику на карандаш)
/// 3. Чистая LIVE-карта
enum AppStage { splash, selectRegion, radarMap }

class RootFlowController extends StatefulWidget {
  const RootFlowController({super.key});

  @override
  State<RootFlowController> createState() => _RootFlowControllerState();
}

class _RootFlowControllerState extends State<RootFlowController> {
  AppStage _stage = AppStage.splash;
  String? _userRegion;

  @override
  void initState() {
    super.initState();
    _initializeFlow();
  }

  Future<void> _initializeFlow() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRegion = prefs.getString('user_home_region');

    // Даем проиграться плавной стартовой анимации
    await Future.delayed(const Duration(milliseconds: 2200));

    if (!mounted) return;
    setState(() {
      _userRegion = savedRegion;
      _stage =
          savedRegion == null ? AppStage.selectRegion : AppStage.radarMap;
    });
  }

  Future<void> _onRegionSaved(String newRegion) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_home_region', newRegion);
    if (!mounted) return;
    setState(() {
      _userRegion = newRegion;
      _stage = AppStage.radarMap;
    });
  }

  void _openRegionEditor() {
    setState(() {
      _stage = AppStage.selectRegion;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 550),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _buildCurrentStage(),
    );
  }

  Widget _buildCurrentStage() {
    switch (_stage) {
      case AppStage.splash:
        return const AppleSplashView(key: ValueKey('splash'));
      case AppStage.selectRegion:
        return RegionSelectionScreen(
          key: const ValueKey('region_select'),
          initialRegion: _userRegion,
          onSelect: _onRegionSaved,
        );
      case AppStage.radarMap:
        return LiveRadarMapScreen(
          key: const ValueKey('radar_map'),
          userRegion: _userRegion ?? GeoDatabase.availableRegions.first,
          onEditRegion: _openRegionEditor,
        );
    }
  }
}

/// 1. ЭКРАН ЗАГРУЗКИ В СТИЛЕ APPLE
class AppleSplashView extends StatefulWidget {
  const AppleSplashView({super.key});

  @override
  State<AppleSplashView> createState() => _AppleSplashViewState();
}

class _AppleSplashViewState extends State<AppleSplashView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090C10),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 130,
              height: 130,
              child: AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, _) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Расходящиеся волны радара
                      for (int i = 0; i < 3; i++)
                        Builder(builder: (context) {
                          final progress = (_pulseCtrl.value + i * 0.33) % 1.0;
                          return Container(
                            width: 36 + (progress * 94),
                            height: 36 + (progress * 94),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFFF3B30)
                                    .withOpacity((1.0 - progress) * 0.65),
                                width: 1.8,
                              ),
                            ),
                          );
                        }),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF453A), Color(0xFFD70015)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF3B30).withOpacity(0.5),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.radar_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'SKYRADAR',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Подключение к прямому эфиру...',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 2. ПОЛНОЭКРАННЫЙ ВЫБОР РЕГИОНА (В СТИЛЕ iOS ONBOARDING)
class RegionSelectionScreen extends StatefulWidget {
  final String? initialRegion;
  final ValueChanged<String> onSelect;

  const RegionSelectionScreen({
    super.key,
    required this.initialRegion,
    required this.onSelect,
  });

  @override
  State<RegionSelectionScreen> createState() => _RegionSelectionScreenState();
}

class _RegionSelectionScreenState extends State<RegionSelectionScreen> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialRegion ?? GeoDatabase.availableRegions.first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090C10),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30).withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Color(0xFFFF453A),
                  size: 28,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Где вы проживаете?',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Выберите свой регион. Приложение будет мгновенно присылать Push-уведомления при угрозе БПЛА и отбое тревоги.',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withOpacity(0.55),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: GeoDatabase.availableRegions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final region = GeoDatabase.availableRegions[index];
                    final isChosen = region == _selected;

                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => _selected = region);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: isChosen
                              ? const Color(0xFFFF3B30).withOpacity(0.16)
                              : const Color(0xFF131720),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isChosen
                                ? const Color(0xFFFF453A)
                                : Colors.white.withOpacity(0.06),
                            width: isChosen ? 1.6 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                region,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: isChosen
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: isChosen
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.8),
                                ),
                              ),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isChosen
                                    ? const Color(0xFFFF453A)
                                    : Colors.transparent,
                                border: Border.all(
                                  color: isChosen
                                      ? const Color(0xFFFF453A)
                                      : Colors.white24,
                                  width: 2,
                                ),
                              ),
                              child: isChosen
                                  ? const Icon(
                                      Icons.check_rounded,
                                      size: 16,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B30),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    widget.onSelect(_selected);
                  },
                  child: const Text(
                    'Продолжить',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// МОДЕЛИ АКТИВНЫХ СОБЫТИЙ
class SourceReport {
  final String channel;
  final String text;
  final DateTime time;

  SourceReport({required this.channel, required this.text, required this.time});
}

class ActiveAlert {
  final GeoPoint point;
  ThreatType type;
  DateTime lastUpdated;
  final List<SourceReport> reports;

  ActiveAlert({
    required this.point,
    required this.type,
    required this.lastUpdated,
    required this.reports,
  });
}

/// 3. ГЛАВНЫЙ ЭКРАН ЖИВОЙ ТАКТИЧЕСКОЙ КАРТЫ
class LiveRadarMapScreen extends StatefulWidget {
  final String userRegion;
  final VoidCallback onEditRegion;

  const LiveRadarMapScreen({
    super.key,
    required this.userRegion,
    required this.onEditRegion,
  });

  @override
  State<LiveRadarMapScreen> createState() => _LiveRadarMapScreenState();
}

class _LiveRadarMapScreenState extends State<LiveRadarMapScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final List<String> _channels = [
    'Radar_Moscow_99',
    'radar_moscoww',
    'radarrussiia',
  ];

  final Map<String, ActiveAlert> _activeAlerts = {};
  bool _isScanning = false;

  late final AnimationController _radarBeaconCtrl;
  Timer? _liveStreamTimer;

  // Матрица фильтрации: превращает стандартную карту OpenStreetMap
  // в стильную темную тактическую карту без всяких API-ключей!
  static const List<double> _tacticalDarkMatrix = <double>[
    -0.82, 0.0, 0.0, 0.0, 195.0,
    0.0, -0.80, 0.0, 0.0, 205.0,
    0.0, 0.0, -0.72, 0.0, 225.0,
    0.0, 0.0, 0.0, 1.0, 0.0,
  ];

  @override
  void initState() {
    super.initState();

    _radarBeaconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _initNotifications();
    _startRealtimeStream();
  }

  Future<void> _initNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings);

    final androidPlugin =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
  }

  Future<void> _sendPush({
    required String title,
    required String body,
    bool isCancel = false,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      isCancel ? 'sky_radar_clear' : 'sky_radar_danger',
      isCancel ? 'Отбой опасности' : 'Экстренные оповещения БПЛА',
      importance: Importance.max,
      priority: Priority.high,
      color: isCancel ? const Color(0xFF30D158) : const Color(0xFFFF453A),
      enableVibration: true,
      playSound: true,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _startRealtimeStream() async {
    // Первичная загрузка сводки
    await _fetchLiveUpdates(isInitial: true);

    // Прямой эфир: опрос каждые 8 секунд без участия пользователя
    _liveStreamTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _fetchLiveUpdates(isInitial: false),
    );
  }

  Future<void> _fetchLiveUpdates({required bool isInitial}) async {
    if (_isScanning) return;
    if (mounted) setState(() => _isScanning = true);

    try {
      final results = await Future.wait(
        _channels.map(
          (ch) => TelegramWebScraper.fetchChannel(ch, isInitialLoad: isInitial),
        ),
      );

      for (final channelPosts in results) {
        for (final msg in channelPosts) {
          _processIncomingMessage(msg, allowPush: !isInitial);
        }
      }
      _purgeExpiredAlerts();
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _processIncomingMessage(ScrapedMessage msg, {required bool allowPush}) {
    final lower = msg.text.toLowerCase();

    final isCancel = GeoDatabase.cancelKeywords.any(lower.contains);
    final isMissile = GeoDatabase.missileKeywords.any(lower.contains);
    final isDrone = GeoDatabase.droneKeywords.any(lower.contains);

    if (!isCancel && !isMissile && !isDrone) return;

    final Set<String> matchedLocations = {};

    for (final geo in GeoDatabase.locations) {
      if (lower.contains(geo.key)) {
        if (matchedLocations.contains(geo.name)) continue;
        matchedLocations.add(geo.name);

        // 1. ОТБОЙ ТРЕВОГИ
        if (isCancel && !isDrone) {
          if (_activeAlerts.containsKey(geo.name)) {
            setState(() => _activeAlerts.remove(geo.name));

            if (allowPush && widget.userRegion == geo.regionGroup) {
              _sendPush(
                title: '🟢 Отбой опасности: ${geo.name}',
                body:
                    'В регионе (${geo.regionGroup}) снята воздушная угроза. Источник: @${msg.channel}',
                isCancel: true,
              );
            }
          }
          continue;
        }

        // 2. ОБНАРУЖЕНИЕ УГРОЗЫ (БПЛА ИЛИ РАКЕТНАЯ/ПВО)
        final ThreatType type =
            isMissile ? ThreatType.missile : ThreatType.drone;
        final bool alreadyExists = _activeAlerts.containsKey(geo.name);

        setState(() {
          if (alreadyExists) {
            final existing = _activeAlerts[geo.name]!;
            existing.lastUpdated = msg.timestamp;
            if (type == ThreatType.missile) {
              existing.type = ThreatType.missile;
            }
            final duplicate =
                existing.reports.any((r) => r.text == msg.text);
            if (!duplicate) {
              existing.reports.insert(
                0,
                SourceReport(
                  channel: msg.channel,
                  text: msg.text,
                  time: msg.timestamp,
                ),
              );
            }
          } else {
            _activeAlerts[geo.name] = ActiveAlert(
              point: geo,
              type: type,
              lastUpdated: msg.timestamp,
              reports: [
                SourceReport(
                  channel: msg.channel,
                  text: msg.text,
                  time: msg.timestamp,
                ),
              ],
            );
          }
        });

        if (allowPush && !alreadyExists && widget.userRegion == geo.regionGroup) {
          final prefix = type == ThreatType.missile
              ? '🚨 Ракетная опасность / ПВО'
              : '⚠️ Опасность БПЛА';
          _sendPush(
            title: '$prefix • ${geo.name}',
            body: msg.text.length > 140
                ? '${msg.text.substring(0, 140)}...'
                : msg.text,
            isCancel: false,
          );
        }
      }
    }
  }

  void _purgeExpiredAlerts() {
    final now = DateTime.now();
    setState(() {
      _activeAlerts.removeWhere(
        (_, alert) => now.difference(alert.lastUpdated).inMinutes > 35,
      );
    });
  }

  @override
  void dispose() {
    _liveStreamTimer?.cancel();
    _radarBeaconCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alerts = _activeAlerts.values.toList();

    return Scaffold(
      body: Stack(
        children: [
          // 1. ЖИВАЯ ТАКТИЧЕСКАЯ КАРТА (РАБОТАЕТ БЕЗ API КЛЮЧЕЙ)
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(55.55, 37.45),
              initialZoom: 7.2,
              minZoom: 4.0,
              maxZoom: 17.5,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              ColorFiltered(
                colorFilter: const ColorFilter.matrix(_tacticalDarkMatrix),
                child: TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.skyshield.radar',
                  maxZoom: 18,
                ),
              ),

              // Мягкое свечение радиуса зоны опасности
              CircleLayer(
                circles: alerts.map((alert) {
                  final color = alert.type == ThreatType.missile
                      ? const Color(0xFFFF9F0A)
                      : const Color(0xFFFF453A);
                  return CircleMarker(
                    point: alert.point.coords,
                    radius: alert.point.radiusKm * 900,
                    useRadiusInMeter: true,
                    color: color.withOpacity(0.11),
                    borderColor: color.withOpacity(0.35),
                    borderStrokeWidth: 1.2,
                  );
                }).toList(),
              ),

              // Слой аккуратных мигающих радарных маяков (Apple-style)
              MarkerLayer(
                markers: alerts.map((alert) {
                  return Marker(
                    point: alert.point.coords,
                    width: 110,
                    height: 76,
                    rotate: false,
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showAppleAlertSheet(alert);
                      },
                      child: AnimatedBuilder(
                        animation: _radarBeaconCtrl,
                        builder: (context, _) {
                          return _buildRadarBeaconMarker(
                            alert: alert,
                            progress: _radarBeaconCtrl.value,
                          );
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // 2. ВЕРХНЯЯ МАТОВАЯ КАПСУЛА (DYNAMIC ISLAND В СТИЛЕ APPLE)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141820).withOpacity(0.78),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.09),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Мигающий индикатор ПРЯМОГО ЭФИРА
                        _buildLiveDot(),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    'ПРЯМОЙ ЭФИР',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                      color: Color(0xFF30D158),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '• Угроз: ${alerts.length}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: alerts.isEmpty
                                          ? Colors.white54
                                          : const Color(0xFFFF453A),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.userRegion,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        // Кнопка-карандаш для смены региона
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            widget.onEditRegion();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.edit_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// АККУРАТНЫЙ МИГАЮЩИЙ РАДАРНЫЙ МАЯК НА КАРТЕ (БЕЗ САМОДЕЛЬНЫХ КРИВЫХ ДРОНОВ)
  Widget _buildRadarBeaconMarker({
    required ActiveAlert alert,
    required double progress,
  }) {
    final bool isMissile = alert.type == ThreatType.missile;
    final Color mainColor =
        isMissile ? const Color(0xFFFF9F0A) : const Color(0xFFFF3B30);

    final double wave2 = (progress + 0.5) % 1.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Первая расходящаяся волна радара
              Container(
                width: 18 + (progress * 30),
                height: 18 + (progress * 30),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mainColor.withOpacity((1.0 - progress) * 0.35),
                  border: Border.all(
                    color: mainColor.withOpacity(1.0 - progress),
                    width: 1.5,
                  ),
                ),
              ),
              // Вторая расходящаяся волна радара
              Container(
                width: 18 + (wave2 * 30),
                height: 18 + (wave2 * 30),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: mainColor.withOpacity((1.0 - wave2) * 0.7),
                    width: 1.2,
                  ),
                ),
              ),
              // Центральное ядро радара
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: mainColor,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: mainColor.withOpacity(0.8),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        // Компактная капсула с названием города
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1218).withOpacity(0.88),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: mainColor.withOpacity(0.55),
              width: 0.8,
            ),
          ),
          child: Text(
            alert.point.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveDot() {
    return AnimatedBuilder(
      animation: _radarBeaconCtrl,
      builder: (context, _) {
        final glow = (1.0 - (_radarBeaconCtrl.value - 0.5).abs() * 2)
            .clamp(0.2, 1.0);
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isScanning
                ? const Color(0xFFFFD60A)
                : const Color(0xFF30D158),
            boxShadow: [
              BoxShadow(
                color: (_isScanning
                        ? const Color(0xFFFFD60A)
                        : const Color(0xFF30D158))
                    .withOpacity(glow),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
        );
      },
    );
  }

  /// КАРТОЧКА ДЕТАЛЕЙ В СТИЛЕ iOS BOTTOM SHEET ПРИ НАЖАТИИ НА РАДАР
  void _showAppleAlertSheet(ActiveAlert alert) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              decoration: BoxDecoration(
                color: const Color(0xFF141821).withOpacity(0.92),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30).withOpacity(0.16),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.radar_rounded,
                          color: Color(0xFFFF453A),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              alert.point.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${alert.point.regionGroup} • Сводка из ${alert.reports.length} ист.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      itemCount: alert.reports.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, idx) {
                        final rep = alert.reports[idx];
                        final timeStr =
                            '${rep.time.hour.toString().padLeft(2, '0')}:${rep.time.minute.toString().padLeft(2, '0')}';
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.06),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '@${rep.channel}',
                                    style: const TextStyle(
                                      color: Color(0xFF0A84FF),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.4),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                rep.text,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
