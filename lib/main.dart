import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'geo_data.dart';
import 'tg_scraper.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        scaffoldBackgroundColor: const Color(0xFF0B0E14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF3B30),
          secondary: Color(0xFF00E676),
        ),
      ),
      home: const RadarDashboard(),
    );
  }
}

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

// 0 = Тёмный радар, 1 = Спутник, 2 = Светлая схема
enum MapStyleMode { darkRadar, satellite, lightOsm }

class RadarDashboard extends StatefulWidget {
  const RadarDashboard({super.key});

  @override
  State<RadarDashboard> createState() => _RadarDashboardState();
}

class _RadarDashboardState extends State<RadarDashboard>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final List<String> _channels = [
    'Radar_Moscow_99',
    'radar_moscoww',
    'radarrussiia',
  ];

  // Активные тревоги без дублирования (ключ = point.name)
  final Map<String, ActiveAlert> _activeAlerts = {};

  String? _userRegion;
  MapStyleMode _mapStyle = MapStyleMode.darkRadar;
  bool _isScanning = false;
  String _statusText = 'Синхронизация с каналами...';

  late final AnimationController _radarSweepController;
  late final AnimationController _pulseController;
  Timer? _pollTimer;

  // Цветовая матрица для превращения бесплатной карты OSM в тактическую темную карту
  static const ColorFilter _darkRadarFilter = ColorFilter.matrix(<double>[
    -0.85,  0.0,   0.0,   0.0, 225.0,
     0.0,  -0.85,  0.0,   0.0, 230.0,
     0.0,   0.0,  -0.75,  0.0, 245.0,
     0.0,   0.0,   0.0,   1.0,   0.0,
  ]);

  @override
  void initState() {
    super.initState();

    _radarSweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _bootAppNonBlocking();
  }

  Future<void> _bootAppNonBlocking() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 2));
      final savedRegion = prefs.getString('user_home_region');

      if (savedRegion == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showRegionOnboardingDialog(isFirstLaunch: true);
        });
      } else {
        if (mounted) setState(() => _userRegion = savedRegion);
      }
    } catch (_) {}

    unawaited(_initNotificationsSafe());
    unawaited(_scanAllChannels(isInitial: true));

    _pollTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => _scanAllChannels(isInitial: false),
    );
  }

  Future<void> _initNotificationsSafe() async {
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      await _notifications
          .initialize(initSettings)
          .timeout(const Duration(seconds: 3));

      final androidPlugin =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    } catch (_) {}
  }

  Future<void> _sendPush({
    required String title,
    required String body,
    bool isCancel = false,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        isCancel ? 'sky_radar_clear' : 'sky_radar_danger',
        isCancel ? 'Отбой тревоги' : 'Экстренные оповещения БПЛА',
        importance: Importance.max,
        priority: Priority.high,
        color: isCancel ? const Color(0xFF00E676) : const Color(0xFFFF2A2A),
        enableVibration: true,
        playSound: true,
      );

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        NotificationDetails(android: androidDetails),
      );
    } catch (_) {}
  }

  Future<void> _scanAllChannels({bool isInitial = false}) async {
    if (_isScanning) return;
    if (mounted) {
      setState(() {
        _isScanning = true;
        _statusText = 'Обновление сводки из 3 каналов...';
      });
    }

    try {
      final results = await Future.wait(
        _channels.map(
          (ch) => TelegramWebScraper.fetchChannel(ch, isInitialLoad: isInitial),
        ),
      ).timeout(const Duration(seconds: 12));

      for (final channelPosts in results) {
        for (final msg in channelPosts) {
          _analyzeMessage(msg, allowPush: !isInitial);
        }
      }
      _cleanupExpiredAlerts();

      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      if (mounted) {
        setState(() {
          _statusText = 'Прямой эфир активен (обновлено в $timeStr)';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _statusText = 'Ожидание ответа сети... Повтор через 12 сек';
        });
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _analyzeMessage(ScrapedMessage msg, {required bool allowPush}) {
    final lower = msg.text.toLowerCase();

    final isCancel = GeoDatabase.cancelKeywords.any(lower.contains);
    final isMissile = GeoDatabase.missileKeywords.any(lower.contains);
    final isDrone = GeoDatabase.droneKeywords.any(lower.contains);

    if (!isCancel && !isMissile && !isDrone) return;

    final Set<String> matchedLocationNames = {};

    for (final geo in GeoDatabase.locations) {
      if (lower.contains(geo.key)) {
        if (matchedLocationNames.contains(geo.name)) continue;
        matchedLocationNames.add(geo.name);

        // СЦЕНАРИЙ 1: ОТБОЙ ОПАСНОСТИ
        if (isCancel && !isDrone) {
          if (_activeAlerts.containsKey(geo.name)) {
            setState(() => _activeAlerts.remove(geo.name));

            if (allowPush && _userRegion == geo.regionGroup) {
              _sendPush(
                title: '🟢 ОТБОЙ ОПАСНОСТИ: ${geo.name}',
                body:
                    'В вашем регионе (${geo.regionGroup}) снята воздушная угроза. Источник: @${msg.channel}',
                isCancel: true,
              );
            }
          }
          continue;
        }

        // СЦЕНАРИЙ 2: ОБНАРУЖЕНИЕ ДРОНА ИЛИ РАКЕТНОЙ ОПАСНОСТИ
        final ThreatType detectedType =
            isMissile ? ThreatType.missile : ThreatType.drone;

        final bool wasAlreadyActive = _activeAlerts.containsKey(geo.name);

        setState(() {
          if (wasAlreadyActive) {
            final existing = _activeAlerts[geo.name]!;
            existing.lastUpdated = msg.timestamp;
            if (detectedType == ThreatType.missile) {
              existing.type = ThreatType.missile;
            }
            final isDuplicateText =
                existing.reports.any((r) => r.text == msg.text);
            if (!isDuplicateText) {
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
              type: detectedType,
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

        if (allowPush && !wasAlreadyActive && _userRegion == geo.regionGroup) {
          final String prefix = detectedType == ThreatType.missile
              ? '🚨 РАКЕТНАЯ / ПВО ТРЕВОГА'
              : '⚠️ УГРОЗА БПЛА';
          _sendPush(
            title: '$prefix: ${geo.name}',
            body: msg.text.length > 140
                ? '${msg.text.substring(0, 140)}...'
                : msg.text,
            isCancel: false,
          );
        }
      }
    }
  }

  void _cleanupExpiredAlerts() {
    final now = DateTime.now();
    if (!mounted) return;
    setState(() {
      _activeAlerts.removeWhere(
        (_, alert) => now.difference(alert.lastUpdated).inMinutes > 35,
      );
    });
  }

  void _cycleMapStyle() {
    setState(() {
      if (_mapStyle == MapStyleMode.darkRadar) {
        _mapStyle = MapStyleMode.satellite;
      } else if (_mapStyle == MapStyleMode.satellite) {
        _mapStyle = MapStyleMode.lightOsm;
      } else {
        _mapStyle = MapStyleMode.darkRadar;
      }
    });
  }

  Widget _buildMapTileLayer() {
    if (_mapStyle == MapStyleMode.satellite) {
      return TileLayer(
        urlTemplate:
            'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        userAgentPackageName: 'com.skyshield.radar',
      );
    }

    final osmLayer = TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.skyshield.radar',
    );

    if (_mapStyle == MapStyleMode.darkRadar) {
      return ColorFiltered(
        colorFilter: _darkRadarFilter,
        child: osmLayer,
      );
    }

    return osmLayer;
  }

  Future<void> _showRegionOnboardingDialog({bool isFirstLaunch = false}) async {
    String selected = _userRegion ?? GeoDatabase.availableRegions.first;

    await showDialog(
      context: context,
      barrierDismissible: !isFirstLaunch,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF151922),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Colors.redAccent, width: 1),
              ),
              title: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: Colors.redAccent),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Ваш регион проживания',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Выберите свой регион, чтобы мгновенно получать Push-уведомления об угрозе БПЛА и отбое тревоги:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B0E14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selected,
                        isExpanded: true,
                        dropdownColor: const Color(0xFF151922),
                        items: GeoDatabase.availableRegions.map((reg) {
                          return DropdownMenuItem(
                            value: reg,
                            child: Text(
                              reg,
                              style: const TextStyle(fontSize: 14),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selected = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B30),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    setState(() => _userRegion = selected);
                    if (context.mounted) Navigator.pop(context);
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('user_home_region', selected);
                    } catch (_) {}
                  },
                  child: const Text('Сохранить и включить защиту'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _triggerTestSimulation() {
    final targetRegion = _userRegion ?? 'Москва и МО';
    final samplePoint = GeoDatabase.locations.firstWhere(
      (g) => g.regionGroup == targetRegion,
      orElse: () => GeoDatabase.locations.first,
    );

    final fakeMsg = ScrapedMessage(
      postId: 'sim_${DateTime.now().millisecondsSinceEpoch}',
      channel: 'Radar_Moscow_99 (ТЕСТ)',
      text:
          '⚠️ Внимание! Зафиксировано движение БПЛА в районе ${samplePoint.name}. Соблюдайте осторожность!',
      timestamp: DateTime.now(),
    );

    _analyzeMessage(fakeMsg, allowPush: true);
    _mapController.move(samplePoint.coords, 9.5);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _radarSweepController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alertsList = _activeAlerts.values.toList();

    return Scaffold(
      body: Stack(
        children: [
          // 1. ИНТЕРАКТИВНАЯ КАРТА (БЕЗ КЛЮЧЕЙ API, РАБОТАЕТ ВСЕГДА)
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(55.55, 37.45),
              initialZoom: 7.2,
              minZoom: 4.0,
              maxZoom: 18.0,
            ),
            children: [
              _buildMapTileLayer(),

              CircleLayer(
                circles: alertsList.map((alert) {
                  final isMissile = alert.type == ThreatType.missile;
                  return CircleMarker(
                    point: alert.point.coords,
                    radius: alert.point.radiusKm * 1000,
                    useRadiusInMeter: true,
                    color:
                        (isMissile ? Colors.deepOrange : const Color(0xFFFF2A2A))
                            .withOpacity(0.16),
                    borderColor:
                        (isMissile ? Colors.orangeAccent : Colors.redAccent)
                            .withOpacity(0.65),
                    borderStrokeWidth: 1.8,
                  );
                }).toList(),
              ),

              MarkerLayer(
                markers: alertsList.map((alert) {
                  return Marker(
                    point: alert.point.coords,
                    width: 90,
                    height: 90,
                    child: GestureDetector(
                      onTap: () => _openAlertDetailsSheet(alert),
                      child: AnimatedBuilder(
                        animation: Listenable.merge([
                          _radarSweepController,
                          _pulseController,
                        ]),
                        builder: (context, _) {
                          return CustomPaint(
                            painter: RealisticTargetPainter(
                              sweepAngle:
                                  _radarSweepController.value * 2 * math.pi,
                              pulseValue: _pulseController.value,
                              type: alert.type,
                              sourcesCount: alert.reports.length,
                            ),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 58),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.85),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.redAccent.withOpacity(0.7),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    alert.point.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // 2. ВЕРХНЯЯ ПАНЕЛЬ УПРАВЛЕНИЯ (ТАКТИЧЕСКИЙ HUD)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12161F).withOpacity(0.92),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                      boxShadow: const [
                        BoxShadow(color: Colors.black54, blurRadius: 12),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isScanning
                                ? Colors.amberAccent
                                : const Color(0xFF00E676),
                            boxShadow: [
                              BoxShadow(
                                color: _isScanning
                                    ? Colors.amber
                                    : const Color(0xFF00E676),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'SKYRADAR • МОНИТОРИНГ БПЛА',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  letterSpacing: 0.6,
                                ),
                              ),
                              Text(
                                'Регион: ${_userRegion ?? "Не выбран"} • Активных угроз: ${alertsList.length}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                _statusText,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Сменить регион уведомлений',
                          icon: const Icon(
                            Icons.edit_location_alt_outlined,
                            color: Colors.redAccent,
                            size: 22,
                          ),
                          onPressed: () =>
                              _showRegionOnboardingDialog(isFirstLaunch: false),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. ПРАВАЯ ПАНЕЛЬ БЫСТРЫХ КНОПОК
          Positioned(
            right: 14,
            bottom: 110,
            child: Column(
              children: [
                _buildHudButton(
                  icon: _mapStyle == MapStyleMode.satellite
                      ? Icons.map_outlined
                      : Icons.satellite_alt,
                  tooltip: 'Сменить вид карты (Тёмный радар / Спутник / Схема)',
                  onTap: _cycleMapStyle,
                ),
                const SizedBox(height: 10),
                _buildHudButton(
                  icon: Icons.refresh,
                  tooltip: 'Принудительно опросить каналы',
                  onTap: () => _scanAllChannels(isInitial: false),
                ),
                const SizedBox(height: 10),
                _buildHudButton(
                  icon: Icons.bug_report_outlined,
                  tooltip: 'Тест дрона и Push-уведомления',
                  color: Colors.amberAccent,
                  onTap: _triggerTestSimulation,
                ),
              ],
            ),
          ),

          // 4. НИЖНЯЯ СВОДКА АКТИВНЫХ СИГНАЛОВ
          Positioned(
            left: 14,
            right: 14,
            bottom: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF12161F).withOpacity(0.94),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: alertsList.isEmpty
                      ? Colors.white12
                      : Colors.redAccent.withOpacity(0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    alertsList.isEmpty
                        ? Icons.verified_user_outlined
                        : Icons.radar,
                    color: alertsList.isEmpty
                        ? const Color(0xFF00E676)
                        : const Color(0xFFFF3B30),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      alertsList.isEmpty
                          ? 'Небо чистое. Активных угроз в каналах не зафиксировано.'
                          : 'Внимание! Зафиксирована активность в ${alertsList.length} р-нах. Нажмите на метку дрона для сводки.',
                      style:
                          const TextStyle(fontSize: 12.5, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHudButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return Material(
      color: const Color(0xFF161B26).withOpacity(0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.white12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }

  void _openAlertDetailsSheet(ActiveAlert alert) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141821),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      alert.type == ThreatType.missile
                          ? Icons.rocket_launch
                          : Icons.airplanemode_active,
                      color: Colors.redAccent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alert.point.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Регион: ${alert.point.regionGroup} • Подтверждений: ${alert.reports.length}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      setState(() => _activeAlerts.remove(alert.point.name));
                      Navigator.pop(ctx);
                    },
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Снять'),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: alert.reports.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, idx) {
                    final rep = alert.reports[idx];
                    final timeStr =
                        '${rep.time.hour.toString().padLeft(2, '0')}:${rep.time.minute.toString().padLeft(2, '0')}';
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0E14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '@${rep.channel}',
                                style: const TextStyle(
                                  color: Colors.lightBlueAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                timeStr,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            rep.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
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
        );
      },
    );
  }
}

/// КАСТОМНАЯ ОТРИСОВКА РЕАЛИСТИЧНОГО СИЛУЭТА БПЛА И РАДАРА
class RealisticTargetPainter extends CustomPainter {
  final double sweepAngle;
  final double pulseValue;
  final ThreatType type;
  final int sourcesCount;

  RealisticTargetPainter({
    required this.sweepAngle,
    required this.pulseValue,
    required this.type,
    required this.sourcesCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 6);
    final baseColor = type == ThreatType.missile
        ? const Color(0xFFFF9100)
        : const Color(0xFFFF2A2A);

    final pulsePaint = Paint()
      ..color = baseColor.withOpacity(0.45 * (1.0 - pulseValue))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, 14 + (pulseValue * 22), pulsePaint);

    final sweepRect = Rect.fromCircle(center: center, radius: 24);
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: math.pi * 2,
        colors: [
          baseColor.withOpacity(0.0),
          baseColor.withOpacity(0.35),
        ],
        stops: const [0.55, 1.0],
        transform: GradientRotation(sweepAngle),
      ).createShader(sweepRect);
    canvas.drawCircle(center, 24, sweepPaint);

    final ringPaint = Paint()
      ..color = baseColor.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawCircle(center, 24, ringPaint);

    final dronePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path();
    if (type == ThreatType.drone) {
      path.moveTo(center.dx, center.dy - 12);
      path.lineTo(center.dx + 3, center.dy - 5);
      path.lineTo(center.dx + 13, center.dy + 4);
      path.lineTo(center.dx + 13, center.dy + 8);
      path.lineTo(center.dx + 3, center.dy + 6);
      path.lineTo(center.dx + 5, center.dy + 11);
      path.lineTo(center.dx, center.dy + 9);
      path.lineTo(center.dx - 5, center.dy + 11);
      path.lineTo(center.dx - 3, center.dy + 6);
      path.lineTo(center.dx - 13, center.dy + 8);
      path.lineTo(center.dx - 13, center.dy + 4);
      path.lineTo(center.dx - 3, center.dy - 5);
      path.close();
    } else {
      path.moveTo(center.dx, center.dy - 13);
      path.lineTo(center.dx + 4, center.dy - 3);
      path.lineTo(center.dx + 4, center.dy + 6);
      path.lineTo(center.dx + 8, center.dy + 11);
      path.lineTo(center.dx - 8, center.dy + 11);
      path.lineTo(center.dx - 4, center.dy + 6);
      path.lineTo(center.dx - 4, center.dy - 3);
      path.close();
    }

    canvas.drawShadow(path, baseColor, 6, true);
    canvas.drawPath(path, dronePaint);
  }

  @override
  bool shouldRepaint(covariant RealisticTargetPainter oldDelegate) => true;
}
