import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/ebike_models.dart';
import '../models/poi_model.dart';
import '../models/route_models.dart';
import '../models/saved_location_model.dart';
import '../services/ebike_calculator.dart';
import '../services/gemini_command_service.dart';
import '../services/openroute_service.dart';
import '../services/overpass_service.dart';
import '../services/saved_locations_service.dart';
import '../services/telemetry_bridge.dart';
import '../widgets/cockpit_bottom_sheet.dart';
import '../widgets/saved_location_dialog.dart';
import '../widgets/turn_by_turn_banner.dart';
import 'ebike_settings_screen.dart';
import 'gpx_import_screen.dart';
import 'offline_maps_screen.dart';

class HomeNavigationScreen extends StatefulWidget {
  const HomeNavigationScreen({super.key});

  @override
  State<HomeNavigationScreen> createState() => _HomeNavigationScreenState();
}

class _HomeNavigationScreenState extends State<HomeNavigationScreen> {
  final MapController _mapController = MapController();
  final GeminiCommandService _geminiService = GeminiCommandService();

  // Konum & Hareket
  LatLng _currentLocation = const LatLng(36.795, 34.618); // Mersin Sahil
  double _currentBearing = 0.0;
  double _currentSpeedKmh = 0.0;
  double _currentAltitudeMeters = 5.0;
  StreamSubscription<Position>? _positionSub;

  // E-Bike Durumu
  EbikeProfile _profile = EbikeProfile();
  EnergyCalculationResult? _energyResult;

  // Rota ve Navigasyon
  NavigationRoute? _activeRoute;
  String _activeDestinationName = '';
  ManeuverStep? _currentManeuver;
  LatLng? _activeDestinationPoint;
  final List<LatLng> _waypoints = [];

  // Harita İşaretçileri (Pinler)
  final List<TekerCustomMarker> _customMarkers = [];
  final List<TekerPoi> _chargingStations = [];
  Map<String, SavedLocation> _savedShortcuts = {};

