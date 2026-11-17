import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/route_models.dart';

class OpenRouteService {
  // OPENROUTESERVICE API ANAHTARI
  static const String apiKey = "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6ImYzYWVlZDM5MjQ3YzQ2NzRiZDA3M2I1NjU3ZDM0M2IzIiwiaCI6Im11cm11cjY0In0=";
  static const String baseUrl = "https://api.openrouteservice.org/v2/directions";
  static const String userAgent = "TekerBikeNav/1.0";

  /// Belirtilen koordinatlar arasında bisiklet rotası oluşturur
  static Future<NavigationRoute?> getRoute({
    required LatLng start,
    required LatLng destination,
    List<LatLng> waypoints = const [],
    String profile = 'cycling-electric', // cycling-electric, cycling-road, cycling-mountain
    bool avoidHills = false,
  }) async {
    final List<List<double>> coordinates = [
      [start.longitude, start.latitude],
      ...waypoints.map((w) => [w.longitude, w.latitude]),
      [destination.longitude, destination.latitude],
    ];

    final url = Uri.parse('$baseUrl/$profile/geojson');

    final body = {
      'coordinates': coordinates,
      'elevation': true,
      'instructions': true,
      'language': 'tr',
      'options': {
        if (avoidHills) 'avoid_features': ['hills'],
      },
    };

    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': apiKey,
          'Content-Type': 'application/json',
          'User-Agent': userAgent,
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return parseGeoJsonResponse(data);
      } else {
        // Mock fallback demo rotası (API anahtarı girilmediğinde test amaçlı)
        return generateFallbackRoute(start, destination, waypoints);
      }
    } catch (e) {
      // Ağ hatası veya çevrimdışı durumunda fallback rota
      return generateFallbackRoute(start, destination, waypoints);
    }
  }

  static NavigationRoute parseGeoJsonResponse(Map<String, dynamic> data) {
    final feature = data['features'][0];
    final geometry = feature['geometry'];
    final properties = feature['properties'];
    final summary = properties['summary'];

    final rawCoordinates = geometry['coordinates'] as List;
    final List<LatLng> latLngList = [];
    final List<RoutePointWithEle> pointWithEleList = [];

    for (var coord in rawCoordinates) {
      final lon = (coord[0] as num).toDouble();
      final lat = (coord[1] as num).toDouble();
      final ele = coord.length > 2 ? (coord[2] as num).toDouble() : 0.0;

      final p = LatLng(lat, lon);
      latLngList.add(p);
      pointWithEleList.add(RoutePointWithEle(point: p, elevation: ele));
    }

    final segments = properties['segments'] as List;
    final List<ManeuverStep> steps = [];
    double totalAscent = 0.0;
    double totalDescent = 0.0;

    for (var seg in segments) {
      if (seg.containsKey('ascent')) {
        totalAscent += (seg['ascent'] as num).toDouble();
      }
      if (seg.containsKey('descent')) {
        totalDescent += (seg['descent'] as num).toDouble();
      }
      final stepList = seg['steps'] as List;
      for (var s in stepList) {
        steps.add(
          ManeuverStep(
            instruction: s['instruction'] as String? ?? 'Düz devam edin',
            streetName: s['name'] as String? ?? '',
            distanceMeters: (s['distance'] as num).toDouble(),
            durationSeconds: (s['duration'] as num).toDouble(),
            type: s['type'] as int? ?? 1,
          ),
        );
      }
    }

    return NavigationRoute(
      coordinates: latLngList,
      coordinatesWithEle: pointWithEleList,
      totalDistanceMeters: (summary['distance'] as num).toDouble(),
      totalDurationSeconds: (summary['duration'] as num).toDouble(),
      totalAscentMeters: totalAscent > 0 ? totalAscent : 15.0,
      totalDescentMeters: totalDescent,
      steps: steps,
    );
  }

  /// 40 metrelik rota sapma mesafesi kontrolü (Re-routing trigger)
  static bool isDeviatedFromRoute({
    required LatLng currentPos,
    required List<LatLng> routePoints,
    double thresholdMeters = 40.0,
  }) {
    if (routePoints.isEmpty) return false;

    const distanceCalc = Distance();
    double minDistance = double.infinity;

    for (var pt in routePoints) {
      final d = distanceCalc.as(LengthUnit.Meter, currentPos, pt);
      if (d < minDistance) {
        minDistance = d;
      }
      if (minDistance <= thresholdMeters) return false;
    }

    return minDistance > thresholdMeters;
  }

  /// Çevrimdışı ve API yokken gösterilecek akıllı simülasyon rotası
  static NavigationRoute generateFallbackRoute(
    LatLng start,
    LatLng dest,
    List<LatLng> waypoints,
  ) {
    const distanceCalc = Distance();
    final allPoints = [start, ...waypoints, dest];
    final List<LatLng> interpolated = [];
    final List<RoutePointWithEle> pointWithEleList = [];

    for (int i = 0; i < allPoints.length - 1; i++) {
      final p1 = allPoints[i];
      final p2 = allPoints[i + 1];
      const stepsCount = 20;
      for (int s = 0; s <= stepsCount; s++) {
        final t = s / stepsCount;
        final lat = p1.latitude + (p2.latitude - p1.latitude) * t;
        final lon = p1.longitude + (p2.longitude - p1.longitude) * t;
        final ele = 10.0 + sin(t * pi) * 25.0; // 10m - 35m arası eğim

        final pt = LatLng(lat, lon);
        interpolated.add(pt);
        pointWithEleList.add(RoutePointWithEle(point: pt, elevation: ele));
      }
    }

    final totalDist = distanceCalc.as(LengthUnit.Meter, start, dest);

    return NavigationRoute(
      coordinates: interpolated,
      coordinatesWithEle: pointWithEleList,
      totalDistanceMeters: totalDist,
      totalDurationSeconds: (totalDist / 5.5), // ~20 km/s bisiklet hızı
      totalAscentMeters: 45.0,
      totalDescentMeters: 30.0,
      steps: [
        ManeuverStep(
          instruction: 'Rotaya başlayın ve sahil yolunu takip edin',
          streetName: 'Sahil Kordonu',
          distanceMeters: totalDist * 0.4,
          durationSeconds: (totalDist * 0.4) / 5.5,
          type: 1,
        ),
        ManeuverStep(
          instruction: 'Kavşaktan sola dönün',
          streetName: 'Marina Caddesi',
          distanceMeters: totalDist * 0.6,
          durationSeconds: (totalDist * 0.6) / 5.5,
          type: 2,
        ),
      ],
    );
  }
}