  // Sesli Komut Modalı
  final TextEditingController _voicePromptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initGeminiService();
    _loadShortcuts();
    _initLocationTracking();
    _fetchNearbyChargingStations();
  }

  void _loadShortcuts() async {
    final list = await SavedLocationsService.loadSavedLocations();
    if (mounted) {
      setState(() {
        _savedShortcuts = list;
      });
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    TelemetryBridge.stopForegroundService();
    super.dispose();
  }

  void _initGeminiService() {
    _geminiService.currentPosition = _currentLocation;
    _geminiService.currentProfile = _profile;

    _geminiService.onMarkerAdded = (marker) {
      setState(() {
        _customMarkers.add(marker);
      });
      _mapController.move(marker.location, 16.0);
    };

    _geminiService.onMarkersCleared = () {
      setState(() {
        _customMarkers.clear();
      });
    };

    _geminiService.onRouteCreated = (route, destName) {
      _applyNewRoute(route, destName, route.coordinates.last);
    };

    _geminiService.onAssistModeChanged = (mode) {
      setState(() {
        _profile.assistMode = mode;
        _recalculateEnergy();
      });
      _syncTelemetry();
    };

    _geminiService.onPoiSelected = (poi, asWaypoint) {
      if (asWaypoint) {
        setState(() {
          _waypoints.add(poi.location);
        });
        if (_activeDestinationPoint != null) {
          _requestRouteToDestination(_activeDestinationPoint!, _activeDestinationName);
        }
      } else {
        _mapController.move(poi.location, 16.0);
      }
    };
  }

  void _initLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      TelemetryBridge.startForegroundService();
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen((pos) {
      final newPos = LatLng(pos.latitude, pos.longitude);
      final speedKmh = (pos.speed * 3.6).clamp(0.0, 70.0);
      final bearing = pos.heading;
      final altitude = pos.altitude;

      setState(() {
        _currentLocation = newPos;
        _currentBearing = bearing;
        _currentSpeedKmh = speedKmh;
        _currentAltitudeMeters = altitude;
      });

      _geminiService.currentPosition = newPos;

      // Android Auto ve Native Katmana Konum İlet
      TelemetryBridge.syncLocation(
        position: newPos,
        bearing: bearing,
        speedKmh: speedKmh,
        altitudeMeters: altitude,
      );

      // Rotadan 40 metreden fazla sapma kontrolü (Re-routing)
      if (_activeRoute != null && _activeDestinationPoint != null) {
        final isDeviated = OpenRouteService.isDeviatedFromRoute(
          currentPos: newPos,
          routePoints: _activeRoute!.coordinates,
          thresholdMeters: 40.0,
        );

        if (isDeviated) {
          _requestRouteToDestination(_activeDestinationPoint!, _activeDestinationName);
        }
      }

      _recalculateEnergy();
      _syncTelemetry();
    });
  }

  void _fetchNearbyChargingStations() async {
    final pois = await OverpassService.fetchNearbyChargingAndRepairPoints(
      center: _currentLocation,
      radiusMeters: 6000,
    );
    setState(() {
      _chargingStations.clear();
      _chargingStations.addAll(pois);
    });
    TelemetryBridge.syncChargingStations(pois);
  }

  void _requestRouteToDestination(LatLng destination, String name) async {
    final route = await OpenRouteService.getRoute(
      start: _currentLocation,
      destination: destination,
      waypoints: _waypoints,
      profile: 'cycling-electric',
    );

    if (route != null) {
      _applyNewRoute(route, name, destination);
    }
  }

  void _applyNewRoute(NavigationRoute route, String destName, LatLng destPoint) {
    setState(() {
      _activeRoute = route;
      _activeDestinationName = destName;
      _activeDestinationPoint = destPoint;
      if (route.steps.isNotEmpty) {
        _currentManeuver = route.steps.first;
      }
    });

    _recalculateEnergy();
    _syncTelemetry();
    TelemetryBridge.syncRoute(route);
    if (_currentManeuver != null) {
      TelemetryBridge.syncManeuver(_currentManeuver!);
    }

    _mapController.move(_currentLocation, 16.0);
  }

  void _recalculateEnergy() {
    if (_activeRoute != null) {
      final result = EbikeCalculator.calculateRouteEnergy(
        distanceKm: _activeRoute!.totalDistanceKm,
        totalAscentMeters: _activeRoute!.totalAscentMeters,
        profile: _profile,
      );
      setState(() {
        _energyResult = result;
      });
    } else {
      final range = EbikeCalculator.calculateRemainingRangeKm(
        profile: _profile,
        currentSpeedKmh: _currentSpeedKmh,
      );
      setState(() {
        _energyResult = EnergyCalculationResult(
          requiredEnergyWh: 0,
          availableEnergyWh: _profile.availableEnergyWh,
          isSufficient: true,
          deficitWh: 0,
          estimatedRemainingRangeKm: range,
          climbEnergyWh: 0,
          baseDistanceEnergyWh: 0,
        );
      });
    }
  }

  void _syncTelemetry() {
    TelemetryBridge.syncTelemetry(
      speedKmh: _currentSpeedKmh,
      batteryPct: _profile.batteryPercent,
      remainingRangeKm: _energyResult?.estimatedRemainingRangeKm ?? 50.0,
      altitudeMeters: _currentAltitudeMeters,
      remainingDistanceMeters: _activeRoute?.totalDistanceMeters ?? 0.0,
      remainingSeconds: _activeRoute?.totalDurationSeconds.toInt() ?? 0,
      assistMode: _profile.assistMode.displayName,
    );
  }

  void _cycleAssistMode() {
    setState(() {
      switch (_profile.assistMode) {
        case EbikeAssistMode.eco:
          _profile.assistMode = EbikeAssistMode.tour;
          break;
        case EbikeAssistMode.tour:
          _profile.assistMode = EbikeAssistMode.sport;
          break;
        case EbikeAssistMode.sport:
          _profile.assistMode = EbikeAssistMode.turbo;
          break;
        case EbikeAssistMode.turbo:
          _profile.assistMode = EbikeAssistMode.eco;
          break;
      }
      _recalculateEnergy();
      _syncTelemetry();
    });
  }

  void _showVoiceCommandModal() {
    _voicePromptController.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B2430),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Color(0xFF9C27B0),
                    child: Icon(Icons.mic, color: Colors.white),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Hey Google / Gemini Asistan',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _voicePromptController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Örn: "Mersin Marina\'ya rota çiz" veya "Turbo moda geç"',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: const Color(0xFF263238),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (val) {
                  Navigator.pop(ctx);
                  _geminiService.processCommandWithGemini(val);
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Marina\'ya Rota Çiz'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _geminiService.processCommandWithGemini("Mersin Marina'ya rota çiz");
                    },
                  ),
                  ActionChip(
                    label: const Text('En Yakın Şarj İstasyonu'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _geminiService.processCommandWithGemini("En yakın şarj istasyonunu rotaya ekle");
                    },
                  ),
                  ActionChip(
                    label: const Text('Turbo Moda Geç'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _geminiService.processCommandWithGemini("Turbo moda geç");
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('Komutu Çalıştır'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 48),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  final text = _voicePromptController.text.trim();
                  if (text.isNotEmpty) {
                    Navigator.pop(ctx);
                    _geminiService.processCommandWithGemini(text);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Canlı Harita (FlutterMap - CyclOSM Karoları)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: 16.0,
            ),
            children: [
              // CyclOSM Bisiklet ve Eğim Haritası Katmanı
              TileLayer(
                urlTemplate: 'https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.teker.navigation',
              ),

              // Rota Çizgisi (Polyline)
              if (_activeRoute != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _activeRoute!.coordinates,
                      strokeWidth: 6.0,
                      color: const Color(0xFF00BCD4),
                    ),
                  ],
                ),

              // Şarj ve Tamir İstasyonu Pinleri
              MarkerLayer(
                markers: _chargingStations.map((poi) {
                  return Marker(
                    point: poi.location,
                    width: 36,
                    height: 36,
                    child: GestureDetector(
                      onTap: () {
                        _showPoiModal(poi);
                      },
                      child: CircleAvatar(
                        backgroundColor: poi.isRepairStation ? Colors.orange : Colors.amber,
                        child: Icon(
                          poi.isRepairStation ? Icons.build : Icons.electric_bolt,
                          color: Colors.black,
                          size: 20,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              // Sesli Komut / Gemini Özel İşaret Pinleri
              MarkerLayer(
                markers: _customMarkers.map((m) {
                  return Marker(
                    point: m.location,
                    width: 44,
                    height: 44,
                    child: const CircleAvatar(
                      backgroundColor: Color(0xFF9C27B0),
                      child: Icon(Icons.star, color: Colors.white, size: 24),
                    ),
                  );
                }).toList(),
              ),

              // Anlık Kullanıcı Konumu & Bisiklet İmleci
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentLocation,
                    width: 50,
                    height: 50,
                    child: Transform.rotate(
                      angle: (_currentBearing * 3.1415926535 / 180),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF00E676).withOpacity(0.3),
                            ),
                          ),
                          const CircleAvatar(
                            radius: 12,
                            backgroundColor: Color(0xFF00E676),
                            child: Icon(Icons.navigation, color: Colors.black, size: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 2. Üst Kontrol & Arama Çubuğu
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFF161D26),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4))
                          ],
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            const Icon(Icons.directions_bike, color: Color(0xFF00E676)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _activeRoute != null
                                    ? _activeDestinationName
                                    : 'Teker Bisiklet Navigasyonu',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.mic, color: Color(0xFF9C27B0)),
                              onPressed: _showVoiceCommandModal,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // E-Bike Ayarları
                    CircleAvatar(
                      backgroundColor: const Color(0xFF161D26),
                      child: IconButton(
                        icon: const Icon(Icons.battery_charging_full, color: Color(0xFF00BCD4)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EbikeSettingsScreen(
                                profile: _profile,
                                onSave: (updated) {
                                  setState(() => _profile = updated);
                                  _recalculateEnergy();
                                  _syncTelemetry();
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Çevrimdışı Haritalar
                    CircleAvatar(
                      backgroundColor: const Color(0xFF161D26),
                      child: IconButton(
                        icon: const Icon(Icons.offline_pin, color: Color(0xFF00E676)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OfflineMapsScreen(
                                onFocusRegion: (center, zoom) {
                                  _mapController.move(center, zoom);
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // GPX Yükle
                    CircleAvatar(
                      backgroundColor: const Color(0xFF161D26),
                      child: IconButton(
                        icon: const Icon(Icons.file_upload, color: Colors.orangeAccent),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => GpxImportScreen(
                                profile: _profile,
                                onStartGpxRoute: (route) {
                                  _applyNewRoute(route, 'GPX Parkuru', route.coordinates.last);
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Kısayol Konum Çubuğu (Ev, Okul, İş Yeri, Favori)
                _buildShortcutsBar(),

                // Sıradaki Dönüş Bilgisi (Turn-by-Turn)
                if (_currentManeuver != null && _activeRoute != null)
                  TurnByTurnBanner(maneuver: _currentManeuver),
              ],
            ),
          ),

          // 3. Sağ Taraf Hızlı Eylemler (Konumlandır, Şarjlar, Pin Temizle)
          Positioned(
            right: 16,
            bottom: 220,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'recenter',
                  backgroundColor: const Color(0xFF161D26),
                  child: const Icon(Icons.my_location, color: Color(0xFF00E676)),
                  onPressed: () {
                    _mapController.move(_currentLocation, 16.0);
                  },
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'charging',
                  backgroundColor: const Color(0xFF161D26),
                  child: const Icon(Icons.electric_bolt, color: Colors.amber),
                  onPressed: _fetchNearbyChargingStations,
                ),
                if (_customMarkers.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'clear_markers',
                    backgroundColor: const Color(0xFF161D26),
                    child: const Icon(Icons.layers_clear, color: Colors.redAccent),
                    onPressed: () {
                      _geminiService.executeFunctionCall('clearCustomMarkers', {});
                    },
                  ),
                ],
              ],
            ),
          ),

          // 4. Alt Kokpit Paneli (Speed, Battery, Range, ETA)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CockpitBottomSheet(
              currentSpeedKmh: _currentSpeedKmh,
              currentAltitudeMeters: _currentAltitudeMeters,
              profile: _profile,
              energyResult: _energyResult,
              activeRoute: _activeRoute,
              onModeToggle: _cycleAssistMode,
              onAddChargingPoint: () {
                _geminiService.executeFunctionCall('findAndMarkNearestPoi', {
                  'poiType': 'charging_station',
                  'addAsWaypoint': true,
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showPoiModal(TekerPoi poi) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B2430),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final distKm = (poi.distanceMeters / 1000.0).toStringAsFixed(1);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    poi.isRepairStation ? Icons.build : Icons.electric_bolt,
                    color: poi.isRepairStation ? Colors.orange : Colors.amber,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      poi.name,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Mesafe: $distKm km • Çalışma Saatleri: ${poi.openingHours}',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _requestRouteToDestination(poi.location, poi.name);
                      },
                      child: const Text('Doğrudan Rota Çiz'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676),
                        foregroundColor: Colors.black,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _geminiService.onPoiSelected?.call(poi, true);
                      },
                      child: const Text('Rotaya Ara Durak Ekle'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAssignLocationDialog(LocationShortcutType type) {
    final existing = _savedShortcuts[type.id];
    showDialog(
      context: context,
      builder: (ctx) => SavedLocationDialog(
        defaultType: type,
        currentGpsLocation: _currentLocation,
        existingLocation: existing,
        onSaved: (saved) {
          _loadShortcuts();
        },
      ),
    );
  }

  Widget _buildShortcutsBar() {
    final shortcuts = [
      LocationShortcutType.home,
      LocationShortcutType.school,
      LocationShortcutType.work,
      LocationShortcutType.favorite,
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: shortcuts.map((type) {
          final saved = _savedShortcuts[type.id];
          final isAssigned = saved != null;

          IconData icon;
          switch (type) {
            case LocationShortcutType.home:
              icon = Icons.home;
              break;
            case LocationShortcutType.school:
              icon = Icons.school;
              break;
            case LocationShortcutType.work:
              icon = Icons.business;
              break;
            case LocationShortcutType.favorite:
              icon = Icons.star;
              break;
          }

          return Container(
            margin: const EdgeInsets.only(right: 8),
            child: Material(
              color: isAssigned
                  ? const Color(0xFF1B2430)
                  : const Color(0xFF161D26).withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(12),
              elevation: 2,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (isAssigned) {
                    _requestRouteToDestination(saved.location, saved.title);
                  } else {
                    _showAssignLocationDialog(type);
                  }
                },
                onLongPress: () => _showAssignLocationDialog(type),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isAssigned ? const Color(0xFF00E676) : Colors.white24,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        color: isAssigned ? const Color(0xFF00E676) : Colors.white54,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isAssigned ? saved.title : "+ ${type.label}",
                        style: TextStyle(
                          color: isAssigned ? Colors.white : Colors.white60,
                          fontSize: 12,
                          fontWeight: isAssigned ? FontWeight.bold : FontWeight.w500,
                        ),
                      ),
                      if (isAssigned) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _showAssignLocationDialog(type),
                          child: const Icon(Icons.edit, color: Colors.white38, size: 13),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
